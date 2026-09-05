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

struct VaultGeneralFileSummaryView: View {
    let records: [VaultGeneralFileRecord]
    let openFileManager: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Files")
                    .font(.headline)
                Spacer()
                Button("Manage") { openFileManager() }
            }
            .padding(.horizontal)
            .padding(.vertical, 12)

            ForEach(records) { record in
                Button { openFileManager() } label: {
                    HStack(spacing: 14) {
                        Image(systemName: GeneralFilePresentation.iconName(
                            for: record.contentTypeIdentifier
                        ))
                        .font(.title2)
                        .foregroundStyle(.tint)
                        .frame(width: 32)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(record.displayName)
                                .foregroundStyle(.primary)
                                .lineLimit(2)
                            Text(ByteCountFormatter.string(
                                fromByteCount: Int64(record.originalByteCount),
                                countStyle: .file
                            ))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 12)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens encrypted vault files")

                if record.id != records.last?.id {
                    Divider().padding(.leading, 62)
                }
            }
        }
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .padding()
    }
}
