import CryptoKit
import Foundation

/// Provider-object codec used by the local Gate A harness. The provider sees
/// only these opaque bytes and never interprets the encrypted payload.
enum CloudObjectContainerV1 {
    static func seal(
        _ plaintext: Data,
        purpose: CloudObjectPurposeV1,
        accountID: UUID,
        vaultID: UUID,
        objectID: UUID,
        objectVersion: UInt64,
        cloudVaultKey: Data
    ) throws -> Data {
        guard !plaintext.isEmpty else {
            throw CloudProtocolError.invalidLength("cloud-object plaintext")
        }
        let chunkSize = Int(CloudProtocolLimits.cloudObjectChunkByteCount)
        let chunkCount64 = (UInt64(plaintext.count - 1) / UInt64(chunkSize)) + 1
        guard chunkCount64 <= UInt64(UInt32.max) else {
            throw CloudProtocolError.invalidLength("cloud-object chunk count")
        }
        let header = CloudObjectHeaderV1(
            purpose: purpose,
            accountID: accountID,
            vaultID: vaultID,
            objectID: objectID,
            objectVersion: objectVersion,
            plaintextByteCount: UInt64(plaintext.count),
            chunkCount: UInt32(chunkCount64)
        )
        var stored = try header.encoded()
        for sequence in 0..<header.chunkCount {
            let start = Int(sequence) * chunkSize
            let end = min(start + chunkSize, plaintext.count)
            stored.append(
                try CloudObjectChunkV1.seal(
                    Data(plaintext[start..<end]),
                    cloudVaultKey: cloudVaultKey,
                    header: header,
                    sequence: sequence,
                    isFinal: sequence == header.chunkCount - 1
                )
            )
        }
        let expectedStoredByteCount = try CloudObjectHeaderV1.storedByteCount(
            plaintextByteCount: header.plaintextByteCount,
            chunkCount: header.chunkCount
        )
        guard UInt64(stored.count) == expectedStoredByteCount else {
            throw CloudProtocolError.invalidLength("stored cloud object")
        }
        return stored
    }

    static func open(
        _ stored: Data,
        cloudVaultKey: Data
    ) throws -> (header: CloudObjectHeaderV1, plaintext: Data) {
        guard stored.count >= Int(CloudObjectHeaderV1.encodedByteCount) else {
            throw CloudProtocolError.truncated
        }
        let headerLength = Int(CloudObjectHeaderV1.encodedByteCount)
        let header = try CloudObjectHeaderV1(decoding: Data(stored.prefix(headerLength)))
        let expectedStoredByteCount = try CloudObjectHeaderV1.storedByteCount(
            plaintextByteCount: header.plaintextByteCount,
            chunkCount: header.chunkCount
        )
        guard UInt64(stored.count) == expectedStoredByteCount else {
            throw CloudProtocolError.invalidLength("stored cloud object")
        }

        var decoder = try CloudBinaryDecoder(Data(stored.dropFirst(headerLength)))
        var plaintext = Data()
        plaintext.reserveCapacity(Int(header.plaintextByteCount))
        for expectedSequence in 0..<header.chunkCount {
            let sequence = try decoder.readUInt32()
            let final = try decoder.readUInt8()
            let declaredLength = try decoder.readUInt32()
            let sealedLength = try decoder.readUInt32()
            guard sealedLength <= UInt32(CloudProtocolLimits.cloudObjectChunkByteCount)
                    + UInt32(CloudObjectHeaderV1.sealedChunkOverheadByteCount),
                  Int(sealedLength) <= decoder.remainingByteCount else {
                throw CloudProtocolError.invalidLength("sealed cloud-object chunk")
            }

            var frameEncoder = CloudBinaryEncoder()
            frameEncoder.append(sequence)
            frameEncoder.append(final)
            frameEncoder.append(declaredLength)
            frameEncoder.append(sealedLength)
            var frame = frameEncoder.data
            frame.append(
                try decoder.readFixedData(
                    byteCount: Int(sealedLength),
                    field: "sealed cloud-object chunk"
                )
            )
            let opened = try CloudObjectChunkV1.open(
                frame,
                cloudVaultKey: cloudVaultKey,
                header: header
            )
            guard opened.sequence == expectedSequence,
                  opened.isFinal == (expectedSequence == header.chunkCount - 1) else {
                throw CloudProtocolError.invalidValue("cloud-object sequence")
            }
            plaintext.append(opened.plaintext)
        }
        try decoder.requireFinished()
        guard UInt64(plaintext.count) == header.plaintextByteCount else {
            throw CloudProtocolError.invalidLength("cloud-object plaintext")
        }
        return (header, plaintext)
    }

    static func sha256(_ data: Data) -> Data {
        Data(SHA256.hash(data: data))
    }
}
