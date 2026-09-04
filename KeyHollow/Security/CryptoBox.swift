import Foundation
import CryptoKit

public enum CryptoBoxError: Error {
    case invalidEnvelope
}

/// Authenticated encryption wrapper for vault blobs.
/// Production callers must supply independently generated vault keys.
public enum CryptoBox {
    public static func generateKey() -> SymmetricKey {
        SymmetricKey(size: .bits256)
    }

    public static func seal(_ plaintext: Data, using key: SymmetricKey) throws -> Data {
        let box = try AES.GCM.seal(plaintext, using: key)
        guard let combined = box.combined else { throw CryptoBoxError.invalidEnvelope }
        return combined
    }

    public static func open(_ ciphertext: Data, using key: SymmetricKey) throws -> Data {
        let box = try AES.GCM.SealedBox(combined: ciphertext)
        return try AES.GCM.open(box, using: key)
    }
}
