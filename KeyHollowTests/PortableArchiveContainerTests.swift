import CryptoKit
import Foundation
import XCTest
@testable import KeyHollow

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
}
