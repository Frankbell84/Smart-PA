import Foundation
import CryptoKit

struct VaultPayload: Codable {
    let vaultID: UUID
    let vaultKey: Data
    let createdAt: Date
}

struct VaultEnvelope: Codable {
    static let currentVersion = 1

    let version: Int
    let salt: Data
    let sealedPayload: Data

    static func create(
        passcode: String,
        pepper: Data,
        kdf: PasswordKeyDeriving = ProductionArgon2idKDF()
    ) throws -> (envelope: VaultEnvelope, payload: VaultPayload) {
        var saltBytes = [UInt8](repeating: 0, count: 16)
        guard SecRandomCopyBytes(kSecRandomDefault, saltBytes.count, &saltBytes) == errSecSuccess else {
            throw DevicePepperError.invalidData
        }
        let salt = Data(saltBytes)

        var vaultKeyBytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, vaultKeyBytes.count, &vaultKeyBytes) == errSecSuccess else {
            throw DevicePepperError.invalidData
        }

        let payload = VaultPayload(
            vaultID: UUID(),
            vaultKey: Data(vaultKeyBytes),
            createdAt: Date()
        )

        let unlockKey = try kdf.deriveKey(passcode: passcode, salt: salt, pepper: pepper)
        let wrappingKey = VaultKeySchedule.wrappingKey(from: unlockKey)
        let payloadData = try JSONEncoder().encode(payload)
        let sealed = try CryptoBox.seal(payloadData, using: wrappingKey)

        return (
            VaultEnvelope(version: currentVersion, salt: salt, sealedPayload: sealed),
            payload
        )
    }

    func open(
        passcode: String,
        pepper: Data,
        kdf: PasswordKeyDeriving = ProductionArgon2idKDF()
    ) throws -> VaultPayload {
        guard version == Self.currentVersion else { throw CryptoBoxError.invalidEnvelope }
        let unlockKey = try kdf.deriveKey(passcode: passcode, salt: salt, pepper: pepper)
        let wrappingKey = VaultKeySchedule.wrappingKey(from: unlockKey)
        let plaintext = try CryptoBox.open(sealedPayload, using: wrappingKey)
        let payload = try JSONDecoder().decode(VaultPayload.self, from: plaintext)
        guard payload.vaultKey.count == 32 else { throw CryptoBoxError.invalidEnvelope }
        return payload
    }
}
