import CryptoKit
import Foundation

enum EncryptedVaultTransferError: Error, Equatable {
    case archiveVerificationFailed
    case invalidDestination
    case invalidSourceVault
    case restoredCatalogMismatch
}

enum PortableVaultRestoreInstallationError: Error, Equatable {
    case credentialAlreadyUsed
    case credentialCommitFailed
    case destinationExists
}

protocol PortableVaultCredentialStoring: Sendable {
    func contains(locator: String) async -> Bool
    func write(_ envelope: VaultEnvelope, locator: String) async throws
    func delete(locator: String) async throws
}

extension VaultStore: PortableVaultCredentialStoring {}

struct EncryptedVaultExportReceipt: Equatable, Sendable {
    let archiveURL: URL
    let archiveID: UUID
    let encryptedFileCount: Int
    let archiveByteCount: UInt64
}

/// Validation results are immutable. A lock serializes the only two ownership
/// transitions (commit or discard), allowing this single-use object to cross
/// into `VaultUnlockService` without racing its protected staging directory.
final class ValidatedPortableVaultRestore: @unchecked Sendable {
    let archiveID: UUID
    let sourceVaultID: UUID
    let sourceVaultCreatedAt: Date
    let destinationVaultPayload: VaultPayload
    let manifest: VaultPhotoManifest
    let catalog: PortableArchivePayloadCatalog

    private let stagedPayload: PortableArchiveStagedPayload
    private let ownershipLock = NSLock()
    private var ownsStagingDirectory = true

    var stagingURL: URL { stagedPayload.directoryURL }

    fileprivate init(
        secrets: PortableArchiveSecrets,
        manifest: VaultPhotoManifest,
        catalog: PortableArchivePayloadCatalog,
        stagedPayload: PortableArchiveStagedPayload
    ) {
        archiveID = secrets.archiveID
        sourceVaultID = secrets.sourceVaultID
        sourceVaultCreatedAt = secrets.sourceVaultCreatedAt
        destinationVaultPayload = VaultPayload(
            vaultID: UUID(),
            vaultKey: secrets.vaultKey,
            createdAt: secrets.sourceVaultCreatedAt
        )
        self.manifest = manifest
        self.catalog = catalog
        self.stagedPayload = stagedPayload
    }

    func discard() {
        ownershipLock.lock()
        defer { ownershipLock.unlock() }
        guard ownsStagingDirectory else { return }
        stagedPayload.discard()
        ownsStagingDirectory = false
    }

    func commitEncryptedFiles(to destinationURL: URL) throws {
        ownershipLock.lock()
        defer { ownershipLock.unlock() }
        guard ownsStagingDirectory else {
            throw PortableArchivePayloadError.alreadyFinished
        }
        try stagedPayload.commit(to: destinationURL)
        ownsStagingDirectory = false
    }
}

/// Installs only an already authenticated and fully validated portable vault.
/// The caller is responsible for deriving `localUnlockKey` from a newly chosen,
/// policy-compliant local LowKey. Portable recovery credentials never become a
/// local unlock path.
struct PortableVaultRestoreInstaller {
    private let credentialStore: any PortableVaultCredentialStoring
    private let photoDataRoot: URL

    init(
        credentialStore: any PortableVaultCredentialStoring,
        photoDataRootOverride: URL? = nil
    ) throws {
        self.credentialStore = credentialStore

        if let photoDataRootOverride {
            photoDataRoot = photoDataRootOverride.standardizedFileURL
        } else {
            let appSupport = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            photoDataRoot = appSupport
                .appendingPathComponent("KeyHollow/PhotoData", isDirectory: true)
                .standardizedFileURL
        }

        try Self.prepareProtectedRoot(photoDataRoot)
    }

    func install(
        _ restore: ValidatedPortableVaultRestore,
        localUnlockKey: SymmetricKey
    ) async throws -> UnlockedVault {
        let payload = restore.destinationVaultPayload
        let locator = VaultLocator.derive(from: localUnlockKey)
        guard !(await credentialStore.contains(locator: locator)) else {
            throw PortableVaultRestoreInstallationError.credentialAlreadyUsed
        }

        let destinationURL = photoDataRoot.appendingPathComponent(
            payload.vaultID.uuidString.lowercased(),
            isDirectory: true
        )
        guard !FileManager.default.fileExists(atPath: destinationURL.path) else {
            throw PortableVaultRestoreInstallationError.destinationExists
        }

        let envelope = try VaultEnvelope.seal(
            payload: payload,
            using: localUnlockKey
        )

        // Move the already validated ciphertext into its fresh vault directory
        // first. Only then publish the LowKey wrapper. A normal write failure
        // rolls the moved directory back so no partial vault becomes unlockable.
        try restore.commitEncryptedFiles(to: destinationURL)
        do {
            try await credentialStore.write(envelope, locator: locator)
        } catch {
            // A store can fail after its atomic write but before its protection
            // metadata is finalized. Remove both sides of the transaction.
            try? await credentialStore.delete(locator: locator)
            try? FileManager.default.removeItem(at: destinationURL)
            throw PortableVaultRestoreInstallationError.credentialCommitFailed
        }

        return UnlockedVault(
            vaultID: payload.vaultID,
            vaultKey: SymmetricKey(data: payload.vaultKey),
            createdAt: payload.createdAt
        )
    }

    private static func prepareProtectedRoot(_ root: URL) throws {
        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: root.path) {
            try fileManager.createDirectory(
                at: root,
                withIntermediateDirectories: true,
                attributes: [.protectionKey: FileProtectionType.complete]
            )
        }
        try fileManager.setAttributes(
            [.protectionKey: FileProtectionType.complete],
            ofItemAtPath: root.path
        )
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var protectedRoot = root
        try protectedRoot.setResourceValues(values)
    }
}

struct EncryptedVaultTransferCoordinator {
    /// The caller must re-authenticate the currently open vault before invoking
    /// this operation. This layer accepts only an already-unlocked vault and
    /// never enumerates any other local vault.
    func exportVault(
        unlockedVault: UnlockedVault,
        credential: PortableArchiveCredential,
        destinationURL: URL,
        sourceRootOverride: URL? = nil,
        workingRootOverride: URL? = nil,
        keyDeriver: any PortableArchiveKeyDeriving = PortableArchiveArgon2idKeyDeriver()
    ) async throws -> EncryptedVaultExportReceipt {
        guard destinationURL.pathExtension.lowercased() == "khvault" else {
            throw EncryptedVaultTransferError.invalidDestination
        }
        guard !FileManager.default.fileExists(atPath: destinationURL.path) else {
            throw PortableArchiveContainerError.destinationExists
        }

        let sourceRoot = try Self.photoRoot(
            vaultID: unlockedVault.vaultID,
            override: sourceRootOverride
        )
        guard !Self.isDescendant(destinationURL, of: sourceRoot) else {
            throw EncryptedVaultTransferError.invalidDestination
        }

        let vaultKeyData = unlockedVault.vaultKey.withUnsafeBytes { Data($0) }
        guard vaultKeyData.count == 32 else {
            throw EncryptedVaultTransferError.invalidSourceVault
        }
        let sourceStore = try VaultPhotoStore(
            vaultID: unlockedVault.vaultID,
            vaultKey: unlockedVault.vaultKey,
            storageRoot: sourceRoot
        )
        let sourceManifest = try await sourceStore.loadManifest()
        let source = try PortableArchivePayloadSource.create(
            rootURL: sourceRoot,
            manifest: sourceManifest
        )

        let prepared = try EncryptedVaultArchiveHeader.prepare(
            vaultPayload: VaultPayload(
                vaultID: unlockedVault.vaultID,
                vaultKey: vaultKeyData,
                createdAt: unlockedVault.createdAt
            ),
            credential: credential,
            keyDeriver: keyDeriver
        )

        let writer = try PortableArchiveContainerWriter(
            destinationURL: destinationURL,
            preparedArchive: prepared
        )
        var exportSucceeded = false
        defer {
            if !exportSucceeded {
                try? FileManager.default.removeItem(at: destinationURL)
            }
        }
        do {
            try PortableArchivePayloadWriter.write(source: source, to: writer)
            try writer.finish()
        } catch {
            writer.cancel()
            throw error
        }

        let verified = try await stageAndValidateRestore(
            archiveURL: destinationURL,
            credential: credential,
            workingRootOverride: workingRootOverride,
            keyDeriver: keyDeriver
        )
        defer { verified.discard() }

        guard verified.archiveID == prepared.secrets.archiveID,
              verified.sourceVaultID == unlockedVault.vaultID,
              verified.destinationVaultPayload.vaultKey == vaultKeyData,
              verified.catalog == source.catalog,
              verified.manifest.version == sourceManifest.version,
              verified.manifest.photos == sourceManifest.photos else {
            throw EncryptedVaultTransferError.archiveVerificationFailed
        }

        let attributes = try FileManager.default.attributesOfItem(atPath: destinationURL.path)
        guard let size = attributes[.size] as? NSNumber else {
            throw EncryptedVaultTransferError.archiveVerificationFailed
        }

        exportSucceeded = true
        return EncryptedVaultExportReceipt(
            archiveURL: destinationURL,
            archiveID: prepared.secrets.archiveID,
            encryptedFileCount: source.catalog.entries.count,
            archiveByteCount: size.uint64Value
        )
    }

    func stageAndValidateRestore(
        archiveURL: URL,
        credential: PortableArchiveCredential,
        workingRootOverride: URL? = nil,
        keyDeriver: any PortableArchiveKeyDeriving = PortableArchiveArgon2idKeyDeriver()
    ) async throws -> ValidatedPortableVaultRestore {
        let workingRoot = try Self.workingRoot(override: workingRootOverride)
        let stagingURL = workingRoot
            .appendingPathComponent(UUID().uuidString.lowercased(), isDirectory: true)
        let extractor = try PortableArchivePayloadExtractor(stagingURL: stagingURL)
        let reader = try PortableArchiveContainerReader(sourceURL: archiveURL)

        let secrets = try reader.streamAuthenticatedContent(
            credential: credential,
            keyDeriver: keyDeriver
        ) { chunk in
            try extractor.receive(chunk)
        }
        let stagedPayload = try extractor.finish()

        do {
            let vaultKey = SymmetricKey(data: secrets.vaultKey)
            let stagedStore = try VaultPhotoStore(
                vaultID: secrets.sourceVaultID,
                vaultKey: vaultKey,
                storageRoot: stagedPayload.directoryURL
            )
            let manifest = try await stagedStore.loadManifest()
            try Self.validate(catalog: stagedPayload.catalog, against: manifest)

            // Authenticate every inner AES-GCM blob. Decrypted media exists only
            // transiently in memory and is never written during this validation.
            for photo in manifest.photos {
                _ = try await stagedStore.loadPhoto(photo)
                _ = try await stagedStore.loadThumbnail(photo)
            }

            return ValidatedPortableVaultRestore(
                secrets: secrets,
                manifest: manifest,
                catalog: stagedPayload.catalog,
                stagedPayload: stagedPayload
            )
        } catch {
            stagedPayload.discard()
            throw error
        }
    }

    static func validate(
        catalog: PortableArchivePayloadCatalog,
        against manifest: VaultPhotoManifest
    ) throws {
        guard manifest.version == VaultPhotoManifest.currentVersion else {
            throw EncryptedVaultTransferError.restoredCatalogMismatch
        }

        var expected: [String: PortableArchivePayloadEntryRole] = [
            "manifest.khm": .manifest
        ]
        for photo in manifest.photos {
            guard expected.updateValue(.original, forKey: photo.blobName) == nil,
                  expected.updateValue(.thumbnail, forKey: photo.thumbnailName) == nil else {
                throw EncryptedVaultTransferError.restoredCatalogMismatch
            }
        }

        guard expected.count == catalog.entries.count else {
            throw EncryptedVaultTransferError.restoredCatalogMismatch
        }
        for entry in catalog.entries {
            guard expected[entry.storageName] == entry.role else {
                throw EncryptedVaultTransferError.restoredCatalogMismatch
            }
        }
    }

    private static func photoRoot(vaultID: UUID, override: URL?) throws -> URL {
        if let override { return override.standardizedFileURL }
        let appSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return appSupport
            .appendingPathComponent("KeyHollow/PhotoData", isDirectory: true)
            .appendingPathComponent(vaultID.uuidString.lowercased(), isDirectory: true)
            .standardizedFileURL
    }

    private static func workingRoot(override: URL?) throws -> URL {
        let root: URL
        if let override {
            root = override.standardizedFileURL
        } else {
            let appSupport = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            root = appSupport
                .appendingPathComponent("KeyHollow/TransferWorking", isDirectory: true)
                .standardizedFileURL
        }

        if !FileManager.default.fileExists(atPath: root.path) {
            try FileManager.default.createDirectory(
                at: root,
                withIntermediateDirectories: true,
                attributes: [.protectionKey: FileProtectionType.complete]
            )
        }
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var protectedRoot = root
        try protectedRoot.setResourceValues(values)
        return root
    }

    private static func isDescendant(_ candidate: URL, of directory: URL) -> Bool {
        var directoryPath = directory.standardizedFileURL.path
        while directoryPath.count > 1 && directoryPath.hasSuffix("/") {
            directoryPath.removeLast()
        }
        let candidatePath = candidate.standardizedFileURL.path
        return candidatePath == directoryPath || candidatePath.hasPrefix(directoryPath + "/")
    }
}
