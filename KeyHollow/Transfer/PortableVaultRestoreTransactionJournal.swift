import CryptoKit
import Foundation
import KeyHollowCryptoCore
import KeyHollowVaultCore

enum PortableVaultRestoreTransactionError: Error, Equatable {
    case invalidJournal
    case rollbackIncomplete
}

enum PortableVaultRestoreJournalKeySchedule {
    static func key(devicePepper: Data) throws -> SymmetricKey {
        guard devicePepper.count == 32 else {
            throw DevicePepperError.invalidData
        }
        return HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: devicePepper),
            salt: Data("keyhollow.restore-journal.v1".utf8),
            info: Data(),
            outputByteCount: 32
        )
    }
}

struct PortableVaultRestoreTransactionRecord: Codable, Equatable, Sendable {
    static let currentVersion = 1

    let version: Int
    let transactionID: UUID
    let destinationVaultID: UUID
    let credentialLocator: String
    let credentialEnvelopeSHA256: Data

    init(
        transactionID: UUID = UUID(),
        destinationVaultID: UUID,
        credentialLocator: String,
        credentialEnvelopeSHA256: Data
    ) {
        version = Self.currentVersion
        self.transactionID = transactionID
        self.destinationVaultID = destinationVaultID
        self.credentialLocator = credentialLocator
        self.credentialEnvelopeSHA256 = credentialEnvelopeSHA256
    }

    func validate() throws {
        guard version == Self.currentVersion,
              credentialLocator.count == 64,
              credentialLocator.utf8.allSatisfy({ byte in
                  (48...57).contains(byte) || (97...102).contains(byte)
              }),
              credentialEnvelopeSHA256.count == 32 else {
            throw PortableVaultRestoreTransactionError.invalidJournal
        }
    }
}

struct PortableVaultRestoreTransactionJournal {
    private static let fileExtension = "khtxn"

    let journalRoot: URL
    let photoDataRoot: URL

    private let authenticationKey: SymmetricKey
    private let fileManager = FileManager.default

    /// Avoids creating Keychain material or protected directories during an
    /// ordinary launch when no portable restore transaction can exist.
    static func recoveryRequired(journalRootOverride: URL? = nil) throws -> Bool {
        let fileManager = FileManager.default
        let root: URL
        if let journalRootOverride {
            root = journalRootOverride.standardizedFileURL
        } else {
            let appSupport = try fileManager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: false
            )
            root = appSupport
                .appendingPathComponent("KeyHollow/RestoreTransactions", isDirectory: true)
                .standardizedFileURL
        }

        guard fileManager.fileExists(atPath: root.path) else {
            return false
        }
        let values = try root.resourceValues(
            forKeys: [.isDirectoryKey, .isSymbolicLinkKey]
        )
        guard values.isDirectory == true,
              values.isSymbolicLink != true else {
            throw PortableVaultRestoreTransactionError.invalidJournal
        }
        return try !fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: nil,
            options: [.skipsSubdirectoryDescendants]
        ).isEmpty
    }

    init(
        authenticationKey: SymmetricKey,
        journalRootOverride: URL? = nil,
        photoDataRootOverride: URL? = nil
    ) throws {
        self.authenticationKey = authenticationKey

        if let journalRootOverride {
            journalRoot = journalRootOverride.standardizedFileURL
        } else {
            let appSupport = try fileManager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            journalRoot = appSupport
                .appendingPathComponent("KeyHollow/RestoreTransactions", isDirectory: true)
                .standardizedFileURL
        }

        if let photoDataRootOverride {
            photoDataRoot = photoDataRootOverride.standardizedFileURL
        } else {
            let appSupport = try fileManager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            photoDataRoot = appSupport
                .appendingPathComponent("KeyHollow/PhotoData", isDirectory: true)
                .standardizedFileURL
        }

        try Self.prepareProtectedRoot(journalRoot)
        try Self.prepareProtectedRoot(photoDataRoot)
    }

    func begin(
        destinationVaultID: UUID,
        credentialLocator: String,
        credentialEnvelope: VaultEnvelope
    ) throws -> PortableVaultRestoreTransactionRecord {
        let record = PortableVaultRestoreTransactionRecord(
            destinationVaultID: destinationVaultID,
            credentialLocator: credentialLocator,
            credentialEnvelopeSHA256: Self.digest(credentialEnvelope)
        )
        try record.validate()

        let target = url(for: record)
        guard !fileManager.fileExists(atPath: target.path) else {
            throw PortableVaultRestoreTransactionError.invalidJournal
        }
        let encoded = try JSONEncoder().encode(record)
        let sealed = try CryptoBox.seal(encoded, using: authenticationKey)
        try sealed.write(to: target, options: [.atomic, .completeFileProtection])
        try Self.protectAndExclude(target)
        return record
    }

    func finish(_ record: PortableVaultRestoreTransactionRecord) throws {
        try record.validate()
        let target = url(for: record)
        guard fileManager.fileExists(atPath: target.path) else { return }
        try fileManager.removeItem(at: target)
    }

    func recoverAll(
        credentialStore: any PortableVaultCredentialStoring
    ) async throws {
        let urls = try fileManager.contentsOfDirectory(
            at: journalRoot,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
            options: []
        )

        for url in urls {
            guard url.pathExtension == Self.fileExtension else {
                throw PortableVaultRestoreTransactionError.invalidJournal
            }
            let values = try url.resourceValues(
                forKeys: [.isRegularFileKey, .isSymbolicLinkKey]
            )
            guard values.isRegularFile == true,
                  values.isSymbolicLink != true else {
                throw PortableVaultRestoreTransactionError.invalidJournal
            }

            let sealed = try Data(contentsOf: url, options: [.mappedIfSafe])
            let plaintext: Data
            do {
                plaintext = try CryptoBox.open(sealed, using: authenticationKey)
            } catch {
                throw PortableVaultRestoreTransactionError.invalidJournal
            }

            let record: PortableVaultRestoreTransactionRecord
            do {
                record = try JSONDecoder().decode(
                    PortableVaultRestoreTransactionRecord.self,
                    from: plaintext
                )
                try record.validate()
            } catch {
                throw PortableVaultRestoreTransactionError.invalidJournal
            }

            guard url.deletingPathExtension().lastPathComponent
                == record.transactionID.uuidString.lowercased() else {
                throw PortableVaultRestoreTransactionError.invalidJournal
            }

            try await rollback(record, credentialStore: credentialStore)
        }
    }

    func rollback(
        _ record: PortableVaultRestoreTransactionRecord,
        credentialStore: any PortableVaultCredentialStoring
    ) async throws {
        try record.validate()
        let currentEnvelope: VaultEnvelope?
        do {
            currentEnvelope = try await credentialStore.read(
                locator: record.credentialLocator
            )
        } catch {
            throw PortableVaultRestoreTransactionError.rollbackIncomplete
        }
        if let currentEnvelope,
           Self.digest(currentEnvelope) == record.credentialEnvelopeSHA256 {
            try? await credentialStore.delete(locator: record.credentialLocator)
        }

        let destinationURL = photoDataRoot.appendingPathComponent(
            record.destinationVaultID.uuidString.lowercased(),
            isDirectory: true
        )
        if fileManager.fileExists(atPath: destinationURL.path) {
            try? fileManager.removeItem(at: destinationURL)
        }

        let remainingEnvelope: VaultEnvelope?
        do {
            remainingEnvelope = try await credentialStore.read(
                locator: record.credentialLocator
            )
        } catch {
            throw PortableVaultRestoreTransactionError.rollbackIncomplete
        }
        let transactionEnvelopeRemains = remainingEnvelope.map {
            Self.digest($0) == record.credentialEnvelopeSHA256
        } ?? false
        guard !transactionEnvelopeRemains,
              !fileManager.fileExists(atPath: destinationURL.path) else {
            throw PortableVaultRestoreTransactionError.rollbackIncomplete
        }
        try finish(record)
    }

    private func url(for record: PortableVaultRestoreTransactionRecord) -> URL {
        journalRoot
            .appendingPathComponent(
                record.transactionID.uuidString.lowercased(),
                isDirectory: false
            )
            .appendingPathExtension(Self.fileExtension)
    }

    private static func digest(_ envelope: VaultEnvelope) -> Data {
        var version = Int64(envelope.version).littleEndian
        var canonical = Swift.withUnsafeBytes(of: &version) { Data($0) }
        canonical.append(envelope.sealedPayload)
        return Data(SHA256.hash(data: canonical))
    }

    private static func prepareProtectedRoot(_ root: URL) throws {
        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: root.path) {
            try fileManager.createDirectory(
                at: root,
                withIntermediateDirectories: true,
                attributes: [.protectionKey: FileProtectionType.complete]
            )
        }
        let values = try root.resourceValues(
            forKeys: [.isDirectoryKey, .isSymbolicLinkKey]
        )
        guard values.isDirectory == true,
              values.isSymbolicLink != true else {
            throw PortableVaultRestoreTransactionError.invalidJournal
        }
        try protectAndExclude(root)
    }

    private static func protectAndExclude(_ url: URL) throws {
        try FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.complete],
            ofItemAtPath: url.path
        )
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var protectedURL = url
        try protectedURL.setResourceValues(values)
    }
}

