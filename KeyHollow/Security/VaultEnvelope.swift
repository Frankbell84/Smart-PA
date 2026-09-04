import Foundation
import CryptoKit
import KeyHollowCryptoCore
import Security

public struct VaultPayload: Codable, Sendable {
    public let vaultID: UUID
    public let vaultKey: Data
    public let createdAt: Date

    public init(vaultID: UUID, vaultKey: Data, createdAt: Date) {
        self.vaultID = vaultID
        self.vaultKey = vaultKey
        self.createdAt = createdAt
    }
}

public enum VaultEnvelopeError: Error {
    case randomGenerationFailed
}

public struct VaultEnvelope: Codable, Sendable {
    public static let currentVersion = 1

    public let version: Int
    public let sealedPayload: Data

    public init(version: Int, sealedPayload: Data) {
        self.version = version
        self.sealedPayload = sealedPayload
    }

    public static func create(using unlockKey: SymmetricKey) throws -> (envelope: VaultEnvelope, payload: VaultPayload) {
        var vaultKeyBytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, vaultKeyBytes.count, &vaultKeyBytes) == errSecSuccess else {
            throw VaultEnvelopeError.randomGenerationFailed
        }

        let payload = VaultPayload(
            vaultID: UUID(),
            vaultKey: Data(vaultKeyBytes),
            createdAt: Date()
        )

        return (try seal(payload: payload, using: unlockKey), payload)
    }

    public static func seal(payload: VaultPayload, using unlockKey: SymmetricKey) throws -> VaultEnvelope {
        guard payload.vaultKey.count == 32 else { throw CryptoBoxError.invalidEnvelope }
        let wrappingKey = VaultKeySchedule.wrappingKey(from: unlockKey)
        let payloadData = try JSONEncoder().encode(payload)
        let sealed = try CryptoBox.seal(payloadData, using: wrappingKey)
        return VaultEnvelope(version: currentVersion, sealedPayload: sealed)
    }

    public func open(using unlockKey: SymmetricKey) throws -> VaultPayload {
        guard version == Self.currentVersion else { throw CryptoBoxError.invalidEnvelope }
        let wrappingKey = VaultKeySchedule.wrappingKey(from: unlockKey)
        let plaintext = try CryptoBox.open(sealedPayload, using: wrappingKey)
        let payload = try JSONDecoder().decode(VaultPayload.self, from: plaintext)
        guard payload.vaultKey.count == 32 else { throw CryptoBoxError.invalidEnvelope }
        return payload
    }
}

