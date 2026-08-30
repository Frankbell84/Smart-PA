import Foundation
import CryptoKit
import Argon2Swift

enum KeyDerivationError: Error {
    case invalidPasscode
    case invalidSalt
    case invalidOutput
}

protocol PasswordKeyDeriving {
    func deriveKey(passcode: String, salt: Data, pepper: Data) throws -> SymmetricKey
}

/// Production candidate KDF for NoxLock.
///
/// The passcode is first keyed with the device-local pepper using HMAC-SHA256,
/// then fed to Argon2id with a per-vault random salt. This prevents ambiguous
/// concatenation and means a stolen app container is not enough to test PIN
/// guesses without also recovering the device-local Keychain pepper.
///
/// Release gate: benchmark these Argon2id parameters on the minimum supported
/// iPhone and independently review the dependency + integration before launch.
struct ProductionArgon2idKDF: PasswordKeyDeriving {
    static let memoryKiB = 65_536   // 64 MiB
    static let iterations = 3
    static let parallelism = 2
    static let outputByteCount = 32

    func deriveKey(passcode: String, salt: Data, pepper: Data) throws -> SymmetricKey {
        guard PasscodePolicy.isValid(passcode) else { throw KeyDerivationError.invalidPasscode }
        guard salt.count >= 16 else { throw KeyDerivationError.invalidSalt }
        guard pepper.count == 32 else { throw KeyDerivationError.invalidOutput }

        let pepperKey = SymmetricKey(data: pepper)
        let prehash = HMAC<SHA256>.authenticationCode(
            for: Data(passcode.utf8),
            using: pepperKey
        )

        let result = try Argon2Swift.hashPasswordBytes(
            password: Data(prehash),
            salt: Salt(bytes: salt),
            iterations: Self.iterations,
            memory: Self.memoryKiB,
            parallelism: Self.parallelism,
            length: Self.outputByteCount,
            type: .id,
            version: .V13
        )

        let data = result.hashData()
        guard data.count == Self.outputByteCount else { throw KeyDerivationError.invalidOutput }
        return SymmetricKey(data: data)
    }
}

enum VaultKeySchedule {
    static func locatorKey(from pepper: Data) -> SymmetricKey {
        HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: pepper),
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
