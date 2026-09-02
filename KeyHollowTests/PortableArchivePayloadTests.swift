import CryptoKit
import Foundation
import XCTest
@testable import KeyHollow

final class PortableArchivePayloadTests: XCTestCase {
    func testEncryptedVaultPayloadRoundTripsWithoutPlaintextMedia() async throws {
        let sourceRoot = temporaryURL(label: "source")
        let archiveURL = temporaryURL(label: "archive").appendingPathExtension("khvault")
        let stagingURL = temporaryURL(label: "staging")
        defer {
            try? FileManager.default.removeItem(at: sourceRoot)
            try? FileManager.default.removeItem(at: archiveURL)
            try? FileManager.default.removeItem(at: stagingURL)
        }

        let vaultID = UUID()
        let vaultKeyData = Data(repeating: 0x6d, count: 32)
        let vaultKey = SymmetricKey(data: vaultKeyData)
        let store = try VaultPhotoStore(
            vaultID: vaultID,
            vaultKey: vaultKey,
            storageRoot: sourceRoot
        )
        let originalMarker = Data("KEYHOLLOW-NEVER-EXPORT-PLAINTEXT-ORIGINAL".utf8)
        let thumbnailMarker = Data("KEYHOLLOW-NEVER-EXPORT-PLAINTEXT-THUMBNAIL".utf8)
        _ = try await store.importPhoto(
            originalData: originalMarker,
            thumbnailData: thumbnailMarker
        )

        let manifest = try await store.loadManifest()
        let source = try PortableArchivePayloadSource.create(
            rootURL: sourceRoot,
            manifest: manifest
        )
        let credential = PortableArchiveCredential.recoveryCode(
            "0123-4567-89AB-CDEF-GHJK-MNPQ-RSTV-WXYZ"
        )
        let prepared = try EncryptedVaultArchiveHeader.prepare(
            vaultPayload: VaultPayload(
                vaultID: vaultID,
                vaultKey: vaultKeyData,
                createdAt: Date(timeIntervalSince1970: 1_700_000_000)
            ),
            credential: credential,
            keyDeriver: TestPayloadKeyDeriver()
        )

        let writer = try PortableArchiveContainerWriter(
            destinationURL: archiveURL,
            preparedArchive: prepared
        )
        try PortableArchivePayloadWriter.write(source: source, to: writer)
        try writer.finish()

        let archiveBytes = try Data(contentsOf: archiveURL)
        XCTAssertNil(archiveBytes.range(of: originalMarker))
        XCTAssertNil(archiveBytes.range(of: thumbnailMarker))
        for entry in source.catalog.entries {
            XCTAssertNil(archiveBytes.range(of: Data(entry.storageName.utf8)))
        }

        let extractor = try PortableArchivePayloadExtractor(stagingURL: stagingURL)
        let reader = try PortableArchiveContainerReader(sourceURL: archiveURL)
        let secrets = try reader.streamAuthenticatedContent(
            credential: credential,
            keyDeriver: TestPayloadKeyDeriver()
        ) { chunk in
            try extractor.receive(chunk)
        }
        let staged = try extractor.finish()

        XCTAssertEqual(secrets.vaultKey, vaultKeyData)
        XCTAssertEqual(staged.catalog, source.catalog)
        for entry in source.catalog.entries {
            XCTAssertEqual(
                try Data(contentsOf: sourceRoot.appendingPathComponent(entry.storageName)),
                try Data(contentsOf: stagingURL.appendingPathComponent(entry.storageName))
            )
        }
        staged.discard()
        XCTAssertFalse(FileManager.default.fileExists(atPath: stagingURL.path))
    }

    func testCatalogRejectsTraversalAndDuplicateStorageNames() {
        let digest = Data(
            repeating: 0x11,
            count: PortableArchivePayloadFormat.sha256ByteCount
        )
        let traversal = PortableArchivePayloadCatalog(
            version: PortableArchivePayloadCatalog.currentVersion,
            entries: [
                PortableArchivePayloadEntry(
                    storageName: "manifest.khm",
                    role: .manifest,
                    ciphertextByteCount: 28,
                    ciphertextSHA256: digest
                ),
                PortableArchivePayloadEntry(
                    storageName: "../escape.khp",
                    role: .original,
                    ciphertextByteCount: 28,
                    ciphertextSHA256: digest
                )
            ]
        )
        XCTAssertThrowsError(try traversal.validate())

        let duplicate = PortableArchivePayloadCatalog(
            version: PortableArchivePayloadCatalog.currentVersion,
            entries: [
                PortableArchivePayloadEntry(
                    storageName: "manifest.khm",
                    role: .manifest,
                    ciphertextByteCount: 28,
                    ciphertextSHA256: digest
                ),
                PortableArchivePayloadEntry(
                    storageName: "same.khp",
                    role: .original,
                    ciphertextByteCount: 28,
                    ciphertextSHA256: digest
                ),
                PortableArchivePayloadEntry(
                    storageName: "same.khp",
                    role: .original,
                    ciphertextByteCount: 28,
                    ciphertextSHA256: digest
                )
            ]
        )
        XCTAssertThrowsError(try duplicate.validate()) { error in
            XCTAssertEqual(
                error as? PortableArchivePayloadError,
                .duplicateEntry("same.khp")
            )
        }
    }

    func testCatalogRejectsEntryAndAggregateSizeExhaustion() {
        let digest = Data(
            repeating: 0x11,
            count: PortableArchivePayloadFormat.sha256ByteCount
        )
        let oversizedEntry = PortableArchivePayloadCatalog(
            version: PortableArchivePayloadCatalog.currentVersion,
            entries: [
                PortableArchivePayloadEntry(
                    storageName: "manifest.khm",
                    role: .manifest,
                    ciphertextByteCount: PortableArchivePayloadFormat.maximumEntryByteCount + 1,
                    ciphertextSHA256: digest
                )
            ]
        )

        XCTAssertThrowsError(try oversizedEntry.validate()) { error in
            XCTAssertEqual(
                error as? PortableArchivePayloadError,
                .invalidEntry("manifest.khm")
            )
        }

        let excessiveTotalEntries = (0..<5).map { index in
            PortableArchivePayloadEntry(
                storageName: index == 0 ? "manifest.khm" : "photo-\(index).khp",
                role: index == 0 ? .manifest : .original,
                ciphertextByteCount: PortableArchivePayloadFormat.maximumEntryByteCount,
                ciphertextSHA256: digest
            )
        }
        let excessiveTotal = PortableArchivePayloadCatalog(
            version: PortableArchivePayloadCatalog.currentVersion,
            entries: excessiveTotalEntries
        )

        XCTAssertThrowsError(try excessiveTotal.validate()) { error in
            XCTAssertEqual(error as? PortableArchivePayloadError, .invalidCatalog)
        }
    }

    func testExtractorRejectsOversizedCatalogBeforeCreatingStagingDirectory() throws {
        let stagingURL = temporaryURL(label: "oversized-catalog-staging")
        defer { try? FileManager.default.removeItem(at: stagingURL) }

        var prefix = PortableArchivePayloadFormat.magic
        prefix.appendPayloadLittleEndianForTesting(PortableArchivePayloadFormat.currentVersion)
        prefix.appendPayloadLittleEndianForTesting(
            UInt32(PortableArchivePayloadFormat.maximumCatalogByteCount + 1)
        )
        let extractor = try PortableArchivePayloadExtractor(stagingURL: stagingURL)

        XCTAssertThrowsError(try extractor.receive(prefix)) { error in
            XCTAssertEqual(error as? PortableArchivePayloadError, .invalidCatalogLength)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: stagingURL.path))
    }

    func testPayloadWriterDetectsSourceChangedAfterCatalogCreation() async throws {
        let sourceRoot = temporaryURL(label: "source-change")
        let archiveURL = temporaryURL(label: "source-change-archive")
            .appendingPathExtension("khvault")
        defer {
            try? FileManager.default.removeItem(at: sourceRoot)
            try? FileManager.default.removeItem(at: archiveURL)
        }

        let key = SymmetricKey(size: .bits256)
        let store = try VaultPhotoStore(
            vaultID: UUID(),
            vaultKey: key,
            storageRoot: sourceRoot
        )
        let record = try await store.importPhoto(
            originalData: Data("original".utf8),
            thumbnailData: Data("thumbnail".utf8)
        )
        let manifest = try await store.loadManifest()
        let source = try PortableArchivePayloadSource.create(
            rootURL: sourceRoot,
            manifest: manifest
        )

        let changedURL = sourceRoot.appendingPathComponent(record.blobName)
        var changed = try Data(contentsOf: changedURL)
        changed[changed.startIndex] ^= 0x01
        try changed.write(to: changedURL, options: .atomic)

        let fixture = try preparedFixture()
        let writer = try PortableArchiveContainerWriter(
            destinationURL: archiveURL,
            preparedArchive: fixture.prepared
        )
        XCTAssertThrowsError(
            try PortableArchivePayloadWriter.write(source: source, to: writer)
        ) { error in
            XCTAssertEqual(
                error as? PortableArchivePayloadError,
                .sourceChanged(record.blobName)
            )
        }
        writer.cancel()
        XCTAssertFalse(FileManager.default.fileExists(atPath: archiveURL.path))
    }

    func testDigestMismatchRemovesStagingDirectory() throws {
        let fixture = try preparedFixture()
        let archiveURL = temporaryURL(label: "bad-digest").appendingPathExtension("khvault")
        let stagingURL = temporaryURL(label: "bad-digest-staging")
        defer {
            try? FileManager.default.removeItem(at: archiveURL)
            try? FileManager.default.removeItem(at: stagingURL)
        }

        let ciphertext = Data(repeating: 0x44, count: 28)
        let catalog = PortableArchivePayloadCatalog(
            version: PortableArchivePayloadCatalog.currentVersion,
            entries: [
                PortableArchivePayloadEntry(
                    storageName: "manifest.khm",
                    role: .manifest,
                    ciphertextByteCount: UInt64(ciphertext.count),
                    ciphertextSHA256: Data(
                        repeating: 0xff,
                        count: PortableArchivePayloadFormat.sha256ByteCount
                    )
                )
            ]
        )
        let writer = try PortableArchiveContainerWriter(
            destinationURL: archiveURL,
            preparedArchive: fixture.prepared
        )
        try writeRawPayload(catalog: catalog, fileBytes: ciphertext, to: writer)
        try writer.finish()

        let extractor = try PortableArchivePayloadExtractor(stagingURL: stagingURL)
        let reader = try PortableArchiveContainerReader(sourceURL: archiveURL)
        XCTAssertThrowsError(
            try reader.streamAuthenticatedContent(
                credential: fixture.credential,
                keyDeriver: TestPayloadKeyDeriver()
            ) { chunk in
                try extractor.receive(chunk)
            }
        ) { error in
            XCTAssertEqual(
                error as? PortableArchivePayloadError,
                .digestMismatch("manifest.khm")
            )
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: stagingURL.path))
    }

    func testTruncatedInnerPayloadCannotBecomeStagedVault() throws {
        let fixture = try preparedFixture()
        let archiveURL = temporaryURL(label: "truncated-inner").appendingPathExtension("khvault")
        let stagingURL = temporaryURL(label: "truncated-inner-staging")
        defer {
            try? FileManager.default.removeItem(at: archiveURL)
            try? FileManager.default.removeItem(at: stagingURL)
        }

        let partialCiphertext = Data(repeating: 0x22, count: 28)
        let catalog = PortableArchivePayloadCatalog(
            version: PortableArchivePayloadCatalog.currentVersion,
            entries: [
                PortableArchivePayloadEntry(
                    storageName: "manifest.khm",
                    role: .manifest,
                    ciphertextByteCount: 56,
                    ciphertextSHA256: Data(
                        repeating: 0x33,
                        count: PortableArchivePayloadFormat.sha256ByteCount
                    )
                )
            ]
        )
        let writer = try PortableArchiveContainerWriter(
            destinationURL: archiveURL,
            preparedArchive: fixture.prepared
        )
        try writeRawPayload(catalog: catalog, fileBytes: partialCiphertext, to: writer)
        try writer.finish()

        let extractor = try PortableArchivePayloadExtractor(stagingURL: stagingURL)
        let reader = try PortableArchiveContainerReader(sourceURL: archiveURL)
        try reader.streamAuthenticatedContent(
            credential: fixture.credential,
            keyDeriver: TestPayloadKeyDeriver()
        ) { chunk in
            try extractor.receive(chunk)
        }
        XCTAssertThrowsError(try extractor.finish()) { error in
            XCTAssertEqual(error as? PortableArchivePayloadError, .truncatedPayload)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: stagingURL.path))
    }

    private func writeRawPayload(
        catalog: PortableArchivePayloadCatalog,
        fileBytes: Data,
        to writer: PortableArchiveContainerWriter
    ) throws {
        let encodedCatalog = try JSONEncoder().encode(catalog)
        var prefix = PortableArchivePayloadFormat.magic
        prefix.appendPayloadLittleEndianForTesting(PortableArchivePayloadFormat.currentVersion)
        prefix.appendPayloadLittleEndianForTesting(UInt32(encodedCatalog.count))
        try writer.append(prefix)
        try writer.append(encodedCatalog)
        try writer.append(fileBytes)
    }

    private func preparedFixture() throws -> (
        prepared: PreparedEncryptedVaultArchive,
        credential: PortableArchiveCredential
    ) {
        let credential = PortableArchiveCredential.recoveryCode(
            "0123-4567-89AB-CDEF-GHJK-MNPQ-RSTV-WXYZ"
        )
        let prepared = try EncryptedVaultArchiveHeader.prepare(
            vaultPayload: VaultPayload(
                vaultID: UUID(),
                vaultKey: Data(repeating: 0x51, count: 32),
                createdAt: Date(timeIntervalSince1970: 1_700_000_000)
            ),
            credential: credential,
            keyDeriver: TestPayloadKeyDeriver()
        )
        return (prepared, credential)
    }

    private func temporaryURL(label: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("KeyHollow-\(label)-\(UUID().uuidString)")
    }
}

private struct TestPayloadKeyDeriver: PortableArchiveKeyDeriving {
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
    mutating func appendPayloadLittleEndianForTesting<T: FixedWidthInteger>(_ value: T) {
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) { bytes in
            append(contentsOf: bytes)
        }
    }
}
