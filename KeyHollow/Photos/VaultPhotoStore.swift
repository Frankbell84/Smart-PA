import Foundation
import CryptoKit

actor VaultPhotoStore {
    enum StoreError: Error {
        case invalidManifest
        case verificationFailed
    }

    private let fileManager = FileManager.default
    private let root: URL
    private let vaultID: UUID
    private let vaultKey: SymmetricKey

    init(vaultID: UUID, vaultKey: SymmetricKey, storageRoot: URL? = nil) throws {
        self.vaultID = vaultID
        self.vaultKey = vaultKey

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
                .appendingPathComponent("KeyHollow/PhotoData", isDirectory: true)
                .appendingPathComponent(vaultID.uuidString.lowercased(), isDirectory: true)
        }

        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        try Self.protectAndExclude(root, fileManager: fileManager)
    }

    func loadManifest() throws -> VaultPhotoManifest {
        let target = manifestURL
        guard fileManager.fileExists(atPath: target.path) else { return .empty }

        let ciphertext = try Data(contentsOf: target, options: [.mappedIfSafe])
        let plaintext = try CryptoBox.open(
            ciphertext,
            using: VaultPhotoKeySchedule.manifestKey(from: vaultKey)
        )

        let manifest = try JSONDecoder().decode(VaultPhotoManifest.self, from: plaintext)
        guard manifest.version == VaultPhotoManifest.currentVersion else {
            throw StoreError.invalidManifest
        }
        return manifest
    }

    func importPhoto(originalData: Data, thumbnailData: Data) throws -> VaultPhotoRecord {
        let id = UUID()
        let blobName = randomName(extension: "khp")
        let thumbnailName = randomName(extension: "kht")
        let record = VaultPhotoRecord(
            id: id,
            importedAt: Date(),
            blobName: blobName,
            thumbnailName: thumbnailName
        )

        let originalCiphertext = try CryptoBox.seal(
            originalData,
            using: VaultPhotoKeySchedule.photoKey(from: vaultKey, id: id)
        )
        let thumbnailCiphertext = try CryptoBox.seal(
            thumbnailData,
            using: VaultPhotoKeySchedule.thumbnailKey(from: vaultKey, id: id)
        )

        let originalURL = root.appendingPathComponent(blobName)
        let thumbnailURL = root.appendingPathComponent(thumbnailName)

        do {
            try secureWrite(originalCiphertext, to: originalURL)
            try secureWrite(thumbnailCiphertext, to: thumbnailURL)

            let verifiedOriginal = try CryptoBox.open(
                Data(contentsOf: originalURL),
                using: VaultPhotoKeySchedule.photoKey(from: vaultKey, id: id)
            )
            let verifiedThumbnail = try CryptoBox.open(
                Data(contentsOf: thumbnailURL),
                using: VaultPhotoKeySchedule.thumbnailKey(from: vaultKey, id: id)
            )

            guard verifiedOriginal == originalData,
                  verifiedThumbnail == thumbnailData else {
                throw StoreError.verificationFailed
            }

            var manifest = try loadManifest()
            manifest.photos.insert(record, at: 0)
            try saveManifest(manifest)
            return record
        } catch {
            try? fileManager.removeItem(at: originalURL)
            try? fileManager.removeItem(at: thumbnailURL)
            throw error
        }
    }

    func loadPhoto(_ record: VaultPhotoRecord) throws -> Data {
        let ciphertext = try Data(contentsOf: root.appendingPathComponent(record.blobName))
        return try CryptoBox.open(
            ciphertext,
            using: VaultPhotoKeySchedule.photoKey(from: vaultKey, id: record.id)
        )
    }

    func loadThumbnail(_ record: VaultPhotoRecord) throws -> Data {
        let ciphertext = try Data(contentsOf: root.appendingPathComponent(record.thumbnailName))
        return try CryptoBox.open(
            ciphertext,
            using: VaultPhotoKeySchedule.thumbnailKey(from: vaultKey, id: record.id)
        )
    }

    func delete(_ record: VaultPhotoRecord) throws {
        try delete([record])
    }

    func delete(_ records: [VaultPhotoRecord]) throws {
        guard !records.isEmpty else { return }

        let recordIDs = Set(records.map(\.id))
        var manifest = try loadManifest()
        manifest.photos.removeAll { recordIDs.contains($0.id) }

        try saveManifest(manifest)

        for record in records {
            try? fileManager.removeItem(at: root.appendingPathComponent(record.blobName))
            try? fileManager.removeItem(at: root.appendingPathComponent(record.thumbnailName))
        }
    }

    static func destroyVaultData(vaultID: UUID, storageRoot: URL? = nil) throws {
        let fileManager = FileManager.default
        let photoDataRoot: URL
        if let storageRoot {
            photoDataRoot = storageRoot
        } else {
            let appSupport = try fileManager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            photoDataRoot = appSupport
                .appendingPathComponent("KeyHollow/PhotoData", isDirectory: true)
        }
        let target = photoDataRoot
            .appendingPathComponent(vaultID.uuidString.lowercased(), isDirectory: true)

        guard fileManager.fileExists(atPath: target.path) else { return }
        try fileManager.removeItem(at: target)
    }

    private var manifestURL: URL {
        root.appendingPathComponent("manifest.khm")
    }

    private func saveManifest(_ manifest: VaultPhotoManifest) throws {
        let plaintext = try JSONEncoder().encode(manifest)
        let ciphertext = try CryptoBox.seal(
            plaintext,
            using: VaultPhotoKeySchedule.manifestKey(from: vaultKey)
        )
        try secureWrite(ciphertext, to: manifestURL)
    }

    private func secureWrite(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        try Self.protectAndExclude(url, fileManager: fileManager)
    }

    private func randomName(extension fileExtension: String) -> String {
        "\(UUID().uuidString.lowercased()).\(fileExtension)"
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

