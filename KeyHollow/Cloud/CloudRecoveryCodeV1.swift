import CryptoKit
import Foundation
import Security

struct DecodedCloudRecoveryCodeV1: Equatable, Sendable {
    let rawBytes: Data
    let dataCharacters: String
    let checksumCharacters: String

    var formatted: String {
        let groups = stride(from: 0, to: dataCharacters.count, by: 4).map { offset in
            let start = dataCharacters.index(dataCharacters.startIndex, offsetBy: offset)
            let end = dataCharacters.index(
                start,
                offsetBy: min(4, dataCharacters.count - offset)
            )
            return String(dataCharacters[start..<end])
        }
        return "KH1-" + groups.joined(separator: "-") + "-" + checksumCharacters
    }
}

enum CloudRecoveryCodeV1 {
    static let randomByteCount = 20
    static let encodedDataCharacterCount = 32
    static let encodedChecksumCharacterCount = 2
    static let versionPrefix = "KH1"
    static let keyMaterialPrefix = "keyhollow.cloud-recovery-key.v1:"
    static let argon2AssociatedData = Data("keyhollow.cloud.recovery-rwk.v1".utf8)

    private static let checksumDomain = Data("keyhollow.cloud.crk-checksum.v1".utf8)
    private static let alphabet = Array("0123456789ABCDEFGHJKMNPQRSTVWXYZ")
    private static let allowed = Set(alphabet)

    static func generate() throws -> String {
        var bytes = [UInt8](repeating: 0, count: randomByteCount)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            throw CloudProtocolError.randomGenerationFailed
        }
        return try value(rawBytes: Data(bytes)).formatted
    }

    static func decode(_ input: String) throws -> DecodedCloudRecoveryCodeV1 {
        let compact = input.uppercased().filter { character in
            character != "-" && !character.isWhitespace
        }.map(normalizedCharacter)

        let expectedCount = versionPrefix.count
            + encodedDataCharacterCount
            + encodedChecksumCharacterCount
        guard compact.count == expectedCount,
              String(compact.prefix(versionPrefix.count)) == versionPrefix else {
            throw CloudProtocolError.invalidValue("cloud recovery code")
        }

        let payloadStart = versionPrefix.count
        let checksumStart = payloadStart + encodedDataCharacterCount
        let dataCharacters = String(compact[payloadStart..<checksumStart])
        let checksumCharacters = String(compact[checksumStart..<expectedCount])
        guard dataCharacters.allSatisfy({ allowed.contains($0) }),
              checksumCharacters.allSatisfy({ allowed.contains($0) }) else {
            throw CloudProtocolError.invalidValue("cloud recovery code")
        }

        let rawBytes = try decodeBase32(dataCharacters)
        let decoded = try value(rawBytes: rawBytes)
        guard decoded.dataCharacters == dataCharacters,
              decoded.checksumCharacters == checksumCharacters else {
            throw CloudProtocolError.invalidValue("cloud recovery code checksum")
        }
        return decoded
    }

    static func keyMaterial(from input: String) throws -> Data {
        let decoded = try decode(input)
        return Data((keyMaterialPrefix + decoded.dataCharacters).utf8)
    }

    static func value(rawBytes: Data) throws -> DecodedCloudRecoveryCodeV1 {
        guard rawBytes.count == randomByteCount else {
            throw CloudProtocolError.invalidLength("cloud recovery key")
        }
        let dataCharacters = try encodeBase32(rawBytes)
        return DecodedCloudRecoveryCodeV1(
            rawBytes: rawBytes,
            dataCharacters: dataCharacters,
            checksumCharacters: checksum(rawBytes)
        )
    }

    private static func normalizedCharacter(_ character: Character) -> Character {
        switch character {
        case "O": return "0"
        case "I", "L": return "1"
        default: return character
        }
    }

    private static func checksum(_ rawBytes: Data) -> String {
        var input = checksumDomain
        input.append(0)
        input.append(rawBytes)
        let digest = SHA256.hash(data: input)
        let first = digest[digest.startIndex]
        let second = digest[digest.index(after: digest.startIndex)]
        let tenBits = (UInt16(first) << 2) | (UInt16(second) >> 6)
        return String(alphabet[Int((tenBits >> 5) & 0x1f)])
            + String(alphabet[Int(tenBits & 0x1f)])
    }

    private static func encodeBase32(_ data: Data) throws -> String {
        var result = ""
        var accumulator: UInt64 = 0
        var bitCount = 0

        for byte in data {
            accumulator = (accumulator << 8) | UInt64(byte)
            bitCount += 8
            while bitCount >= 5 {
                let shift = bitCount - 5
                result.append(alphabet[Int((accumulator >> UInt64(shift)) & 0x1f)])
                bitCount -= 5
                accumulator &= bitCount == 0 ? 0 : (1 << UInt64(bitCount)) - 1
            }
        }
        guard bitCount == 0,
              result.count == encodedDataCharacterCount else {
            throw CloudProtocolError.invalidLength("cloud recovery key")
        }
        return result
    }

    private static func decodeBase32(_ string: String) throws -> Data {
        var output = Data()
        output.reserveCapacity(randomByteCount)
        var accumulator: UInt64 = 0
        var bitCount = 0

        for character in string {
            guard let index = alphabet.firstIndex(of: character) else {
                throw CloudProtocolError.invalidValue("cloud recovery code")
            }
            accumulator = (accumulator << 5) | UInt64(index)
            bitCount += 5
            while bitCount >= 8 {
                let shift = bitCount - 8
                output.append(UInt8((accumulator >> UInt64(shift)) & 0xff))
                bitCount -= 8
                accumulator &= bitCount == 0 ? 0 : (1 << UInt64(bitCount)) - 1
            }
        }

        guard bitCount == 0,
              output.count == randomByteCount else {
            throw CloudProtocolError.invalidValue("cloud recovery code")
        }
        return output
    }
}
