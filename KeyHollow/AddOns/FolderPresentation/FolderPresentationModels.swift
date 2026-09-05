import Foundation

public enum VaultPresentedContentKind: String, Codable, Hashable, Sendable {
    case photo
    case generalFile
}

/// A neutral reference lets the presentation add-on organize content without
/// importing or owning either protected content store.
public struct VaultPresentedContentReference: Codable, Hashable, Sendable {
    public let kind: VaultPresentedContentKind
    public let id: UUID

    public init(kind: VaultPresentedContentKind, id: UUID) {
        self.kind = kind
        self.id = id
    }
}

public struct VaultFolderRecord: Codable, Identifiable, Hashable, Sendable {
    public let id: UUID
    public var name: String
    public let createdAt: Date

    public init(id: UUID, name: String, createdAt: Date) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
    }
}

public struct VaultFolderMembership: Codable, Hashable, Sendable {
    public let item: VaultPresentedContentReference
    public let folderID: UUID

    public init(item: VaultPresentedContentReference, folderID: UUID) {
        self.item = item
        self.folderID = folderID
    }
}

public struct VaultPresentationThumbnailRecord: Codable, Hashable, Sendable {
    public let item: VaultPresentedContentReference
    public let blobName: String

    public init(item: VaultPresentedContentReference, blobName: String) {
        self.item = item
        self.blobName = blobName
    }
}

public struct VaultFolderPresentationManifest: Codable, Equatable, Sendable {
    public static let currentVersion = 1

    public let version: Int
    public var folders: [VaultFolderRecord]
    public var memberships: [VaultFolderMembership]
    public var thumbnails: [VaultPresentationThumbnailRecord]

    public init(
        version: Int,
        folders: [VaultFolderRecord],
        memberships: [VaultFolderMembership],
        thumbnails: [VaultPresentationThumbnailRecord]
    ) {
        self.version = version
        self.folders = folders
        self.memberships = memberships
        self.thumbnails = thumbnails
    }

    public static var empty: VaultFolderPresentationManifest {
        VaultFolderPresentationManifest(
            version: currentVersion,
            folders: [],
            memberships: [],
            thumbnails: []
        )
    }
}

public enum VaultFolderPresentationKeyPurpose: Sendable {
    case manifest
    case thumbnail(VaultPresentedContentReference)

    public var cryptographicDomain: String {
        switch self {
        case .manifest:
            "folder-presentation.manifest.v1"
        case .thumbnail(let item):
            "folder-presentation.thumbnail.v1.\(item.kind.rawValue).\(item.id.uuidString.lowercased())"
        }
    }
}

/// The unlocked app session retains exclusive key ownership and supplies only
/// scoped seal/open operations to this add-on.
public protocol VaultFolderPresentationCryptographicAccess: Sendable {
    var vaultID: UUID { get }

    func seal(
        _ plaintext: Data,
        for purpose: VaultFolderPresentationKeyPurpose
    ) throws -> Data
    func open(
        _ ciphertext: Data,
        for purpose: VaultFolderPresentationKeyPurpose
    ) throws -> Data
}
