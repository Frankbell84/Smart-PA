import Foundation

enum CloudProtocolSuite {
    static let version: UInt32 = 1
    static let algorithmSuite: UInt32 = 1
    static let kdfProfile: UInt32 = 1
}

struct CloudRecoveryEnvelopeHeaderV1: Equatable, Sendable {
    static let magic = Data([0x4b, 0x48, 0x43, 0x52, 0x45, 0x43, 0x31, 0x00])
    static let aadDomain = Data("keyhollow.cloud.recovery-envelope.v1".utf8)
    static let encodedByteCount = 60

    let accountKeyID: UUID
    let envelopeGeneration: UInt64
    let kdfSalt: Data

    func validate() throws {
        guard !accountKeyID.isCloudNilUUID else {
            throw CloudProtocolError.invalidValue("account key ID")
        }
        guard envelopeGeneration >= 1 else {
            throw CloudProtocolError.invalidValue("recovery envelope generation")
        }
        guard kdfSalt.count == 16 else {
            throw CloudProtocolError.invalidLength("Argon2id salt")
        }
    }

    func encoded() throws -> Data {
        try validate()
        var encoder = CloudBinaryEncoder()
        try encoder.append(fixed: Self.magic, byteCount: 8, field: "recovery magic")
        encoder.append(CloudProtocolSuite.version)
        encoder.append(CloudProtocolSuite.algorithmSuite)
        encoder.append(CloudProtocolSuite.kdfProfile)
        encoder.append(uuid: accountKeyID)
        encoder.append(envelopeGeneration)
        try encoder.append(fixed: kdfSalt, byteCount: 16, field: "Argon2id salt")
        return encoder.data
    }

    func authenticationData() throws -> Data {
        var result = Self.aadDomain
        result.append(0)
        result.append(try encoded())
        return result
    }

    init(accountKeyID: UUID, envelopeGeneration: UInt64, kdfSalt: Data) {
        self.accountKeyID = accountKeyID
        self.envelopeGeneration = envelopeGeneration
        self.kdfSalt = kdfSalt
    }

    init(decoding data: Data) throws {
        var decoder = try CloudBinaryDecoder(data)
        try decoder.requireMagic(Self.magic)
        guard try decoder.readUInt32() == CloudProtocolSuite.version else {
            throw CloudProtocolError.unsupportedVersion
        }
        guard try decoder.readUInt32() == CloudProtocolSuite.algorithmSuite,
              try decoder.readUInt32() == CloudProtocolSuite.kdfProfile else {
            throw CloudProtocolError.invalidValue("cryptographic profile")
        }
        accountKeyID = try decoder.readUUID()
        envelopeGeneration = try decoder.readUInt64()
        kdfSalt = try decoder.readFixedData(byteCount: 16, field: "Argon2id salt")
        try decoder.requireFinished()
        try validate()
    }
}

struct CloudVaultKeyEnvelopeHeaderV1: Equatable, Sendable {
    static let magic = Data([0x4b, 0x48, 0x43, 0x56, 0x4b, 0x45, 0x59, 0x00])
    static let aadDomain = Data("keyhollow.cloud.vault-key-envelope.v1".utf8)
    static let keyDerivationDomain = Data("keyhollow.cloud.vault-key-wrapper.v1".utf8)
    static let encodedByteCount = 72

    let accountID: UUID
    let vaultID: UUID
    let vaultKeyID: UUID
    let accountKeyGeneration: UInt64

    func validate() throws {
        guard !accountID.isCloudNilUUID,
              !vaultID.isCloudNilUUID,
              !vaultKeyID.isCloudNilUUID else {
            throw CloudProtocolError.invalidValue("vault-key envelope identifier")
        }
        guard accountKeyGeneration >= 1 else {
            throw CloudProtocolError.invalidValue("account key generation")
        }
    }

    func encoded() throws -> Data {
        try validate()
        var encoder = CloudBinaryEncoder()
        try encoder.append(fixed: Self.magic, byteCount: 8, field: "vault-key magic")
        encoder.append(CloudProtocolSuite.version)
        encoder.append(CloudProtocolSuite.algorithmSuite)
        encoder.append(uuid: accountID)
        encoder.append(uuid: vaultID)
        encoder.append(uuid: vaultKeyID)
        encoder.append(accountKeyGeneration)
        return encoder.data
    }

    func authenticationData() throws -> Data {
        var result = Self.aadDomain
        result.append(0)
        result.append(try encoded())
        return result
    }

    func keyDerivationInfo() throws -> Data {
        try encoded()
    }

    init(
        accountID: UUID,
        vaultID: UUID,
        vaultKeyID: UUID,
        accountKeyGeneration: UInt64
    ) {
        self.accountID = accountID
        self.vaultID = vaultID
        self.vaultKeyID = vaultKeyID
        self.accountKeyGeneration = accountKeyGeneration
    }

    init(decoding data: Data) throws {
        var decoder = try CloudBinaryDecoder(data)
        try decoder.requireMagic(Self.magic)
        guard try decoder.readUInt32() == CloudProtocolSuite.version else {
            throw CloudProtocolError.unsupportedVersion
        }
        guard try decoder.readUInt32() == CloudProtocolSuite.algorithmSuite else {
            throw CloudProtocolError.invalidValue("algorithm suite")
        }
        accountID = try decoder.readUUID()
        vaultID = try decoder.readUUID()
        vaultKeyID = try decoder.readUUID()
        accountKeyGeneration = try decoder.readUInt64()
        try decoder.requireFinished()
        try validate()
    }
}

enum CloudObjectPurposeV1: UInt8, Sendable {
    case manifest = 1
    case content = 2
}

struct CloudObjectHeaderV1: Equatable, Sendable {
    static let magic = Data([0x4b, 0x48, 0x43, 0x4f, 0x42, 0x4a, 0x31, 0x00])
    static let aadDomain = Data("keyhollow.cloud.object-chunk.v1".utf8)
    static let keyDerivationDomain = Data("keyhollow.cloud.object-chunk-key.v1".utf8)
    static let encodedByteCount: UInt64 = 89
    static let framePrefixByteCount: UInt64 = 13
    static let sealedChunkOverheadByteCount: UInt64 = 28

    let purpose: CloudObjectPurposeV1
    let accountID: UUID
    let vaultID: UUID
    let objectID: UUID
    let objectVersion: UInt64
    let plaintextByteCount: UInt64
    let plaintextChunkByteCount: UInt32
    let chunkCount: UInt32

    func validate() throws {
        guard !accountID.isCloudNilUUID,
              !vaultID.isCloudNilUUID,
              !objectID.isCloudNilUUID else {
            throw CloudProtocolError.invalidValue("cloud-object identifier")
        }
        guard objectVersion >= 1 else {
            throw CloudProtocolError.invalidValue("cloud-object version")
        }
        let maximum: UInt64 = purpose == .manifest
            ? UInt64(CloudProtocolLimits.manifestPlaintextByteCount)
            : CloudProtocolLimits.innerObjectByteCount
        guard plaintextByteCount > 0,
              plaintextByteCount <= maximum,
              plaintextChunkByteCount == CloudProtocolLimits.cloudObjectChunkByteCount else {
            throw CloudProtocolError.invalidLength("cloud-object plaintext")
        }
        let expectedChunks = ((plaintextByteCount - 1) / UInt64(plaintextChunkByteCount)) + 1
        guard expectedChunks <= UInt64(UInt32.max),
              chunkCount == UInt32(expectedChunks) else {
            throw CloudProtocolError.invalidValue("cloud-object chunk count")
        }
    }

    func encoded() throws -> Data {
        try validate()
        var encoder = CloudBinaryEncoder()
        try encoder.append(fixed: Self.magic, byteCount: 8, field: "object magic")
        encoder.append(CloudProtocolSuite.version)
        encoder.append(CloudProtocolSuite.algorithmSuite)
        encoder.append(purpose.rawValue)
        encoder.append(uuid: accountID)
        encoder.append(uuid: vaultID)
        encoder.append(uuid: objectID)
        encoder.append(objectVersion)
        encoder.append(plaintextByteCount)
        encoder.append(plaintextChunkByteCount)
        encoder.append(chunkCount)
        return encoder.data
    }

    func chunkKeyInfo(sequence: UInt32) throws -> Data {
        try validateSequence(sequence)
        var encoder = CloudBinaryEncoder()
        encoder.append(purpose.rawValue)
        encoder.append(uuid: objectID)
        encoder.append(objectVersion)
        encoder.append(sequence)
        return encoder.data
    }

    static func storedByteCount(
        plaintextByteCount: UInt64,
        chunkCount: UInt32
    ) throws -> UInt64 {
        let perChunkOverhead = framePrefixByteCount + sealedChunkOverheadByteCount
        let (allChunkOverhead, multiplyOverflow) = perChunkOverhead.multipliedReportingOverflow(
            by: UInt64(chunkCount)
        )
        guard !multiplyOverflow else {
            throw CloudProtocolError.invalidLength("stored cloud object")
        }
        let (withPlaintext, plaintextOverflow) = encodedByteCount.addingReportingOverflow(
            plaintextByteCount
        )
        let (total, totalOverflow) = withPlaintext.addingReportingOverflow(allChunkOverhead)
        guard !plaintextOverflow, !totalOverflow else {
            throw CloudProtocolError.invalidLength("stored cloud object")
        }
        return total
    }

    func authenticationData(
        sequence: UInt32,
        isFinal: Bool,
        declaredPlaintextByteCount: UInt32
    ) throws -> Data {
        try validateSequence(sequence)
        let expectedFinal = sequence == chunkCount - 1
        guard isFinal == expectedFinal else {
            throw CloudProtocolError.invalidValue("cloud-object final flag")
        }
        let consumedBefore = UInt64(sequence) * UInt64(plaintextChunkByteCount)
        let remaining = plaintextByteCount - consumedBefore
        let expectedLength = UInt32(min(UInt64(plaintextChunkByteCount), remaining))
        guard declaredPlaintextByteCount == expectedLength else {
            throw CloudProtocolError.invalidLength("cloud-object chunk")
        }

        var result = Self.aadDomain
        result.append(0)
        result.append(try encoded())
        var encoder = CloudBinaryEncoder()
        encoder.append(sequence)
        encoder.append(isFinal ? 1 : 0)
        encoder.append(declaredPlaintextByteCount)
        result.append(encoder.data)
        return result
    }

    private func validateSequence(_ sequence: UInt32) throws {
        try validate()
        guard sequence < chunkCount else {
            throw CloudProtocolError.invalidValue("cloud-object sequence")
        }
    }

    init(
        purpose: CloudObjectPurposeV1,
        accountID: UUID,
        vaultID: UUID,
        objectID: UUID,
        objectVersion: UInt64,
        plaintextByteCount: UInt64,
        plaintextChunkByteCount: UInt32 = CloudProtocolLimits.cloudObjectChunkByteCount,
        chunkCount: UInt32
    ) {
        self.purpose = purpose
        self.accountID = accountID
        self.vaultID = vaultID
        self.objectID = objectID
        self.objectVersion = objectVersion
        self.plaintextByteCount = plaintextByteCount
        self.plaintextChunkByteCount = plaintextChunkByteCount
        self.chunkCount = chunkCount
    }

    init(decoding data: Data) throws {
        var decoder = try CloudBinaryDecoder(data)
        try decoder.requireMagic(Self.magic)
        guard try decoder.readUInt32() == CloudProtocolSuite.version else {
            throw CloudProtocolError.unsupportedVersion
        }
        guard try decoder.readUInt32() == CloudProtocolSuite.algorithmSuite else {
            throw CloudProtocolError.invalidValue("algorithm suite")
        }
        guard let purpose = CloudObjectPurposeV1(rawValue: try decoder.readUInt8()) else {
            throw CloudProtocolError.invalidValue("cloud-object purpose")
        }
        self.purpose = purpose
        accountID = try decoder.readUUID()
        vaultID = try decoder.readUUID()
        objectID = try decoder.readUUID()
        objectVersion = try decoder.readUInt64()
        plaintextByteCount = try decoder.readUInt64()
        plaintextChunkByteCount = try decoder.readUInt32()
        chunkCount = try decoder.readUInt32()
        try decoder.requireFinished()
        try validate()
    }
}
