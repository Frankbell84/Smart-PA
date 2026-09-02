import CryptoKit
import Foundation
import XCTest
@testable import KeyHollow

final class CloudProviderFreeRoundTripTests: XCTestCase {
    func testImmutableSnapshotRoundTripRestoresBuild11VaultOnlyAfterVerification() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let sourceStore = try VaultPhotoStore(
            vaultID: fixture.sourceVaultID,
            vaultKey: fixture.localVaultKey,
            storageRoot: fixture.sourceRoot
        )
        let first = try await sourceStore.importPhoto(
            originalData: Data("first original".utf8),
            thumbnailData: Data("first thumbnail".utf8)
        )
        let snapshot = try await sourceStore.captureCloudSnapshot(
            sourceVaultCreatedAt: fixture.sourceCreatedAt,
            workingRoot: fixture.snapshotRoot
        )
        let snapshotURL = snapshot.directoryURL

        // A later live-vault mutation must not alter the captured generation.
        _ = try await sourceStore.importPhoto(
            originalData: Data("second original".utf8),
            thumbnailData: Data("second thumbnail".utf8)
        )

        let store = CloudMockObjectStoreV1(quotaByteCount: 16 * 1_024 * 1_024)
        let receipt = try await CloudProviderFreeBackupCoordinatorV1().backup(
            snapshot: snapshot,
            accountID: fixture.accountID,
            cloudVaultID: fixture.cloudVaultID,
            cloudVaultKey: fixture.cloudVaultKey,
            store: store,
            nowMilliseconds: fixture.nowMilliseconds
        )
        XCTAssertEqual(receipt.generation, 1)
        XCTAssertEqual(receipt.objectCount, 4)
        XCTAssertFalse(FileManager.default.fileExists(atPath: snapshotURL.path))

        let restore = try await CloudProviderFreeRestoreCoordinatorV1().stageAndValidate(
            accountID: fixture.accountID,
            cloudVaultID: fixture.cloudVaultID,
            cloudVaultKey: fixture.cloudVaultKey,
            store: store,
            workingRoot: fixture.restoreRoot
        )
        XCTAssertEqual(restore.manifest.photos, [first])
        XCTAssertEqual(restore.localVaultKey, fixture.localVaultKey.withUnsafeBytes { Data($0) })
        XCTAssertEqual(
            restore.sourceVaultCreatedAt.timeIntervalSince1970,
            fixture.sourceCreatedAt.timeIntervalSince1970,
            accuracy: 0.001
        )

        let published = fixture.root.appendingPathComponent("published", isDirectory: true)
        try restore.commitEncryptedFiles(to: published)
        let reopened = try VaultPhotoStore(
            vaultID: UUID(),
            vaultKey: fixture.localVaultKey,
            storageRoot: published
        )
        let reopenedOriginal = try await reopened.loadPhoto(first)
        let reopenedThumbnail = try await reopened.loadThumbnail(first)
        XCTAssertEqual(reopenedOriginal, Data("first original".utf8))
        XCTAssertEqual(reopenedThumbnail, Data("first thumbnail".utf8))
    }

    func testCancellationRemovesSnapshotReservationAndUploadedObjects() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let sourceStore = try VaultPhotoStore(
            vaultID: fixture.sourceVaultID,
            vaultKey: fixture.localVaultKey,
            storageRoot: fixture.sourceRoot
        )
        _ = try await sourceStore.importPhoto(
            originalData: Data("original".utf8),
            thumbnailData: Data("thumbnail".utf8)
        )
        let snapshot = try await sourceStore.captureCloudSnapshot(
            sourceVaultCreatedAt: fixture.sourceCreatedAt,
            workingRoot: fixture.snapshotRoot
        )
        let snapshotURL = snapshot.directoryURL
        let store = CloudMockObjectStoreV1(quotaByteCount: 16 * 1_024 * 1_024)
        let hooks = CloudBackupHooksV1 { progress in
            if case .objectCommitted(1) = progress {
                throw CancellationError()
            }
        }

        do {
            _ = try await CloudProviderFreeBackupCoordinatorV1().backup(
                snapshot: snapshot,
                accountID: fixture.accountID,
                cloudVaultID: fixture.cloudVaultID,
                cloudVaultKey: fixture.cloudVaultKey,
                store: store,
                nowMilliseconds: fixture.nowMilliseconds,
                hooks: hooks
            )
            XCTFail("Expected cancellation")
        } catch is CancellationError {
            // Expected.
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: snapshotURL.path))
        let statistics = await store.statistics()
        XCTAssertEqual(
            statistics,
            CloudMockStoreStatisticsV1(
                objectCount: 0,
                activeReservationCount: 0,
                retainedGenerationCount: 0
            )
        )
    }

    func testMutatedManifestFailsBeforeAnyRestoreCanBePublished() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let sourceStore = try VaultPhotoStore(
            vaultID: fixture.sourceVaultID,
            vaultKey: fixture.localVaultKey,
            storageRoot: fixture.sourceRoot
        )
        _ = try await sourceStore.importPhoto(
            originalData: Data("original".utf8),
            thumbnailData: Data("thumbnail".utf8)
        )
        let snapshot = try await sourceStore.captureCloudSnapshot(
            sourceVaultCreatedAt: fixture.sourceCreatedAt,
            workingRoot: fixture.snapshotRoot
        )
        let store = CloudMockObjectStoreV1(quotaByteCount: 16 * 1_024 * 1_024)
        let receipt = try await CloudProviderFreeBackupCoordinatorV1().backup(
            snapshot: snapshot,
            accountID: fixture.accountID,
            cloudVaultID: fixture.cloudVaultID,
            cloudVaultKey: fixture.cloudVaultKey,
            store: store,
            nowMilliseconds: fixture.nowMilliseconds
        )
        try await store.mutateStoredObjectForTesting(objectID: receipt.manifestObjectID)

        await XCTAssertThrowsErrorAsync {
            _ = try await CloudProviderFreeRestoreCoordinatorV1().stageAndValidate(
                accountID: fixture.accountID,
                cloudVaultID: fixture.cloudVaultID,
                cloudVaultKey: fixture.cloudVaultKey,
                store: store,
                workingRoot: fixture.restoreRoot
            )
        }
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: fixture.restoreRoot.path), [])
    }

    func testReservationAndCommitRetriesAreIdempotent() async throws {
        let store = CloudMockObjectStoreV1(quotaByteCount: 1_024)
        let accountID = UUID()
        let vaultID = UUID()
        let idempotencyKey = UUID()
        let bytes = Data("opaque ciphertext".utf8)
        let digest = CloudObjectContainerV1.sha256(bytes)
        let objectID = UUID()
        let first = try await store.reserve(
            accountID: accountID,
            vaultID: vaultID,
            idempotencyKey: idempotencyKey,
            declaredByteCount: UInt64(bytes.count),
            nowMilliseconds: 1
        )
        let retry = try await store.reserve(
            accountID: accountID,
            vaultID: vaultID,
            idempotencyKey: idempotencyKey,
            declaredByteCount: UInt64(bytes.count),
            nowMilliseconds: 2
        )
        XCTAssertEqual(first, retry)
        try await store.putObject(
            reservation: first,
            objectID: objectID,
            storedBytes: bytes,
            expectedSHA256: digest,
            nowMilliseconds: 1
        )
        try await store.putObject(
            reservation: retry,
            objectID: objectID,
            storedBytes: bytes,
            expectedSHA256: digest,
            nowMilliseconds: 2
        )
        try await store.commitObject(
            reservation: first,
            objectID: objectID,
            observedByteCount: UInt64(bytes.count),
            observedSHA256: digest
        )
        let committed = try await store.commitGeneration(
            reservation: first,
            generation: 1,
            expectedParent: nil,
            manifestObjectID: objectID,
            manifestSHA256: digest,
            referencedObjectIDs: [objectID]
        )
        let retryCommit = try await store.commitGeneration(
                reservation: retry,
                generation: 1,
                expectedParent: nil,
                manifestObjectID: objectID,
                manifestSHA256: digest,
                referencedObjectIDs: [objectID]
        )
        XCTAssertEqual(retryCommit, committed)
    }

    func testStaleParentCommitIsRejected() async throws {
        let store = CloudMockObjectStoreV1(quotaByteCount: 4_096)
        let accountID = UUID()
        let vaultID = UUID()
        let first = try await commitOpaqueGeneration(
            store: store,
            accountID: accountID,
            vaultID: vaultID,
            generation: 1,
            parent: nil,
            marker: 1
        )
        let parent = CloudManifestParentV1(
            generation: first.generation,
            manifestObjectID: first.manifestObjectID,
            storedObjectSHA256: first.manifestSHA256
        )
        _ = try await commitOpaqueGeneration(
            store: store,
            accountID: accountID,
            vaultID: vaultID,
            generation: 2,
            parent: parent,
            marker: 2
        )

        do {
            _ = try await commitOpaqueGeneration(
                store: store,
                accountID: accountID,
                vaultID: vaultID,
                generation: 2,
                parent: parent,
                marker: 3
            )
            XCTFail("Expected stale-parent rejection")
        } catch {
            XCTAssertEqual(error as? CloudMockStoreErrorV1, .staleParent)
        }
    }

    func testConcurrentQuotaReservationsAllowOnlyOneWinner() async throws {
        let store = CloudMockObjectStoreV1(quotaByteCount: 100)
        let accountID = UUID()
        let vaultID = UUID()
        async let first = Self.reservationResult(
            store: store,
            accountID: accountID,
            vaultID: vaultID,
            byteCount: 80
        )
        async let second = Self.reservationResult(
            store: store,
            accountID: accountID,
            vaultID: vaultID,
            byteCount: 80
        )
        let (firstResult, secondResult) = await (first, second)
        let results = [firstResult, secondResult]
        XCTAssertEqual(results.filter { $0 }.count, 1)
        let statistics = await store.statistics()
        XCTAssertEqual(statistics.activeReservationCount, 1)
    }

    func testOrphanCleanupPreservesObjectsReferencedByRetainedGeneration() async throws {
        let store = CloudMockObjectStoreV1(quotaByteCount: 4_096)
        let accountID = UUID()
        let vaultID = UUID()
        _ = try await commitOpaqueGeneration(
            store: store,
            accountID: accountID,
            vaultID: vaultID,
            generation: 1,
            parent: nil,
            marker: 1
        )
        let orphan = try await store.reserve(
            accountID: accountID,
            vaultID: vaultID,
            idempotencyKey: UUID(),
            declaredByteCount: 1,
            nowMilliseconds: 1
        )
        let orphanID = UUID()
        let bytes = Data([0xee])
        try await store.putObject(
            reservation: orphan,
            objectID: orphanID,
            storedBytes: bytes,
            expectedSHA256: CloudObjectContainerV1.sha256(bytes),
            nowMilliseconds: 1
        )

        _ = await store.cleanupOrphans(olderThanMilliseconds: 1)
        let statistics = await store.statistics()
        XCTAssertEqual(
            statistics,
            CloudMockStoreStatisticsV1(
                objectCount: 1,
                activeReservationCount: 0,
                retainedGenerationCount: 1
            )
        )
    }

    private func makeFixture() throws -> Fixture {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "cloud-round-trip-\(UUID().uuidString)",
            isDirectory: true
        )
        let source = root.appendingPathComponent("source", isDirectory: true)
        let snapshots = root.appendingPathComponent("snapshots", isDirectory: true)
        let restores = root.appendingPathComponent("restores", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: snapshots, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: restores, withIntermediateDirectories: true)
        return Fixture(
            root: root,
            sourceRoot: source,
            snapshotRoot: snapshots,
            restoreRoot: restores,
            accountID: UUID(),
            cloudVaultID: UUID(),
            sourceVaultID: UUID(),
            localVaultKey: SymmetricKey(data: Data(repeating: 0x31, count: 32)),
            cloudVaultKey: Data(repeating: 0x72, count: 32),
            sourceCreatedAt: Date(timeIntervalSince1970: 1_710_000_000.321),
            nowMilliseconds: 1_720_000_000_123
        )
    }

    private static func reservationResult(
        store: CloudMockObjectStoreV1,
        accountID: UUID,
        vaultID: UUID,
        byteCount: UInt64
    ) async -> Bool {
        do {
            _ = try await store.reserve(
                accountID: accountID,
                vaultID: vaultID,
                idempotencyKey: UUID(),
                declaredByteCount: byteCount,
                nowMilliseconds: 1
            )
            return true
        } catch {
            return false
        }
    }

    private func commitOpaqueGeneration(
        store: CloudMockObjectStoreV1,
        accountID: UUID,
        vaultID: UUID,
        generation: UInt64,
        parent: CloudManifestParentV1?,
        marker: UInt8
    ) async throws -> CloudMockGenerationHeadV1 {
        let bytes = Data([marker])
        let digest = CloudObjectContainerV1.sha256(bytes)
        let objectID = UUID()
        let reservation = try await store.reserve(
            accountID: accountID,
            vaultID: vaultID,
            idempotencyKey: UUID(),
            declaredByteCount: UInt64(bytes.count),
            nowMilliseconds: UInt64(marker)
        )
        try await store.putObject(
            reservation: reservation,
            objectID: objectID,
            storedBytes: bytes,
            expectedSHA256: digest,
            nowMilliseconds: UInt64(marker)
        )
        try await store.commitObject(
            reservation: reservation,
            objectID: objectID,
            observedByteCount: UInt64(bytes.count),
            observedSHA256: digest
        )
        return try await store.commitGeneration(
            reservation: reservation,
            generation: generation,
            expectedParent: parent,
            manifestObjectID: objectID,
            manifestSHA256: digest,
            referencedObjectIDs: [objectID]
        )
    }
}

private struct Fixture {
    let root: URL
    let sourceRoot: URL
    let snapshotRoot: URL
    let restoreRoot: URL
    let accountID: UUID
    let cloudVaultID: UUID
    let sourceVaultID: UUID
    let localVaultKey: SymmetricKey
    let cloudVaultKey: Data
    let sourceCreatedAt: Date
    let nowMilliseconds: UInt64
}

private func XCTAssertThrowsErrorAsync(
    _ expression: () async throws -> Void,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        try await expression()
        XCTFail("Expected error", file: file, line: line)
    } catch {
        // Expected.
    }
}
