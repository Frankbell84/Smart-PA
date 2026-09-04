import Foundation
import CryptoKit
import KeyHollowPhotoCore
import KeyHollowTransferCore
import KeyHollowVaultCore

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

struct ReauthenticatedVault {
    let vaultID: UUID
    let createdAt: Date
}

actor VaultUnlockService {
    private let secrets: DeviceSecretProviding
    private let kdf: PasswordKeyDeriving
    private let limiter: UnlockAttemptLimiter
    private let store: VaultStore
    private let photoStorageRootOverride: URL?

    init(
        kdf: PasswordKeyDeriving = ProductionArgon2idKDF(),
        limiter: UnlockAttemptLimiter = UnlockAttemptLimiter(),
        secrets: DeviceSecretProviding = DevicePepperStore(),
        vaultStorageRootOverride: URL? = nil,
        photoStorageRootOverride: URL? = nil
    ) throws {
        self.kdf = kdf
        self.limiter = limiter
        self.secrets = secrets
        self.store = try VaultStore(rootOverride: vaultStorageRootOverride)
        self.photoStorageRootOverride = photoStorageRootOverride
    }

    func hasAnyVaults() async throws -> Bool {
        try await store.hasAnyVaults()
    }

    /// Rolls back any portable-vault install that was interrupted before its
    /// authenticated transaction journal could be cleared. Call during startup
    /// before allowing unlock or vault creation.
    func recoverInterruptedPortableVaultInstalls() async throws {
        guard try PortableVaultRestoreTransactionJournal.recoveryRequired() else {
            return
        }
        let installer = try PortableVaultRestoreInstaller(
            credentialStore: store,
            journalAuthenticationKey: try portableRestoreJournalKey()
        )
        try await installer.recoverInterruptedInstalls()
    }

    func createVault(passcode: String) async throws -> UnlockedVault {
        guard PasscodePolicy.isAcceptableNewPasscode(passcode) else {
            throw KeyDerivationError.invalidPasscode
        }

        let unlockKey = try deriveUnlockKey(passcode: passcode)
        let locator = VaultLocator.derive(from: unlockKey)

        if await store.contains(locator: locator) {
            throw VaultUnlockError.passcodeAlreadyUsed
        }

        let created = try VaultEnvelope.create(using: unlockKey)
        try await store.write(created.envelope, locator: locator)

        return unlockedVault(from: created.payload)
    }

    /// Gives a fully validated portable vault a new device-local LowKey
    /// wrapper. The archive recovery credential is never accepted by the
    /// normal keypad and no existing vault credential or photo directory is
    /// replaced.
    func installValidatedPortableVault(
        _ restore: ValidatedPortableVaultRestore,
        newPasscode: String
    ) async throws -> UnlockedVault {
        guard PasscodePolicy.isAcceptableNewPasscode(newPasscode) else {
            throw KeyDerivationError.invalidPasscode
        }

        let unlockKey = try deriveUnlockKey(passcode: newPasscode)
        let installer = try PortableVaultRestoreInstaller(
            credentialStore: store,
            journalAuthenticationKey: try portableRestoreJournalKey()
        )
        do {
            let payload = try await installer.install(
                restore,
                localUnlockKey: unlockKey
            )
            return unlockedVault(from: payload)
        } catch PortableVaultRestoreInstallationError.credentialAlreadyUsed {
            throw VaultUnlockError.passcodeAlreadyUsed
        } catch {
            throw VaultUnlockError.mutationFailed
        }
    }

    func unlock(passcode: String) async throws -> UnlockedVault {
        do {
            try await limiter.checkAllowed()
        } catch UnlockAttemptLimiter.LimitError.temporarilyLocked(let until) {
            throw VaultUnlockError.temporarilyLocked(until)
        }

        guard PasscodePolicy.isValidForUnlock(passcode) else {
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

    /// Re-authenticates the vault that is already open without revealing or
    /// accepting credentials for any other local vault.
    func reauthenticateCurrentVault(
        passcode: String,
        expectedVaultID: UUID
    ) async throws -> ReauthenticatedVault {
        guard PasscodePolicy.isValidForUnlock(passcode) else {
            throw VaultUnlockError.invalidCredentials
        }

        let unlockKey = try deriveUnlockKey(passcode: passcode)
        let locator = VaultLocator.derive(from: unlockKey)
        guard let envelope = try await store.read(locator: locator) else {
            throw VaultUnlockError.invalidCredentials
        }

        let payload: VaultPayload
        do {
            payload = try envelope.open(using: unlockKey)
        } catch {
            throw VaultUnlockError.invalidCredentials
        }
        guard payload.vaultID == expectedVaultID else {
            throw VaultUnlockError.invalidCredentials
        }
        // Deliberately do not return a second copy of the vault key. The active
        // session capability remains the only key source used by export.
        return ReauthenticatedVault(
            vaultID: payload.vaultID,
            createdAt: payload.createdAt
        )
    }

    /// Changes only the passcode wrapper. The vault's random data key and all
    /// encrypted photo blobs remain unchanged, avoiding bulk decrypt/re-encrypt.
    /// The current passcode must resolve to the vault that is actually open.
    func changePasscode(
        currentPasscode: String,
        newPasscode: String,
        expectedVaultID: UUID
    ) async throws -> UnlockedVault {
        guard PasscodePolicy.isValidForUnlock(currentPasscode) else {
            throw VaultUnlockError.invalidCredentials
        }
        guard PasscodePolicy.isAcceptableNewPasscode(newPasscode) else {
            throw KeyDerivationError.invalidPasscode
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
        guard PasscodePolicy.isValidForUnlock(currentPasscode) else {
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
            try VaultPhotoStore.destroyVaultData(
                vaultID: payload.vaultID,
                storageRoot: photoStorageRootOverride
            )
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

    private func portableRestoreJournalKey() throws -> SymmetricKey {
        try PortableVaultRestoreJournalKeySchedule.key(
            devicePepper: secrets.loadOrCreate()
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

