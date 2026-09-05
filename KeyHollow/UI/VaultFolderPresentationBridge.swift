import Foundation
import KeyHollowFolderPresentationAddOn

final class SessionFolderPresentationAccess: VaultFolderPresentationCryptographicAccess,
    @unchecked Sendable {
    let vaultID: UUID
    private let capability: VaultAccessCapability

    init(capability: VaultAccessCapability) {
        vaultID = capability.vaultID
        self.capability = capability
    }

    func seal(
        _ plaintext: Data,
        for purpose: VaultFolderPresentationKeyPurpose
    ) throws -> Data {
        try capability.sealScopedData(plaintext, domain: purpose.cryptographicDomain)
    }

    func open(
        _ ciphertext: Data,
        for purpose: VaultFolderPresentationKeyPurpose
    ) throws -> Data {
        try capability.openScopedData(ciphertext, domain: purpose.cryptographicDomain)
    }
}
