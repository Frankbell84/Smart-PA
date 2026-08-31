import CryptoKit
import Foundation
import Security

enum PortableArchiveError: Error, Equatable {
    case invalidCredential
    case invalidHeader
    case invalidKDFParameters
    case authenticationFailed
    case unsupportedVersion
    case randomGenerationFailed
}

struct PortableArchiveKDFParameters: Codable, Equatable, Sendable {
    static let algorithmIdentifier = "argon2id-v1.3"
    static let saltByteCount = 16
    static let memoryKiB: UInt32 = 65_536
    static let iterations: UInt32 = 3
    static let parallelism: UInt32 = 2
    static let outputByteCount = 32

    let algorithm: String
    let salt: Data
    let memoryKiB: UInt32
    let iterations: UInt32
    let parallelism: UInt32
    let outputByteCount: Int

    static func create() throws -> PortableArchiveKDFParameters {
        PortableArchiveKDFParameters(
            algorithm: algorithmIdentifier,
            salt: try SecureRandom.data(byteCount: saltByteCount),
            memoryKiB: memoryKiB,
            iterations: iterations,
            parallelism: parallelism,
            outputByteCount: outputByteCount
        )
    }

    func validate() throws {
        guard algorithm == Self.algorithmIdentifier,
              salt.count == Self.saltByteCount,
              memoryKiB == Self.memoryKiB,
              iterations == Self.iterations,
              parallelism == Self.parallelism,
              outputByteCount == Self.outputByteCount else {
            throw PortableArchiveError.invalidKDFParameters
        }
    }

    func authenticationData(archiveVersion: Int) -> Data {
        var result = Data("keyhollow.encrypted-vault.header".utf8)
        result.append(0)
        result.append(Data(algorithm.utf8))
        result.append(0)
        result.appendFixedWidth(UInt32(archiveVersion))
        result.appendFixedWidth(memoryKiB)
        result.appendFixedWidth(iterations)
        result.appendFixedWidth(parallelism)
        result.appendFixedWidth(UInt32(outputByteCount))
        result.append(salt)
        return result
    }
}

enum PortableArchiveCredential: Equatable, Sendable {
    case recoveryCode(String)
    case passphrase(String)

    func keyMaterial() throws -> Data {
        switch self {
        case .recoveryCode(let code):
            let canonical = try PortableArchiveRecoveryCode.canonicalize(code)
            return Data("keyhollow.recovery-code.v1:\(canonical)".utf8)

        case .passphrase(let passphrase):
            let canonical = passphrase.precomposedStringWithCanonicalMapping
            guard canonical == canonical.trimmingCharacters(in: .whitespacesAndNewlines),
                  canonical.count >= 16,
                  canonical.count <= 128,
                  canonical.utf8.count <= 256,
                  Set(canonical).count >= 6 else {
                throw PortableArchiveError.invalidCredential
            }
            return Data("keyhollow.passphrase.v1:\(canonical)".utf8)
        }
    }
}

enum PortableArchiveRecoveryCode {
    static let randomByteCount = 20
    static let encodedCharacterCount = 32
    private static let alphabet = Array("0123456789ABCDEFGHJKMNPQRSTVWXYZ")
    private static let allowed = Set(alphabet)

    static func generate() throws -> String {
        let raw = try SecureRandom.data(byteCount: randomByteCount)
        let encoded = encode(raw)
        return stride(from: 0, to: encoded.count, by: 4)
            .map { offset in
                let start = encoded.index(encoded.startIndex, offsetBy: offset)
                let end = encoded.index(start, offsetBy: min(4, encoded.count - offset))
                return String(encoded[start..<end])
            }
            .joined(separator: "-")
    }

    static func canonicalize(_ input: String) throws -> String {
        let compact = input.uppercased().filter { character in
            character != "-" && !character.isWhitespace
        }

        let canonical = compact.map { character -> Character in
            switch character {
            case "O": return "0"
            case "I", "L": return "1"
            default: return character
            }
        }

        guard canonical.count == encodedCharacterCount,
              canonical.allSatisfy({ allowed.contains($0) }) else {
            throw PortableArchiveError.invalidCredential
        }
        return String(canonical)
    }

    private static func encode(_ data: Data) -> String {
        var result = ""
        var accumulator: UInt64 = 0
        var bitCount = 0

        for byte in data {
            accumulator = (accumulator << 8) | UInt64(byte)
            bitCount += 8

            while bitCount >= 5 {
                let shift = bitCount - 5
                let index = Int((accumulator >> UInt64(shift)) & 0x1f)
                result.append(alphabet[index])
                bitCount -= 5
                accumulator &= bitCount == 0 ? 0 : (1 << UInt64(bitCount)) - 1
            }
        }

        if bitCount > 0 {
            let index = Int((accumulator << UInt64(5 - bitCount)) & 0x1f)
            result.append(alphabet[index])
        }
        return result
    }
}

protocol PortableArchiveKeyDeriving: Sendable {
    func deriveWrappingKey(
        credential: PortableArchiveCredential,
        parameters: PortableArchiveKDFParameters
    ) throws -> SymmetricKey
}

struct PortableArchiveArgon2idKeyDeriver: PortableArchiveKeyDeriving {
    func deriveWrappingKey(
        credential: PortableArchiveCredential,
        parameters: PortableArchiveKDFParameters
    ) throws -> SymmetricKey {
        try parameters.validate()
        return try Argon2id.deriveKey(
            password: credential.keyMaterial(),
            salt: parameters.salt,
            memoryKiB: parameters.memoryKiB,
            iterations: parameters.iterations,
            parallelism: parameters.parallelism,
            outputByteCount: parameters.outputByteCount,
            associatedData: Data("keyhollow.portable-archive.wrapper.v1".utf8)
        )
    }
}

struct PortableArchiveSecrets: Codable, Equatable, Sendable {
    let archiveID: UUID
    let sourceVaultID: UUID
    let sourceVaultCreatedAt: Date
    let exportedAt: Date
    let vaultKey: Data
    let contentKey: Data
}

struct PreparedEncryptedVaultArchive: Sendable {
    let header: EncryptedVaultArchiveHeader
    let secrets: PortableArchiveSecrets
}

struct EncryptedVaultArchiveHeader: Codable, Equatable, Sendable {
    static let formatIdentifier = "com.keyhollow.encrypted-vault"
    static let currentVersion = 1

    let format: String
    let version: Int
    let kdf: PortableArchiveKDFParameters
    let sealedSecrets: Data

    static func create(
        vaultPayload: VaultPayload,
        credential: PortableArchiveCredential,
        exportedAt: Date = Date(),
        keyDeriver: any PortableArchiveKeyDeriving = PortableArchiveArgon2idKeyDeriver()
    ) throws -> EncryptedVaultArchiveHeader {
        try prepare(
            vaultPayload: vaultPayload,
            credential: credential,
            exportedAt: exportedAt,
            keyDeriver: keyDeriver
        ).header
    }

    static func prepare(
        vaultPayload: VaultPayload,
        credential: PortableArchiveCredential,
        exportedAt: Date = Date(),
        keyDeriver: any PortableArchiveKeyDeriving = PortableArchiveArgon2idKeyDeriver()
    ) throws -> PreparedEncryptedVaultArchive {
        guard vaultPayload.vaultKey.count == 32 else {
            throw PortableArchiveError.invalidHeader
        }

        let kdf = try PortableArchiveKDFParameters.create()
        let secrets = PortableArchiveSecrets(
            archiveID: UUID(),
            sourceVaultID: vaultPayload.vaultID,
            sourceVaultCreatedAt: vaultPayload.createdAt,
            exportedAt: exportedAt,
            vaultKey: vaultPayload.vaultKey,
            contentKey: try SecureRandom.data(byteCount: 32)
        )
        let plaintext = try JSONEncoder().encode(secrets)
        let wrappingKey = try keyDeriver.deriveWrappingKey(
            credential: credential,
            parameters: kdf
        )
        let box = try AES.GCM.seal(
            plaintext,
            using: wrappingKey,
            authenticating: kdf.authenticationData(archiveVersion: currentVersion)
        )
        guard let combined = box.combined else {
            throw PortableArchiveError.invalidHeader
        }

        let header = EncryptedVaultArchiveHeader(
            format: formatIdentifier,
            version: currentVersion,
            kdf: kdf,
            sealedSecrets: combined
        )
        return PreparedEncryptedVaultArchive(header: header, secrets: secrets)
    }

    func open(
        credential: PortableArchiveCredential,
        keyDeriver: any PortableArchiveKeyDeriving = PortableArchiveArgon2idKeyDeriver()
    ) throws -> PortableArchiveSecrets {
        guard format == Self.formatIdentifier else {
            throw PortableArchiveError.invalidHeader
        }
        guard version == Self.currentVersion else {
            throw PortableArchiveError.unsupportedVersion
        }
        try kdf.validate()

        do {
            let wrappingKey = try keyDeriver.deriveWrappingKey(
                credential: credential,
                parameters: kdf
            )
            let box = try AES.GCM.SealedBox(combined: sealedSecrets)
            let plaintext = try AES.GCM.open(
                box,
                using: wrappingKey,
                authenticating: kdf.authenticationData(archiveVersion: version)
            )
            let secrets = try JSONDecoder().decode(PortableArchiveSecrets.self, from: plaintext)
            guard secrets.vaultKey.count == 32,
                  secrets.contentKey.count == 32 else {
                throw PortableArchiveError.invalidHeader
            }
            return secrets
        } catch let error as PortableArchiveError {
            throw error
        } catch {
            throw PortableArchiveError.authenticationFailed
        }
    }
}

private enum SecureRandom {
    static func data(byteCount: Int) throws -> Data {
        guard byteCount > 0 else { throw PortableArchiveError.randomGenerationFailed }
        var bytes = [UInt8](repeating: 0, count: byteCount)
        guard SecRandomCopyBytes(kSecRandomDefault, byteCount, &bytes) == errSecSuccess else {
            throw PortableArchiveError.randomGenerationFailed
        }
        return Data(bytes)
    }
}

private extension Data {
    mutating func appendFixedWidth(_ value: UInt32) {
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) { bytes in
            append(contentsOf: bytes)
        }
    }
}
