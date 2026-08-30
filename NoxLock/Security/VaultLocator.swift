import Foundation
import CryptoKit

enum VaultLocator {
    /// Derives an opaque stable locator for a passcode on this installation.
    /// The locator is not a password hash and is useless without the Keychain
    /// pepper. Full 256-bit output keeps collisions negligible.
    static func derive(passcode: String, pepper: Data) throws -> String {
        guard PasscodePolicy.isValid(passcode) else { throw KeyDerivationError.invalidPasscode }
        let key = VaultKeySchedule.locatorKey(from: pepper)
        var message = Data("noxlock.vault-locator.v1".utf8)
        message.append(0)
        message.append(contentsOf: passcode.utf8)
        let code = HMAC<SHA256>.authenticationCode(for: message, using: key)
        return Data(code).map { String(format: "%02x", $0) }.joined()
    }
}
