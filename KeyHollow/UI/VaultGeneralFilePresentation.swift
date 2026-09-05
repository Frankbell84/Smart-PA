import Foundation
import SwiftUI
import UniformTypeIdentifiers
import KeyHollowGeneralFileSupportAddOn

final class SessionGeneralFileAccess: VaultGeneralFileCryptographicAccess,
    @unchecked Sendable {
    let vaultID: UUID
    private let capability: VaultAccessCapability

    init(capability: VaultAccessCapability) {
        vaultID = capability.vaultID
        self.capability = capability
    }

    func seal(_ plaintext: Data, for purpose: VaultGeneralFileKeyPurpose) throws -> Data {
        try capability.sealScopedData(plaintext, domain: domain(for: purpose))
    }

    func open(_ ciphertext: Data, for purpose: VaultGeneralFileKeyPurpose) throws -> Data {
        try capability.openScopedData(ciphertext, domain: domain(for: purpose))
    }

    private func domain(for purpose: VaultGeneralFileKeyPurpose) -> String {
        switch purpose {
        case .manifest:
            "general-files.manifest.v1"
        case .file(let id):
            "general-files.blob.v1.\(id.uuidString.lowercased())"
        }
    }
}

enum VaultContentAvailability {
    static func isEmpty(photoCount: Int, generalFileCount: Int) -> Bool {
        photoCount == 0 && generalFileCount == 0
    }
}

enum GeneralFilePresentation {
    static func iconName(for identifier: String?) -> String {
        guard let identifier,
              let type = UTType(identifier) else { return "doc" }
        if type.conforms(to: .pdf) { return "doc.richtext" }
        if type.conforms(to: .audio) { return "waveform" }
        if type.conforms(to: .archive) { return "archivebox" }
        if type.conforms(to: .image) { return "photo" }
        if type.conforms(to: .text) { return "doc.text" }
        return "doc"
    }
}

struct VaultGeneralFileTileView: View {
    let record: VaultGeneralFileRecord
    let isEnabled: Bool
    let openFileManager: () -> Void

    private var formattedSize: String {
        ByteCountFormatter.string(
            fromByteCount: Int64(record.originalByteCount),
            countStyle: .file
        )
    }

    var body: some View {
        Button { openFileManager() } label: {
            GeometryReader { proxy in
                ZStack(alignment: .bottomLeading) {
                    Rectangle()
                        .fill(.secondary.opacity(0.12))

                    VStack(spacing: 0) {
                        Image(systemName: GeneralFilePresentation.iconName(
                            for: record.contentTypeIdentifier
                        ))
                        .font(.system(size: 38, weight: .regular))
                        .foregroundStyle(.tint)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(record.displayName)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.primary)
                                .lineLimit(2)
                            Text(formattedSize)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                        .background(.ultraThinMaterial)
                    }
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
            }
            .aspectRatio(1, contentMode: .fit)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.45)
        .accessibilityLabel(record.displayName)
        .accessibilityValue("Encrypted file, \(formattedSize)")
        .accessibilityHint(
            isEnabled
                ? "Opens encrypted vault files"
                : "Exit photo selection mode to manage this file"
        )
    }
}
