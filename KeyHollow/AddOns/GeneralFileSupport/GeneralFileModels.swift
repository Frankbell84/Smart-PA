import Foundation

/// A short-lived, security-scoped selection owned by the add-on while the user
/// reviews an import. Discarding a candidate releases access without changing
/// the encrypted vault.
public final class VaultGeneralFileImportCandidate: Identifiable, @unchecked Sendable {
    public let id = UUID()
    public let displayName: String
    public let originalByteCount: UInt64?
    public let contentTypeIdentifier: String?

    let sourceURL: URL
    private let accessLock = NSLock()
    private var hasSecurityScopedAccess: Bool

    public init(sourceURL: URL) {
        self.sourceURL = sourceURL
        displayName = sourceURL.lastPathComponent.isEmpty
            ? "Selected File"
            : sourceURL.lastPathComponent
        hasSecurityScopedAccess = sourceURL.startAccessingSecurityScopedResource()
        let values = try? sourceURL.resourceValues(forKeys: [.fileSizeKey, .typeIdentifierKey])
        originalByteCount = values?.fileSize.flatMap { size in
            size >= 0 ? UInt64(size) : nil
        }
        contentTypeIdentifier = values?.typeIdentifier
    }

    public func discard() {
        accessLock.lock()
        let shouldStop = hasSecurityScopedAccess
        hasSecurityScopedAccess = false
        accessLock.unlock()

        if shouldStop {
            sourceURL.stopAccessingSecurityScopedResource()
        }
    }

    deinit {
        discard()
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
