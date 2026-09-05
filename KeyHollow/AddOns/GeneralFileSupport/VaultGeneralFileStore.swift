import Foundation

public actor VaultGeneralFileStore {
    public enum StoreError: Error, Equatable {
        case accessMismatch
        case batchTooLarge
        case emptyFile
        case fileTooLarge
        case invalidManifest
        case protectedFileType
        case sourceUnavailable
        case unsupportedItem
        case verificationFailed
    }

    /// A bounded first release avoids large plaintext/ciphertext copies causing
    /// memory pressure. Video receives its own streaming add-on later.
    public static let maximumFileByteCount: UInt64 = 100 * 1_024 * 1_024
    public static let maximumBatchCount = 50

    private static let protectedExtensions: Set<String> = [
        "app", "bat", "cmd", "com", "command", "dmg", "exe", "ipa",
        "khvault", "msi", "pkg", "sh"
    ]

    private let fileManager = FileManager.default
    private let root: URL
    private let temporaryRoot: URL
    private let vaultID: UUID
    private let access: any VaultGeneralFileCryptographicAccess

    public init(
        vaultID: UUID,
        access: any VaultGeneralFileCryptographicAccess,
        storageRoot: URL? = nil,
        temporaryRoot: URL? = nil
    ) throws {
        guard access.vaultID == vaultID else { throw StoreError.accessMismatch }
        self.vaultID = vaultID
        self.access = access
        self.temporaryRoot = temporaryRoot ?? fileManager.temporaryDirectory

        if let storageRoot {
            root = storageRoot
        } else {
            let appSupport = try fileManager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            root = appSupport
                .appendingPathComponent("KeyHollow/GeneralFileData", isDirectory: true)
                .appendingPathComponent(vaultID.uuidString.lowercased(), isDirectory: true)
        }

        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        try Self.protectAndExclude(root, fileManager: fileManager)
        try Self.purgeStaleTemporaryData(at: self.temporaryRoot, fileManager: fileManager)
    }

    public func loadManifest() throws -> VaultGeneralFileManifest {
        try Task.checkCancellation()
        guard fileManager.fileExists(atPath: manifestURL.path) else { return .empty }

        let ciphertext = try Data(contentsOf: manifestURL, options: [.mappedIfSafe])
        let plaintext = try access.open(ciphertext, for: .manifest)
        try Task.checkCancellation()
        let manifest = try JSONDecoder().decode(VaultGeneralFileManifest.self, from: plaintext)
        guard manifest.version == VaultGeneralFileManifest.currentVersion else {
            throw StoreError.invalidManifest
        }
        return manifest
    }

    public func importFile(at sourceURL: URL) throws -> VaultGeneralFileRecord {
        try Task.checkCancellation()
        let staged = try stageSourceFile(sourceURL)
        defer { try? fileManager.removeItem(at: staged.rootURL) }

        let plaintext = try Data(contentsOf: staged.fileURL, options: [.mappedIfSafe])
        try Task.checkCancellation()
        let id = UUID()
        let blobName = "\(UUID().uuidString.lowercased()).khf"
        let record = VaultGeneralFileRecord(
            id: id,
            importedAt: Date(),
            displayName: safeDisplayName(sourceURL.lastPathComponent),
            contentTypeIdentifier: staged.contentTypeIdentifier,
            originalByteCount: UInt64(plaintext.count),
            blobName: blobName
        )
        let ciphertext = try access.seal(plaintext, for: .file(id))
        let blobURL = root.appendingPathComponent(blobName)

        do {
            try secureWrite(ciphertext, to: blobURL)
            let verified = try access.open(
                Data(contentsOf: blobURL, options: [.mappedIfSafe]),
                for: .file(id)
            )
            try Task.checkCancellation()
            guard verified == plaintext else { throw StoreError.verificationFailed }

            var manifest = try loadManifest()
            manifest.files.insert(record, at: 0)
            try saveManifest(manifest)
            return record
        } catch {
            try? fileManager.removeItem(at: blobURL)
            throw error
        }
    }

    public func importFiles(at sourceURLs: [URL]) throws -> VaultGeneralFileImportResult {
        guard sourceURLs.count <= Self.maximumBatchCount else {
            throw StoreError.batchTooLarge
        }

        var importedCount = 0
        var failedCount = 0
        for sourceURL in sourceURLs {
            try Task.checkCancellation()
            do {
                _ = try importFile(at: sourceURL)
                importedCount += 1
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                failedCount += 1
            }
        }
        return VaultGeneralFileImportResult(
            importedCount: importedCount,
            failedCount: failedCount
        )
    }

    public func prepareExport(_ records: [VaultGeneralFileRecord]) throws -> PreparedGeneralFileExport {
        guard !records.isEmpty else { throw StoreError.unsupportedItem }
        try Task.checkCancellation()

        let exportID = UUID()
        let exportRoot = temporaryRoot
            .appendingPathComponent("KeyHollowGeneralFileExports", isDirectory: true)
            .appendingPathComponent(exportID.uuidString.lowercased(), isDirectory: true)
        try fileManager.createDirectory(at: exportRoot, withIntermediateDirectories: true)
        try Self.protectAndExclude(exportRoot, fileManager: fileManager)

        do {
            var urls: [URL] = []
            var usedNames: Set<String> = []
            for record in records {
                try Task.checkCancellation()
                let ciphertext = try Data(
                    contentsOf: root.appendingPathComponent(record.blobName),
                    options: [.mappedIfSafe]
                )
                let plaintext = try access.open(ciphertext, for: .file(record.id))
                guard UInt64(plaintext.count) == record.originalByteCount else {
                    throw StoreError.verificationFailed
                }

                let name = uniqueName(for: record.displayName, usedNames: &usedNames)
                let target = exportRoot.appendingPathComponent(name, isDirectory: false)
                try secureWrite(plaintext, to: target)
                urls.append(target)
            }
            return PreparedGeneralFileExport(id: exportID, urls: urls, rootURL: exportRoot)
        } catch {
            try? fileManager.removeItem(at: exportRoot)
            throw error
        }
    }

    public func discardExport(_ export: PreparedGeneralFileExport) {
        try? fileManager.removeItem(at: export.rootURL)
    }

    public func delete(_ records: [VaultGeneralFileRecord]) throws {
        guard !records.isEmpty else { return }
        let ids = Set(records.map(\.id))
        var manifest = try loadManifest()
        manifest.files.removeAll { ids.contains($0.id) }
        try saveManifest(manifest)

        for record in records {
            try? fileManager.removeItem(at: root.appendingPathComponent(record.blobName))
        }
    }

    public static func destroyVaultData(vaultID: UUID, storageRoot: URL? = nil) throws {
        let fileManager = FileManager.default
        let dataRoot: URL
        if let storageRoot {
            dataRoot = storageRoot
        } else {
            let appSupport = try fileManager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            dataRoot = appSupport.appendingPathComponent(
                "KeyHollow/GeneralFileData",
                isDirectory: true
            )
        }
        let target = dataRoot.appendingPathComponent(
            vaultID.uuidString.lowercased(),
            isDirectory: true
        )
        guard fileManager.fileExists(atPath: target.path) else { return }
        try fileManager.removeItem(at: target)
    }

    private var manifestURL: URL { root.appendingPathComponent("manifest.khm") }

    private func saveManifest(_ manifest: VaultGeneralFileManifest) throws {
        try Task.checkCancellation()
        let plaintext = try JSONEncoder().encode(manifest)
        let ciphertext = try access.seal(plaintext, for: .manifest)
        try Task.checkCancellation()
        try secureWrite(ciphertext, to: manifestURL)
    }

    private func stageSourceFile(_ sourceURL: URL) throws -> (
        rootURL: URL,
        fileURL: URL,
        contentTypeIdentifier: String?
    ) {
        let didAccess = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if didAccess { sourceURL.stopAccessingSecurityScopedResource() }
        }

        let values: URLResourceValues
        do {
            values = try sourceURL.resourceValues(forKeys: [
                .isRegularFileKey,
                .isDirectoryKey,
                .isPackageKey,
                .fileSizeKey,
                .typeIdentifierKey
            ])
        } catch {
            throw StoreError.sourceUnavailable
        }

        guard values.isRegularFile == true,
              values.isDirectory != true,
              values.isPackage != true else { throw StoreError.unsupportedItem }
        guard !Self.protectedExtensions.contains(sourceURL.pathExtension.lowercased()) else {
            throw StoreError.protectedFileType
        }

        if let sourceSize = values.fileSize {
            let byteCount = UInt64(max(sourceSize, 0))
            guard byteCount > 0 else { throw StoreError.emptyFile }
            guard byteCount <= Self.maximumFileByteCount else { throw StoreError.fileTooLarge }
        }

        let stagingRoot = temporaryRoot
            .appendingPathComponent("KeyHollowGeneralFileImports", isDirectory: true)
            .appendingPathComponent(UUID().uuidString.lowercased(), isDirectory: true)
        let stagedURL = stagingRoot.appendingPathComponent("incoming", isDirectory: false)
        try fileManager.createDirectory(at: stagingRoot, withIntermediateDirectories: true)
        try Self.protectAndExclude(stagingRoot, fileManager: fileManager)

        do {
            var coordinationError: NSError?
            var copyError: Error?
            let coordinator = NSFileCoordinator()
            coordinator.coordinate(readingItemAt: sourceURL, options: [], error: &coordinationError) {
                coordinatedURL in
                do {
                    try fileManager.copyItem(at: coordinatedURL, to: stagedURL)
                } catch {
                    copyError = error
                }
            }
            if let coordinationError { throw coordinationError }
            if let copyError { throw copyError }
            let stagedValues = try stagedURL.resourceValues(forKeys: [
                .fileSizeKey,
                .isRegularFileKey,
                .isSymbolicLinkKey
            ])
            guard stagedValues.isRegularFile == true,
                  stagedValues.isSymbolicLink != true,
                  let stagedSize = stagedValues.fileSize else {
                throw StoreError.unsupportedItem
            }
            guard stagedSize > 0 else { throw StoreError.emptyFile }
            guard UInt64(stagedSize) <= Self.maximumFileByteCount else {
                throw StoreError.fileTooLarge
            }
            try Self.protectAndExclude(stagedURL, fileManager: fileManager)
            return (stagingRoot, stagedURL, values.typeIdentifier)
        } catch let error as StoreError {
            try? fileManager.removeItem(at: stagingRoot)
            throw error
        } catch {
            try? fileManager.removeItem(at: stagingRoot)
            throw StoreError.sourceUnavailable
        }
    }

    private func secureWrite(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        try Self.protectAndExclude(url, fileManager: fileManager)
    }

    /// Remove protected plaintext left only when iOS terminated the app before
    /// an import or export completion handler could perform normal cleanup.
    private static func purgeStaleTemporaryData(
        at temporaryRoot: URL,
        fileManager: FileManager
    ) throws {
        for directoryName in [
            "KeyHollowGeneralFileImports",
            "KeyHollowGeneralFileExports"
        ] {
            let directory = temporaryRoot.appendingPathComponent(directoryName, isDirectory: true)
            guard fileManager.fileExists(atPath: directory.path) else { continue }
            try fileManager.removeItem(at: directory)
        }
    }

    private func safeDisplayName(_ proposed: String) -> String {
        let leaf = URL(fileURLWithPath: proposed).lastPathComponent
            .replacingOccurrences(of: ":", with: "-")
        return leaf.isEmpty ? "Vault File" : String(leaf.prefix(180))
    }

    private func uniqueName(for proposed: String, usedNames: inout Set<String>) -> String {
        let safe = safeDisplayName(proposed)
        let url = URL(fileURLWithPath: safe)
        let fileExtension = url.pathExtension
        let base = url.deletingPathExtension().lastPathComponent
        var candidate = safe
        var suffix = 2
        while usedNames.contains(candidate.lowercased()) {
            candidate = fileExtension.isEmpty
                ? "\(base) \(suffix)"
                : "\(base) \(suffix).\(fileExtension)"
            suffix += 1
        }
        usedNames.insert(candidate.lowercased())
        return candidate
    }

    private static func protectAndExclude(_ url: URL, fileManager: FileManager) throws {
        try fileManager.setAttributes(
            [.protectionKey: FileProtectionType.complete],
            ofItemAtPath: url.path
        )
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutableURL = url
        try mutableURL.setResourceValues(values)
    }
}
