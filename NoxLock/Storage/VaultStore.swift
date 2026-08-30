import Foundation

actor VaultStore {
    private let fileManager = FileManager.default
    private let root: URL

    init() throws {
        let appSupport = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        root = appSupport.appendingPathComponent("NoxLock/Vaults", isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        try protectAndExclude(root)
    }

    func contains(locator: String) -> Bool {
        fileManager.fileExists(atPath: url(for: locator).path)
    }

    func read(locator: String) throws -> VaultEnvelope? {
        let target = url(for: locator)
        guard fileManager.fileExists(atPath: target.path) else { return nil }
        let data = try Data(contentsOf: target, options: [.mappedIfSafe])
        return try JSONDecoder().decode(VaultEnvelope.self, from: data)
    }

    func write(_ envelope: VaultEnvelope, locator: String) throws {
        let target = url(for: locator)
        let data = try JSONEncoder().encode(envelope)
        try data.write(to: target, options: [.atomic, .completeFileProtection])
        try protectAndExclude(target)
    }

    private func url(for locator: String) -> URL {
        root.appendingPathComponent(locator).appendingPathExtension("nox")
    }

    private func protectAndExclude(_ url: URL) throws {
        try fileManager.setAttributes(
            [.protectionKey: FileProtectionType.complete],
            ofItemAtPath: url.path
        )
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutableURL = url
        try mutableURL.setResourceValues(values)
    }
}
