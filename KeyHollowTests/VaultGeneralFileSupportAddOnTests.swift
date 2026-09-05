import CryptoKit
import Foundation
import XCTest
@testable import KeyHollow
import KeyHollowCryptoCore
import KeyHollowGeneralFileSupportAddOn

final class VaultGeneralFileSupportAddOnTests: XCTestCase {
    func testPrimaryVaultIsNotEmptyWhenOnlyGeneralFilesExist() {
        XCTAssertFalse(VaultContentAvailability.isEmpty(photoCount: 0, generalFileCount: 1))
        XCTAssertFalse(VaultContentAvailability.isEmpty(photoCount: 1, generalFileCount: 0))
        XCTAssertFalse(VaultContentAvailability.isEmpty(photoCount: 1, generalFileCount: 1))
        XCTAssertTrue(VaultContentAvailability.isEmpty(photoCount: 0, generalFileCount: 0))
    }

    func testBatchImportEncryptsSelectionAndLeavesSourcesUntouched() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let firstData = Data("pdf data".utf8)
        let secondData = Data("private notes".utf8)
        let first = try fixture.source(named: "Invoice.pdf", data: firstData)
        let second = try fixture.source(named: "Notes.txt", data: secondData)

        let result = try await fixture.store.importFiles(at: [first, second])
        let manifest = try await fixture.store.loadManifest()

        XCTAssertEqual(result, VaultGeneralFileImportResult(importedCount: 2, failedCount: 0))
        XCTAssertEqual(Set(manifest.files.map(\.displayName)), Set(["Invoice.pdf", "Notes.txt"]))
        XCTAssertEqual(try Data(contentsOf: first), firstData)
        XCTAssertEqual(try Data(contentsOf: second), secondData)
    }

    func testBatchImportReportsRejectedItemsWithoutRollingBackValidFiles() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let valid = try fixture.source(named: "Notes.txt", data: Data("notes".utf8))
        let rejected = try fixture.source(named: "Backup.khvault", data: Data("backup".utf8))

        let result = try await fixture.store.importFiles(at: [valid, rejected])
        let manifest = try await fixture.store.loadManifest()

        XCTAssertEqual(result, VaultGeneralFileImportResult(importedCount: 1, failedCount: 1))
        XCTAssertEqual(manifest.files.map(\.displayName), ["Notes.txt"])
    }

    func testBatchImportRejectsMoreThanMaximumSelection() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let source = try fixture.source(named: "Notes.txt", data: Data("notes".utf8))
        let selection = Array(
            repeating: source,
            count: VaultGeneralFileStore.maximumBatchCount + 1
        )

        await XCTAssertThrowsErrorAsync(try await fixture.store.importFiles(at: selection)) {
            XCTAssertEqual($0 as? VaultGeneralFileStore.StoreError, .batchTooLarge)
        }
        let manifest = try await fixture.store.loadManifest()
        XCTAssertTrue(manifest.files.isEmpty)
    }

    func testImportEncryptsFileAndLeavesSourceUntouched() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let source = try fixture.source(named: "Tax Notes.txt", data: Data("private notes".utf8))

        let record = try await fixture.store.importFile(at: source)
        let manifest = try await fixture.store.loadManifest()

        XCTAssertEqual(manifest.files, [record])
        XCTAssertEqual(record.displayName, "Tax Notes.txt")
        XCTAssertEqual(record.originalByteCount, 13)
        XCTAssertEqual(try Data(contentsOf: source), Data("private notes".utf8))

        let encryptedBlob = try Data(
            contentsOf: fixture.storageRoot.appendingPathComponent(record.blobName)
        )
        XCTAssertNotEqual(encryptedBlob, Data("private notes".utf8))
        XCTAssertFalse(String(decoding: encryptedBlob, as: UTF8.self).contains("private notes"))
    }

    func testExportAuthenticatesAndRestoresOriginalBytes() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let original = Data([0, 1, 2, 3, 254, 255])
        let source = try fixture.source(named: "document.bin", data: original)
        let record = try await fixture.store.importFile(at: source)

        let export = try await fixture.store.prepareExport([record])

        XCTAssertEqual(export.urls.count, 1)
        XCTAssertEqual(export.urls[0].lastPathComponent, "document.bin")
        XCTAssertEqual(try Data(contentsOf: export.urls[0]), original)
        await fixture.store.discardExport(export)
    }

    func testTamperedBlobCannotBeExported() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let source = try fixture.source(named: "document.pdf", data: Data("pdf data".utf8))
        let record = try await fixture.store.importFile(at: source)
        let blobURL = fixture.storageRoot.appendingPathComponent(record.blobName)
        var ciphertext = try Data(contentsOf: blobURL)
        ciphertext[ciphertext.startIndex] ^= 0x01
        try ciphertext.write(to: blobURL, options: .atomic)

        do {
            _ = try await fixture.store.prepareExport([record])
            XCTFail("Tampered authenticated data must not be exported")
        } catch {
            XCTAssertNotNil(error)
        }
    }

    func testDeleteCommitsManifestBeforeRemovingBlob() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let source = try fixture.source(named: "notes.txt", data: Data("notes".utf8))
        let record = try await fixture.store.importFile(at: source)
        let blobURL = fixture.storageRoot.appendingPathComponent(record.blobName)
        XCTAssertTrue(FileManager.default.fileExists(atPath: blobURL.path))

        try await fixture.store.delete([record])

        let manifest = try await fixture.store.loadManifest()
        XCTAssertTrue(manifest.files.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: blobURL.path))
        XCTAssertEqual(try Data(contentsOf: source), Data("notes".utf8))
    }

    func testBackupAndExecutableTypesAreRejected() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let backup = try fixture.source(named: "backup.khvault", data: Data("backup".utf8))
        let executable = try fixture.source(named: "installer.exe", data: Data("binary".utf8))

        await XCTAssertThrowsErrorAsync(try await fixture.store.importFile(at: backup)) {
            XCTAssertEqual($0 as? VaultGeneralFileStore.StoreError, .protectedFileType)
        }
        await XCTAssertThrowsErrorAsync(try await fixture.store.importFile(at: executable)) {
            XCTAssertEqual($0 as? VaultGeneralFileStore.StoreError, .protectedFileType)
        }
        let manifest = try await fixture.store.loadManifest()
        XCTAssertTrue(manifest.files.isEmpty)
    }

    func testEmptyFilesAreRejectedWithoutChangingManifest() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let source = try fixture.source(named: "empty.txt", data: Data())

        await XCTAssertThrowsErrorAsync(try await fixture.store.importFile(at: source)) {
            XCTAssertEqual($0 as? VaultGeneralFileStore.StoreError, .emptyFile)
        }
        let manifest = try await fixture.store.loadManifest()
        XCTAssertTrue(manifest.files.isEmpty)
    }

    func testAccessMustBelongToSameVault() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "GeneralFileMismatch-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let access = TestAccess(vaultID: UUID())

        XCTAssertThrowsError(
            try VaultGeneralFileStore(vaultID: UUID(), access: access, storageRoot: root)
        ) { error in
            XCTAssertEqual(error as? VaultGeneralFileStore.StoreError, .accessMismatch)
        }
    }

    func testDestroyVaultDataRemovesOnlyRequestedVaultDirectory() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "GeneralFileDestroyTests-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let firstID = UUID()
        let secondID = UUID()
        let first = root.appendingPathComponent(firstID.uuidString.lowercased(), isDirectory: true)
        let second = root.appendingPathComponent(secondID.uuidString.lowercased(), isDirectory: true)
        try FileManager.default.createDirectory(at: first, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: second, withIntermediateDirectories: true)

        try VaultGeneralFileStore.destroyVaultData(vaultID: firstID, storageRoot: root)

        XCTAssertFalse(FileManager.default.fileExists(atPath: first.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: second.path))
    }

    func testOpeningStorePurgesInterruptedPlaintextStaging() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "GeneralFileStagingCleanupTests-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let temporaryRoot = root.appendingPathComponent("Temporary", isDirectory: true)
        let importRoot = temporaryRoot
            .appendingPathComponent("KeyHollowGeneralFileImports", isDirectory: true)
            .appendingPathComponent("interrupted-import", isDirectory: true)
        let exportRoot = temporaryRoot
            .appendingPathComponent("KeyHollowGeneralFileExports", isDirectory: true)
            .appendingPathComponent("interrupted-export", isDirectory: true)
        try FileManager.default.createDirectory(at: importRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: exportRoot, withIntermediateDirectories: true)
        try Data("import plaintext".utf8).write(
            to: importRoot.appendingPathComponent("incoming")
        )
        try Data("export plaintext".utf8).write(
            to: exportRoot.appendingPathComponent("document.txt")
        )

        let vaultID = UUID()
        _ = try VaultGeneralFileStore(
            vaultID: vaultID,
            access: TestAccess(vaultID: vaultID),
            storageRoot: root.appendingPathComponent("Store", isDirectory: true),
            temporaryRoot: temporaryRoot
        )

        XCTAssertFalse(FileManager.default.fileExists(atPath: importRoot.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: exportRoot.path))
    }
}

private struct Fixture {
    let root: URL
    let sourceRoot: URL
    let storageRoot: URL
    let store: VaultGeneralFileStore

    init() throws {
        let vaultID = UUID()
        root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "GeneralFileSupportTests-\(UUID().uuidString)",
            isDirectory: true
        )
        sourceRoot = root.appendingPathComponent("Source", isDirectory: true)
        storageRoot = root.appendingPathComponent("Store", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceRoot, withIntermediateDirectories: true)
        store = try VaultGeneralFileStore(
            vaultID: vaultID,
            access: TestAccess(vaultID: vaultID),
            storageRoot: storageRoot,
            temporaryRoot: root.appendingPathComponent("Temporary", isDirectory: true)
        )
    }

    func source(named name: String, data: Data) throws -> URL {
        let url = sourceRoot.appendingPathComponent(name)
        try data.write(to: url, options: .atomic)
        return url
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: root)
    }
}

private final class TestAccess: VaultGeneralFileCryptographicAccess, @unchecked Sendable {
    let vaultID: UUID
    private let key = SymmetricKey(size: .bits256)

    init(vaultID: UUID) {
        self.vaultID = vaultID
    }

    func seal(_ plaintext: Data, for purpose: VaultGeneralFileKeyPurpose) throws -> Data {
        try CryptoBox.seal(plaintext, using: derivedKey(for: purpose))
    }

    func open(_ ciphertext: Data, for purpose: VaultGeneralFileKeyPurpose) throws -> Data {
        try CryptoBox.open(ciphertext, using: derivedKey(for: purpose))
    }

    private func derivedKey(for purpose: VaultGeneralFileKeyPurpose) -> SymmetricKey {
        let domain: String
        switch purpose {
        case .manifest:
            domain = "manifest"
        case .file(let id):
            domain = "file.\(id.uuidString.lowercased())"
        }
        return HKDF<SHA256>.deriveKey(
            inputKeyMaterial: key,
            salt: Data(domain.utf8),
            info: Data(),
            outputByteCount: 32
        )
    }
}

private func XCTAssertThrowsErrorAsync<T>(
    _ expression: @autoclosure () async throws -> T,
    _ errorHandler: (Error) -> Void = { _ in }
) async {
    do {
        _ = try await expression()
        XCTFail("Expected expression to throw")
    } catch {
        errorHandler(error)
    }
}
