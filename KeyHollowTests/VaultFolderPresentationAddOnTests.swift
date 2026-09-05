import CryptoKit
import Foundation
import XCTest
import KeyHollowCryptoCore
@testable import KeyHollowFolderPresentationAddOn

final class VaultFolderPresentationAddOnTests: XCTestCase {
    func testFolderLifecycleMovesReferencesWithoutOwningContent() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let item = VaultPresentedContentReference(kind: .generalFile, id: UUID())

        let folder = try await fixture.store.createFolder(named: "  Contracts  ")
        XCTAssertEqual(folder.name, "Contracts")
        try await fixture.store.move(item, to: folder.id)
        let assignedFolderID = try await fixture.store.folderID(for: item)
        XCTAssertEqual(assignedFolderID, folder.id)

        try await fixture.store.renameFolder(id: folder.id, to: "Legal")
        let renamedManifest = try await fixture.store.loadManifest()
        XCTAssertEqual(renamedManifest.folders.first?.name, "Legal")

        try await fixture.store.deleteFolder(id: folder.id)
        let deletedFolderID = try await fixture.store.folderID(for: item)
        let deletedManifest = try await fixture.store.loadManifest()
        XCTAssertNil(deletedFolderID)
        XCTAssertTrue(deletedManifest.folders.isEmpty)
    }

    func testMovingBetweenFoldersAndRootKeepsAtMostOneMembership() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let item = VaultPresentedContentReference(kind: .photo, id: UUID())
        let first = try await fixture.store.createFolder(named: "First")
        let second = try await fixture.store.createFolder(named: "Second")

        try await fixture.store.move(item, to: first.id)
        try await fixture.store.move(item, to: second.id)
        var manifest = try await fixture.store.loadManifest()
        XCTAssertEqual(manifest.memberships.count, 1)
        XCTAssertEqual(manifest.memberships.first?.folderID, second.id)

        try await fixture.store.move(item, to: nil)
        manifest = try await fixture.store.loadManifest()
        XCTAssertTrue(manifest.memberships.isEmpty)
        let rootFolderID = try await fixture.store.folderID(for: item)
        XCTAssertNil(rootFolderID)
    }

    func testDuplicateAndInvalidFolderNamesFailWithoutChangingManifest() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        _ = try await fixture.store.createFolder(named: "Receipts")

        await XCTAssertThrowsErrorAsync(
            try await fixture.store.createFolder(named: "receipts")
        ) { error in
            XCTAssertEqual(error as? VaultFolderPresentationStore.StoreError, .duplicateFolderName)
        }
        await XCTAssertThrowsErrorAsync(
            try await fixture.store.createFolder(named: "   ")
        ) { error in
            XCTAssertEqual(error as? VaultFolderPresentationStore.StoreError, .invalidFolderName)
        }
        let unchangedManifest = try await fixture.store.loadManifest()
        XCTAssertEqual(unchangedManifest.folders.count, 1)
    }

    func testThumbnailIsEncryptedAndAuthenticatedAtRest() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let item = VaultPresentedContentReference(kind: .generalFile, id: UUID())
        let thumbnail = Data("KEYHOLLOW-PRIVATE-THUMBNAIL".utf8)

        try await fixture.store.storeThumbnail(thumbnail, for: item)
        let manifest = try await fixture.store.loadManifest()
        let blobName = try XCTUnwrap(manifest.thumbnails.first?.blobName)
        let stored = try Data(contentsOf: fixture.storageRoot.appendingPathComponent(blobName))

        XCTAssertNotEqual(stored, thumbnail)
        XCTAssertNil(stored.range(of: thumbnail))
        let reopenedThumbnail = try await fixture.store.loadThumbnail(for: item)
        XCTAssertEqual(reopenedThumbnail, thumbnail)
    }

    func testReconcileRemovesOnlyPresentationDataForMissingItems() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let retained = VaultPresentedContentReference(kind: .photo, id: UUID())
        let removed = VaultPresentedContentReference(kind: .generalFile, id: UUID())
        let folder = try await fixture.store.createFolder(named: "Keep")
        try await fixture.store.move(retained, to: folder.id)
        try await fixture.store.move(removed, to: folder.id)
        try await fixture.store.storeThumbnail(Data("retained".utf8), for: retained)
        try await fixture.store.storeThumbnail(Data("removed".utf8), for: removed)

        try await fixture.store.reconcile(validItems: [retained])
        let manifest = try await fixture.store.loadManifest()

        XCTAssertEqual(manifest.memberships.map(\.item), [retained])
        XCTAssertEqual(manifest.thumbnails.map(\.item), [retained])
        let retainedThumbnail = try await fixture.store.loadThumbnail(for: retained)
        let removedThumbnail = try await fixture.store.loadThumbnail(for: removed)
        XCTAssertEqual(retainedThumbnail, Data("retained".utf8))
        XCTAssertNil(removedThumbnail)
    }

    func testOversizedThumbnailIsRejectedWithoutChangingManifest() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let item = VaultPresentedContentReference(kind: .generalFile, id: UUID())
        let oversized = Data(
            repeating: 0xA5,
            count: VaultFolderPresentationStore.maximumThumbnailByteCount + 1
        )

        await XCTAssertThrowsErrorAsync(
            try await fixture.store.storeThumbnail(oversized, for: item)
        ) { error in
            XCTAssertEqual(error as? VaultFolderPresentationStore.StoreError, .verificationFailed)
        }
        let manifest = try await fixture.store.loadManifest()
        XCTAssertTrue(manifest.thumbnails.isEmpty)
    }

    func testAccessMustMatchVault() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "FolderPresentationMismatch-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: root) }
        XCTAssertThrowsError(
            try VaultFolderPresentationStore(
                vaultID: UUID(),
                access: TestAccess(vaultID: UUID()),
                storageRoot: root
            )
        ) { error in
            XCTAssertEqual(error as? VaultFolderPresentationStore.StoreError, .accessMismatch)
        }
    }
}

private struct Fixture {
    let root: URL
    let storageRoot: URL
    let store: VaultFolderPresentationStore

    init() throws {
        let vaultID = UUID()
        root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "FolderPresentationTests-\(UUID().uuidString)",
            isDirectory: true
        )
        storageRoot = root.appendingPathComponent("Store", isDirectory: true)
        store = try VaultFolderPresentationStore(
            vaultID: vaultID,
            access: TestAccess(vaultID: vaultID),
            storageRoot: storageRoot
        )
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: root)
    }
}

private final class TestAccess: VaultFolderPresentationCryptographicAccess,
    @unchecked Sendable {
    let vaultID: UUID
    private let key = SymmetricKey(size: .bits256)

    init(vaultID: UUID) {
        self.vaultID = vaultID
    }

    func seal(
        _ plaintext: Data,
        for purpose: VaultFolderPresentationKeyPurpose
    ) throws -> Data {
        try CryptoBox.seal(plaintext, using: derivedKey(for: purpose))
    }

    func open(
        _ ciphertext: Data,
        for purpose: VaultFolderPresentationKeyPurpose
    ) throws -> Data {
        try CryptoBox.open(ciphertext, using: derivedKey(for: purpose))
    }

    private func derivedKey(for purpose: VaultFolderPresentationKeyPurpose) -> SymmetricKey {
        HKDF<SHA256>.deriveKey(
            inputKeyMaterial: key,
            salt: Data(purpose.cryptographicDomain.utf8),
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
