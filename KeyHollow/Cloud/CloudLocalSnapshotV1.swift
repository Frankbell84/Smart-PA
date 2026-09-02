import Foundation

struct CloudLocalSnapshotEntryV1: Equatable, Sendable {
    let role: CloudManifestEntryRoleV1
    let localStorageName: String
    let fileURL: URL
    let byteCount: UInt64
    let sha256: Data
}

/// Owns a point-in-time copy of the already encrypted True Core vault files.
/// The copy is read-only, protected, excluded from backup, and single-owner.
final class CloudLocalSnapshotV1: @unchecked Sendable {
    let snapshotID: UUID
    let sourceVaultID: UUID
    let sourceVaultCreatedAtMilliseconds: UInt64
    let localVaultKey: Data
    let directoryURL: URL
    let entries: [CloudLocalSnapshotEntryV1]

    private let lock = NSLock()
    private var ownsDirectory = true

    init(
        snapshotID: UUID,
        sourceVaultID: UUID,
        sourceVaultCreatedAtMilliseconds: UInt64,
        localVaultKey: Data,
        directoryURL: URL,
        entries: [CloudLocalSnapshotEntryV1]
    ) {
        self.snapshotID = snapshotID
        self.sourceVaultID = sourceVaultID
        self.sourceVaultCreatedAtMilliseconds = sourceVaultCreatedAtMilliseconds
        self.localVaultKey = localVaultKey
        self.directoryURL = directoryURL
        self.entries = entries
    }

    func discard() {
        lock.lock()
        defer { lock.unlock() }
        guard ownsDirectory else { return }
        try? FileManager.default.removeItem(at: directoryURL)
        ownsDirectory = false
    }
}
