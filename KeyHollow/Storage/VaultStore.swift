import Foundation

actor VaultStore {
    private let fileManager = FileManager.default
    private let root: URL

    init(rootOverride: URL? = nil) throws {
        if let rootOverride {
            root = rootOverride.standardizedFileURL
        } else {
            let appSupport = try fileManager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            root = appSupport.appendingPathComponent("KeyHollow/Vaults", isDirectory: true)
        }
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        try Self.removeAbandonedPendingWrites(root, fileManager: fileManager)
        try Self.protectAndExclude(root, fileManager: fileManager)
    }

    func hasAnyVaults() throws -> Bool {
        let contents = try fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        return contents.contains { $0.pathExtension == "khv" }
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
        try Self.protectAndExclude(target, fileManager: fileManager)
    }

    /// Creates a new credential without replacing any file that won a race for
    /// the same opaque locator. Portable restore uses this after its initial
    /// collision check so another vault can never be overwritten.
    func writeIfAbsent(_ envelope: VaultEnvelope, locator: String) throws {
        let target = url(for: locator)
        guard !fileManager.fileExists(atPath: target.path) else {
            throw CocoaError(.fileWriteFileExists)
        }
        let data = try JSONEncoder().encode(envelope)
        let pending = root
            .appendingPathComponent(".pending-\(UUID().uuidString.lowercased())")
            .appendingPathExtension("khvtmp")
        var linkedTarget = false
        defer { try? fileManager.removeItem(at: pending) }

        do {
            // Fully write and protect a hidden same-volume file, then create
            // the public locator with an exclusive hard link. The locator is
            // therefore either absent or a complete envelope, never partial.
            try data.write(to: pending, options: [.atomic, .completeFileProtection])
            try Self.protectAndExclude(pending, fileManager: fileManager)
            try fileManager.linkItem(at: pending, to: target)
            linkedTarget = true
            try Self.protectAndExclude(target, fileManager: fileManager)
        } catch {
            // If protection metadata fails after creation, do not leave a
            // partially committed credential behind.
            if linkedTarget {
                try? fileManager.removeItem(at: target)
            }
            throw error
        }
    }

    func delete(locator: String) throws {
        let target = url(for: locator)
        guard fileManager.fileExists(atPath: target.path) else { return }
        try fileManager.removeItem(at: target)
    }

    private func url(for locator: String) -> URL {
        root.appendingPathComponent(locator).appendingPathExtension("khv")
    }

    private static func removeAbandonedPendingWrites(
        _ root: URL,
        fileManager: FileManager
    ) throws {
        let urls = try fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
            options: [.skipsSubdirectoryDescendants]
        )
        for url in urls where (
            url.lastPathComponent.hasPrefix(".pending-")
                && url.pathExtension == "khvtmp"
        ) {
            let values = try url.resourceValues(
                forKeys: [.isRegularFileKey, .isSymbolicLinkKey]
            )
            guard values.isRegularFile == true,
                  values.isSymbolicLink != true else {
                continue
            }
            try fileManager.removeItem(at: url)
        }
    }

    private static func protectAndExclude(_ url: URL, fileManager: FileManager) throws {
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
