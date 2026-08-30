import Foundation
import CryptoKit

enum VaultUnlockError: Error, Equatable {
    case invalidCredentials
    case passcodeAlreadyUsed
    case temporarilyLocked(Date)
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

    func createVault(passcode: String) async throws -> UnlockedVault {
        guard PasscodePolicy.isValid(passcode) else { throw KeyDerivationError.invalidPasscode }

        let pepper = try secrets.loadOrCreate()
        let installationSalt = try secrets.loadOrCreateInstallationSalt()
        let unlockKey = try kdf.deriveKey(
            passcode: passcode,
            installationSalt: installationSalt,
            pepper: pepper
        )
        let locator = VaultLocator.derive(from: unlockKey)

        if await store.contains(locator: locator) {
            throw VaultUnlockError.passcodeAlreadyUsed
        }

        let created = try VaultEnvelope.create(using: unlockKey)
        try await store.write(created.envelope, locator: locator)

        return UnlockedVault(
            vaultID: created.payload.vaultID,
            vaultKey: SymmetricKey(data: created.payload.vaultKey),
            createdAt: created.payload.createdAt
        )
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
            let pepper = try secrets.loadOrCreate()
            let installationSalt = try secrets.loadOrCreateInstallationSalt()

            // Intentionally pay the Argon2id cost before checking whether the
            // resulting opaque locator exists. This reduces a basic timing clue
            // between a real passcode and a random guess.
            let unlockKey = try kdf.deriveKey(
                passcode: passcode,
                installationSalt: installationSalt,
                pepper: pepper
            )
            let locator = VaultLocator.derive(from: unlockKey)

            guard let envelope = try await store.read(locator: locator) else {
                await limiter.recordFailure()
                throw VaultUnlockError.invalidCredentials
            }

            let payload = try envelope.open(using: unlockKey)
            await limiter.recordSuccess()

            return UnlockedVault(
                vaultID: payload.vaultID,
                vaultKey: SymmetricKey(data: payload.vaultKey),
                createdAt: payload.createdAt
            )
        } catch let error as VaultUnlockError {
            throw error
        } catch {
            // Do not expose whether failure came from a missing file, malformed
            // envelope, authentication failure, or any other credential path.
            await limiter.recordFailure()
            throw VaultUnlockError.invalidCredentials
        }
    }
}
