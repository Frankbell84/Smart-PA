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
    let archive: URL

    static func create() throws -> TestRoots {
        let parent = FileManager.default.temporaryDirectory
            .appendingPathComponent("KeyHollowTransferTests-\(UUID().uuidString)", isDirectory: true)
        let source = parent.appendingPathComponent("source", isDirectory: true)
        let working = parent.appendingPathComponent("working", isDirectory: true)
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        return TestRoots(
            parent: parent,
            source: source,
            working: working,
            archive: parent.appendingPathComponent("transfer.khvault")
        )
    }

    func remove() {
        try? FileManager.default.removeItem(at: parent)
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
