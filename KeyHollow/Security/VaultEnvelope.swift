import Foundation
import CryptoKit
import Security

struct VaultPayload: Codable {
    let vaultID: UUID
    let vaultKey: Data
    let createdAt: Date
}

struct VaultEnvelope: Codable {
    static let currentVersion = 1

    let version: Int
    let sealedPayload: Data

    static func create(using unlockKey: SymmetricKey) throws -> (envelope: VaultEnvelope, payload: VaultPayload) {
        var vaultKeyBytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, vaultKeyBytes.count, &vaultKeyBytes) == errSecSuccess else {
            throw DevicePepperError.invalidData
        }

        let payload = VaultPayload(
            vaultID: UUID(),
            vaultKey: Data(vaultKeyBytes),
            createdAt: Date()
        )

        return (try seal(payload: payload, using: unlockKey), payload)
    }

    static func seal(payload: VaultPayload, using unlockKey: SymmetricKey) throws -> VaultEnvelope {
        guard payload.vaultKey.count == 32 else { throw CryptoBoxError.invalidEnvelope }
        let wrappingKey = VaultKeySchedule.wrappingKey(from: unlockKey)
        let payloadData = try JSONEncoder().encode(payload)
        let sealed = try CryptoBox.seal(payloadData, using: wrappingKey)
        return VaultEnvelope(version: currentVersion, sealedPayload: sealed)
    }

    func open(using unlockKey: SymmetricKey) throws -> VaultPayload {
        guard version == Self.currentVersion else { throw CryptoBoxError.invalidEnvelope }
        let wrappingKey = VaultKeySchedule.wrappingKey(from: unlockKey)
        let plaintext = try CryptoBox.open(sealedPayload, using: wrappingKey)
        let payload = try JSONDecoder().decode(VaultPayload.self, from: plaintext)
        guard payload.vaultKey.count == 32 else { throw CryptoBoxError.invalidEnvelope }
        return payload
    }
}
