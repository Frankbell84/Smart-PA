import CryptoKit
import Foundation
import XCTest
@testable import KeyHollow

final class EncryptedVaultTransferCoordinatorTests: XCTestCase {
    func testWholeVaultExportIsVerifiedAndSourceRemainsUnchanged() async throws {
        let roots = try TestRoots.create()
        defer { roots.remove() }

        let vaultID = UUID()
        let vaultKeyData = Data(repeating: 0x73, count: 32)
        let vaultKey = SymmetricKey(data: vaultKeyData)
        let originalOne = Data("first private original".utf8)
        let thumbnailOne = Data("first private thumbnail".utf8)
        let originalTwo = Data(repeating: 0xa6, count: 1_300_000)
        let thumbnailTwo = Data(repeating: 0xb7, count: 4_096)
        let store = try VaultPhotoStore(
            vaultID: vaultID,
            vaultKey: vaultKey,
            storageRoot: roots.source
        )
        let first = try await store.importPhoto(
            originalData: originalOne,
            thumbnailData: thumbnailOne
        )
        let second = try await store.importPhoto(
            originalData: originalTwo,
            thumbnailData: thumbnailTwo
        )
        let before = try encryptedDirectorySnapshot(roots.source)

        let credential = PortableArchiveCredential.recoveryCode(
            "0123-4567-89AB-CDEF-GHJK-MNPQ-RSTV-WXYZ"
        )
        let coordinator = EncryptedVaultTransferCoordinator()
        let receipt = try await coordinator.exportVault(
            unlockedVault: UnlockedVault(
                vaultID: vaultID,
                vaultKey: vaultKey,
                createdAt: Date(timeIntervalSince1970: 1_700_000_000)
            ),
            credential: credential,
            destinationURL: roots.archive,
            sourceRootOverride: roots.source,
            workingRootOverride: roots.working,
            keyDeriver: TestTransferKeyDeriver()
        )

        XCTAssertEqual(receipt.archiveURL, roots.archive)
        XCTAssertEqual(receipt.encryptedFileCount, 5)
        XCTAssertGreaterThan(receipt.archiveByteCount, 0)
        XCTAssertEqual(try encryptedDirectorySnapshot(roots.source), before)

        let archiveBytes = try Data(contentsOf: roots.archive)
        XCTAssertNil(archiveBytes.range(of: originalOne))
        XCTAssertNil(archiveBytes.range(of: thumbnailOne))

        let restore = try await coordinator.stageAndValidateRestore(
            archiveURL: roots.archive,
            credential: credential,
            workingRootOverride: roots.working,
            keyDeriver: TestTransferKeyDeriver()
        )
        XCTAssertEqual(restore.sourceVaultID, vaultID)
        XCTAssertNotEqual(restore.destinationVaultPayload.vaultID, vaultID)
        XCTAssertEqual(restore.destinationVaultPayload.vaultKey, vaultKeyData)

        let restoredStore = try VaultPhotoStore(
            vaultID: restore.destinationVaultPayload.vaultID,
            vaultKey: vaultKey,
            storageRoot: restore.stagingURL
        )
        let reopenedOriginalOne = try await restoredStore.loadPhoto(first)
        let reopenedThumbnailOne = try await restoredStore.loadThumbnail(first)
        let reopenedOriginalTwo = try await restoredStore.loadPhoto(second)
        let reopenedThumbnailTwo = try await restoredStore.loadThumbnail(second)
        XCTAssertEqual(reopenedOriginalOne, originalOne)
        XCTAssertEqual(reopenedThumbnailOne, thumbnailOne)
        XCTAssertEqual(reopenedOriginalTwo, originalTwo)
        XCTAssertEqual(reopenedThumbnailTwo, thumbnailTwo)

        let stagingURL = restore.stagingURL
        restore.discard()
        XCTAssertFalse(FileManager.default.fileExists(atPath: stagingURL.path))
    }

    func testWrongRecoveryCodeLeavesNoStagedVault() async throws {
        let roots = try TestRoots.create()
        defer { roots.remove() }
        let fixture = try await createArchive(at: roots)

        let coordinator = EncryptedVaultTransferCoordinator()
        await XCTAssertThrowsErrorAsync {
            _ = try await coordinator.stageAndValidateRestore(
                archiveURL: roots.archive,
                credential: .recoveryCode("1123-4567-89AB-CDEF-GHJK-MNPQ-RSTV-WXYZ"),
                workingRootOverride: roots.working,
                keyDeriver: TestTransferKeyDeriver()
            )
        }

        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: roots.working.path).isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.archiveURL.path))
    }

    func testCorruptedSourceCannotProduceVerifiedExport() async throws {
        let roots = try TestRoots.create()
        defer { roots.remove() }

        let vaultID = UUID()
        let key = SymmetricKey(size: .bits256)
        let store = try VaultPhotoStore(
            vaultID: vaultID,
            vaultKey: key,
            storageRoot: roots.source
        )
        let record = try await store.importPhoto(
            originalData: Data("original".utf8),
            thumbnailData: Data("thumbnail".utf8)
        )
        let sourceBeforeCorruption = try encryptedDirectorySnapshot(roots.source)
        let blobURL = roots.source.appendingPathComponent(record.blobName)
        var corrupted = try Data(contentsOf: blobURL)
        corrupted[corrupted.index(before: corrupted.endIndex)] ^= 0x01
        try corrupted.write(to: blobURL, options: .atomic)
        let corruptedSnapshot = try encryptedDirectorySnapshot(roots.source)
        XCTAssertNotEqual(corruptedSnapshot, sourceBeforeCorruption)

        let coordinator = EncryptedVaultTransferCoordinator()
        await XCTAssertThrowsErrorAsync {
            _ = try await coordinator.exportVault(
                unlockedVault: UnlockedVault(
                    vaultID: vaultID,
                    vaultKey: key,
                    createdAt: Date(timeIntervalSince1970: 1_700_000_000)
                ),
                credential: .passphrase("correct horse battery staple"),
                destinationURL: roots.archive,
                sourceRootOverride: roots.source,
                workingRootOverride: roots.working,
                keyDeriver: TestTransferKeyDeriver()
            )
        }

        XCTAssertFalse(FileManager.default.fileExists(atPath: roots.archive.path))
        XCTAssertEqual(try encryptedDirectorySnapshot(roots.source), corruptedSnapshot)
    }

    func testArchiveCannotBeWrittenInsideSourceVaultDirectory() async throws {
        let roots = try TestRoots.create()
        defer { roots.remove() }
        let vaultID = UUID()
        let key = SymmetricKey(size: .bits256)
        let store = try VaultPhotoStore(
            vaultID: vaultID,
            vaultKey: key,
            storageRoot: roots.source
        )
        _ = try await store.importPhoto(
            originalData: Data("original".utf8),
            thumbnailData: Data("thumbnail".utf8)
        )
        let unsafeDestination = roots.source.appendingPathComponent("backup.khvault")

        let coordinator = EncryptedVaultTransferCoordinator()
        await XCTAssertThrowsErrorAsync {
            _ = try await coordinator.exportVault(
                unlockedVault: UnlockedVault(
                    vaultID: vaultID,
                    vaultKey: key,
                    createdAt: Date()
                ),
                credential: .passphrase("correct horse battery staple"),
                destinationURL: unsafeDestination,
                sourceRootOverride: roots.source,
                workingRootOverride: roots.working,
                keyDeriver: TestTransferKeyDeriver()
            )
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: unsafeDestination.path))
    }

    func testValidatedRestoreInstallsWithFreshIdentityAndLocalWrapper() async throws {
        let roots = try TestRoots.create()
        defer { roots.remove() }
        let fixture = try await createArchive(at: roots)
        let coordinator = EncryptedVaultTransferCoordinator()
        let restore = try await coordinator.stageAndValidateRestore(
            archiveURL: fixture.archiveURL,
            credential: .recoveryCode("0123-4567-89AB-CDEF-GHJK-MNPQ-RSTV-WXYZ"),
            workingRootOverride: roots.working,
            keyDeriver: TestTransferKeyDeriver()
        )
        let stagingURL = restore.stagingURL
        let localUnlockKey = SymmetricKey(data: Data(repeating: 0x42, count: 32))
        let credentialStore = TestPortableVaultCredentialStore()
        let installer = try PortableVaultRestoreInstaller(
            credentialStore: credentialStore,
            journalAuthenticationKey: testRestoreJournalKey,
            journalRootOverride: roots.transactions,
            photoDataRootOverride: roots.installed
        )

        let installed = try await installer.install(
            restore,
            localUnlockKey: localUnlockKey
        )

        XCTAssertNotEqual(installed.vaultID, restore.sourceVaultID)
        XCTAssertEqual(installed.vaultID, restore.destinationVaultPayload.vaultID)
        XCTAssertFalse(FileManager.default.fileExists(atPath: stagingURL.path))

        let destinationURL = roots.installed.appendingPathComponent(
            installed.vaultID.uuidString.lowercased(),
            isDirectory: true
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: destinationURL.path))
        let installedStore = try VaultPhotoStore(
            vaultID: installed.vaultID,
            vaultKey: installed.vaultKey,
            storageRoot: destinationURL
        )
        let manifest = try await installedStore.loadManifest()
        XCTAssertEqual(manifest.photos.count, 1)

        let locator = VaultLocator.derive(from: localUnlockKey)
        let storedEnvelope = await credentialStore.envelope(for: locator)
        let storedPayload = try XCTUnwrap(storedEnvelope).open(using: localUnlockKey)
        XCTAssertEqual(storedPayload.vaultID, installed.vaultID)
        XCTAssertEqual(storedPayload.vaultKey, restore.destinationVaultPayload.vaultKey)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: roots.transactions.path).isEmpty)
    }

    func testUsedLocalLowKeyDoesNotConsumeValidatedRestore() async throws {
        let roots = try TestRoots.create()
        defer { roots.remove() }
        let fixture = try await createArchive(at: roots)
        let restore = try await EncryptedVaultTransferCoordinator().stageAndValidateRestore(
            archiveURL: fixture.archiveURL,
            credential: .recoveryCode("0123-4567-89AB-CDEF-GHJK-MNPQ-RSTV-WXYZ"),
            workingRootOverride: roots.working,
            keyDeriver: TestTransferKeyDeriver()
        )
        let localUnlockKey = SymmetricKey(data: Data(repeating: 0x24, count: 32))
        let locator = VaultLocator.derive(from: localUnlockKey)
        let credentialStore = TestPortableVaultCredentialStore(existingLocators: [locator])
        let installer = try PortableVaultRestoreInstaller(
            credentialStore: credentialStore,
            journalAuthenticationKey: testRestoreJournalKey,
            journalRootOverride: roots.transactions,
            photoDataRootOverride: roots.installed
        )

        await XCTAssertThrowsErrorAsync {
            _ = try await installer.install(restore, localUnlockKey: localUnlockKey)
        }

        XCTAssertTrue(FileManager.default.fileExists(atPath: restore.stagingURL.path))
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: roots.installed.path).isEmpty)
        restore.discard()
    }

    func testCredentialWriteFailureRollsBackCommittedCiphertext() async throws {
        let roots = try TestRoots.create()
        defer { roots.remove() }
        let fixture = try await createArchive(at: roots)
        let restore = try await EncryptedVaultTransferCoordinator().stageAndValidateRestore(
            archiveURL: fixture.archiveURL,
            credential: .recoveryCode("0123-4567-89AB-CDEF-GHJK-MNPQ-RSTV-WXYZ"),
            workingRootOverride: roots.working,
            keyDeriver: TestTransferKeyDeriver()
        )
        let destinationURL = roots.installed.appendingPathComponent(
            restore.destinationVaultPayload.vaultID.uuidString.lowercased(),
            isDirectory: true
        )
        let credentialStore = TestPortableVaultCredentialStore(failAfterWrite: true)
        let localUnlockKey = SymmetricKey(data: Data(repeating: 0x66, count: 32))
        let locator = VaultLocator.derive(from: localUnlockKey)
        let installer = try PortableVaultRestoreInstaller(
            credentialStore: credentialStore,
            journalAuthenticationKey: testRestoreJournalKey,
            journalRootOverride: roots.transactions,
            photoDataRootOverride: roots.installed
        )

        await XCTAssertThrowsErrorAsync {
            _ = try await installer.install(
                restore,
                localUnlockKey: localUnlockKey
            )
        }

        XCTAssertFalse(FileManager.default.fileExists(atPath: destinationURL.path))
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: roots.installed.path).isEmpty)
        let rolledBackEnvelope = await credentialStore.envelope(for: locator)
        XCTAssertNil(rolledBackEnvelope)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: roots.transactions.path).isEmpty)
    }

    func testStartupRecoveryRollsBackInterruptedCredentialAndCiphertext() async throws {
        let roots = try TestRoots.create()
        defer { roots.remove() }
        let credentialStore = TestPortableVaultCredentialStore()
        let localUnlockKey = SymmetricKey(data: Data(repeating: 0x91, count: 32))
        let locator = VaultLocator.derive(from: localUnlockKey)
        let destinationVaultID = UUID()
        let payload = VaultPayload(
            vaultID: destinationVaultID,
            vaultKey: Data(repeating: 0x51, count: 32),
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let envelope = try VaultEnvelope.seal(
            payload: payload,
            using: localUnlockKey
        )
        let journal = try PortableVaultRestoreTransactionJournal(
            authenticationKey: testRestoreJournalKey,
            journalRootOverride: roots.transactions,
            photoDataRootOverride: roots.installed
        )
        _ = try journal.begin(
            destinationVaultID: destinationVaultID,
            credentialLocator: locator,
            credentialEnvelope: envelope
        )

        let destinationURL = roots.installed.appendingPathComponent(
            destinationVaultID.uuidString.lowercased(),
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: destinationURL,
            withIntermediateDirectories: false
        )
        try Data("interrupted encrypted payload".utf8).write(
            to: destinationURL.appendingPathComponent("manifest.khm")
        )
        try await credentialStore.writeIfAbsent(
            envelope,
            locator: locator
        )

        try await journal.recoverAll(credentialStore: credentialStore)

        XCTAssertFalse(FileManager.default.fileExists(atPath: destinationURL.path))
        let recoveredEnvelope = await credentialStore.envelope(for: locator)
        XCTAssertNil(recoveredEnvelope)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: roots.transactions.path).isEmpty)
    }

    func testFreshLaunchDoesNotCreateRestoreJournalUntilARecoveryIsPending() throws {
        let roots = try TestRoots.create()
        defer { roots.remove() }

        XCTAssertFalse(
            try PortableVaultRestoreTransactionJournal.recoveryRequired(
                journalRootOverride: roots.transactions
            )
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: roots.transactions.path))

        try FileManager.default.createDirectory(
            at: roots.transactions,
            withIntermediateDirectories: true
        )
        XCTAssertFalse(
            try PortableVaultRestoreTransactionJournal.recoveryRequired(
                journalRootOverride: roots.transactions
            )
        )

        try Data("pending authenticated transaction".utf8).write(
            to: roots.transactions.appendingPathComponent("pending.khtxn")
        )
        XCTAssertTrue(
            try PortableVaultRestoreTransactionJournal.recoveryRequired(
                journalRootOverride: roots.transactions
            )
        )

        try FileManager.default.removeItem(
            at: roots.transactions.appendingPathComponent("pending.khtxn")
        )
        try Data("unexpected hidden file".utf8).write(
            to: roots.transactions.appendingPathComponent(".unexpected")
        )
        XCTAssertTrue(
            try PortableVaultRestoreTransactionJournal.recoveryRequired(
                journalRootOverride: roots.transactions
            )
        )
    }

    func testTamperedRecoveryJournalFailsClosedWithoutDeletingVaultMaterial() async throws {
        let roots = try TestRoots.create()
        defer { roots.remove() }
        let credentialStore = TestPortableVaultCredentialStore()
        let localUnlockKey = SymmetricKey(data: Data(repeating: 0x92, count: 32))
        let locator = VaultLocator.derive(from: localUnlockKey)
        let destinationVaultID = UUID()
        let payload = VaultPayload(
            vaultID: destinationVaultID,
            vaultKey: Data(repeating: 0x52, count: 32),
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let envelope = try VaultEnvelope.seal(
            payload: payload,
            using: localUnlockKey
        )
        let journal = try PortableVaultRestoreTransactionJournal(
            authenticationKey: testRestoreJournalKey,
            journalRootOverride: roots.transactions,
            photoDataRootOverride: roots.installed
        )
        _ = try journal.begin(
            destinationVaultID: destinationVaultID,
            credentialLocator: locator,
            credentialEnvelope: envelope
        )

        let journalURL = try XCTUnwrap(
            FileManager.default.contentsOfDirectory(
                at: roots.transactions,
                includingPropertiesForKeys: nil
            ).first
        )
        var tamperedJournal = try Data(contentsOf: journalURL)
        tamperedJournal[tamperedJournal.index(before: tamperedJournal.endIndex)] ^= 0x01
        try tamperedJournal.write(to: journalURL, options: .atomic)

        let destinationURL = roots.installed.appendingPathComponent(
            destinationVaultID.uuidString.lowercased(),
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: destinationURL,
            withIntermediateDirectories: false
        )
        try await credentialStore.writeIfAbsent(
            envelope,
            locator: locator
        )

        await XCTAssertThrowsErrorAsync {
            try await journal.recoverAll(credentialStore: credentialStore)
        }

        XCTAssertTrue(FileManager.default.fileExists(atPath: destinationURL.path))
        let untouchedEnvelope = await credentialStore.envelope(for: locator)
        XCTAssertNotNil(untouchedEnvelope)
        XCTAssertTrue(FileManager.default.fileExists(atPath: journalURL.path))
    }

    func testRecoveryNeverDeletesDifferentEnvelopeAtSameLocator() async throws {
        let roots = try TestRoots.create()
        defer { roots.remove() }
        let credentialStore = TestPortableVaultCredentialStore()
        let localUnlockKey = SymmetricKey(data: Data(repeating: 0x93, count: 32))
        let locator = VaultLocator.derive(from: localUnlockKey)
        let interruptedVaultID = UUID()
        let interruptedEnvelope = try VaultEnvelope.seal(
            payload: VaultPayload(
                vaultID: interruptedVaultID,
                vaultKey: Data(repeating: 0x53, count: 32),
                createdAt: Date(timeIntervalSince1970: 1_700_000_000)
            ),
            using: localUnlockKey
        )
        let journal = try PortableVaultRestoreTransactionJournal(
            authenticationKey: testRestoreJournalKey,
            journalRootOverride: roots.transactions,
            photoDataRootOverride: roots.installed
        )
        _ = try journal.begin(
            destinationVaultID: interruptedVaultID,
            credentialLocator: locator,
            credentialEnvelope: interruptedEnvelope
        )

        let unrelatedEnvelope = try VaultEnvelope.seal(
            payload: VaultPayload(
                vaultID: UUID(),
                vaultKey: Data(repeating: 0x54, count: 32),
                createdAt: Date(timeIntervalSince1970: 1_700_000_001)
            ),
            using: localUnlockKey
        )
        try await credentialStore.writeIfAbsent(unrelatedEnvelope, locator: locator)

        let destinationURL = roots.installed.appendingPathComponent(
            interruptedVaultID.uuidString.lowercased(),
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: destinationURL,
            withIntermediateDirectories: false
        )

        try await journal.recoverAll(credentialStore: credentialStore)

        let preservedEnvelopeValue = await credentialStore.envelope(for: locator)
        let preservedEnvelope = try XCTUnwrap(preservedEnvelopeValue)
        XCTAssertEqual(preservedEnvelope.version, unrelatedEnvelope.version)
        XCTAssertEqual(preservedEnvelope.sealedPayload, unrelatedEnvelope.sealedPayload)
        XCTAssertFalse(FileManager.default.fileExists(atPath: destinationURL.path))
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: roots.transactions.path).isEmpty)
    }

    func testCredentialCreateIfAbsentNeverOverwritesExistingVault() async throws {
        let roots = try TestRoots.create()
        defer { roots.remove() }
        let credentialRoot = roots.parent.appendingPathComponent(
            "credential-store",
            isDirectory: true
        )
        let store = try VaultStore(rootOverride: credentialRoot)
        let unlockKey = SymmetricKey(data: Data(repeating: 0x94, count: 32))
        let locator = VaultLocator.derive(from: unlockKey)
        let first = try VaultEnvelope.seal(
            payload: VaultPayload(
                vaultID: UUID(),
                vaultKey: Data(repeating: 0x55, count: 32),
                createdAt: Date(timeIntervalSince1970: 1_700_000_000)
            ),
            using: unlockKey
        )
        let second = try VaultEnvelope.seal(
            payload: VaultPayload(
                vaultID: UUID(),
                vaultKey: Data(repeating: 0x56, count: 32),
                createdAt: Date(timeIntervalSince1970: 1_700_000_001)
            ),
            using: unlockKey
        )

        try await store.writeIfAbsent(first, locator: locator)
        await XCTAssertThrowsErrorAsync {
            try await store.writeIfAbsent(second, locator: locator)
        }

        let preservedValue = try await store.read(locator: locator)
        let preserved = try XCTUnwrap(preservedValue)
        XCTAssertEqual(preserved.version, first.version)
        XCTAssertEqual(preserved.sealedPayload, first.sealedPayload)
    }

    func testIncompleteStartupRollbackKeepsJournalForRetry() async throws {
        let roots = try TestRoots.create()
        defer { roots.remove() }
        let credentialStore = TestPortableVaultCredentialStore(failDeletes: true)
        let localUnlockKey = SymmetricKey(data: Data(repeating: 0x95, count: 32))
        let locator = VaultLocator.derive(from: localUnlockKey)
        let destinationVaultID = UUID()
        let envelope = try VaultEnvelope.seal(
            payload: VaultPayload(
                vaultID: destinationVaultID,
                vaultKey: Data(repeating: 0x57, count: 32),
                createdAt: Date(timeIntervalSince1970: 1_700_000_000)
            ),
            using: localUnlockKey
        )
        let journal = try PortableVaultRestoreTransactionJournal(
            authenticationKey: testRestoreJournalKey,
            journalRootOverride: roots.transactions,
            photoDataRootOverride: roots.installed
        )
        _ = try journal.begin(
            destinationVaultID: destinationVaultID,
            credentialLocator: locator,
            credentialEnvelope: envelope
        )
        try await credentialStore.writeIfAbsent(envelope, locator: locator)

        await XCTAssertThrowsErrorAsync {
            try await journal.recoverAll(credentialStore: credentialStore)
        }

        let retainedEnvelope = await credentialStore.envelope(for: locator)
        XCTAssertNotNil(retainedEnvelope)
        XCTAssertEqual(
            try FileManager.default.contentsOfDirectory(atPath: roots.transactions.path).count,
            1
        )
    }

    func testVaultStoreStartupRemovesOnlyAbandonedPendingCredentials() async throws {
        let roots = try TestRoots.create()
        defer { roots.remove() }
        let credentialRoot = roots.parent.appendingPathComponent(
            "credential-cleanup",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: credentialRoot,
            withIntermediateDirectories: false
        )
        let pending = credentialRoot.appendingPathComponent(
            ".pending-interrupted.khvtmp"
        )
        let unrelated = credentialRoot.appendingPathComponent("keep-this-file")
        try Data("pending credential".utf8).write(to: pending)
        try Data("unrelated".utf8).write(to: unrelated)

        _ = try VaultStore(rootOverride: credentialRoot)

        XCTAssertFalse(FileManager.default.fileExists(atPath: pending.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: unrelated.path))
    }

    private func createArchive(at roots: TestRoots) async throws -> EncryptedVaultExportReceipt {
        let vaultID = UUID()
        let key = SymmetricKey(size: .bits256)
        let store = try VaultPhotoStore(
            vaultID: vaultID,
            vaultKey: key,
            storageRoot: roots.source
        )
        _ = try await store.importPhoto(
            originalData: Data("original".utf8),
            thumbnailData: Data("thumbnail".utf8)
        )
        return try await EncryptedVaultTransferCoordinator().exportVault(
            unlockedVault: UnlockedVault(
                vaultID: vaultID,
                vaultKey: key,
                createdAt: Date(timeIntervalSince1970: 1_700_000_000)
            ),
            credential: .recoveryCode("0123-4567-89AB-CDEF-GHJK-MNPQ-RSTV-WXYZ"),
            destinationURL: roots.archive,
            sourceRootOverride: roots.source,
            workingRootOverride: roots.working,
            keyDeriver: TestTransferKeyDeriver()
        )
    }

    private func encryptedDirectorySnapshot(_ root: URL) throws -> [String: Data] {
        let urls = try FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: nil
        )
        return try Dictionary(uniqueKeysWithValues: urls.map { url in
            (url.lastPathComponent, try Data(contentsOf: url))
        })
    }
}

private struct TestTransferKeyDeriver: PortableArchiveKeyDeriving {
    func deriveWrappingKey(
        credential: PortableArchiveCredential,
        parameters: PortableArchiveKDFParameters
    ) throws -> SymmetricKey {
        try parameters.validate()
        var input = try credential.keyMaterial()
        input.append(parameters.salt)
        return SymmetricKey(data: SHA256.hash(data: input))
    }
}

private struct TestRoots {
    let parent: URL
    let source: URL
    let working: URL
    let installed: URL
    let transactions: URL
    let archive: URL

    static func create() throws -> TestRoots {
        let parent = FileManager.default.temporaryDirectory
            .appendingPathComponent("KeyHollowTransferTests-\(UUID().uuidString)", isDirectory: true)
        let source = parent.appendingPathComponent("source", isDirectory: true)
        let working = parent.appendingPathComponent("working", isDirectory: true)
        let installed = parent.appendingPathComponent("installed", isDirectory: true)
        let transactions = parent.appendingPathComponent("transactions", isDirectory: true)
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        return TestRoots(
            parent: parent,
            source: source,
            working: working,
            installed: installed,
            transactions: transactions,
            archive: parent.appendingPathComponent("transfer.khvault")
        )
    }

    func remove() {
        try? FileManager.default.removeItem(at: parent)
    }
}

private let testRestoreJournalKey = SymmetricKey(
    data: Data(repeating: 0xc4, count: 32)
)

private actor TestPortableVaultCredentialStore: PortableVaultCredentialStoring {
    enum StoreError: Error {
        case forcedFailure
    }

    private let existingLocators: Set<String>
    private let failAfterWrite: Bool
    private let failDeletes: Bool
    private var envelopes: [String: VaultEnvelope] = [:]

    init(
        existingLocators: Set<String> = [],
        failAfterWrite: Bool = false,
        failDeletes: Bool = false
    ) {
        self.existingLocators = existingLocators
        self.failAfterWrite = failAfterWrite
        self.failDeletes = failDeletes
    }

    func contains(locator: String) -> Bool {
        existingLocators.contains(locator) || envelopes[locator] != nil
    }

    func writeIfAbsent(_ envelope: VaultEnvelope, locator: String) throws {
        guard envelopes[locator] == nil,
              !existingLocators.contains(locator) else {
            throw StoreError.forcedFailure
        }
        envelopes[locator] = envelope
        if failAfterWrite {
            throw StoreError.forcedFailure
        }
    }

    func read(locator: String) -> VaultEnvelope? {
        envelopes[locator]
    }

    func delete(locator: String) throws {
        if failDeletes {
            throw StoreError.forcedFailure
        }
        envelopes.removeValue(forKey: locator)
    }

    func envelope(for locator: String) -> VaultEnvelope? {
        envelopes[locator]
    }
}

private func XCTAssertThrowsErrorAsync(
    _ operation: () async throws -> Void,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        try await operation()
        XCTFail("Expected expression to throw", file: file, line: line)
    } catch {}
}
