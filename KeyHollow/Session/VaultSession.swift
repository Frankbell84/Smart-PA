import Foundation
import CryptoKit

@MainActor
final class VaultSession: ObservableObject {
    @Published private(set) var isUnlocked = false
    @Published private(set) var activeVaultID: UUID?

    private var activeKey: SymmetricKey?

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

    func lock() {
        isUnlocked = false
        activeVaultID = nil
        activeKey = nil
    }
}
