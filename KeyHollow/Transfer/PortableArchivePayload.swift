import CryptoKit
import Foundation
import KeyHollowPhotoCore

enum PortableArchivePayloadError: Error, Equatable {
    case alreadyFinished
    case destinationExists
    case digestMismatch(String)
    case duplicateEntry(String)
    case invalidCatalog
    case invalidCatalogLength
    case invalidEntry(String)
    case invalidMagic
    case missingEntry(String)
    case sourceChanged(String)
    case truncatedPayload
    case unexpectedPayloadData
    case unsupportedVersion
}

enum PortableArchivePayloadFormat {
    static let magic = Data([0x4b, 0x48, 0x50, 0x41, 0x59, 0x4c, 0x44, 0x00])
    static let currentVersion: UInt32 = 1
    static let prefixByteCount = 16
    static let maximumCatalogByteCount = 33_554_432
    static let maximumEntryCount = 200_001
    static let maximumEntryByteCount: UInt64 = 1_099_511_627_776
    static let maximumTotalByteCount: UInt64 = 4_398_046_511_104
    static let fileReadByteCount = 1_048_576
    static let sha256ByteCount = 32
}

enum PortableArchivePayloadEntryRole: String, Codable, Sendable {
    case manifest
    case original
    case thumbnail
    case supplementalManifest
    case supplementalBlob
}

struct PortableArchivePayloadEntry: Codable, Equatable, Sendable {
    let storageName: String
    let role: PortableArchivePayloadEntryRole
    let ciphertextByteCount: UInt64
    let ciphertextSHA256: Data
}

public struct PortableArchivePayloadCatalog: Codable, Equatable, Sendable {
    static let legacyPhotoOnlyVersion = 1
    static let currentVersion = 2

    let version: Int
    let entries: [PortableArchivePayloadEntry]

    func validate() throws {
        guard (Self.legacyPhotoOnlyVersion...Self.currentVersion).contains(version),
              !entries.isEmpty,
              entries.count <= PortableArchivePayloadFormat.maximumEntryCount else {
            throw PortableArchivePayloadError.invalidCatalog
        }

        var names = Set<String>()
        var manifestCount = 0
        var supplementalManifestCount = 0
        var supplementalBlobCount = 0
        var totalByteCount: UInt64 = 0

        for entry in entries {
            try Self.validateStorageName(entry.storageName, role: entry.role)
            guard names.insert(entry.storageName).inserted else {
                throw PortableArchivePayloadError.duplicateEntry(entry.storageName)
            }
            guard entry.ciphertextByteCount >= 28,
                  entry.ciphertextByteCount <= PortableArchivePayloadFormat.maximumEntryByteCount,
                  entry.ciphertextSHA256.count == PortableArchivePayloadFormat.sha256ByteCount else {
                throw PortableArchivePayloadError.invalidEntry(entry.storageName)
            }

            let (newTotal, overflow) = totalByteCount.addingReportingOverflow(
                entry.ciphertextByteCount
            )
            guard !overflow,
                  newTotal <= PortableArchivePayloadFormat.maximumTotalByteCount else {
                throw PortableArchivePayloadError.invalidCatalog
            }
            totalByteCount = newTotal

            if entry.role == .manifest {
                manifestCount += 1
            } else if entry.role == .supplementalManifest {
                supplementalManifestCount += 1
            } else if entry.role == .supplementalBlob {
                supplementalBlobCount += 1
            }
        }

        guard manifestCount == 1,
              entries.first?.role == .manifest,
              entries.first?.storageName == "manifest.khm",
              supplementalManifestCount <= 1,
              supplementalBlobCount == 0 || supplementalManifestCount == 1,
              version >= Self.currentVersion
                || (supplementalManifestCount == 0 && supplementalBlobCount == 0) else {
            throw PortableArchivePayloadError.invalidCatalog
        }
    }

    static func validateStorageName(
        _ name: String,
        role: PortableArchivePayloadEntryRole
    ) throws {
        guard !name.isEmpty,
              name.utf8.count <= 255,
              name != ".",
              name != "..",
              !name.contains("\\"),
              !name.contains("\0"),
              !name.hasPrefix("/"),
              !name.hasSuffix("/") else {
            throw PortableArchivePayloadError.invalidEntry(name)
        }

        let expectedExtension: String
        switch role {
        case .manifest:
            guard name == "manifest.khm" else {
                throw PortableArchivePayloadError.invalidEntry(name)
            }
            expectedExtension = "khm"
        case .original:
            guard !name.contains("/") else {
                throw PortableArchivePayloadError.invalidEntry(name)
            }
            expectedExtension = "khp"
        case .thumbnail:
            guard !name.contains("/") else {
                throw PortableArchivePayloadError.invalidEntry(name)
            }
            expectedExtension = "kht"
        case .supplementalManifest:
            guard name == "supplemental/manifest.khm" else {
                throw PortableArchivePayloadError.invalidEntry(name)
            }
            expectedExtension = "khm"
        case .supplementalBlob:
            let components = name.split(separator: "/", omittingEmptySubsequences: false)
            guard components.count == 2,
                  components[0] == "supplemental",
                  !components[1].isEmpty,
                  components[1] != ".",
                  components[1] != ".." else {
                throw PortableArchivePayloadError.invalidEntry(name)
            }
            expectedExtension = "khf"
        }

        let leaf = String(name.split(separator: "/").last ?? "")
        guard URL(fileURLWithPath: leaf).lastPathComponent == leaf,
              URL(fileURLWithPath: leaf).pathExtension.lowercased() == expectedExtension else {
            throw PortableArchivePayloadError.invalidEntry(name)
        }
    }
}

public struct PortableVaultSupplementalArchiveEntry: Sendable {
    public let storageName: String
    public let sourceURL: URL

    public init(storageName: String, sourceURL: URL) {
        self.storageName = storageName
        self.sourceURL = sourceURL
    }
}

public struct PortableVaultSupplementalArchiveInventory: Sendable {
    public let manifestURL: URL?
    public let entries: [PortableVaultSupplementalArchiveEntry]
    public let itemCount: Int

    public init(
        manifestURL: URL?,
        entries: [PortableVaultSupplementalArchiveEntry],
        itemCount: Int
    ) {
        self.manifestURL = manifestURL
        self.entries = entries
        self.itemCount = itemCount
    }

    public static let empty = PortableVaultSupplementalArchiveInventory(
        manifestURL: nil,
        entries: [],
        itemCount: 0
    )
}

struct PortableArchivePayloadSource: Sendable {
    let catalog: PortableArchivePayloadCatalog
    private let sourceURLsByStorageName: [String: URL]

    static func create(
        rootURL: URL,
        manifest: VaultPhotoManifest
    ) throws -> PortableArchivePayloadSource {
        guard manifest.version == VaultPhotoManifest.currentVersion else {
            throw PortableArchivePayloadError.invalidCatalog
        }

        var requestedEntries: [(String, PortableArchivePayloadEntryRole)] = [
            ("manifest.khm", .manifest)
        ]
        for photo in manifest.photos {
            requestedEntries.append((photo.blobName, .original))
            requestedEntries.append((photo.thumbnailName, .thumbnail))
        }

        return try create(requestedEntries.map { entry in
            (
                entry.0,
                entry.1,
                rootURL.appendingPathComponent(entry.0, isDirectory: false)
            )
        })
    }

    static func create(
        photoRootURL: URL,
        photoManifest: VaultPhotoManifest,
        supplementalInventory: PortableVaultSupplementalArchiveInventory
    ) throws -> PortableArchivePayloadSource {
        guard photoManifest.version == VaultPhotoManifest.currentVersion else {
            throw PortableArchivePayloadError.invalidCatalog
        }

        var requestedEntries: [(String, PortableArchivePayloadEntryRole, URL)] = [
            (
                "manifest.khm",
                .manifest,
                photoRootURL.appendingPathComponent("manifest.khm", isDirectory: false)
            )
        ]
        for photo in photoManifest.photos {
            requestedEntries.append((
                photo.blobName,
                .original,
                photoRootURL.appendingPathComponent(photo.blobName, isDirectory: false)
            ))
            requestedEntries.append((
                photo.thumbnailName,
                .thumbnail,
                photoRootURL.appendingPathComponent(photo.thumbnailName, isDirectory: false)
            ))
        }

        guard supplementalInventory.itemCount >= 0 else {
            throw PortableArchivePayloadError.invalidCatalog
        }
        if supplementalInventory.itemCount == 0 {
            guard supplementalInventory.manifestURL == nil,
                  supplementalInventory.entries.isEmpty else {
                throw PortableArchivePayloadError.invalidCatalog
            }
        } else {
            guard let manifestURL = supplementalInventory.manifestURL,
                  supplementalInventory.entries.count == supplementalInventory.itemCount else {
                throw PortableArchivePayloadError.missingEntry("supplemental/manifest.khm")
            }
            requestedEntries.append(("supplemental/manifest.khm", .supplementalManifest, manifestURL))
            for entry in supplementalInventory.entries {
                requestedEntries.append((
                    "supplemental/\(entry.storageName)",
                    .supplementalBlob,
                    entry.sourceURL
                ))
            }
        }
        return try create(requestedEntries)
    }

    private static func create(
        _ requestedEntries: [(String, PortableArchivePayloadEntryRole, URL)]
    ) throws -> PortableArchivePayloadSource {
        var entries: [PortableArchivePayloadEntry] = []
        var sourceURLsByStorageName: [String: URL] = [:]
        entries.reserveCapacity(requestedEntries.count)
        for (storageName, role, fileURL) in requestedEntries {
            try PortableArchivePayloadCatalog.validateStorageName(storageName, role: role)
            let properties = try fileURL.resourceValues(
                forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey]
            )
            guard properties.isRegularFile == true,
                  properties.isSymbolicLink != true,
                  let fileSize = properties.fileSize,
                  fileSize >= 28 else {
                throw PortableArchivePayloadError.missingEntry(storageName)
            }

            let digest = try Self.hashFile(fileURL)
            entries.append(
                PortableArchivePayloadEntry(
                    storageName: storageName,
                    role: role,
                    ciphertextByteCount: UInt64(fileSize),
                    ciphertextSHA256: digest
                )
            )
            guard sourceURLsByStorageName.updateValue(fileURL, forKey: storageName) == nil else {
                throw PortableArchivePayloadError.duplicateEntry(storageName)
            }
        }

        let catalog = PortableArchivePayloadCatalog(
            version: PortableArchivePayloadCatalog.currentVersion,
            entries: entries
        )
        try catalog.validate()
        return PortableArchivePayloadSource(
            catalog: catalog,
            sourceURLsByStorageName: sourceURLsByStorageName
        )
    }

    fileprivate func sourceURL(for storageName: String) throws -> URL {
        guard let url = sourceURLsByStorageName[storageName] else {
            throw PortableArchivePayloadError.missingEntry(storageName)
        }
        return url
    }

    fileprivate static func hashFile(_ fileURL: URL) throws -> Data {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }
        var hasher = SHA256()

        while let data = try handle.read(
            upToCount: PortableArchivePayloadFormat.fileReadByteCount
        ), !data.isEmpty {
            try Task.checkCancellation()
            hasher.update(data: data)
        }
        return Data(hasher.finalize())
    }
}

enum PortableArchivePayloadWriter {
    static func write(
        source: PortableArchivePayloadSource,
        to containerWriter: PortableArchiveContainerWriter
    ) throws {
        try source.catalog.validate()
        let encodedCatalog = try JSONEncoder().encode(source.catalog)
        guard !encodedCatalog.isEmpty,
              encodedCatalog.count <= PortableArchivePayloadFormat.maximumCatalogByteCount else {
            throw PortableArchivePayloadError.invalidCatalogLength
        }

        var prefix = PortableArchivePayloadFormat.magic
        prefix.appendPayloadLittleEndian(PortableArchivePayloadFormat.currentVersion)
        prefix.appendPayloadLittleEndian(UInt32(encodedCatalog.count))
        try containerWriter.append(prefix)
        try containerWriter.append(encodedCatalog)

        for entry in source.catalog.entries {
            try Task.checkCancellation()
            let fileURL = try source.sourceURL(for: entry.storageName)
            let handle = try FileHandle(forReadingFrom: fileURL)
            var hasher = SHA256()
            var writtenByteCount: UInt64 = 0

            do {
                while let data = try handle.read(
                    upToCount: PortableArchivePayloadFormat.fileReadByteCount
                ), !data.isEmpty {
                    try Task.checkCancellation()
                    let (newCount, overflow) = writtenByteCount.addingReportingOverflow(
                        UInt64(data.count)
                    )
                    guard !overflow,
                          newCount <= entry.ciphertextByteCount else {
                        throw PortableArchivePayloadError.sourceChanged(entry.storageName)
                    }
                    writtenByteCount = newCount
                    hasher.update(data: data)
                    try containerWriter.append(data)
                }
                try handle.close()
            } catch {
                try? handle.close()
                throw error
            }

            guard writtenByteCount == entry.ciphertextByteCount,
                  Data(hasher.finalize()) == entry.ciphertextSHA256 else {
                throw PortableArchivePayloadError.sourceChanged(entry.storageName)
            }
        }
    }
}

final class PortableArchiveStagedPayload {
    let directoryURL: URL
    let catalog: PortableArchivePayloadCatalog

    private var ownsDirectory = true

    fileprivate init(directoryURL: URL, catalog: PortableArchivePayloadCatalog) {
        self.directoryURL = directoryURL
        self.catalog = catalog
    }

    deinit {
        if ownsDirectory {
            try? FileManager.default.removeItem(at: directoryURL)
        }
    }

    func discard() {
        guard ownsDirectory else { return }
        try? FileManager.default.removeItem(at: directoryURL)
        ownsDirectory = false
    }

    func commit(
        to destinationURL: URL,
        generalFileDestinationURL: URL? = nil
    ) throws {
        guard ownsDirectory else {
            throw PortableArchivePayloadError.alreadyFinished
        }
        guard !FileManager.default.fileExists(atPath: destinationURL.path) else {
            throw PortableArchivePayloadError.destinationExists
        }
        if let generalFileDestinationURL {
            guard !FileManager.default.fileExists(atPath: generalFileDestinationURL.path) else {
                throw PortableArchivePayloadError.destinationExists
            }
            let stagedGeneralFiles = directoryURL.appendingPathComponent(
                "supplemental",
                isDirectory: true
            )
            guard FileManager.default.fileExists(atPath: stagedGeneralFiles.path) else {
                throw PortableArchivePayloadError.missingEntry("supplemental/manifest.khm")
            }
            try FileManager.default.moveItem(
                at: stagedGeneralFiles,
                to: generalFileDestinationURL
            )
        }
        try FileManager.default.moveItem(at: directoryURL, to: destinationURL)
        ownsDirectory = false
    }
}

final class PortableArchivePayloadExtractor {
    private let stagingURL: URL
    private var buffer = Data()
    private var expectedCatalogByteCount: Int?
    private var catalog: PortableArchivePayloadCatalog?
    private var currentEntryIndex = 0
    private var currentEntryRemainingByteCount: UInt64 = 0
    private var currentEntryWrittenByteCount: UInt64 = 0
    private var currentEntryHasher = SHA256()
    private var currentEntryHandle: FileHandle?
    private var isComplete = false
    private var isFinished = false
    private var relinquishedStagingDirectory = false

    init(stagingURL: URL) throws {
        guard !FileManager.default.fileExists(atPath: stagingURL.path) else {
            throw PortableArchivePayloadError.destinationExists
        }
        self.stagingURL = stagingURL
    }

    deinit {
        try? currentEntryHandle?.close()
        if !relinquishedStagingDirectory {
            try? FileManager.default.removeItem(at: stagingURL)
        }
    }

    func receive(_ data: Data) throws {
        guard !isFinished else {
            throw PortableArchivePayloadError.alreadyFinished
        }
        guard !isComplete || data.isEmpty else {
            failAndCleanUp()
            throw PortableArchivePayloadError.unexpectedPayloadData
        }
        guard !data.isEmpty else { return }

        buffer.append(data)
        do {
            try processAvailableBytes()
        } catch {
            failAndCleanUp()
            throw error
        }
    }

    func finish() throws -> PortableArchiveStagedPayload {
        guard !isFinished else {
            throw PortableArchivePayloadError.alreadyFinished
        }
        isFinished = true

        guard isComplete,
              buffer.isEmpty,
              currentEntryHandle == nil,
              let catalog else {
            failAndCleanUp()
            throw PortableArchivePayloadError.truncatedPayload
        }

        relinquishedStagingDirectory = true
        return PortableArchiveStagedPayload(directoryURL: stagingURL, catalog: catalog)
    }

    func cancel() {
        guard !isFinished else { return }
        isFinished = true
        failAndCleanUp()
    }

    private func processAvailableBytes() throws {
        if expectedCatalogByteCount == nil {
            guard buffer.count >= PortableArchivePayloadFormat.prefixByteCount else { return }
            let prefix = Data(buffer.prefix(PortableArchivePayloadFormat.prefixByteCount))
            guard prefix.prefix(PortableArchivePayloadFormat.magic.count)
                == PortableArchivePayloadFormat.magic else {
                throw PortableArchivePayloadError.invalidMagic
            }

            let versionRange = 8..<12
            let lengthRange = 12..<16
            let version = decodePayloadUInt32(Data(prefix[versionRange]))
            guard version == PortableArchivePayloadFormat.currentVersion else {
                throw PortableArchivePayloadError.unsupportedVersion
            }
            let catalogByteCount = Int(decodePayloadUInt32(Data(prefix[lengthRange])))
            guard catalogByteCount > 0,
                  catalogByteCount <= PortableArchivePayloadFormat.maximumCatalogByteCount else {
                throw PortableArchivePayloadError.invalidCatalogLength
            }
            expectedCatalogByteCount = catalogByteCount
            buffer.removeFirst(PortableArchivePayloadFormat.prefixByteCount)
        }

        if catalog == nil {
            guard let expectedCatalogByteCount,
                  buffer.count >= expectedCatalogByteCount else { return }

            let encodedCatalog = Data(buffer.prefix(expectedCatalogByteCount))
            buffer.removeFirst(expectedCatalogByteCount)
            let decodedCatalog: PortableArchivePayloadCatalog
            do {
                decodedCatalog = try JSONDecoder().decode(
                    PortableArchivePayloadCatalog.self,
                    from: encodedCatalog
                )
            } catch {
                throw PortableArchivePayloadError.invalidCatalog
            }
            try decodedCatalog.validate()
            try createProtectedStagingDirectory()
            catalog = decodedCatalog
            try beginCurrentEntry()
        }

        while !isComplete, !buffer.isEmpty {
            try Task.checkCancellation()
            guard let catalog,
                  currentEntryIndex < catalog.entries.count,
                  let handle = currentEntryHandle else {
                throw PortableArchivePayloadError.invalidCatalog
            }

            let count = min(
                buffer.count,
                Int(min(currentEntryRemainingByteCount, UInt64(Int.max)))
            )
            guard count > 0 else {
                throw PortableArchivePayloadError.invalidCatalog
            }

            let data = Data(buffer.prefix(count))
            buffer.removeFirst(count)
            try handle.write(contentsOf: data)
            currentEntryHasher.update(data: data)
            currentEntryRemainingByteCount -= UInt64(count)
            currentEntryWrittenByteCount += UInt64(count)

            if currentEntryRemainingByteCount == 0 {
                try finishCurrentEntry()
            }
        }

        if isComplete, !buffer.isEmpty {
            throw PortableArchivePayloadError.unexpectedPayloadData
        }
    }

    private func createProtectedStagingDirectory() throws {
        try FileManager.default.createDirectory(
            at: stagingURL,
            withIntermediateDirectories: false,
            attributes: [.protectionKey: FileProtectionType.complete]
        )
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var protectedURL = stagingURL
        try protectedURL.setResourceValues(values)
    }

    private func beginCurrentEntry() throws {
        guard let catalog else {
            throw PortableArchivePayloadError.invalidCatalog
        }
        guard currentEntryIndex < catalog.entries.count else {
            isComplete = true
            return
        }

        let entry = catalog.entries[currentEntryIndex]
        let destinationURL = stagingURL.appendingPathComponent(
            entry.storageName,
            isDirectory: false
        )
        let parentURL = destinationURL.deletingLastPathComponent()
        if parentURL != stagingURL,
           !FileManager.default.fileExists(atPath: parentURL.path) {
            try FileManager.default.createDirectory(
                at: parentURL,
                withIntermediateDirectories: false,
                attributes: [.protectionKey: FileProtectionType.complete]
            )
        }
        guard FileManager.default.createFile(
            atPath: destinationURL.path,
            contents: nil,
            attributes: [.protectionKey: FileProtectionType.complete]
        ) else {
            throw PortableArchivePayloadError.invalidEntry(entry.storageName)
        }

        currentEntryHandle = try FileHandle(forWritingTo: destinationURL)
        currentEntryRemainingByteCount = entry.ciphertextByteCount
        currentEntryWrittenByteCount = 0
        currentEntryHasher = SHA256()
    }

    private func finishCurrentEntry() throws {
        guard let catalog,
              currentEntryIndex < catalog.entries.count,
              let handle = currentEntryHandle else {
            throw PortableArchivePayloadError.invalidCatalog
        }
        let entry = catalog.entries[currentEntryIndex]
        try handle.synchronize()
        try handle.close()
        currentEntryHandle = nil

        guard currentEntryWrittenByteCount == entry.ciphertextByteCount,
              Data(currentEntryHasher.finalize()) == entry.ciphertextSHA256 else {
            throw PortableArchivePayloadError.digestMismatch(entry.storageName)
        }

        currentEntryIndex += 1
        try beginCurrentEntry()
    }

    private func failAndCleanUp() {
        isFinished = true
        try? currentEntryHandle?.close()
        currentEntryHandle = nil
        buffer.removeAll(keepingCapacity: false)
        try? FileManager.default.removeItem(at: stagingURL)
    }
}

private func decodePayloadUInt32(_ data: Data) -> UInt32 {
    precondition(data.count == 4)
    return data.enumerated().reduce(into: UInt32(0)) { result, element in
        result |= UInt32(element.element) << UInt32(element.offset * 8)
    }
}

private extension Data {
    mutating func appendPayloadLittleEndian<T: FixedWidthInteger>(_ value: T) {
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) { bytes in
            append(contentsOf: bytes)
        }
    }
}
