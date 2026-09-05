import CryptoKit
import Foundation
import KeyHollowCryptoCore
import KeyHollowGeneralFileSupportAddOn
import KeyHollowTransferCore

/// App-composition adapter between the independently compiled general-file
/// add-on and the generic supplemental-ciphertext seam in TransferCore.
struct GeneralFilePortableTransferBridge: PortableVaultSupplementalContentProviding {
    private let access: (any VaultGeneralFileCryptographicAccess)?

    init(access: (any VaultGeneralFileCryptographicAccess)? = nil) {
        self.access = access
    }

    func authenticatedArchiveInventory(
        vaultID: UUID,
        sourceRootOverride: URL?
    ) async throws -> PortableVaultSupplementalArchiveInventory {
        guard let access, access.vaultID == vaultID else {
            throw VaultGeneralFileStore.StoreError.accessMismatch
        }
        let store = try VaultGeneralFileStore(
            vaultID: vaultID,
            access: access,
            storageRoot: try Self.storageRoot(
                vaultID: vaultID,
                override: sourceRootOverride
            )
        )
        let inventory = try await store.authenticatedArchiveInventory()
        guard !inventory.manifest.files.isEmpty else { return .empty }

        return PortableVaultSupplementalArchiveInventory(
            manifestURL: inventory.manifestURL,
            entries: try inventory.manifest.files.map { record in
                guard let sourceURL = inventory.blobURLsByName[record.blobName] else {
                    throw VaultGeneralFileStore.StoreError.invalidManifest
                }
                return PortableVaultSupplementalArchiveEntry(
                    storageName: record.blobName,
                    sourceURL: sourceURL
                )
            },
            itemCount: inventory.manifest.files.count
        )
    }

    func validateStagedContent(
        at rootURL: URL,
        sourceVaultID: UUID,
        vaultKey: SymmetricKey
    ) async throws -> PortableVaultSupplementalValidation {
        let store = try VaultGeneralFileStore(
            vaultID: sourceVaultID,
            access: PortableGeneralFileAccess(
                vaultID: sourceVaultID,
                vaultKey: vaultKey
            ),
            storageRoot: rootURL
        )
        let manifest = try await store.validateAllEncryptedFiles()
        return PortableVaultSupplementalValidation(
            itemCount: manifest.files.count,
            storageNames: Set(manifest.files.map(\.blobName))
        )
    }

    private static func storageRoot(vaultID: UUID, override: URL?) throws -> URL {
        if let override { return override.standardizedFileURL }
        let appSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return appSupport
            .appendingPathComponent("KeyHollow/GeneralFileData", isDirectory: true)
            .appendingPathComponent(vaultID.uuidString.lowercased(), isDirectory: true)
            .standardizedFileURL
    }
}

private struct PortableGeneralFileAccess: VaultGeneralFileCryptographicAccess {
    let vaultID: UUID
    let vaultKey: SymmetricKey

    func seal(_ plaintext: Data, for purpose: VaultGeneralFileKeyPurpose) throws -> Data {
        try CryptoBox.seal(plaintext, using: derivedKey(for: purpose))
    }

    func open(_ ciphertext: Data, for purpose: VaultGeneralFileKeyPurpose) throws -> Data {
        try CryptoBox.open(ciphertext, using: derivedKey(for: purpose))
    }

    private func derivedKey(for purpose: VaultGeneralFileKeyPurpose) -> SymmetricKey {
        let label = "keyhollow.addon.\(purpose.cryptographicDomain)"
        return HKDF<SHA256>.deriveKey(
            inputKeyMaterial: vaultKey,
            salt: Data(label.utf8),
            info: Data(),
            outputByteCount: 32
        )
    }
}
