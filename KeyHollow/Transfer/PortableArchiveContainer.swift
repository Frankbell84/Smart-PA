import CryptoKit
import Foundation

enum PortableArchiveContainerError: Error, Equatable {
    case alreadyConsumed
    case alreadyFinished
    case authenticationFailed
    case contentAfterFinalChunk
    case destinationExists
    case invalidFrame
    case invalidHeader
    case invalidHeaderLength
    case invalidMagic
    case missingFinalChunk
    case truncated
    case unexpectedSequence(expected: UInt64, actual: UInt64)
    case unsupportedVersion
}

enum PortableArchiveContainerFormat {
    static let magic = Data([0x4b, 0x48, 0x56, 0x41, 0x55, 0x4c, 0x54, 0x00])
    static let currentVersion: UInt32 = 1
    static let maximumHeaderByteCount = 65_536
    static let plaintextChunkByteCount = 1_048_576
    static let maximumSealedChunkByteCount = plaintextChunkByteCount + 64
    static let framePrefixByteCount = 13
}

struct PortableArchiveContentChunk: Equatable, Sendable {
    let sequence: UInt64
    let isFinal: Bool
    let sealedContent: Data

    static func seal(
        _ plaintext: Data,
        sequence: UInt64,
        isFinal: Bool,
        archiveID: UUID,
        contentKey: SymmetricKey
    ) throws -> PortableArchiveContentChunk {
        guard plaintext.count <= PortableArchiveContainerFormat.plaintextChunkByteCount else {
            throw PortableArchiveContainerError.invalidFrame
        }
        let box = try AES.GCM.seal(
            plaintext,
            using: contentKey,
            authenticating: authenticationData(
                archiveID: archiveID,
                sequence: sequence,
                isFinal: isFinal
            )
        )
        guard let combined = box.combined else {
            throw PortableArchiveContainerError.invalidFrame
        }
        return PortableArchiveContentChunk(
            sequence: sequence,
            isFinal: isFinal,
            sealedContent: combined
        )
    }

    func open(
        expectedSequence: UInt64,
        archiveID: UUID,
        contentKey: SymmetricKey
    ) throws -> Data {
        guard sequence == expectedSequence else {
            throw PortableArchiveContainerError.unexpectedSequence(
                expected: expectedSequence,
                actual: sequence
            )
        }
        guard sealedContent.count >= 28,
              sealedContent.count <= PortableArchiveContainerFormat.maximumSealedChunkByteCount else {
            throw PortableArchiveContainerError.invalidFrame
        }

        do {
            let box = try AES.GCM.SealedBox(combined: sealedContent)
            return try AES.GCM.open(
                box,
                using: contentKey,
                authenticating: Self.authenticationData(
                    archiveID: archiveID,
                    sequence: sequence,
                    isFinal: isFinal
                )
            )
        } catch {
            throw PortableArchiveContainerError.authenticationFailed
        }
    }

    static func authenticationData(
        archiveID: UUID,
        sequence: UInt64,
        isFinal: Bool
    ) -> Data {
        var result = Data("keyhollow.encrypted-vault.content-chunk.v1".utf8)
        result.append(0)
        result.append(Data(archiveID.uuidString.lowercased().utf8))
        result.append(0)
        result.appendLittleEndian(sequence)
        result.append(isFinal ? 1 : 0)
        return result
    }
}

final class PortableArchiveContainerWriter {
    private let destinationURL: URL
    private let archiveID: UUID
    private let contentKey: SymmetricKey
    private var fileHandle: FileHandle?
    private var plaintextBuffer = Data()
    private var nextSequence: UInt64 = 0
    private var isFinished = false

    init(
        destinationURL: URL,
        preparedArchive: PreparedEncryptedVaultArchive
    ) throws {
        guard preparedArchive.header.format == EncryptedVaultArchiveHeader.formatIdentifier,
              preparedArchive.header.version == EncryptedVaultArchiveHeader.currentVersion,
              preparedArchive.secrets.vaultKey.count == 32,
              preparedArchive.secrets.contentKey.count == 32 else {
            throw PortableArchiveContainerError.invalidHeader
        }

        let fileManager = FileManager.default
        guard !fileManager.fileExists(atPath: destinationURL.path) else {
            throw PortableArchiveContainerError.destinationExists
        }

        let encodedHeader = try JSONEncoder().encode(preparedArchive.header)
        guard !encodedHeader.isEmpty,
              encodedHeader.count <= PortableArchiveContainerFormat.maximumHeaderByteCount else {
            throw PortableArchiveContainerError.invalidHeaderLength
        }

        self.destinationURL = destinationURL
        archiveID = preparedArchive.secrets.archiveID
        contentKey = SymmetricKey(data: preparedArchive.secrets.contentKey)

        do {
            guard fileManager.createFile(
                atPath: destinationURL.path,
                contents: nil,
                attributes: [.protectionKey: FileProtectionType.complete]
            ) else {
                throw PortableArchiveContainerError.invalidHeader
            }
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            var protectedURL = destinationURL
            try protectedURL.setResourceValues(values)

            let handle = try FileHandle(forWritingTo: destinationURL)
            fileHandle = handle
            try handle.write(contentsOf: PortableArchiveContainerFormat.magic)
            try handle.write(contentsOf: encodedLittleEndian(PortableArchiveContainerFormat.currentVersion))
            try handle.write(contentsOf: encodedLittleEndian(UInt32(encodedHeader.count)))
            try handle.write(contentsOf: encodedHeader)
        } catch {
            try? fileHandle?.close()
            fileHandle = nil
            try? fileManager.removeItem(at: destinationURL)
            throw error
        }
    }

    deinit {
        guard !isFinished else { return }
        try? fileHandle?.close()
        try? FileManager.default.removeItem(at: destinationURL)
    }

    func append(_ data: Data) throws {
        guard !isFinished, fileHandle != nil else {
            throw PortableArchiveContainerError.alreadyFinished
        }
        guard !data.isEmpty else { return }

        var offset = data.startIndex
        while offset < data.endIndex {
            let capacity = PortableArchiveContainerFormat.plaintextChunkByteCount - plaintextBuffer.count
            let remaining = data.distance(from: offset, to: data.endIndex)
            let count = min(capacity, remaining)
            let end = data.index(offset, offsetBy: count)
            plaintextBuffer.append(contentsOf: data[offset..<end])
            offset = end

            if plaintextBuffer.count == PortableArchiveContainerFormat.plaintextChunkByteCount {
                try writeFrame(plaintextBuffer, isFinal: false)
                plaintextBuffer.removeAll(keepingCapacity: true)
            }
        }
    }

    @discardableResult
    func finish() throws -> URL {
        guard !isFinished, let handle = fileHandle else {
            throw PortableArchiveContainerError.alreadyFinished
        }

        do {
            try writeFrame(plaintextBuffer, isFinal: true)
            plaintextBuffer.removeAll(keepingCapacity: false)
            try handle.synchronize()
            try handle.close()
            fileHandle = nil
            isFinished = true
            return destinationURL
        } catch {
            try? handle.close()
            fileHandle = nil
            try? FileManager.default.removeItem(at: destinationURL)
            throw error
        }
    }

    func cancel() {
        guard !isFinished else { return }
        try? fileHandle?.close()
        fileHandle = nil
        try? FileManager.default.removeItem(at: destinationURL)
        isFinished = true
    }

    private func writeFrame(_ plaintext: Data, isFinal: Bool) throws {
        guard let handle = fileHandle else {
            throw PortableArchiveContainerError.alreadyFinished
        }
        let chunk = try PortableArchiveContentChunk.seal(
            plaintext,
            sequence: nextSequence,
            isFinal: isFinal,
            archiveID: archiveID,
            contentKey: contentKey
        )
        guard chunk.sealedContent.count <= PortableArchiveContainerFormat.maximumSealedChunkByteCount else {
            throw PortableArchiveContainerError.invalidFrame
        }

        try handle.write(contentsOf: encodedLittleEndian(chunk.sequence))
        try handle.write(contentsOf: Data([chunk.isFinal ? 1 : 0]))
        try handle.write(contentsOf: encodedLittleEndian(UInt32(chunk.sealedContent.count)))
        try handle.write(contentsOf: chunk.sealedContent)

        let (incremented, overflow) = nextSequence.addingReportingOverflow(1)
        guard !overflow else { throw PortableArchiveContainerError.invalidFrame }
        nextSequence = incremented
    }
}

final class PortableArchiveContainerReader {
    let header: EncryptedVaultArchiveHeader

    private var fileHandle: FileHandle?
    private var isConsumed = false

    init(sourceURL: URL) throws {
        let handle = try FileHandle(forReadingFrom: sourceURL)

        do {
            let magic = try Self.readExactly(
                PortableArchiveContainerFormat.magic.count,
                from: handle
            )
            guard magic == PortableArchiveContainerFormat.magic else {
                throw PortableArchiveContainerError.invalidMagic
            }

            let version = decodeUInt32(try Self.readExactly(4, from: handle))
            guard version == PortableArchiveContainerFormat.currentVersion else {
                throw PortableArchiveContainerError.unsupportedVersion
            }

            let headerLength = Int(decodeUInt32(try Self.readExactly(4, from: handle)))
            guard headerLength > 0,
                  headerLength <= PortableArchiveContainerFormat.maximumHeaderByteCount else {
                throw PortableArchiveContainerError.invalidHeaderLength
            }

            let encodedHeader = try Self.readExactly(headerLength, from: handle)
            let decodedHeader: EncryptedVaultArchiveHeader
            do {
                decodedHeader = try JSONDecoder().decode(
                    EncryptedVaultArchiveHeader.self,
                    from: encodedHeader
                )
            } catch {
                throw PortableArchiveContainerError.invalidHeader
            }
            guard decodedHeader.version == Int(version) else {
                throw PortableArchiveContainerError.unsupportedVersion
            }
            header = decodedHeader
            fileHandle = handle
        } catch {
            try? handle.close()
            throw error
        }
    }

    deinit {
        try? fileHandle?.close()
    }

    @discardableResult
    func streamAuthenticatedContent(
        credential: PortableArchiveCredential,
        keyDeriver: any PortableArchiveKeyDeriving = PortableArchiveArgon2idKeyDeriver(),
        receive: (Data) throws -> Void
    ) throws -> PortableArchiveSecrets {
        guard !isConsumed, let handle = fileHandle else {
            throw PortableArchiveContainerError.alreadyConsumed
        }
        isConsumed = true

        do {
            let secrets = try header.open(credential: credential, keyDeriver: keyDeriver)
            let contentKey = SymmetricKey(data: secrets.contentKey)
            var expectedSequence: UInt64 = 0
            var foundFinalChunk = false

            while !foundFinalChunk {
                let prefix: Data
                do {
                    prefix = try Self.readExactly(
                        PortableArchiveContainerFormat.framePrefixByteCount,
                        from: handle
                    )
                } catch PortableArchiveContainerError.truncated {
                    throw PortableArchiveContainerError.missingFinalChunk
                }

                let sequence = decodeUInt64(prefix.subdata(in: 0..<8))
                let flags = prefix[8]
                guard flags == 0 || flags == 1 else {
                    throw PortableArchiveContainerError.invalidFrame
                }
                let sealedLength = Int(decodeUInt32(prefix.subdata(in: 9..<13)))
                guard sealedLength >= 28,
                      sealedLength <= PortableArchiveContainerFormat.maximumSealedChunkByteCount else {
                    throw PortableArchiveContainerError.invalidFrame
                }

                let chunk = PortableArchiveContentChunk(
                    sequence: sequence,
                    isFinal: flags == 1,
                    sealedContent: try Self.readExactly(sealedLength, from: handle)
                )
                let plaintext = try chunk.open(
                    expectedSequence: expectedSequence,
                    archiveID: secrets.archiveID,
                    contentKey: contentKey
                )
                try receive(plaintext)
                foundFinalChunk = chunk.isFinal

                let (incremented, overflow) = expectedSequence.addingReportingOverflow(1)
                guard !overflow else { throw PortableArchiveContainerError.invalidFrame }
                expectedSequence = incremented
            }

            let trailing = try handle.read(upToCount: 1) ?? Data()
            guard trailing.isEmpty else {
                throw PortableArchiveContainerError.contentAfterFinalChunk
            }

            try handle.close()
            fileHandle = nil
            return secrets
        } catch {
            try? handle.close()
            fileHandle = nil
            throw error
        }
    }

    private static func readExactly(_ count: Int, from handle: FileHandle) throws -> Data {
        guard count >= 0 else { throw PortableArchiveContainerError.truncated }
        var result = Data()
        result.reserveCapacity(count)

        while result.count < count {
            let requested = count - result.count
            guard let part = try handle.read(upToCount: requested), !part.isEmpty else {
                throw PortableArchiveContainerError.truncated
            }
            result.append(part)
        }
        return result
    }
}

private func encodedLittleEndian<T: FixedWidthInteger>(_ value: T) -> Data {
    var littleEndian = value.littleEndian
    return Swift.withUnsafeBytes(of: &littleEndian) { Data($0) }
}

private func decodeUInt32(_ data: Data) -> UInt32 {
    precondition(data.count == 4)
    return data.enumerated().reduce(into: UInt32(0)) { result, element in
        result |= UInt32(element.element) << UInt32(element.offset * 8)
    }
}

private func decodeUInt64(_ data: Data) -> UInt64 {
    precondition(data.count == 8)
    return data.enumerated().reduce(into: UInt64(0)) { result, element in
        result |= UInt64(element.element) << UInt64(element.offset * 8)
    }
}

private extension Data {
    mutating func appendLittleEndian<T: FixedWidthInteger>(_ value: T) {
        append(encodedLittleEndian(value))
    }
}
