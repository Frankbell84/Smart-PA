import Foundation
import CryptoKit

@MainActor
final class VaultSession: ObservableObject {
    @Published private(set) var isUnlocked = false
    @Published private(set) var activeVaultID: UUID?
    @Published private(set) var isSystemInteractionActive = false

    private var activeKey: SymmetricKey?
    private var systemInteractionCount = 0

    var isSystemPhotoOperationActive: Bool { isSystemInteractionActive }

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

    func beginSystemInteraction() {
        systemInteractionCount += 1
        isSystemInteractionActive = true
    }

    func endSystemInteraction() {
        systemInteractionCount = max(0, systemInteractionCount - 1)
        isSystemInteractionActive = systemInteractionCount > 0
    }

    func beginSystemPhotoOperation() {
        beginSystemInteraction()
    }

    func endSystemPhotoOperation() {
        endSystemInteraction()
    }

    func lock() {
        isUnlocked = false
        activeVaultID = nil
        activeKey = nil
        systemInteractionCount = 0
        isSystemInteractionActive = false
    }
}

