import CryptoKit
import Foundation

enum CloudSecretKeyV1 {
    static let byteCount = 32

    static func generate() -> Data {
        SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }
    }
}

struct CloudAccountMasterKeySecretV1: Equatable, Sendable {
    static let magic = Data([0x4b, 0x48, 0x43, 0x41, 0x4d, 0x4b, 0x31, 0x00])
    static let encodedByteCount = 60

    let accountMasterKey: Data
    let createdAtMilliseconds: UInt64
    let generation: UInt64

    func encoded() throws -> Data {
        guard accountMasterKey.count == CloudSecretKeyV1.byteCount,
              createdAtMilliseconds > 0,
              generation >= 1 else {
            throw CloudProtocolError.invalidValue("account master key secret")
        }
        var encoder = CloudBinaryEncoder()
        try encoder.append(fixed: Self.magic, byteCount: 8, field: "AMK magic")
        encoder.append(CloudProtocolSuite.version)
        try encoder.append(
            fixed: accountMasterKey,
            byteCount: CloudSecretKeyV1.byteCount,
            field: "AMK"
        )
        encoder.append(createdAtMilliseconds)
        encoder.append(generation)
        return encoder.data
    }

    init(accountMasterKey: Data, createdAtMilliseconds: UInt64, generation: UInt64) {
        self.accountMasterKey = accountMasterKey
        self.createdAtMilliseconds = createdAtMilliseconds
        self.generation = generation
    }

    init(decoding data: Data) throws {
        var decoder = try CloudBinaryDecoder(data, maximumByteCount: Self.encodedByteCount)
        try decoder.requireMagic(Self.magic)
        guard try decoder.readUInt32() == CloudProtocolSuite.version else {
            throw CloudProtocolError.unsupportedVersion
        }
        accountMasterKey = try decoder.readFixedData(
            byteCount: CloudSecretKeyV1.byteCount,
            field: "AMK"
        )
        createdAtMilliseconds = try decoder.readUInt64()
        generation = try decoder.readUInt64()
        try decoder.requireFinished()
        guard createdAtMilliseconds > 0, generation >= 1 else {
            throw CloudProtocolError.invalidValue("account master key secret")
        }
    }
}

struct CloudVaultKeySecretV1: Equatable, Sendable {
    static let magic = Data([0x4b, 0x48, 0x43, 0x43, 0x56, 0x4b, 0x31, 0x00])
    static let encodedByteCount = 60

    let cloudVaultKey: Data
    let createdAtMilliseconds: UInt64
    let generation: UInt64

    func encoded() throws -> Data {
        guard cloudVaultKey.count == CloudSecretKeyV1.byteCount,
              createdAtMilliseconds > 0,
              generation >= 1 else {
            throw CloudProtocolError.invalidValue("cloud vault key secret")
        }
        var encoder = CloudBinaryEncoder()
        try encoder.append(fixed: Self.magic, byteCount: 8, field: "CVK magic")
        encoder.append(CloudProtocolSuite.version)
        try encoder.append(
            fixed: cloudVaultKey,
            byteCount: CloudSecretKeyV1.byteCount,
            field: "CVK"
        )
        encoder.append(createdAtMilliseconds)
        encoder.append(generation)
        return encoder.data
    }

    init(cloudVaultKey: Data, createdAtMilliseconds: UInt64, generation: UInt64) {
        self.cloudVaultKey = cloudVaultKey
        self.createdAtMilliseconds = createdAtMilliseconds
        self.generation = generation
    }

    init(decoding data: Data) throws {
        var decoder = try CloudBinaryDecoder(data, maximumByteCount: Self.encodedByteCount)
        try decoder.requireMagic(Self.magic)
        guard try decoder.readUInt32() == CloudProtocolSuite.version else {
            throw CloudProtocolError.unsupportedVersion
        }
        cloudVaultKey = try decoder.readFixedData(
            byteCount: CloudSecretKeyV1.byteCount,
            field: "CVK"
        )
        createdAtMilliseconds = try decoder.readUInt64()
        generation = try decoder.readUInt64()
        try decoder.requireFinished()
        guard createdAtMilliseconds > 0, generation >= 1 else {
            throw CloudProtocolError.invalidValue("cloud vault key secret")
        }
    }
}

enum CloudKeyDerivationV1 {
    static func recoveryWrappingKey(
        recoveryCode: String,
        header: CloudRecoveryEnvelopeHeaderV1
    ) throws -> SymmetricKey {
        try header.validate()
        return try Argon2id.deriveKey(
            password: CloudRecoveryCodeV1.keyMaterial(from: recoveryCode),
            salt: header.kdfSalt,
            memoryKiB: 65_536,
            iterations: 3,
            parallelism: 2,
            outputByteCount: 32,
            associatedData: CloudRecoveryCodeV1.argon2AssociatedData
        )
    }

    static func vaultWrappingKey(
        accountMasterKey: Data,
        header: CloudVaultKeyEnvelopeHeaderV1
    ) throws -> SymmetricKey {
        guard accountMasterKey.count == CloudSecretKeyV1.byteCount else {
            throw CloudProtocolError.invalidLength("AMK")
        }
        return HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: accountMasterKey),
            salt: CloudVaultKeyEnvelopeHeaderV1.keyDerivationDomain,
            info: try header.keyDerivationInfo(),
            outputByteCount: 32
        )
    }

    static func objectChunkKey(
        cloudVaultKey: Data,
        header: CloudObjectHeaderV1,
        sequence: UInt32
    ) throws -> SymmetricKey {
        guard cloudVaultKey.count == CloudSecretKeyV1.byteCount else {
            throw CloudProtocolError.invalidLength("CVK")
        }
        return HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: cloudVaultKey),
            salt: CloudObjectHeaderV1.keyDerivationDomain,
            info: try header.chunkKeyInfo(sequence: sequence),
            outputByteCount: 32
        )
    }

}

protocol CloudRecoveryKeyDeriving: Sendable {
    func derive(
        recoveryCode: String,
        header: CloudRecoveryEnvelopeHeaderV1
    ) throws -> SymmetricKey
}

struct CloudArgon2idRecoveryKeyDeriver: CloudRecoveryKeyDeriving {
    func derive(
        recoveryCode: String,
        header: CloudRecoveryEnvelopeHeaderV1
    ) throws -> SymmetricKey {
        try CloudKeyDerivationV1.recoveryWrappingKey(
            recoveryCode: recoveryCode,
            header: header
        )
    }
}

enum CloudRecoveryEnvelopeV1 {
    static func seal(
        _ secret: CloudAccountMasterKeySecretV1,
        recoveryCode: String,
        header: CloudRecoveryEnvelopeHeaderV1,
        keyDeriver: any CloudRecoveryKeyDeriving = CloudArgon2idRecoveryKeyDeriver()
    ) throws -> Data {
        try seal(
            secret,
            recoveryCode: recoveryCode,
            header: header,
            keyDeriver: keyDeriver,
            nonce: nil
        )
    }

    static func open(
        _ container: Data,
        recoveryCode: String,
        keyDeriver: any CloudRecoveryKeyDeriving = CloudArgon2idRecoveryKeyDeriver()
    ) throws -> (header: CloudRecoveryEnvelopeHeaderV1, secret: CloudAccountMasterKeySecretV1) {
        guard container.count <= CloudProtocolLimits.sealedEnvelopeByteCount,
              container.count >= CloudRecoveryEnvelopeHeaderV1.encodedByteCount + 4 else {
            throw CloudProtocolError.invalidLength("recovery envelope")
        }
        let headerData = container.prefix(CloudRecoveryEnvelopeHeaderV1.encodedByteCount)
        let header = try CloudRecoveryEnvelopeHeaderV1(decoding: Data(headerData))
        var decoder = try CloudBinaryDecoder(Data(container.dropFirst(headerData.count)))
        let sealed = try decoder.readLengthPrefixedData(
            maximum: CloudProtocolLimits.sealedEnvelopeByteCount,
            field: "sealed recovery secret"
        )
        try decoder.requireFinished()
        do {
            let box = try AES.GCM.SealedBox(combined: sealed)
            let plaintext = try AES.GCM.open(
                box,
                using: try keyDeriver.derive(recoveryCode: recoveryCode, header: header),
                authenticating: header.authenticationData()
            )
            return (header, try CloudAccountMasterKeySecretV1(decoding: plaintext))
        } catch let error as CloudProtocolError {
            throw error
        } catch {
            throw CloudProtocolError.authenticationFailed
        }
    }

#if DEBUG
    static func sealForTesting(
        _ secret: CloudAccountMasterKeySecretV1,
        recoveryCode: String,
        header: CloudRecoveryEnvelopeHeaderV1,
        keyDeriver: any CloudRecoveryKeyDeriving,
        nonce: Data
    ) throws -> Data {
        try seal(
            secret,
            recoveryCode: recoveryCode,
            header: header,
            keyDeriver: keyDeriver,
            nonce: nonce
        )
    }
#endif

    private static func seal(
        _ secret: CloudAccountMasterKeySecretV1,
        recoveryCode: String,
        header: CloudRecoveryEnvelopeHeaderV1,
        keyDeriver: any CloudRecoveryKeyDeriving,
        nonce: Data?
    ) throws -> Data {
        let key = try keyDeriver.derive(recoveryCode: recoveryCode, header: header)
        let plaintext = try secret.encoded()
        let box: AES.GCM.SealedBox
        if let nonce {
            box = try AES.GCM.seal(
                plaintext,
                using: key,
                nonce: try AES.GCM.Nonce(data: nonce),
                authenticating: header.authenticationData()
            )
        } else {
            box = try AES.GCM.seal(
                plaintext,
                using: key,
                authenticating: header.authenticationData()
            )
        }
        guard let combined = box.combined else {
            throw CloudProtocolError.authenticationFailed
        }
        var container = try header.encoded()
        var encoder = CloudBinaryEncoder()
        try encoder.append(
            lengthPrefixed: combined,
            maximum: CloudProtocolLimits.sealedEnvelopeByteCount,
            field: "sealed recovery secret"
        )
        container.append(encoder.data)
        guard container.count <= CloudProtocolLimits.sealedEnvelopeByteCount else {
            throw CloudProtocolError.invalidLength("recovery envelope")
        }
        return container
    }

}

enum CloudVaultKeyEnvelopeV1 {
    static func seal(
        _ secret: CloudVaultKeySecretV1,
        accountMasterKey: Data,
        header: CloudVaultKeyEnvelopeHeaderV1
    ) throws -> Data {
        try seal(secret, accountMasterKey: accountMasterKey, header: header, nonce: nil)
    }

    static func open(
        _ container: Data,
        accountMasterKey: Data
    ) throws -> (header: CloudVaultKeyEnvelopeHeaderV1, secret: CloudVaultKeySecretV1) {
        guard container.count <= CloudProtocolLimits.sealedEnvelopeByteCount,
              container.count >= CloudVaultKeyEnvelopeHeaderV1.encodedByteCount + 4 else {
            throw CloudProtocolError.invalidLength("vault-key envelope")
        }
        let headerData = container.prefix(CloudVaultKeyEnvelopeHeaderV1.encodedByteCount)
        let header = try CloudVaultKeyEnvelopeHeaderV1(decoding: Data(headerData))
        var decoder = try CloudBinaryDecoder(Data(container.dropFirst(headerData.count)))
        let sealed = try decoder.readLengthPrefixedData(
            maximum: CloudProtocolLimits.sealedEnvelopeByteCount,
            field: "sealed vault key"
        )
        try decoder.requireFinished()
        do {
            let box = try AES.GCM.SealedBox(combined: sealed)
            let plaintext = try AES.GCM.open(
                box,
                using: CloudKeyDerivationV1.vaultWrappingKey(
                    accountMasterKey: accountMasterKey,
                    header: header
                ),
                authenticating: header.authenticationData()
            )
            return (header, try CloudVaultKeySecretV1(decoding: plaintext))
        } catch let error as CloudProtocolError {
            throw error
        } catch {
            throw CloudProtocolError.authenticationFailed
        }
    }

#if DEBUG
    static func sealForTesting(
        _ secret: CloudVaultKeySecretV1,
        accountMasterKey: Data,
        header: CloudVaultKeyEnvelopeHeaderV1,
        nonce: Data
    ) throws -> Data {
        try seal(secret, accountMasterKey: accountMasterKey, header: header, nonce: nonce)
    }
#endif

    private static func seal(
        _ secret: CloudVaultKeySecretV1,
        accountMasterKey: Data,
        header: CloudVaultKeyEnvelopeHeaderV1,
        nonce: Data?
    ) throws -> Data {
        let key = try CloudKeyDerivationV1.vaultWrappingKey(
            accountMasterKey: accountMasterKey,
            header: header
        )
        let plaintext = try secret.encoded()
        let box: AES.GCM.SealedBox
        if let nonce {
            box = try AES.GCM.seal(
                plaintext,
                using: key,
                nonce: try AES.GCM.Nonce(data: nonce),
                authenticating: header.authenticationData()
            )
        } else {
            box = try AES.GCM.seal(
                plaintext,
                using: key,
                authenticating: header.authenticationData()
            )
        }
        guard let combined = box.combined else {
            throw CloudProtocolError.authenticationFailed
        }
        var container = try header.encoded()
        var encoder = CloudBinaryEncoder()
        try encoder.append(
            lengthPrefixed: combined,
            maximum: CloudProtocolLimits.sealedEnvelopeByteCount,
            field: "sealed vault key"
        )
        container.append(encoder.data)
        guard container.count <= CloudProtocolLimits.sealedEnvelopeByteCount else {
            throw CloudProtocolError.invalidLength("vault-key envelope")
        }
        return container
    }
}

enum CloudObjectChunkV1 {
    private static let maximumFrameByteCount = Int(
        CloudObjectHeaderV1.framePrefixByteCount
            + CloudObjectHeaderV1.sealedChunkOverheadByteCount
            + UInt64(CloudProtocolLimits.cloudObjectChunkByteCount)
    )

    static func seal(
        _ plaintext: Data,
        cloudVaultKey: Data,
        header: CloudObjectHeaderV1,
        sequence: UInt32,
        isFinal: Bool
    ) throws -> Data {
        try seal(
            plaintext,
            cloudVaultKey: cloudVaultKey,
            header: header,
            sequence: sequence,
            isFinal: isFinal,
            nonce: nil
        )
    }

    static func open(
        _ frame: Data,
        cloudVaultKey: Data,
        header: CloudObjectHeaderV1
    ) throws -> (sequence: UInt32, isFinal: Bool, plaintext: Data) {
        var decoder = try CloudBinaryDecoder(
            frame,
            maximumByteCount: Self.maximumFrameByteCount
        )
        let sequence = try decoder.readUInt32()
        let finalValue = try decoder.readUInt8()
        guard finalValue == 0 || finalValue == 1 else {
            throw CloudProtocolError.invalidValue("cloud-object final flag")
        }
        let isFinal = finalValue == 1
        let plaintextLength = try decoder.readUInt32()
        let sealedLength = Int(try decoder.readUInt32())
        guard sealedLength == Int(plaintextLength) + Int(CloudObjectHeaderV1.sealedChunkOverheadByteCount),
              sealedLength == decoder.remainingByteCount else {
            throw CloudProtocolError.invalidLength("sealed cloud-object chunk")
        }
        let sealed = try decoder.readFixedData(byteCount: sealedLength, field: "sealed cloud-object chunk")
        try decoder.requireFinished()
        let aad = try header.authenticationData(
            sequence: sequence,
            isFinal: isFinal,
            declaredPlaintextByteCount: plaintextLength
        )
        do {
            let box = try AES.GCM.SealedBox(combined: sealed)
            let plaintext = try AES.GCM.open(
                box,
                using: CloudKeyDerivationV1.objectChunkKey(
                    cloudVaultKey: cloudVaultKey,
                    header: header,
                    sequence: sequence
                ),
                authenticating: aad
            )
            guard plaintext.count == Int(plaintextLength) else {
                throw CloudProtocolError.invalidLength("cloud-object chunk")
            }
            return (sequence, isFinal, plaintext)
        } catch let error as CloudProtocolError {
            throw error
        } catch {
            throw CloudProtocolError.authenticationFailed
        }
    }

#if DEBUG
    static func sealForTesting(
        _ plaintext: Data,
        cloudVaultKey: Data,
        header: CloudObjectHeaderV1,
        sequence: UInt32,
        isFinal: Bool,
        nonce: Data
    ) throws -> Data {
        try seal(
            plaintext,
            cloudVaultKey: cloudVaultKey,
            header: header,
            sequence: sequence,
            isFinal: isFinal,
            nonce: nonce
        )
    }
#endif

    private static func seal(
        _ plaintext: Data,
        cloudVaultKey: Data,
        header: CloudObjectHeaderV1,
        sequence: UInt32,
        isFinal: Bool,
        nonce: Data?
    ) throws -> Data {
        guard plaintext.count <= Int(UInt32.max) else {
            throw CloudProtocolError.invalidLength("cloud-object chunk")
        }
        let plaintextLength = UInt32(plaintext.count)
        let aad = try header.authenticationData(
            sequence: sequence,
            isFinal: isFinal,
            declaredPlaintextByteCount: plaintextLength
        )
        let key = try CloudKeyDerivationV1.objectChunkKey(
            cloudVaultKey: cloudVaultKey,
            header: header,
            sequence: sequence
        )
        let box: AES.GCM.SealedBox
        if let nonce {
            box = try AES.GCM.seal(
                plaintext,
                using: key,
                nonce: try AES.GCM.Nonce(data: nonce),
                authenticating: aad
            )
        } else {
            box = try AES.GCM.seal(
                plaintext,
                using: key,
                authenticating: aad
            )
        }
        guard let sealed = box.combined,
              sealed.count == plaintext.count + Int(CloudObjectHeaderV1.sealedChunkOverheadByteCount) else {
            throw CloudProtocolError.authenticationFailed
        }
        var encoder = CloudBinaryEncoder()
        encoder.append(sequence)
        encoder.append(UInt8(isFinal ? 1 : 0))
        encoder.append(plaintextLength)
        encoder.append(UInt32(sealed.count))
        var frame = encoder.data
        frame.append(sealed)
        return frame
    }
}
