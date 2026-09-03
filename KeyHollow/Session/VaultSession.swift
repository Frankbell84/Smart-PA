import Foundation
import CryptoKit

enum VaultAccessError: Error, Equatable {
    case revoked
}

/// A narrow, revocable boundary around a vault key.
///
/// Callers never receive a key to retain. A revocation waits for any currently
/// executing synchronous key operation to leave the critical section, clears
/// the capability's key reference, and prevents every later operation.
final class VaultAccessCapability: @unchecked Sendable {
    let vaultID: UUID

    private let lock = NSLock()
    private var vaultKey: SymmetricKey?

    init(vaultID: UUID, vaultKey: SymmetricKey) {
        self.vaultID = vaultID
        self.vaultKey = vaultKey
    }

    func withKey<T>(_ operation: (SymmetricKey) throws -> T) throws -> T {
        lock.lock()
        defer { lock.unlock() }
        guard let vaultKey else { throw VaultAccessError.revoked }
        return try operation(vaultKey)
    }

    func revoke() {
        lock.lock()
        vaultKey = nil
        lock.unlock()
    }

    var isRevoked: Bool {
        lock.lock()
        defer { lock.unlock() }
        return vaultKey == nil
    }
}

@MainActor
final class VaultSession: ObservableObject {
    @Published private(set) var isUnlocked = false
    @Published private(set) var activeVaultID: UUID?
    @Published private(set) var isSystemInteractionActive = false

    private var activeCapability: VaultAccessCapability?
    private var systemInteractionCount = 0
    private var sensitiveTasks: [UUID: Task<Void, Never>] = [:]

    var isSystemPhotoOperationActive: Bool { isSystemInteractionActive }

    func unlock(vaultID: UUID, key: SymmetricKey) {
        activeCapability?.revoke()
        sensitiveTasks.values.forEach { $0.cancel() }
        sensitiveTasks.removeAll()
        activeVaultID = vaultID
        activeCapability = VaultAccessCapability(vaultID: vaultID, vaultKey: key)
        isUnlocked = true
    }

    /// A compatibility probe for lifecycle tests. The closure cannot return or
    /// retain the key; production storage uses `activeVaultContext()` instead.
    @discardableResult
    func withActiveKey(_ operation: (SymmetricKey) throws -> Void) rethrows -> Bool {
        guard isUnlocked, let activeCapability else { return false }
        do {
            try activeCapability.withKey(operation)
            return true
        } catch VaultAccessError.revoked {
            return false
        }
    }

    func activeVaultContext() -> (id: UUID, access: VaultAccessCapability)? {
        guard isUnlocked,
              let activeVaultID,
              let activeCapability,
              !activeCapability.isRevoked else { return nil }
        return (activeVaultID, activeCapability)
    }

    /// Starts work that must not outlive the unlocked vault session. Locking
    /// revokes the capability first, then cancels every registered task.
    @discardableResult
    func startSensitiveTask(
        _ operation: @escaping @MainActor (VaultAccessCapability) async -> Void
    ) -> UUID? {
        guard isUnlocked,
              let capability = activeCapability,
              !capability.isRevoked else { return nil }

        let id = UUID()
        let task = Task { @MainActor [weak self] in
            await operation(capability)
            self?.sensitiveTasks[id] = nil
        }
        sensitiveTasks[id] = task
        return id
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
        let capability = activeCapability
        let tasks = Array(sensitiveTasks.values)

        isUnlocked = false
        activeVaultID = nil
        activeCapability = nil
        systemInteractionCount = 0
        isSystemInteractionActive = false

        // Revoke synchronously. Because capability key use is serialized under
        // the same lock, this returns only after an in-flight atomic key use has
        // ended; no later store operation can acquire the key.
        capability?.revoke()
        tasks.forEach { $0.cancel() }
        sensitiveTasks.removeAll()
    }

    /// Test and shutdown boundary that also observes registered task cleanup.
    func lockAndWait() async {
        let tasks = Array(sensitiveTasks.values)
        lock()
        for task in tasks {
            await task.value
        }
    }
}

