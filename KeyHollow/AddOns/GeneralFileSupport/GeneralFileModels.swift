import Foundation

public struct VaultGeneralFileImportResult: Equatable, Sendable {
    public let importedCount: Int
    public let failedCount: Int

    public init(importedCount: Int, failedCount: Int) {
        self.importedCount = importedCount
        self.failedCount = failedCount
    }
}

public struct VaultGeneralFileRecord: Codable, Identifiable, Hashable, Sendable {
    public let id: UUID
    public let importedAt: Date
    public let displayName: String
    public let contentTypeIdentifier: String?
    public let originalByteCount: UInt64
    public let blobName: String

    public init(
        id: UUID,
        importedAt: Date,
        displayName: String,
        contentTypeIdentifier: String?,
        originalByteCount: UInt64,
        blobName: String
    ) {
        self.id = id
        self.importedAt = importedAt
        self.displayName = displayName
        self.contentTypeIdentifier = contentTypeIdentifier
        self.originalByteCount = originalByteCount
        self.blobName = blobName
    }
}

public struct VaultGeneralFileManifest: Codable, Sendable {
    public static let currentVersion = 1

    public let version: Int
    public var files: [VaultGeneralFileRecord]

    public init(version: Int, files: [VaultGeneralFileRecord]) {
        self.version = version
        self.files = files
    }

    public static var empty: VaultGeneralFileManifest {
        VaultGeneralFileManifest(version: currentVersion, files: [])
    }
}

public enum VaultGeneralFileKeyPurpose: Sendable {
    case manifest
    case file(UUID)
}

/// The add-on can authenticate encrypted data while the unlocked session keeps
/// exclusive ownership of the vault key and revocation lifecycle.
public protocol VaultGeneralFileCryptographicAccess: Sendable {
    var vaultID: UUID { get }

    func seal(_ plaintext: Data, for purpose: VaultGeneralFileKeyPurpose) throws -> Data
    func open(_ ciphertext: Data, for purpose: VaultGeneralFileKeyPurpose) throws -> Data
}

public struct PreparedGeneralFileExport: Identifiable, Sendable {
    public let id: UUID
    public let urls: [URL]
    let rootURL: URL

    init(id: UUID, urls: [URL], rootURL: URL) {
        self.id = id
        self.urls = urls
        self.rootURL = rootURL
    }
}
