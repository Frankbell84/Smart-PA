import Foundation
import CryptoKit

enum VaultLocator {
    /// Derives a stable opaque file locator only after the expensive passcode
    /// KDF has completed. Full 256-bit output keeps collisions negligible.
    static func derive(from unlockKey: SymmetricKey) -> String {
        let key = VaultKeySchedule.locatorKey(from: unlockKey)
        let code = HMAC<SHA256>.authenticationCode(
            for: Data("noxlock.vault-locator.v1".utf8),
            using: key
        )
        return Data(code).map { String(format: "%02x", $0) }.joined()
    }
}
