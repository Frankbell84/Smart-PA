import Foundation
import CryptoKit

enum VaultUnlockError: Error, Equatable {
    case invalidCredentials
    case passcodeAlreadyUsed
    case temporarilyLocked(Date)
    case mutationFailed
}

struct UnlockedVault {
    let vaultID: UUID
    let vaultKey: SymmetricKey
    let createdAt: Date
}

actor VaultUnlockService {
    private let secrets = DevicePepperStore()
    private let kdf: PasswordKeyDeriving
    private let limiter: UnlockAttemptLimiter
    private let store: VaultStore

    init(
        kdf: PasswordKeyDeriving = ProductionArgon2idKDF(),
        limiter: UnlockAttemptLimiter = UnlockAttemptLimiter()
    ) throws {
        self.kdf = kdf
        self.limiter = limiter
        self.store = try VaultStore()
    }

    func hasAnyVaults() async throws -> Bool {
        try await store.hasAnyVaults()
    }

    func createVault(passcode: String) async throws -> UnlockedVault {
        guard PasscodePolicy.isValid(passcode) else { throw KeyDerivationError.invalidPasscode }

        let unlockKey = try deriveUnlockKey(passcode: passcode)
        let locator = VaultLocator.derive(from: unlockKey)

        if await store.contains(locator: locator) {
            throw VaultUnlockError.passcodeAlreadyUsed
        }

        let created = try VaultEnvelope.create(using: unlockKey)
        try await store.write(created.envelope, locator: locator)

        return unlockedVault(from: created.payload)
    }

    func unlock(passcode: String) async throws -> UnlockedVault {
        do {
            try await limiter.checkAllowed()
        } catch UnlockAttemptLimiter.LimitError.temporarilyLocked(let until) {
            throw VaultUnlockError.temporarilyLocked(until)
        }

        guard PasscodePolicy.isValid(passcode) else {
            await limiter.recordFailure()
            throw VaultUnlockError.invalidCredentials
        }

        do {
            let unlockKey = try deriveUnlockKey(passcode: passcode)
            let locator = VaultLocator.derive(from: unlockKey)

            guard let envelope = try await store.read(locator: locator) else {
                await limiter.recordFailure()
                throw VaultUnlockError.invalidCredentials
            }

            let payload = try envelope.open(using: unlockKey)
            await limiter.recordSuccess()
            return unlockedVault(from: payload)
        } catch let error as VaultUnlockError {
            throw error
        } catch {
            await limiter.recordFailure()
            throw VaultUnlockError.invalidCredentials
        }
    }

    /// Changes only the passcode wrapper. The vault's random data key and all
    /// encrypted photo blobs remain unchanged, avoiding bulk decrypt/re-encrypt.
    /// The current passcode must resolve to the vault that is actually open.
    func changePasscode(
        currentPasscode: String,
        newPasscode: String,
        expectedVaultID: UUID
    ) async throws -> UnlockedVault {
        guard PasscodePolicy.isValid(currentPasscode),
              PasscodePolicy.isValid(newPasscode) else {
            throw VaultUnlockError.invalidCredentials
        }

        let currentKey = try deriveUnlockKey(passcode: currentPasscode)
        let currentLocator = VaultLocator.derive(from: currentKey)
        guard let currentEnvelope = try await store.read(locator: currentLocator) else {
            throw VaultUnlockError.invalidCredentials
        }

        let payload: VaultPayload
        do {
            payload = try currentEnvelope.open(using: currentKey)
        } catch {
            throw VaultUnlockError.invalidCredentials
        }
        guard payload.vaultID == expectedVaultID else {
            throw VaultUnlockError.invalidCredentials
        }

        let newKey = try deriveUnlockKey(passcode: newPasscode)
        let newLocator = VaultLocator.derive(from: newKey)
        guard newLocator != currentLocator else {
            throw VaultUnlockError.passcodeAlreadyUsed
        }
        guard !(await store.contains(locator: newLocator)) else {
            throw VaultUnlockError.passcodeAlreadyUsed
        }

        let replacement = try VaultEnvelope.seal(payload: payload, using: newKey)

        // Write the replacement first so a storage failure cannot strand the
        // user without a valid envelope. Then remove the old credential path.
        try await store.write(replacement, locator: newLocator)
        do {
            try await store.delete(locator: currentLocator)
        } catch {
            // Best-effort rollback. If rollback itself fails, both wrappers point
            // to the same vault key; the caller still receives a mutation error.
            try? await store.delete(locator: newLocator)
            throw VaultUnlockError.mutationFailed
        }

        return unlockedVault(from: payload)
    }

    /// Deletes the credential envelope first, cryptographically removing the
    /// app's route to the vault key, then removes the encrypted photo directory.
    func deleteVault(currentPasscode: String, expectedVaultID: UUID) async throws {
        guard PasscodePolicy.isValid(currentPasscode) else {
            throw VaultUnlockError.invalidCredentials
        }

        let currentKey = try deriveUnlockKey(passcode: currentPasscode)
        let currentLocator = VaultLocator.derive(from: currentKey)
        guard let currentEnvelope = try await store.read(locator: currentLocator) else {
            throw VaultUnlockError.invalidCredentials
        }

        let payload: VaultPayload
        do {
            payload = try currentEnvelope.open(using: currentKey)
        } catch {
            throw VaultUnlockError.invalidCredentials
        }
        guard payload.vaultID == expectedVaultID else {
            throw VaultUnlockError.invalidCredentials
        }

        // Remove the only persisted wrapper around the random vault data key
        // before deleting encrypted blobs. If blob cleanup later fails, orphaned
        // ciphertext remains inaccessible through KeyHollow.
        try await store.delete(locator: currentLocator)
        do {
            try VaultPhotoStore.destroyVaultData(vaultID: payload.vaultID)
        } catch {
            // Credential destruction succeeded, so do not recreate the envelope.
            // Surface the cleanup failure without restoring access to deleted data.
            throw VaultUnlockError.mutationFailed
        }
    }

    private func deriveUnlockKey(passcode: String) throws -> SymmetricKey {
        let pepper = try secrets.loadOrCreate()
        let installationSalt = try secrets.loadOrCreateInstallationSalt()
        return try kdf.deriveKey(
            passcode: passcode,
            installationSalt: installationSalt,
            pepper: pepper
        )
    }

    private func unlockedVault(from payload: VaultPayload) -> UnlockedVault {
        UnlockedVault(
            vaultID: payload.vaultID,
            vaultKey: SymmetricKey(data: payload.vaultKey),
            createdAt: payload.createdAt
        )
    }
}
