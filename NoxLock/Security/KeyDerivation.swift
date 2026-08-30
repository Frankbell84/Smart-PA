import Foundation
import CryptoKit

enum KeyDerivationError: Error {
    case productionKDFNotConfigured
    case invalidPasscode
}

protocol PasswordKeyDeriving {
    func deriveKey(passcode: String, salt: Data, pepper: Data) throws -> SymmetricKey
}

/// Fails closed until a vetted Argon2id implementation is wired into the app.
/// Do not replace this with SHA-256, HKDF, or a low-iteration PBKDF solely to make the UI unlock.
struct ProductionArgon2idKDF: PasswordKeyDeriving {
    func deriveKey(passcode: String, salt: Data, pepper: Data) throws -> SymmetricKey {
        guard PasscodePolicy.isValid(passcode) else { throw KeyDerivationError.invalidPasscode }

        // SECURITY RELEASE GATE:
        // Integrate a reviewed Argon2id Swift package and benchmark parameters on
        // the minimum supported iPhone. The passcode and a device-local pepper
        // are combined as KDF input; the per-installation/vault salt is public.
        throw KeyDerivationError.productionKDFNotConfigured
    }
}

enum VaultKeySchedule {
    static func locatorKey(from unlockKey: SymmetricKey) -> SymmetricKey {
        HKDF<SHA256>.deriveKey(
            inputKeyMaterial: unlockKey,
            salt: Data("noxlock.locator.v1".utf8),
            info: Data(),
            outputByteCount: 32
        )
    }

    static func wrappingKey(from unlockKey: SymmetricKey) -> SymmetricKey {
        HKDF<SHA256>.deriveKey(
            inputKeyMaterial: unlockKey,
            salt: Data("noxlock.wrapper.v1".utf8),
            info: Data(),
            outputByteCount: 32
        )
    }
}
