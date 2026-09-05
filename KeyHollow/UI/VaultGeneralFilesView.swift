import SwiftUI
import UIKit
import UniformTypeIdentifiers
import KeyHollowGeneralFileSupportAddOn

private final class SessionGeneralFileAccess: VaultGeneralFileCryptographicAccess,
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

struct VaultGeneralFilesView: View {
    @EnvironmentObject private var session: VaultSession
    @Environment(\.dismiss) private var dismiss

    let beginImportOnAppear: Bool

    @State private var store: VaultGeneralFileStore?
    @State private var records: [VaultGeneralFileRecord] = []
    @State private var pendingImports: [VaultGeneralFileImportCandidate] = []
    @State private var selectedIDs: Set<UUID> = []
    @State private var isSelecting = false
    @State private var isImporting = false
    @State private var isWorking = false
    @State private var export: PreparedGeneralFileExport?
    @State private var message: String?
    @State private var showingDeleteConfirmation = false
    @State private var didBeginInitialImport = false

    init(beginImportOnAppear: Bool = false) {
        self.beginImportOnAppear = beginImportOnAppear
    }

    var body: some View {
        NavigationStack {
            Group {
                if !pendingImports.isEmpty {
                    importReview
                } else if records.isEmpty && !isWorking {
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
                    Button(isSelecting || isReviewingImport ? "Cancel" : "Done") {
                        if isReviewingImport {
                            cancelPendingImport()
                        } else if isSelecting {
                            leaveSelectionMode()
                        } else {
                            dismiss()
                        }
                    }
                    .disabled(isWorking)
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if !isSelecting && !isReviewingImport {
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
                if isSelecting && !isReviewingImport {
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
            prepareImportReview(result)
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
            await beginInitialImportIfNeeded()
        }
        .onDisappear {
            if !isWorking {
                cancelPendingImport()
            }
        }
    }

    private var isReviewingImport: Bool { !pendingImports.isEmpty }

    private var navigationTitle: String {
        if isReviewingImport { return "Review Import" }
        return isSelecting ? "\(selectedIDs.count) Selected" : "Vault Files"
    }

    private var importButtonTitle: String {
        let noun = pendingImports.count == 1 ? "File" : "Files"
        return "Import \(pendingImports.count) \(noun) into Vault"
    }

    private var importReview: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Review selected files")
                    .font(.headline)
                Text("Nothing has been added yet. Confirm the selection below to encrypt these files into this vault.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()

            List {
                ForEach(pendingImports) { pending in
                    pendingFileRow(pending)
                        .deleteDisabled(isWorking)
                }
                .onDelete(perform: removePendingImports)
            }
            .listStyle(.insetGrouped)

            Button {
                importPendingFiles()
            } label: {
                Text(importButtonTitle)
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(isWorking)
            .padding()
            .accessibilityIdentifier("general-file-import-confirm")
        }
        .accessibilityIdentifier("general-file-import-review")
    }

    private func fileRow(_ record: VaultGeneralFileRecord) -> some View {
        HStack(spacing: 14) {
            Image(systemName: iconName(for: record.contentTypeIdentifier))
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

    private func pendingFileRow(_ pending: VaultGeneralFileImportCandidate) -> some View {
        HStack(spacing: 14) {
            Image(systemName: iconName(for: pending.contentTypeIdentifier))
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 4) {
                Text(pending.displayName)
                    .lineLimit(2)
                if let byteCount = pending.originalByteCount {
                    Text(ByteCountFormatter.string(fromByteCount: Int64(byteCount), countStyle: .file))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func iconName(for identifier: String?) -> String {
        guard let identifier,
              let type = UTType(identifier) else { return "doc" }
        if type.conforms(to: .pdf) { return "doc.richtext" }
        if type.conforms(to: .audio) { return "waveform" }
        if type.conforms(to: .archive) { return "archivebox" }
        if type.conforms(to: .image) { return "photo" }
        if type.conforms(to: .text) { return "doc.text" }
        return "doc"
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

    @MainActor
    private func beginInitialImportIfNeeded() async {
        guard beginImportOnAppear,
              !didBeginInitialImport,
              store != nil else { return }
        didBeginInitialImport = true
        await Task.yield()
        session.beginSystemInteraction()
        isImporting = true
    }

    private func prepareImportReview(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result else { return }
        guard !urls.isEmpty else { return }
        guard urls.count <= VaultGeneralFileStore.maximumBatchCount else {
            message = "Choose no more than \(VaultGeneralFileStore.maximumBatchCount) files at a time."
            return
        }
        guard store != nil, !isWorking else { return }
        cancelPendingImport()
        pendingImports = urls.map(VaultGeneralFileImportCandidate.init(sourceURL:))
    }

    private func importPendingFiles() {
        let selection = pendingImports
        guard let store, !selection.isEmpty, !isWorking else { return }
        isWorking = true

        session.startSensitiveTask { _ in
            defer {
                selection.forEach { $0.discard() }
                pendingImports.removeAll()
                isWorking = false
            }
            var imported = 0
            var failed = 0
            for pending in selection {
                guard !Task.isCancelled else { return }
                do {
                    _ = try await store.importFile(pending)
                    imported += 1
                } catch {
                    failed += 1
                }
            }
            guard !Task.isCancelled else { return }
            records = (try? await store.loadManifest().files) ?? records
            if imported > 0 {
                let noun = imported == 1 ? "file" : "files"
                message = failed == 0
                    ? "Encrypted \(imported) \(noun) into this vault. The originals were kept."
                    : "Encrypted \(imported) \(noun). \(failed) selected items were not supported or could not be read."
            } else {
                message = "No files were imported. Choose regular files up to 100 MB; vault backups, folders, apps, and executable files are excluded."
            }
        }
    }

    private func removePendingImports(at offsets: IndexSet) {
        let removed = offsets.map { pendingImports[$0] }
        pendingImports.remove(atOffsets: offsets)
        removed.forEach { $0.discard() }
    }

    private func cancelPendingImport() {
        pendingImports.forEach { $0.discard() }
        pendingImports.removeAll()
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
