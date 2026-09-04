import Foundation
import CryptoKit
import KeyHollowCryptoCore
import KeyHollowVaultCore

enum VaultAccessError: Error, Equatable {
    case revoked
}

enum VaultKeyPurpose {
    case manifest
    case photo(UUID)
    case thumbnail(UUID)
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

    private func withKey<T>(_ operation: (SymmetricKey) throws -> T) throws -> T {
        lock.lock()
        defer { lock.unlock() }
        guard let vaultKey else { throw VaultAccessError.revoked }
        return try operation(vaultKey)
    }

    func seal(_ plaintext: Data, for purpose: VaultKeyPurpose) throws -> Data {
        try withKey { vaultKey in
            try CryptoBox.seal(plaintext, using: derivedKey(from: vaultKey, for: purpose))
        }
    }

    func open(_ ciphertext: Data, for purpose: VaultKeyPurpose) throws -> Data {
        try withKey { vaultKey in
            try CryptoBox.open(ciphertext, using: derivedKey(from: vaultKey, for: purpose))
        }
    }

    func preparePortableArchive(
        createdAt: Date,
        credential: PortableArchiveCredential,
        keyDeriver: any PortableArchiveKeyDeriving
    ) throws -> PreparedEncryptedVaultArchive {
        try withKey { vaultKey in
            let keyData = vaultKey.withUnsafeBytes { Data($0) }
            return try EncryptedVaultArchiveHeader.prepare(
                vaultPayload: VaultPayload(
                    vaultID: vaultID,
                    vaultKey: keyData,
                    createdAt: createdAt
                ),
                credential: credential,
                keyDeriver: keyDeriver
            )
        }
    }

    func checkAccess() throws {
        _ = try withKey { _ in () }
    }

    private func derivedKey(from vaultKey: SymmetricKey, for purpose: VaultKeyPurpose) -> SymmetricKey {
        switch purpose {
        case .manifest:
            VaultPhotoKeySchedule.manifestKey(from: vaultKey)
        case .photo(let id):
            VaultPhotoKeySchedule.photoKey(from: vaultKey, id: id)
        case .thumbnail(let id):
            VaultPhotoKeySchedule.thumbnailKey(from: vaultKey, id: id)
        }
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
    @Published private(set) var securityEpoch: UInt64 = 0

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

    var hasActiveAccess: Bool {
        isUnlocked && activeCapability?.isRevoked == false
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
            if !Task.isCancelled {
                await operation(capability)
            }
            self?.sensitiveTasks[id] = nil
        }
        sensitiveTasks[id] = task
        return id
    }

    /// Tracks cryptographic work that does not use the currently unlocked
    /// vault capability, such as authenticating an encrypted portable vault.
    /// Background locking cancels this work even when the keypad is showing.
    @discardableResult
    func startProtectedTask(
        _ operation: @escaping @MainActor () async -> Void
    ) -> UUID {
        let id = UUID()
        let task = Task { @MainActor [weak self] in
            if !Task.isCancelled {
                await operation()
            }
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
        securityEpoch &+= 1

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


