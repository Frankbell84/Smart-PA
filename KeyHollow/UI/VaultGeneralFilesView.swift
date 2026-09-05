import SwiftUI
import UIKit
import KeyHollowGeneralFileSupportAddOn

struct VaultGeneralFilesView: View {
    @EnvironmentObject private var session: VaultSession
    @Environment(\.dismiss) private var dismiss

    @State private var store: VaultGeneralFileStore?
    @State private var records: [VaultGeneralFileRecord] = []
    @State private var selectedIDs: Set<UUID> = []
    @State private var isSelecting = false
    @State private var isImporting = false
    @State private var isWorking = false
    @State private var export: PreparedGeneralFileExport?
    @State private var message: String?
    @State private var showingDeleteConfirmation = false

    var body: some View {
        NavigationStack {
            Group {
                if records.isEmpty && !isWorking {
                    ContentUnavailableView(
                        "No Vault Files",
                        systemImage: "doc.badge.plus",
                        description: Text(
                            "Import documents, PDFs, audio, and other files as encrypted local copies."
                        )
                    )
                } else {
                    List(records, selection: $selectedIDs) { record in
                        fileRow(record)
                            .tag(record.id)
                            .contextMenu {
                                Button {
                                    selectedIDs = [record.id]
                                    exportSelected()
                                } label: {
                                    Label("Export to Files", systemImage: "square.and.arrow.up")
                                }

                                Button("Delete from Vault", role: .destructive) {
                                    selectedIDs = [record.id]
                                    showingDeleteConfirmation = true
                                }
                            }
                    }
                    .environment(\.editMode, .constant(isSelecting ? .active : .inactive))
                }
            }
            .overlay {
                if isWorking {
                    ProgressView()
                        .padding()
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(isSelecting ? "Cancel" : "Done") {
                        if isSelecting {
                            leaveSelectionMode()
                        } else {
                            dismiss()
                        }
                    }
                    .disabled(isWorking)
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if !isSelecting {
                        Button("Select") { isSelecting = true }
                            .disabled(records.isEmpty || isWorking)
                        Button {
                            session.beginSystemInteraction()
                            isImporting = true
                        } label: {
                            Image(systemName: "plus")
                        }
                        .disabled(isWorking)
                        .accessibilityLabel("Import files")
                    }
                }
                if isSelecting {
                    ToolbarItemGroup(placement: .bottomBar) {
                        Button {
                            exportSelected()
                        } label: {
                            Label("Export", systemImage: "square.and.arrow.up")
                        }
                        .disabled(selectedIDs.isEmpty || isWorking)

                        Spacer()

                        Button(role: .destructive) {
                            showingDeleteConfirmation = true
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        .disabled(selectedIDs.isEmpty || isWorking)
                    }
                }
            }
        }
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [.data],
            allowsMultipleSelection: true
        ) { result in
            session.endSystemInteraction()
            importSelectedFiles(result)
        }
        .sheet(item: $export) { prepared in
            GeneralFileShareSheet(urls: prepared.urls) {
                finishExport(prepared)
            }
        }
        .confirmationDialog(
            "Delete Selected Files?",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button(deleteButtonTitle, role: .destructive) { deleteSelected() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "This permanently removes the selected encrypted copies from this vault. Original files outside KeyHollow are not affected."
            )
        }
        .alert("KeyHollow", isPresented: Binding(
            get: { message != nil },
            set: { if !$0 { message = nil } }
        )) {
            Button("OK") { message = nil }
        } message: {
            Text(message ?? "")
        }
        .task(id: session.activeVaultID) {
            await initializeStore()
        }
    }

    private var navigationTitle: String {
        return isSelecting ? "\(selectedIDs.count) Selected" : "Vault Files"
    }

    private func fileRow(_ record: VaultGeneralFileRecord) -> some View {
        HStack(spacing: 14) {
            Image(systemName: GeneralFilePresentation.iconName(for: record.contentTypeIdentifier))
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 4) {
                Text(record.displayName)
                    .lineLimit(2)
                Text(ByteCountFormatter.string(fromByteCount: Int64(record.originalByteCount), countStyle: .file))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func initializeStore() async {
        guard store == nil,
              let context = session.activeVaultContext() else { return }
        do {
            let access = SessionGeneralFileAccess(capability: context.access)
            let created = try VaultGeneralFileStore(vaultID: context.id, access: access)
            store = created
            records = try await created.loadManifest().files
        } catch {
            message = "The encrypted file store could not be opened."
        }
    }

    private func importSelectedFiles(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result else {
            return
        }
        guard !urls.isEmpty else { return }
        guard urls.count <= VaultGeneralFileStore.maximumBatchCount else {
            message = "Choose no more than \(VaultGeneralFileStore.maximumBatchCount) files at a time."
            return
        }
        guard let store, !isWorking else { return }
        isWorking = true

        session.startSensitiveTask { _ in
            defer { isWorking = false }
            do {
                let outcome = try await store.importFiles(at: urls)
                guard !Task.isCancelled else { return }
                records = try await store.loadManifest().files
                message = GeneralFileImportPresentation.message(for: outcome)
            } catch is CancellationError {
                return
            } catch {
                message = "The selected files could not be imported into this vault."
            }
        }
    }

    private var selectedRecords: [VaultGeneralFileRecord] {
        records.filter { selectedIDs.contains($0.id) }
    }

    private var deleteButtonTitle: String {
        let noun = selectedIDs.count == 1 ? "File" : "Files"
        return "Delete \(selectedIDs.count) \(noun) from Vault"
    }

    private func exportSelected() {
        let selection = selectedRecords
        guard let store, !selection.isEmpty, !isWorking else { return }
        isWorking = true
        session.startSensitiveTask { _ in
            defer { isWorking = false }
            do {
                let prepared = try await store.prepareExport(selection)
                guard !Task.isCancelled else {
                    await store.discardExport(prepared)
                    return
                }
                session.beginSystemInteraction()
                export = prepared
            } catch is CancellationError {
                return
            } catch {
                message = "The selected files could not be authenticated and exported."
            }
        }
    }

    private func finishExport(_ prepared: PreparedGeneralFileExport) {
        export = nil
        session.endSystemInteraction()
        guard let store else { return }
        Task { await store.discardExport(prepared) }
    }

    private func deleteSelected() {
        let selection = selectedRecords
        guard let store, !selection.isEmpty, !isWorking else { return }
        isWorking = true
        session.startSensitiveTask { _ in
            defer { isWorking = false }
            do {
                try await store.delete(selection)
                records = try await store.loadManifest().files
                leaveSelectionMode()
                let noun = selection.count == 1 ? "file" : "files"
                message = "Deleted \(selection.count) \(noun) from this vault."
            } catch is CancellationError {
                return
            } catch {
                message = "The selected files could not be deleted from the vault."
            }
        }
    }

    private func leaveSelectionMode() {
        isSelecting = false
        selectedIDs.removeAll()
    }
}

private struct GeneralFileShareSheet: UIViewControllerRepresentable {
    let urls: [URL]
    let onComplete: () -> Void

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: urls, applicationActivities: nil)
        controller.completionWithItemsHandler = { _, _, _, _ in
            DispatchQueue.main.async { onComplete() }
        }
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
