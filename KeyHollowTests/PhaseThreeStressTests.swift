import CryptoKit
import Foundation
import XCTest
@testable import KeyHollow

final class PhaseThreeStressTests: XCTestCase {
    func testFiftyLargePhotosRoundTripWithoutChangingTheSourceVault() async throws {
        let roots = try PhaseThreeRoots.create()
        defer { roots.remove() }

        let photoCount = 50
        let originalByteCount = 512 * 1_024
        let thumbnailByteCount = 16 * 1_024
        let vaultID = UUID()
        let vaultKey = SymmetricKey(data: Data(repeating: 0x71, count: 32))
        let store = try VaultPhotoStore(
            vaultID: vaultID,
            vaultKey: vaultKey,
            storageRoot: roots.source
        )

        var expected: [(VaultPhotoRecord, UInt8)] = []
        expected.reserveCapacity(photoCount)
        for index in 0..<photoCount {
            let marker = UInt8(index)
            let record = try await store.importPhoto(
                originalData: Data(repeating: marker, count: originalByteCount),
                thumbnailData: Data(repeating: marker ^ 0xff, count: thumbnailByteCount)
            )
            expected.append((record, marker))
        }
        let sourceBefore = try directorySnapshot(roots.source)

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
            keyDeriver: PhaseThreeKeyDeriver()
        )

        XCTAssertEqual(receipt.encryptedFileCount, photoCount * 2 + 1)
        XCTAssertEqual(try directorySnapshot(roots.source), sourceBefore)

        let restore = try await coordinator.stageAndValidateRestore(
            archiveURL: roots.archive,
            credential: credential,
            workingRootOverride: roots.working,
            keyDeriver: PhaseThreeKeyDeriver()
        )
        defer { restore.discard() }

        XCTAssertEqual(restore.manifest.photos.count, photoCount)
        let restoredStore = try VaultPhotoStore(
            vaultID: restore.destinationVaultPayload.vaultID,
            vaultKey: vaultKey,
            storageRoot: restore.stagingURL
        )

        for (record, marker) in expected {
            let original = try await restoredStore.loadPhoto(record)
            let thumbnail = try await restoredStore.loadThumbnail(record)
            XCTAssertEqual(original.count, originalByteCount)
            XCTAssertEqual(original.first, marker)
            XCTAssertEqual(original.last, marker)
            XCTAssertEqual(thumbnail.count, thumbnailByteCount)
            XCTAssertEqual(thumbnail.first, marker ^ 0xff)
            XCTAssertEqual(thumbnail.last, marker ^ 0xff)
        }
    }

    private func directorySnapshot(_ root: URL) throws -> [String: Data] {
        let urls = try FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: nil
        )
        return try Dictionary(uniqueKeysWithValues: urls.map { url in
            (url.lastPathComponent, try Data(contentsOf: url))
        })
    }
}

private struct PhaseThreeKeyDeriver: PortableArchiveKeyDeriving {
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

private struct PhaseThreeRoots {
    let parent: URL
    let source: URL
    let working: URL
    let archive: URL

    static func create() throws -> PhaseThreeRoots {
        let parent = FileManager.default.temporaryDirectory.appendingPathComponent(
            "KeyHollowPhaseThreeTests-\(UUID().uuidString)",
            isDirectory: true
        )
        let source = parent.appendingPathComponent("source", isDirectory: true)
        let working = parent.appendingPathComponent("working", isDirectory: true)
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        return PhaseThreeRoots(
            parent: parent,
            source: source,
            working: working,
            archive: parent.appendingPathComponent("stress-transfer.khvault")
        )
    }

    func remove() {
        try? FileManager.default.removeItem(at: parent)
    }
}
