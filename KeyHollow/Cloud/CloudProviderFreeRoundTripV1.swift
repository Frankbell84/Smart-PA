import CryptoKit
import Foundation

enum CloudProviderFreeErrorV1: Error, Equatable {
    case digestMismatch
    case invalidManifestBinding
    case invalidSnapshot
    case restoredCatalogMismatch
}

enum CloudBackupProgressV1: Sendable {
    case snapshotCaptured
    case objectCommitted(Int)
    case manifestCommitted
}

struct CloudBackupHooksV1: Sendable {
    let didReach: @Sendable (CloudBackupProgressV1) async throws -> Void

    static let none = CloudBackupHooksV1 { _ in }
}

struct CloudBackupReceiptV1: Equatable, Sendable {
    let snapshotID: UUID
    let generation: UInt64
    let manifestObjectID: UUID
    let manifestSHA256: Data
    let objectCount: Int
    let storedByteCount: UInt64
}

private struct CloudPreparedObjectV1: Sendable {
    let objectID: UUID
    let storedBytes: Data
    let sha256: Data
}

/// Gate A's provider-free client path. It intentionally exercises the same
/// opaque object and compare-and-swap contracts expected from a future backend.
struct CloudProviderFreeBackupCoordinatorV1: Sendable {
    func backup(
        snapshot: CloudLocalSnapshotV1,
        accountID: UUID,
        cloudVaultID: UUID,
        cloudVaultKey: Data,
        store: CloudMockObjectStoreV1,
        idempotencyKey: UUID = UUID(),
        nowMilliseconds: UInt64,
        hooks: CloudBackupHooksV1 = .none
    ) async throws -> CloudBackupReceiptV1 {
        defer { snapshot.discard() }
        try Task.checkCancellation()
        guard snapshot.localVaultKey.count == CloudSecretKeyV1.byteCount,
              !snapshot.entries.isEmpty,
              snapshot.entries.first?.role == .localManifest else {
            throw CloudProviderFreeErrorV1.invalidSnapshot
        }
        try await hooks.didReach(.snapshotCaptured)

        let currentHead = await store.currentHead(accountID: accountID, vaultID: cloudVaultID)
        let (generation, generationOverflow) = (currentHead?.generation ?? 0)
            .addingReportingOverflow(1)
        guard !generationOverflow else {
            throw CloudProtocolError.invalidValue("backup generation")
        }
        let parent = currentHead.map {
            CloudManifestParentV1(
                generation: $0.generation,
                manifestObjectID: $0.manifestObjectID,
                storedObjectSHA256: $0.manifestSHA256
            )
        }

        var contentObjects: [CloudPreparedObjectV1] = []
        var manifestEntries: [CloudManifestEntryV1] = []
        contentObjects.reserveCapacity(snapshot.entries.count)
        manifestEntries.reserveCapacity(snapshot.entries.count)
        for entry in snapshot.entries {
            try Task.checkCancellation()
            let inner = try Data(contentsOf: entry.fileURL, options: [.mappedIfSafe])
            guard UInt64(inner.count) == entry.byteCount,
                  CloudObjectContainerV1.sha256(inner) == entry.sha256 else {
                throw CloudProviderFreeErrorV1.invalidSnapshot
            }
            let objectID = UUID()
            let stored = try CloudObjectContainerV1.seal(
                inner,
                purpose: .content,
                accountID: accountID,
                vaultID: cloudVaultID,
                objectID: objectID,
                objectVersion: 1,
                cloudVaultKey: cloudVaultKey
            )
            let storedDigest = CloudObjectContainerV1.sha256(stored)
            let chunkCount = UInt32(
                ((UInt64(inner.count) - 1)
                    / UInt64(CloudProtocolLimits.cloudObjectChunkByteCount)) + 1
            )
            contentObjects.append(
                CloudPreparedObjectV1(
                    objectID: objectID,
                    storedBytes: stored,
                    sha256: storedDigest
                )
            )
            manifestEntries.append(
                CloudManifestEntryV1(
                    entryID: UUID(),
                    role: entry.role,
                    localStorageName: entry.localStorageName,
                    cloudObjectID: objectID,
                    cloudObjectVersion: 1,
                    innerCiphertextByteCount: UInt64(inner.count),
                    innerCiphertextSHA256: entry.sha256,
                    storedCloudObjectByteCount: UInt64(stored.count),
                    storedCloudObjectSHA256: storedDigest,
                    chunkCount: chunkCount
                )
            )
        }

        let manifest = CloudManifestV1(
            accountID: accountID,
            vaultID: cloudVaultID,
            snapshotID: snapshot.snapshotID,
            generation: generation,
            parent: parent,
            createdAtMilliseconds: nowMilliseconds,
            localVaultSecret: CloudLocalVaultSecretV1(
                localVaultKey: snapshot.localVaultKey,
                sourceVaultCreatedAtMilliseconds: snapshot.sourceVaultCreatedAtMilliseconds
            ),
            entries: manifestEntries
        )
        let manifestPlaintext = try manifest.encoded()
        let manifestObjectID = UUID()
        let storedManifest = try CloudObjectContainerV1.seal(
            manifestPlaintext,
            purpose: .manifest,
            accountID: accountID,
            vaultID: cloudVaultID,
            objectID: manifestObjectID,
            objectVersion: generation,
            cloudVaultKey: cloudVaultKey
        )
        let manifestDigest = CloudObjectContainerV1.sha256(storedManifest)
        let manifestObject = CloudPreparedObjectV1(
            objectID: manifestObjectID,
            storedBytes: storedManifest,
            sha256: manifestDigest
        )
        let allObjects = contentObjects + [manifestObject]
        let totalByteCount = try allObjects.reduce(UInt64(0)) { partial, object in
            let (total, overflow) = partial.addingReportingOverflow(UInt64(object.storedBytes.count))
            guard !overflow else { throw CloudProtocolError.invalidLength("backup generation") }
            return total
        }

        let reservation = try await store.reserve(
            accountID: accountID,
            vaultID: cloudVaultID,
            idempotencyKey: idempotencyKey,
            declaredByteCount: totalByteCount,
            nowMilliseconds: nowMilliseconds
        )
        do {
            for (index, object) in allObjects.enumerated() {
                try Task.checkCancellation()
                try await store.putObject(
                    reservation: reservation,
                    objectID: object.objectID,
                    storedBytes: object.storedBytes,
                    expectedSHA256: object.sha256,
                    nowMilliseconds: nowMilliseconds
                )
                try await store.commitObject(
                    reservation: reservation,
                    objectID: object.objectID,
                    observedByteCount: UInt64(object.storedBytes.count),
                    observedSHA256: object.sha256
                )
                try await hooks.didReach(.objectCommitted(index + 1))
            }

            let referencedIDs = Set(allObjects.map(\.objectID))
            let committed = try await store.commitGeneration(
                reservation: reservation,
                generation: generation,
                expectedParent: parent,
                manifestObjectID: manifestObjectID,
                manifestSHA256: manifestDigest,
                referencedObjectIDs: referencedIDs
            )
            try await hooks.didReach(.manifestCommitted)

            // Backup success is reported only after re-downloading and
            // authenticating the exact manifest that the control plane committed.
            let downloaded = try await store.getObject(
                accountID: accountID,
                vaultID: cloudVaultID,
                objectID: committed.manifestObjectID
            )
            guard CloudObjectContainerV1.sha256(downloaded) == committed.manifestSHA256 else {
                throw CloudProviderFreeErrorV1.digestMismatch
            }
            let opened = try CloudObjectContainerV1.open(
                downloaded,
                cloudVaultKey: cloudVaultKey
            )
            let verified = try CloudManifestV1(decoding: opened.plaintext)
            guard opened.header.purpose == .manifest,
                  opened.header.accountID == accountID,
                  opened.header.vaultID == cloudVaultID,
                  opened.header.objectID == manifestObjectID,
                  opened.header.objectVersion == generation,
                  verified == manifest else {
                throw CloudProviderFreeErrorV1.invalidManifestBinding
            }
            return CloudBackupReceiptV1(
                snapshotID: snapshot.snapshotID,
                generation: generation,
                manifestObjectID: manifestObjectID,
                manifestSHA256: manifestDigest,
                objectCount: allObjects.count,
                storedByteCount: totalByteCount
            )
        } catch {
            await store.cancel(reservation)
            throw error
        }
    }
}

final class CloudValidatedRestoreV1: @unchecked Sendable {
    let stagingURL: URL
    let localVaultKey: Data
    let sourceVaultCreatedAt: Date
    let manifest: VaultPhotoManifest

    private let lock = NSLock()
    private var ownsStaging = true

    init(
        stagingURL: URL,
        localVaultKey: Data,
        sourceVaultCreatedAt: Date,
        manifest: VaultPhotoManifest
    ) {
        self.stagingURL = stagingURL
        self.localVaultKey = localVaultKey
        self.sourceVaultCreatedAt = sourceVaultCreatedAt
        self.manifest = manifest
    }

    func discard() {
        lock.lock()
        defer { lock.unlock() }
        guard ownsStaging else { return }
        try? FileManager.default.removeItem(at: stagingURL)
        ownsStaging = false
    }

    func commitEncryptedFiles(to destinationURL: URL) throws {
        lock.lock()
        defer { lock.unlock() }
        guard ownsStaging,
              !FileManager.default.fileExists(atPath: destinationURL.path) else {
            throw CloudProviderFreeErrorV1.invalidSnapshot
        }
        try FileManager.default.moveItem(at: stagingURL, to: destinationURL)
        ownsStaging = false
    }
}

struct CloudProviderFreeRestoreCoordinatorV1: Sendable {
    func stageAndValidate(
        accountID: UUID,
        cloudVaultID: UUID,
        cloudVaultKey: Data,
        store: CloudMockObjectStoreV1,
        workingRoot: URL
    ) async throws -> CloudValidatedRestoreV1 {
        guard let head = await store.currentHead(accountID: accountID, vaultID: cloudVaultID) else {
            throw CloudMockStoreErrorV1.objectNotFound
        }
        let storedManifest = try await store.getObject(
            accountID: accountID,
            vaultID: cloudVaultID,
            objectID: head.manifestObjectID
        )
        guard CloudObjectContainerV1.sha256(storedManifest) == head.manifestSHA256 else {
            throw CloudProviderFreeErrorV1.digestMismatch
        }
        let openedManifest = try CloudObjectContainerV1.open(
            storedManifest,
            cloudVaultKey: cloudVaultKey
        )
        let cloudManifest = try CloudManifestV1(decoding: openedManifest.plaintext)
        guard openedManifest.header.purpose == .manifest,
              openedManifest.header.accountID == accountID,
              openedManifest.header.vaultID == cloudVaultID,
              openedManifest.header.objectID == head.manifestObjectID,
              openedManifest.header.objectVersion == head.generation,
              cloudManifest.accountID == accountID,
              cloudManifest.vaultID == cloudVaultID,
              cloudManifest.generation == head.generation else {
            throw CloudProviderFreeErrorV1.invalidManifestBinding
        }

        let stagingURL = workingRoot.appendingPathComponent(
            UUID().uuidString.lowercased(),
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: workingRoot,
            withIntermediateDirectories: true
        )
        try protectAndExclude(workingRoot)
        try FileManager.default.createDirectory(
            at: stagingURL,
            withIntermediateDirectories: false
        )
        var completed = false
        defer {
            if !completed {
                try? FileManager.default.removeItem(at: stagingURL)
            }
        }
        try protectAndExclude(stagingURL)

        for entry in cloudManifest.entries {
            try Task.checkCancellation()
            let stored = try await store.getObject(
                accountID: accountID,
                vaultID: cloudVaultID,
                objectID: entry.cloudObjectID
            )
            guard UInt64(stored.count) == entry.storedCloudObjectByteCount,
                  CloudObjectContainerV1.sha256(stored) == entry.storedCloudObjectSHA256 else {
                throw CloudProviderFreeErrorV1.digestMismatch
            }
            let opened = try CloudObjectContainerV1.open(stored, cloudVaultKey: cloudVaultKey)
            guard opened.header.purpose == .content,
                  opened.header.accountID == accountID,
                  opened.header.vaultID == cloudVaultID,
                  opened.header.objectID == entry.cloudObjectID,
                  opened.header.objectVersion == entry.cloudObjectVersion,
                  UInt64(opened.plaintext.count) == entry.innerCiphertextByteCount,
                  CloudObjectContainerV1.sha256(opened.plaintext) == entry.innerCiphertextSHA256 else {
                throw CloudProviderFreeErrorV1.invalidManifestBinding
            }
            let destination = stagingURL.appendingPathComponent(entry.localStorageName)
            try opened.plaintext.write(to: destination, options: [.atomic, .completeFileProtection])
            try protectAndExclude(destination)
        }

        let localKey = cloudManifest.localVaultSecret.localVaultKey
        let stagedStore = try VaultPhotoStore(
            vaultID: UUID(),
            vaultKey: SymmetricKey(data: localKey),
            storageRoot: stagingURL
        )
        let localManifest = try await stagedStore.loadManifest()
        try validate(cloudManifest: cloudManifest, localManifest: localManifest)
        for photo in localManifest.photos {
            _ = try await stagedStore.loadPhoto(photo)
            _ = try await stagedStore.loadThumbnail(photo)
        }

        completed = true
        return CloudValidatedRestoreV1(
            stagingURL: stagingURL,
            localVaultKey: localKey,
            sourceVaultCreatedAt: Date(
                timeIntervalSince1970: Double(
                    cloudManifest.localVaultSecret.sourceVaultCreatedAtMilliseconds
                ) / 1_000
            ),
            manifest: localManifest
        )
    }

    private func validate(
        cloudManifest: CloudManifestV1,
        localManifest: VaultPhotoManifest
    ) throws {
        var expected: [String: CloudManifestEntryRoleV1] = [
            "manifest.khm": .localManifest
        ]
        for photo in localManifest.photos {
            guard expected.updateValue(.encryptedOriginal, forKey: photo.blobName) == nil,
                  expected.updateValue(.encryptedThumbnail, forKey: photo.thumbnailName) == nil else {
                throw CloudProviderFreeErrorV1.restoredCatalogMismatch
            }
        }
        guard expected.count == cloudManifest.entries.count else {
            throw CloudProviderFreeErrorV1.restoredCatalogMismatch
        }
        for entry in cloudManifest.entries where expected[entry.localStorageName] != entry.role {
            throw CloudProviderFreeErrorV1.restoredCatalogMismatch
        }
    }

    private func protectAndExclude(_ url: URL) throws {
        try FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.complete],
            ofItemAtPath: url.path
        )
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutableURL = url
        try mutableURL.setResourceValues(values)
    }
}
