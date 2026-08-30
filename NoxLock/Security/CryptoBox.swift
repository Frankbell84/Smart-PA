import Foundation
import CryptoKit

enum CryptoBoxError: Error {
    case invalidEnvelope
}

/// Authenticated encryption wrapper for vault blobs.
/// Production callers must supply independently generated vault keys.
enum CryptoBox {
    static func generateKey() -> SymmetricKey {
        SymmetricKey(size: .bits256)
    }

    static func seal(_ plaintext: Data, using key: SymmetricKey) throws -> Data {
        let box = try AES.GCM.seal(plaintext, using: key)
        guard let combined = box.combined else { throw CryptoBoxError.invalidEnvelope }
        return combined
    }

    static func open(_ ciphertext: Data, using key: SymmetricKey) throws -> Data {
        let box = try AES.GCM.SealedBox(combined: ciphertext)
        return try AES.GCM.open(box, using: key)
    }
}
