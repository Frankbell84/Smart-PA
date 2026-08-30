import Foundation
import CryptoKit
import Argon2idSwiftNative

enum KeyDerivationError: Error {
    case invalidPasscode
    case invalidSalt
    case invalidOutput
}

protocol PasswordKeyDeriving: Sendable {
    func deriveKey(passcode: String, installationSalt: Data, pepper: Data) throws -> SymmetricKey
}

/// Production-candidate KDF for KeyHollow.
///
/// Every unlock attempt runs this KDF before any vault-file lookup. That avoids
/// a simple timing signal where nonexistent passcodes would otherwise fail much
/// faster than valid ones.
///
/// The passcode is first keyed with the device-local pepper using HMAC-SHA256,
/// then fed to Argon2id with a random installation salt. The pepper and salt are
/// both device-local in V1; neither is an alternate unlock credential.
///
/// Release gate: benchmark these parameters on the minimum supported iPhone and
/// independently review this dependency + integration before launch.
struct ProductionArgon2idKDF: PasswordKeyDeriving {
    static let memoryKiB: UInt32 = 65_536   // 64 MiB development starting point
    static let iterations: UInt32 = 3
    static let parallelism: UInt32 = 2

    func deriveKey(passcode: String, installationSalt: Data, pepper: Data) throws -> SymmetricKey {
        guard PasscodePolicy.isValid(passcode) else { throw KeyDerivationError.invalidPasscode }
        guard installationSalt.count >= 16 else { throw KeyDerivationError.invalidSalt }
        guard pepper.count == 32 else { throw KeyDerivationError.invalidOutput }

        let pepperKey = SymmetricKey(data: pepper)
        let prehash = HMAC<SHA256>.authenticationCode(
            for: Data(passcode.utf8),
            using: pepperKey
        )

        return try Argon2id.deriveKey(
            password: Data(prehash),
            salt: installationSalt,
            memoryKiB: Self.memoryKiB,
            iterations: Self.iterations,
            parallelism: Self.parallelism
        )
    }
}

enum VaultKeySchedule {
    static func locatorKey(from unlockKey: SymmetricKey) -> SymmetricKey {
        HKDF<SHA256>.deriveKey(
            inputKeyMaterial: unlockKey,
            salt: Data("keyhollow.locator.v1".utf8),
            info: Data(),
            outputByteCount: 32
        )
    }

    static func wrappingKey(from unlockKey: SymmetricKey) -> SymmetricKey {
        HKDF<SHA256>.deriveKey(
            inputKeyMaterial: unlockKey,
            salt: Data("keyhollow.wrapper.v1".utf8),
            info: Data(),
            outputByteCount: 32
        )
    }
}
