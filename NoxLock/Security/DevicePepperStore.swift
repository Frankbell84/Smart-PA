import Foundation
import Security

enum DevicePepperError: Error {
    case keychain(OSStatus)
    case invalidData
}

/// Stores device-local cryptographic material.
///
/// Neither secret is an alternate unlock mechanism. No Face ID, Touch ID, or
/// device-passcode access-control flag is attached to these Keychain items.
/// `ThisDeviceOnly` deliberately prevents migration to another device in V1.
final class DevicePepperStore {
    private let service = "com.noxlock.security"
    private let pepperAccount = "device-pepper-v1"
    private let saltAccount = "installation-salt-v1"

    func loadOrCreate() throws -> Data {
        try loadOrCreate(account: pepperAccount, length: 32)
    }

    func loadOrCreateInstallationSalt() throws -> Data {
        try loadOrCreate(account: saltAccount, length: 16)
    }

    private func loadOrCreate(account: String, length: Int) throws -> Data {
        if let existing = try load(account: account) {
            guard existing.count == length else { throw DevicePepperError.invalidData }
            return existing
        }

        var bytes = [UInt8](repeating: 0, count: length)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard status == errSecSuccess else { throw DevicePepperError.keychain(status) }
        let data = Data(bytes)
        try save(data, account: account)
        return data
    }

    private func load(account: String) throws -> Data? {
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
        guard let data = result as? Data else { throw DevicePepperError.invalidData }
        return data
    }

    private func save(_ data: Data, account: String) throws {
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
