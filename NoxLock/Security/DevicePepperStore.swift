import Foundation
import Security

enum DevicePepperError: Error {
    case keychain(OSStatus)
    case invalidData
}

/// Stores a random device-local secret used as additional KDF input.
/// This secret never unlocks a vault by itself and is not protected by
/// Face ID/Touch ID. `ThisDeviceOnly` prevents migration to another device.
final class DevicePepperStore {
    private let service = "com.noxlock.security"
    private let account = "device-pepper-v1"

    func loadOrCreate() throws -> Data {
        if let existing = try load() { return existing }

        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard status == errSecSuccess else { throw DevicePepperError.keychain(status) }
        let data = Data(bytes)
        try save(data)
        return data
    }

    private func load() throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw DevicePepperError.keychain(status) }
        guard let data = result as? Data, data.count == 32 else { throw DevicePepperError.invalidData }
        return data
    }

    private func save(_ data: Data) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw DevicePepperError.keychain(status) }
    }
}
