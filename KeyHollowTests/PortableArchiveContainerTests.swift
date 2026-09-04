import CryptoKit
import Foundation
import XCTest
@testable import KeyHollow
@testable import KeyHollowVaultCore

final class PortableArchiveContainerTests: XCTestCase {
    func testContainerStreamsMultipleAuthenticatedChunksRoundTrip() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.url) }

        let byteCount = PortableArchiveContainerFormat.plaintextChunkByteCount * 2 + 37
        let plaintext = Data((0..<byteCount).map { UInt8($0 % 251) })
        let writer = try PortableArchiveContainerWriter(
            destinationURL: fixture.url,
            preparedArchive: fixture.prepared
        )
        try writer.append(plaintext.prefix(73))
        try writer.append(plaintext.dropFirst(73).prefix(810_003))
        try writer.append(plaintext.dropFirst(810_076))
        try writer.finish()

        let reader = try PortableArchiveContainerReader(sourceURL: fixture.url)
        var reopened = Data()
        let secrets = try reader.streamAuthenticatedContent(
            credential: fixture.credential,
            keyDeriver: TestContainerKeyDeriver()
        ) { chunk in
            XCTAssertLessThanOrEqual(
                chunk.count,
                PortableArchiveContainerFormat.plaintextChunkByteCount
            )
            reopened.append(chunk)
        }

        XCTAssertEqual(reopened, plaintext)
        XCTAssertEqual(secrets, fixture.prepared.secrets)
    }

    func testEmptyContainerHasAuthenticatedFinalChunk() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.url) }

        let writer = try PortableArchiveContainerWriter(
            destinationURL: fixture.url,
            preparedArchive: fixture.prepared
        )
        try writer.finish()

        let reader = try PortableArchiveContainerReader(sourceURL: fixture.url)
        var receivedChunkCount = 0
        try reader.streamAuthenticatedContent(
            credential: fixture.credential,
            keyDeriver: TestContainerKeyDeriver()
        ) { chunk in
            receivedChunkCount += 1
            XCTAssertTrue(chunk.isEmpty)
        }
        XCTAssertEqual(receivedChunkCount, 1)
    }

    func testTamperedContentFailsClosed() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.url) }
        try writeContainer(fixture: fixture, plaintext: Data("encrypted payload".utf8))

        var bytes = try Data(contentsOf: fixture.url)
        bytes[bytes.index(before: bytes.endIndex)] ^= 0x01
        try bytes.write(to: fixture.url, options: .atomic)

        let reader = try PortableArchiveContainerReader(sourceURL: fixture.url)
        XCTAssertThrowsError(
            try reader.streamAuthenticatedContent(
                credential: fixture.credential,
                keyDeriver: TestContainerKeyDeriver()
            ) { _ in }
        ) { error in
            XCTAssertEqual(error as? PortableArchiveContainerError, .authenticationFailed)
        }
    }

    func testTruncatedContainerFailsWithoutAcceptingPartialSuccess() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.url) }
        try writeContainer(fixture: fixture, plaintext: Data(repeating: 0x55, count: 4_096))

        var bytes = try Data(contentsOf: fixture.url)
        bytes.removeLast(10)
        try bytes.write(to: fixture.url, options: .atomic)

        let reader = try PortableArchiveContainerReader(sourceURL: fixture.url)
        XCTAssertThrowsError(
            try reader.streamAuthenticatedContent(
                credential: fixture.credential,
                keyDeriver: TestContainerKeyDeriver()
            ) { _ in }
        ) { error in
            XCTAssertEqual(error as? PortableArchiveContainerError, .truncated)
        }
    }

    func testTrailingContentAfterFinalChunkIsRejected() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.url) }
        try writeContainer(fixture: fixture, plaintext: Data("payload".utf8))

        let handle = try FileHandle(forWritingTo: fixture.url)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data([0xff]))
        try handle.close()

        let reader = try PortableArchiveContainerReader(sourceURL: fixture.url)
        XCTAssertThrowsError(
            try reader.streamAuthenticatedContent(
                credential: fixture.credential,
                keyDeriver: TestContainerKeyDeriver()
            ) { _ in }
        ) { error in
            XCTAssertEqual(
                error as? PortableArchiveContainerError,
                .contentAfterFinalChunk
            )
        }
    }

    func testChunkCannotBeReorderedOrRelabeledFinal() throws {
        let fixture = try makeFixture()
        let key = SymmetricKey(data: fixture.prepared.secrets.contentKey)
        let chunk = try PortableArchiveContentChunk.seal(
            Data("ciphertext bytes".utf8),
            sequence: 1,
            isFinal: false,
            archiveID: fixture.prepared.secrets.archiveID,
            contentKey: key
        )

        XCTAssertThrowsError(
            try chunk.open(
                expectedSequence: 0,
                archiveID: fixture.prepared.secrets.archiveID,
                contentKey: key
            )
        ) { error in
            XCTAssertEqual(
                error as? PortableArchiveContainerError,
                .unexpectedSequence(expected: 0, actual: 1)
            )
        }

        let relabeled = PortableArchiveContentChunk(
            sequence: chunk.sequence,
            isFinal: true,
            sealedContent: chunk.sealedContent
        )
        XCTAssertThrowsError(
            try relabeled.open(
                expectedSequence: 1,
                archiveID: fixture.prepared.secrets.archiveID,
                contentKey: key
            )
        ) { error in
            XCTAssertEqual(error as? PortableArchiveContainerError, .authenticationFailed)
        }
    }

    func testChunkCannotBeTransplantedAcrossArchives() throws {
        let contentKey = SymmetricKey(data: Data(repeating: 0x42, count: 32))
        let sourceArchiveID = UUID()
        let destinationArchiveID = UUID()
        let chunk = try PortableArchiveContentChunk.seal(
            Data("archive-bound ciphertext".utf8),
            sequence: 0,
            isFinal: true,
            archiveID: sourceArchiveID,
            contentKey: contentKey
        )

        XCTAssertThrowsError(
            try chunk.open(
                expectedSequence: 0,
                archiveID: destinationArchiveID,
                contentKey: contentKey
            )
        ) { error in
            XCTAssertEqual(error as? PortableArchiveContainerError, .authenticationFailed)
        }
    }

    func testDeterministicContentChunkVectorRemainsCompatible() throws {
        let archiveID = try XCTUnwrap(
            UUID(uuidString: "00112233-4455-6677-8899-aabbccddeeff")
        )
        let expectedAAD = try Data(hex: """
        6b6579686f6c6c6f772e656e637279707465642d7661756c742e636f6e74656e
        742d6368756e6b2e76310030303131323233332d343435352d363637372d383839
        392d61616262636364646565666600070000000000000001
        """)
        XCTAssertEqual(
            PortableArchiveContentChunk.authenticationData(
                archiveID: archiveID,
                sequence: 7,
                isFinal: true
            ),
            expectedAAD
        )

        let key = SymmetricKey(data: Data(0x20...0x3f))
        let plaintext = Data("KeyHollow chunk vector\n".utf8)
        let nonce = try AES.GCM.Nonce(data: Data(0xa0...0xab))
        let sealed = try AES.GCM.seal(
            plaintext,
            using: key,
            nonce: nonce,
            authenticating: expectedAAD
        )
        let expectedCombined = try Data(hex: """
        a0a1a2a3a4a5a6a7a8a9aaab3559dd7cabbbecc5d608ced253331d86e71aa273
        53c62cb860d30739de0ee6010cdbe5c75d4698
        """)
        XCTAssertEqual(sealed.combined, expectedCombined)

        let chunk = PortableArchiveContentChunk(
            sequence: 7,
            isFinal: true,
            sealedContent: expectedCombined
        )
        XCTAssertEqual(
            try chunk.open(expectedSequence: 7, archiveID: archiveID, contentKey: key),
            plaintext
        )
    }

    func testInvalidMagicIsRejected() throws {
        let url = temporaryArchiveURL()
        defer { try? FileManager.default.removeItem(at: url) }

        var bytes = PortableArchiveContainerFormat.magic
        bytes[bytes.startIndex] ^= 0x01
        bytes.appendLittleEndianForTesting(PortableArchiveContainerFormat.currentVersion)
        bytes.appendLittleEndianForTesting(UInt32(1))
        bytes.append(0)
        try bytes.write(to: url, options: .atomic)

        XCTAssertThrowsError(try PortableArchiveContainerReader(sourceURL: url)) { error in
            XCTAssertEqual(error as? PortableArchiveContainerError, .invalidMagic)
        }
    }

    func testUnsupportedContainerVersionIsRejected() throws {
        let url = temporaryArchiveURL()
        defer { try? FileManager.default.removeItem(at: url) }

        var bytes = PortableArchiveContainerFormat.magic
        bytes.appendLittleEndianForTesting(PortableArchiveContainerFormat.currentVersion + 1)
        bytes.appendLittleEndianForTesting(UInt32(1))
        bytes.append(0)
        try bytes.write(to: url, options: .atomic)

        XCTAssertThrowsError(try PortableArchiveContainerReader(sourceURL: url)) { error in
            XCTAssertEqual(error as? PortableArchiveContainerError, .unsupportedVersion)
        }
    }

    func testOversizedHeaderIsRejectedBeforeReadingIt() throws {
        let url = temporaryArchiveURL()
        defer { try? FileManager.default.removeItem(at: url) }

        var bytes = PortableArchiveContainerFormat.magic
        bytes.appendLittleEndianForTesting(PortableArchiveContainerFormat.currentVersion)
        bytes.appendLittleEndianForTesting(UInt32.max)
        try bytes.write(to: url, options: .atomic)

        XCTAssertThrowsError(try PortableArchiveContainerReader(sourceURL: url)) { error in
            XCTAssertEqual(error as? PortableArchiveContainerError, .invalidHeaderLength)
        }
    }

    func testCancelledWriterRemovesIncompleteArchive() throws {
        let fixture = try makeFixture()
        let writer = try PortableArchiveContainerWriter(
            destinationURL: fixture.url,
            preparedArchive: fixture.prepared
        )
        try writer.append(Data("partial".utf8))
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.url.path))

        writer.cancel()

        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.url.path))
    }

    private func writeContainer(fixture: Fixture, plaintext: Data) throws {
        let writer = try PortableArchiveContainerWriter(
            destinationURL: fixture.url,
            preparedArchive: fixture.prepared
        )
        try writer.append(plaintext)
        try writer.finish()
    }

    private func makeFixture() throws -> Fixture {
        let credential = PortableArchiveCredential.recoveryCode(
            "0123-4567-89AB-CDEF-GHJK-MNPQ-RSTV-WXYZ"
        )
        let prepared = try EncryptedVaultArchiveHeader.prepare(
            vaultPayload: VaultPayload(
                vaultID: UUID(),
                vaultKey: Data(repeating: 0x7c, count: 32),
                createdAt: Date(timeIntervalSince1970: 1_700_000_000)
            ),
            credential: credential,
            keyDeriver: TestContainerKeyDeriver()
        )
        return Fixture(
            url: temporaryArchiveURL(),
            prepared: prepared,
            credential: credential
        )
    }

    private func temporaryArchiveURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("KeyHollow-\(UUID().uuidString)")
            .appendingPathExtension("khvault")
    }

    private struct Fixture {
        let url: URL
        let prepared: PreparedEncryptedVaultArchive
        let credential: PortableArchiveCredential
    }
}

private struct TestContainerKeyDeriver: PortableArchiveKeyDeriving {
    func deriveWrappingKey(
        credential: PortableArchiveCredential,
        parameters: PortableArchiveKDFParameters
    ) throws -> SymmetricKey {
        try parameters.validate()
        var input = try credential.keyMaterial()
        input.append(parameters.salt)
        return SymmetricKey(data: SHA256.hash(data: input))
    }
}

private extension Data {
    mutating func appendLittleEndianForTesting<T: FixedWidthInteger>(_ value: T) {
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) { bytes in
            append(contentsOf: bytes)
        }
    }

    init(hex: String) throws {
        let compact = hex.filter { !$0.isWhitespace }
        guard compact.count.isMultiple(of: 2) else { throw HexError.invalid }
        var bytes: [UInt8] = []
        bytes.reserveCapacity(compact.count / 2)
        var index = compact.startIndex
        while index < compact.endIndex {
            let next = compact.index(index, offsetBy: 2)
            guard let byte = UInt8(compact[index..<next], radix: 16) else {
                throw HexError.invalid
            }
            bytes.append(byte)
            index = next
        }
        self = Data(bytes)
    }

    enum HexError: Error { case invalid }
}

