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

    func lock() {
        isUnlocked = false
        activeVaultID = nil
        activeKey = nil
    }
}
