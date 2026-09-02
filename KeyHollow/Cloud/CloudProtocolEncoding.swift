import Foundation

enum CloudProtocolError: Error, Equatable {
    case authenticationFailed
    case duplicateIdentifier(String)
    case invalidLength(String)
    case invalidMagic
    case invalidValue(String)
    case randomGenerationFailed
    case trailingData
    case truncated
    case unsupportedVersion
}

enum CloudProtocolLimits {
    static let sealedEnvelopeByteCount = 4_096
    static let manifestPlaintextByteCount = 33_554_432
    static let manifestEntryCount = 200_001
    static let innerObjectByteCount: UInt64 = 1_099_511_627_776
    static let generationInnerByteCount: UInt64 = 4_398_046_511_104
    static let cloudObjectChunkByteCount: UInt32 = 1_048_576
    static let localStorageNameByteCount = 255
    static let sha256ByteCount = 32
}

struct CloudBinaryEncoder {
    private(set) var data = Data()

    mutating func append(_ value: UInt8) {
        data.append(value)
    }

    mutating func append(_ value: UInt32) {
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) { bytes in
            data.append(contentsOf: bytes)
        }
    }

    mutating func append(_ value: UInt64) {
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) { bytes in
            data.append(contentsOf: bytes)
        }
    }

    mutating func append(uuid: UUID) {
        var bytes = uuid.uuid
        Swift.withUnsafeBytes(of: &bytes) { raw in
            data.append(contentsOf: raw)
        }
    }

    mutating func append(fixed data: Data, byteCount: Int, field: String) throws {
        guard data.count == byteCount else {
            throw CloudProtocolError.invalidLength(field)
        }
        self.data.append(data)
    }

    mutating func append(lengthPrefixed value: Data, maximum: Int, field: String) throws {
        guard value.count <= maximum,
              value.count <= Int(UInt32.max) else {
            throw CloudProtocolError.invalidLength(field)
        }
        append(UInt32(value.count))
        data.append(value)
    }

    mutating func append(string: String, maximumUTF8ByteCount: Int, field: String) throws {
        let canonical = string.precomposedStringWithCanonicalMapping
        guard string == canonical,
              !string.contains("\0") else {
            throw CloudProtocolError.invalidValue(field)
        }
        try append(
            lengthPrefixed: Data(string.utf8),
            maximum: maximumUTF8ByteCount,
            field: field
        )
    }
}

struct CloudBinaryDecoder {
    private let bytes: [UInt8]
    private(set) var offset = 0

    init(_ data: Data, maximumByteCount: Int? = nil) throws {
        if let maximumByteCount, data.count > maximumByteCount {
            throw CloudProtocolError.invalidLength("encoded value")
        }
        bytes = Array(data)
    }

    var remainingByteCount: Int {
        bytes.count - offset
    }

    mutating func readUInt8() throws -> UInt8 {
        guard remainingByteCount >= 1 else { throw CloudProtocolError.truncated }
        defer { offset += 1 }
        return bytes[offset]
    }

    mutating func readUInt32() throws -> UInt32 {
        let value = Array(try readBytes(count: 4))
        return UInt32(value[0])
            | (UInt32(value[1]) << 8)
            | (UInt32(value[2]) << 16)
            | (UInt32(value[3]) << 24)
    }

    mutating func readUInt64() throws -> UInt64 {
        let value = try readBytes(count: 8)
        var result: UInt64 = 0
        for (index, byte) in value.enumerated() {
            result |= UInt64(byte) << UInt64(index * 8)
        }
        return result
    }

    mutating func readUUID() throws -> UUID {
        let value = Array(try readBytes(count: 16))
        return UUID(uuid: (
            value[0], value[1], value[2], value[3],
            value[4], value[5], value[6], value[7],
            value[8], value[9], value[10], value[11],
            value[12], value[13], value[14], value[15]
        ))
    }

    mutating func readFixedData(byteCount: Int, field: String) throws -> Data {
        guard byteCount >= 0 else { throw CloudProtocolError.invalidLength(field) }
        return Data(try readBytes(count: byteCount))
    }

    mutating func readLengthPrefixedData(maximum: Int, field: String) throws -> Data {
        let count = Int(try readUInt32())
        guard count <= maximum else { throw CloudProtocolError.invalidLength(field) }
        return try readFixedData(byteCount: count, field: field)
    }

    mutating func readString(maximumUTF8ByteCount: Int, field: String) throws -> String {
        let value = try readLengthPrefixedData(
            maximum: maximumUTF8ByteCount,
            field: field
        )
        guard let string = String(data: value, encoding: .utf8),
              string == string.precomposedStringWithCanonicalMapping,
              !string.contains("\0") else {
            throw CloudProtocolError.invalidValue(field)
        }
        return string
    }

    mutating func requireMagic(_ expected: Data) throws {
        guard try readFixedData(byteCount: expected.count, field: "magic") == expected else {
            throw CloudProtocolError.invalidMagic
        }
    }

    func requireFinished() throws {
        guard remainingByteCount == 0 else { throw CloudProtocolError.trailingData }
    }

    private mutating func readBytes(count: Int) throws -> ArraySlice<UInt8> {
        guard count >= 0,
              count <= remainingByteCount else {
            throw CloudProtocolError.truncated
        }
        let start = offset
        offset += count
        return bytes[start..<offset]
    }
}

extension UUID {
    var isCloudNilUUID: Bool {
        var bytes = uuid
        return Swift.withUnsafeBytes(of: &bytes) { raw in
            raw.allSatisfy { $0 == 0 }
        }
    }
}
