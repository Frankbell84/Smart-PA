import Foundation

public actor VaultFolderPresentationStore {
    public enum StoreError: Error, Equatable {
        case accessMismatch
        case duplicateFolderName
        case folderNotFound
        case invalidFolderName
        case invalidManifest
        case verificationFailed
    }

    public static let maximumFolderNameLength = 80
    public static let maximumThumbnailByteCount = 2 * 1_024 * 1_024

    private let fileManager: FileManager
    private let root: URL
    private let access: any VaultFolderPresentationCryptographicAccess

    public init(
        vaultID: UUID,
        access: any VaultFolderPresentationCryptographicAccess,
        storageRoot: URL? = nil
    ) throws {
        guard access.vaultID == vaultID else { throw StoreError.accessMismatch }
        let fileManager = FileManager.default
        let resolvedRoot: URL
        if let storageRoot {
            resolvedRoot = storageRoot
        } else {
            let appSupport = try fileManager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            resolvedRoot = appSupport
                .appendingPathComponent("KeyHollow/FolderPresentationData", isDirectory: true)
                .appendingPathComponent(vaultID.uuidString.lowercased(), isDirectory: true)
        }

        self.fileManager = fileManager
        self.root = resolvedRoot
        self.access = access

        try fileManager.createDirectory(at: resolvedRoot, withIntermediateDirectories: true)
        try Self.protectAndExclude(resolvedRoot, fileManager: fileManager)
    }

    public func loadManifest() throws -> VaultFolderPresentationManifest {
        try Task.checkCancellation()
        guard fileManager.fileExists(atPath: manifestURL.path) else { return .empty }
        let ciphertext = try Data(contentsOf: manifestURL, options: [.mappedIfSafe])
        let plaintext = try access.open(ciphertext, for: .manifest)
        try Task.checkCancellation()
        let manifest = try JSONDecoder().decode(
            VaultFolderPresentationManifest.self,
            from: plaintext
        )
        try validate(manifest)
        return manifest
    }

    @discardableResult
    public func createFolder(named proposedName: String) throws -> VaultFolderRecord {
        let name = try normalizedFolderName(proposedName)
        var manifest = try loadManifest()
        guard !manifest.folders.contains(where: {
            $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame
        }) else { throw StoreError.duplicateFolderName }

        let folder = VaultFolderRecord(id: UUID(), name: name, createdAt: Date())
        manifest.folders.append(folder)
        try saveManifest(manifest)
        return folder
    }

    public func renameFolder(id: UUID, to proposedName: String) throws {
        let name = try normalizedFolderName(proposedName)
        var manifest = try loadManifest()
        guard let index = manifest.folders.firstIndex(where: { $0.id == id }) else {
            throw StoreError.folderNotFound
        }
        guard !manifest.folders.contains(where: {
            $0.id != id && $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame
        }) else { throw StoreError.duplicateFolderName }

        manifest.folders[index].name = name
        try saveManifest(manifest)
    }

    /// Deleting a folder returns its content references to the root gallery. It
    /// never deletes content from either protected store.
    public func deleteFolder(id: UUID) throws {
        var manifest = try loadManifest()
        guard manifest.folders.contains(where: { $0.id == id }) else {
            throw StoreError.folderNotFound
        }
        manifest.folders.removeAll { $0.id == id }
        manifest.memberships.removeAll { $0.folderID == id }
        try saveManifest(manifest)
    }

    public func move(_ item: VaultPresentedContentReference, to folderID: UUID?) throws {
        var manifest = try loadManifest()
        if let folderID,
           !manifest.folders.contains(where: { $0.id == folderID }) {
            throw StoreError.folderNotFound
        }
        manifest.memberships.removeAll { $0.item == item }
        if let folderID {
            manifest.memberships.append(VaultFolderMembership(item: item, folderID: folderID))
        }
        try saveManifest(manifest)
    }

    public func folderID(for item: VaultPresentedContentReference) throws -> UUID? {
        try loadManifest().memberships.first(where: { $0.item == item })?.folderID
    }

    /// Stores opaque, locally generated thumbnail bytes. Image decoding and
    /// resizing remain presentation-adapter concerns outside this module.
    public func storeThumbnail(
        _ plaintext: Data,
        for item: VaultPresentedContentReference
    ) throws {
        guard !plaintext.isEmpty,
              plaintext.count <= Self.maximumThumbnailByteCount else {
            throw StoreError.verificationFailed
        }
        var manifest = try loadManifest()
        let previous = manifest.thumbnails.first(where: { $0.item == item })
        let blobName = "\(UUID().uuidString.lowercased()).kht"
        let blobURL = root.appendingPathComponent(blobName, isDirectory: false)
        let ciphertext = try access.seal(plaintext, for: .thumbnail(item))

        do {
            try secureWrite(ciphertext, to: blobURL)
            let reopened = try access.open(
                Data(contentsOf: blobURL, options: [.mappedIfSafe]),
                for: .thumbnail(item)
            )
            guard reopened == plaintext else { throw StoreError.verificationFailed }

            manifest.thumbnails.removeAll { $0.item == item }
            manifest.thumbnails.append(
                VaultPresentationThumbnailRecord(item: item, blobName: blobName)
            )
            try saveManifest(manifest)
            if let previous {
                try? fileManager.removeItem(at: root.appendingPathComponent(previous.blobName))
            }
        } catch {
            try? fileManager.removeItem(at: blobURL)
            throw error
        }
    }

    public func loadThumbnail(for item: VaultPresentedContentReference) throws -> Data? {
        let manifest = try loadManifest()
        guard let record = manifest.thumbnails.first(where: { $0.item == item }) else {
            return nil
        }
        let ciphertext = try Data(
            contentsOf: root.appendingPathComponent(record.blobName),
            options: [.mappedIfSafe]
        )
        return try access.open(ciphertext, for: .thumbnail(item))
    }

    /// Removes references to deleted content without touching either content
    /// store. Orphaned presentation thumbnails are removed only after the new
    /// manifest is durably written.
    public func reconcile(validItems: Set<VaultPresentedContentReference>) throws {
        var manifest = try loadManifest()
        let removedThumbnails = manifest.thumbnails.filter { !validItems.contains($0.item) }
        manifest.memberships.removeAll { !validItems.contains($0.item) }
        manifest.thumbnails.removeAll { !validItems.contains($0.item) }
        try saveManifest(manifest)
        for record in removedThumbnails {
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
                "KeyHollow/FolderPresentationData",
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

    private func normalizedFolderName(_ proposed: String) throws -> String {
        let name = proposed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty,
              name.count <= Self.maximumFolderNameLength,
              name.rangeOfCharacter(from: .controlCharacters) == nil else {
            throw StoreError.invalidFolderName
        }
        return name
    }

    private func validate(_ manifest: VaultFolderPresentationManifest) throws {
        guard manifest.version == VaultFolderPresentationManifest.currentVersion else {
            throw StoreError.invalidManifest
        }
        let folderIDs = Set(manifest.folders.map(\.id))
        guard folderIDs.count == manifest.folders.count,
              Set(manifest.folders.map { $0.name.lowercased() }).count == manifest.folders.count,
              Set(manifest.memberships.map(\.item)).count == manifest.memberships.count,
              manifest.memberships.allSatisfy({ folderIDs.contains($0.folderID) }),
              Set(manifest.thumbnails.map(\.item)).count == manifest.thumbnails.count,
              Set(manifest.thumbnails.map(\.blobName)).count == manifest.thumbnails.count,
              manifest.thumbnails.allSatisfy({ Self.isSafeThumbnailName($0.blobName) }) else {
            throw StoreError.invalidManifest
        }
        for folder in manifest.folders {
            _ = try normalizedFolderName(folder.name)
        }
    }

    private static func isSafeThumbnailName(_ name: String) -> Bool {
        !name.isEmpty
            && name.utf8.count <= 255
            && !name.contains("/")
            && !name.contains("\\")
            && !name.contains("\0")
            && URL(fileURLWithPath: name).lastPathComponent == name
            && URL(fileURLWithPath: name).pathExtension.lowercased() == "kht"
    }

    private func saveManifest(_ manifest: VaultFolderPresentationManifest) throws {
        try validate(manifest)
        try Task.checkCancellation()
        let plaintext = try JSONEncoder().encode(manifest)
        let ciphertext = try access.seal(plaintext, for: .manifest)
        try Task.checkCancellation()
        try secureWrite(ciphertext, to: manifestURL)
    }

    private func secureWrite(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        try Self.protectAndExclude(url, fileManager: fileManager)
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
