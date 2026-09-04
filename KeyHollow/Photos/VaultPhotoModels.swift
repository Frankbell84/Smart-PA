import Foundation
import CryptoKit

public struct VaultPhotoRecord: Codable, Identifiable, Hashable, Sendable {
    public let id: UUID
    public let importedAt: Date
    public let blobName: String
    public let thumbnailName: String

    public init(id: UUID, importedAt: Date, blobName: String, thumbnailName: String) {
        self.id = id
        self.importedAt = importedAt
        self.blobName = blobName
        self.thumbnailName = thumbnailName
    }
}

public struct VaultPhotoManifest: Codable, Sendable {
    public static let currentVersion = 1

    public let version: Int
    public var photos: [VaultPhotoRecord]

    public init(version: Int, photos: [VaultPhotoRecord]) {
        self.version = version
        self.photos = photos
    }

    public static var empty: VaultPhotoManifest {
        VaultPhotoManifest(version: currentVersion, photos: [])
    }
}

public enum VaultPhotoKeySchedule {
    public static func manifestKey(from vaultKey: SymmetricKey) -> SymmetricKey {
        derive(from: vaultKey, label: "keyhollow.photos.manifest.v1")
    }

    public static func photoKey(from vaultKey: SymmetricKey, id: UUID) -> SymmetricKey {
        derive(from: vaultKey, label: "keyhollow.photos.original.v1.\(id.uuidString.lowercased())")
    }

    public static func thumbnailKey(from vaultKey: SymmetricKey, id: UUID) -> SymmetricKey {
        derive(from: vaultKey, label: "keyhollow.photos.thumbnail.v1.\(id.uuidString.lowercased())")
    }

    private static func derive(from vaultKey: SymmetricKey, label: String) -> SymmetricKey {
        HKDF<SHA256>.deriveKey(
            inputKeyMaterial: vaultKey,
            salt: Data(label.utf8),
            info: Data(),
            outputByteCount: 32
        )
    }
}
