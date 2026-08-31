import Foundation
import CryptoKit

@MainActor
final class VaultSession: ObservableObject {
    @Published private(set) var isUnlocked = false
    @Published private(set) var activeVaultID: UUID?
    @Published private(set) var isSystemPhotoOperationActive = false

    private var activeKey: SymmetricKey?
    private var systemPhotoOperationCount = 0

    func unlock(vaultID: UUID, key: SymmetricKey) {
        activeVaultID = vaultID
        activeKey = key
        isUnlocked = true
    }

    func withActiveKey<T>(_ operation: (SymmetricKey) throws -> T) rethrows -> T? {
        guard isUnlocked, let activeKey else { return nil }
        return try operation(activeKey)
    }

    func activeVaultContext() -> (id: UUID, key: SymmetricKey)? {
        guard isUnlocked,
              let activeVaultID,
              let activeKey else { return nil }
        return (activeVaultID, activeKey)
    }

    func beginSystemPhotoOperation() {
        systemPhotoOperationCount += 1
        isSystemPhotoOperationActive = true
    }

    func endSystemPhotoOperation() {
        systemPhotoOperationCount = max(0, systemPhotoOperationCount - 1)
        isSystemPhotoOperationActive = systemPhotoOperationCount > 0
    }

    func lock() {
        isUnlocked = false
        activeVaultID = nil
        activeKey = nil
    }
}

