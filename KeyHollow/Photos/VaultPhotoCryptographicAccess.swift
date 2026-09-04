import CryptoKit
import Foundation
import KeyHollowCryptoCore

public enum VaultKeyPurpose {
    case manifest
    case photo(UUID)
    case thumbnail(UUID)
}

/// The encrypted photo store receives only the operations it needs. Session
/// ownership and revocation remain in the app layer behind this interface.
public protocol VaultPhotoCryptographicAccess: Sendable {
    var vaultID: UUID { get }

    func seal(_ plaintext: Data, for purpose: VaultKeyPurpose) throws -> Data
    func open(_ ciphertext: Data, for purpose: VaultKeyPurpose) throws -> Data
}

final class DirectVaultPhotoAccess: VaultPhotoCryptographicAccess, @unchecked Sendable {
    let vaultID: UUID
    private let vaultKey: SymmetricKey

    init(vaultID: UUID, vaultKey: SymmetricKey) {
        self.vaultID = vaultID
        self.vaultKey = vaultKey
    }

    func seal(_ plaintext: Data, for purpose: VaultKeyPurpose) throws -> Data {
        try CryptoBox.seal(plaintext, using: derivedKey(for: purpose))
    }

    func open(_ ciphertext: Data, for purpose: VaultKeyPurpose) throws -> Data {
        try CryptoBox.open(ciphertext, using: derivedKey(for: purpose))
    }

    private func derivedKey(for purpose: VaultKeyPurpose) -> SymmetricKey {
        switch purpose {
        case .manifest:
            VaultPhotoKeySchedule.manifestKey(from: vaultKey)
        case .photo(let id):
            VaultPhotoKeySchedule.photoKey(from: vaultKey, id: id)
        case .thumbnail(let id):
            VaultPhotoKeySchedule.thumbnailKey(from: vaultKey, id: id)
        }
    }
}
