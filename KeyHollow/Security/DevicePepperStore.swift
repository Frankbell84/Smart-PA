import Foundation
import Security

enum DevicePepperError: Error {
    case keychain(OSStatus)
    case invalidData
}

protocol DeviceSecretProviding: Sendable {
    func loadOrCreate() throws -> Data
    func loadOrCreateInstallationSalt() throws -> Data
}

/// Stores random device-local secrets used as additional KDF input.
/// These secrets never unlock a vault by themselves and are not protected by
/// Face ID/Touch ID. `ThisDeviceOnly` prevents migration to another device.
final class DevicePepperStore: DeviceSecretProviding, @unchecked Sendable {
    private let service = "com.keyhollow.security"
    private let pepperAccount = "device-pepper-v1"
    private let installationSaltAccount = "installation-salt-v1"

    func loadOrCreate() throws -> Data {
        try loadOrCreate(account: pepperAccount, byteCount: 32)
    }

    func loadOrCreateInstallationSalt() throws -> Data {
        try loadOrCreate(account: installationSaltAccount, byteCount: 16)
    }

    private func loadOrCreate(account: String, byteCount: Int) throws -> Data {
        if let existing = try load(account: account) {
            guard existing.count == byteCount else { throw DevicePepperError.invalidData }
            return existing
        }

        var bytes = [UInt8](repeating: 0, count: byteCount)
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
