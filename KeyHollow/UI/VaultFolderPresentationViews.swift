import SwiftUI
import KeyHollowFolderPresentationAddOn

struct VaultFolderTileView: View {
    let folder: VaultFolderRecord
    let itemCount: Int
    let isEnabled: Bool
    let open: () -> Void
    let rename: () -> Void
    let delete: () -> Void

    private var itemDescription: String {
        "\(itemCount) \(itemCount == 1 ? "item" : "items")"
    }

    var body: some View {
        Button(action: open) {
            GeometryReader { proxy in
                VStack(spacing: 0) {
                    Image(systemName: "folder.fill")
                        .font(.system(size: 46, weight: .regular))
                        .foregroundStyle(.tint)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(folder.name)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                        Text(itemDescription)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(.ultraThinMaterial)
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
                .background(.secondary.opacity(0.12))
            }
            .aspectRatio(1, contentMode: .fit)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.45)
        .accessibilityLabel(folder.name)
        .accessibilityValue(itemDescription)
        .accessibilityHint("Opens this vault folder")
        .contextMenu {
            Button(action: rename) {
                Label("Rename Folder", systemImage: "pencil")
            }
            Button(role: .destructive, action: delete) {
                Label("Delete Folder", systemImage: "trash")
            }
        }
    }
}

