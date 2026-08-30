import Foundation
import CryptoKit

struct VaultPhotoRecord: Codable, Identifiable, Hashable {
    let id: UUID
    let importedAt: Date
    let blobName: String
    let thumbnailName: String
}

struct VaultPhotoManifest: Codable {
    static let currentVersion = 1

    let version: Int
    var photos: [VaultPhotoRecord]

    static var empty: VaultPhotoManifest {
        VaultPhotoManifest(version: currentVersion, photos: [])
    }
}

enum VaultPhotoKeySchedule {
    static func manifestKey(from vaultKey: SymmetricKey) -> SymmetricKey {
        derive(from: vaultKey, label: "keyhollow.photos.manifest.v1")
    }

    static func photoKey(from vaultKey: SymmetricKey, id: UUID) -> SymmetricKey {
        derive(from: vaultKey, label: "keyhollow.photos.original.v1.\(id.uuidString.lowercased())")
    }

    static func thumbnailKey(from vaultKey: SymmetricKey, id: UUID) -> SymmetricKey {
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
