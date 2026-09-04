import CryptoKit
import Foundation
import XCTest
@testable import KeyHollow
@testable import KeyHollowPhotoCore
@testable import KeyHollowPhotosAdapter

final class PhaseTwoSecurityTests: XCTestCase {
    func testRevokedCapabilityCannotReadOrMutateVaultStore() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let vaultID = UUID()
        let capability = VaultAccessCapability(
            vaultID: vaultID,
            vaultKey: SymmetricKey(size: .bits256)
        )
        let store = try VaultPhotoStore(
            vaultID: vaultID,
            access: capability,
            storageRoot: root
        )
        let record = try await store.importPhoto(
            originalData: Data("original".utf8),
            thumbnailData: Data("thumbnail".utf8)
        )

        capability.revoke()
        XCTAssertTrue(capability.isRevoked)

        do {
            _ = try await store.loadPhoto(record)
            XCTFail("A revoked capability still decrypted a photo")
        } catch VaultAccessError.revoked {}

        do {
            _ = try await store.importPhoto(
                originalData: Data("second".utf8),
                thumbnailData: Data("second thumb".utf8)
            )
            XCTFail("A revoked capability still mutated the vault")
        } catch VaultAccessError.revoked {}
    }

    @MainActor
    func testLockRevokesCapabilityCancelsTaskAndWaitsForCleanup() async throws {
        let session = VaultSession()
        session.unlock(vaultID: UUID(), key: SymmetricKey(size: .bits256))

        let started = expectation(description: "sensitive work started")
        var sawCancellation = false
        var sawRevocation = false
        let taskID = session.startSensitiveTask { access in
            started.fulfill()
            do {
                try await Task.sleep(for: .seconds(30))
            } catch {}
            sawCancellation = Task.isCancelled
            sawRevocation = access.isRevoked
        }
        XCTAssertNotNil(taskID)
        await fulfillment(of: [started])

        await session.lockAndWait()

        XCTAssertFalse(session.isUnlocked)
        XCTAssertNil(session.activeVaultID)
        XCTAssertTrue(sawCancellation)
        XCTAssertTrue(sawRevocation)
    }

    @MainActor
    func testPhotoBatchProcessorNeverHasMoreThanOneFullSizeItemResident() async {
        let inputs = Array(0..<25)
        var activeLoads = 0
        var maximumActiveLoads = 0
        var consumed: [Int] = []
        var failureCount = 0

        await SequentialPhotoBatchProcessor.process(
            inputs,
            load: { value in
                activeLoads += 1
                maximumActiveLoads = max(maximumActiveLoads, activeLoads)
                await Task.yield()
                activeLoads -= 1
                if value == 7 { throw SyntheticFailure.expected }
                return value
            },
            consume: { value in
                consumed.append(value)
                await Task.yield()
            },
            didFail: {
                failureCount += 1
            }
        )

        XCTAssertEqual(maximumActiveLoads, 1)
        XCTAssertEqual(failureCount, 1)
        XCTAssertEqual(consumed, inputs.filter { $0 != 7 })
        XCTAssertEqual(SecurePhotoPicker.maximumResidentFullSizePhotos, 1)
        XCTAssertEqual(PhotoLibrarySaveService.maximumResidentFullSizePhotos, 1)
    }

    @MainActor
    func testPhotoBatchProcessorStopsAfterCancellationAndReleasesCurrentItem() async {
        var consumed: [Int] = []
        var loaded: [Int] = []
        let reachedCutoff = expectation(description: "fifth item consumed")

        let task = Task { @MainActor in
            await SequentialPhotoBatchProcessor.process(
                Array(0..<100),
                load: { value in
                    loaded.append(value)
                    return value
                },
                consume: { value in
                    consumed.append(value)
                    if value == 4 {
                        reachedCutoff.fulfill()
                        while !Task.isCancelled { await Task.yield() }
                    }
                },
                didFail: {}
            )
        }

        // The production cancellation source is VaultSession.lock(). This
        // focused test cancels at a deterministic item boundary.
        await fulfillment(of: [reachedCutoff])
        task.cancel()
        await task.value

        XCTAssertEqual(loaded, Array(0...4))
        XCTAssertEqual(consumed, Array(0...4))
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(
            "KeyHollowPhaseTwoTests-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

private enum SyntheticFailure: Error {
    case expected
}
