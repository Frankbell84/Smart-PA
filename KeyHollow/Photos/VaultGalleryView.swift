import SwiftUI
import UIKit
import KeyHollowPhotoCore

private enum VaultImportMode {
    case copy
    case move
}

private struct VaultImportProgress {
    let mode: VaultImportMode
    let total: Int
    var importedCount = 0
    var failedCount = 0
    var identifiersToDelete: [String] = []
}

private struct DecryptedPhoto: Identifiable {
    let id: UUID
    let record: VaultPhotoRecord
    let originalData: Data
    let image: UIImage
}

struct VaultGalleryView: View {
    @EnvironmentObject private var session: VaultSession

    let service: VaultUnlockService

    @State private var store: VaultPhotoStore?
    @State private var records: [VaultPhotoRecord] = []
    @State private var thumbnails: [UUID: UIImage] = [:]
    @State private var decryptedPhoto: DecryptedPhoto?
    @State private var showingImportOptions = false
    @State private var showingPicker = false
    @State private var showingNewVault = false
    @State private var showingSecuritySettings = false
    @State private var showingEncryptedImport = false
    @State private var showingEncryptedExport = false
    @State private var showingDeleteSelectionConfirmation = false
    @State private var importMode: VaultImportMode = .copy
    @State private var isSelecting = false
    @State private var selectedPhotoIDs: Set<UUID> = []
    @State private var isWorking = false
    @State private var message: String?
    @State private var importProgress: VaultImportProgress?

    private let maximumCachedThumbnails = 48

    private let columns = Array(
        repeating: GridItem(.flexible(), spacing: 3),
        count: 3
    )

    var body: some View {
        VStack(spacing: 0) {
            galleryHeader
            Divider()

            Group {
                if records.isEmpty && !isWorking {
                    ContentUnavailableView(
                        "Empty Vault",
                        systemImage: "photo.on.rectangle.angled",
                        description: Text("Import photos to store encrypted copies inside this vault.")
                    )
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 3) {
                            ForEach(records) { record in
                                thumbnailCell(record)
                            }
                        }
                        .padding(.horizontal, 3)
                        .padding(.vertical, 3)
                    }
                }
            }
            .overlay {
                if isWorking {
                    ProgressView()
                        .padding()
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }

            if isSelecting {
                Divider()
                selectionActionBar
            }
        }
        .confirmationDialog("Import Photos", isPresented: $showingImportOptions, titleVisibility: .visible) {
            Button("Copy to Vault") {
                importMode = .copy
                showingPicker = true
            }
            Button("Move to Vault") {
                importMode = .move
                showingPicker = true
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Copy keeps the originals in Photos. Move encrypts and verifies the vault copies first, then asks iOS to delete the originals.")
        }
        .sheet(isPresented: $showingPicker) {
            SecurePhotoPicker(selectionLimit: 50) { event in
                await handleImportEvent(event)
            }
        }
        .sheet(isPresented: $showingNewVault) {
            AdditionalVaultSetupView(service: service)
                .environmentObject(session)
        }
        .sheet(isPresented: $showingSecuritySettings) {
            VaultSecuritySettingsView(service: service)
                .environmentObject(session)
        }
        .sheet(isPresented: $showingEncryptedImport) {
            EncryptedVaultImportView(service: service)
                .environmentObject(session)
        }
        .sheet(isPresented: $showingEncryptedExport) {
            EncryptedVaultExportView(service: service)
                .environmentObject(session)
        }
        .sheet(item: $decryptedPhoto) { photo in
            DecryptedPhotoView(photo: photo) {
                delete(photo.record)
            }
        }
        .confirmationDialog(
            "Delete Selected Photos?",
            isPresented: $showingDeleteSelectionConfirmation,
            titleVisibility: .visible
        ) {
            Button(deleteSelectionButtonTitle, role: .destructive) {
                deleteSelectedPhotos()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently removes the selected encrypted copies from this vault. Photos outside KeyHollow are not affected.")
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
            store = nil
            records = []
            thumbnails = [:]
            decryptedPhoto = nil
            leaveSelectionMode()
            await initializeStore()
        }
    }

    private var galleryHeader: some View {
        HStack(spacing: 18) {
            if isSelecting {
                Button("Cancel") { leaveSelectionMode() }

                Spacer()

                Button(allPhotosSelected ? "Deselect All" : "Select All") {
                    toggleSelectAll()
                }
                .disabled(records.isEmpty || isWorking)
            } else {
                Button("Lock") { session.lock() }

                Spacer()

                Button("Select") {
                    isSelecting = true
                }
                .disabled(records.isEmpty || isWorking)

                Button {
                    showingImportOptions = true
                } label: {
                    Image(systemName: "plus")
                }
                .disabled(isWorking)
                .accessibilityLabel("Import photos")

                Menu {
                    Button {
                        showingNewVault = true
                    } label: {
                        Label("Create New Vault", systemImage: "lock.badge.plus")
                    }

                    Button {
                        showingEncryptedImport = true
                    } label: {
                        Label("Import Encrypted Vault", systemImage: "square.and.arrow.down.on.square")
                    }

                    Button {
                        showingEncryptedExport = true
                    } label: {
                        Label("Export Encrypted Vault", systemImage: "square.and.arrow.up.on.square")
                    }

                    Button {
                        showingSecuritySettings = true
                    } label: {
                        Label("Vault Security", systemImage: "shield.lefthalf.filled")
                    }

                    Button {
                        session.lock()
                    } label: {
                        Label("Lock KeyHollow", systemImage: "lock.fill")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .disabled(isWorking)
                .accessibilityLabel("Vault options")
            }
        }
        .overlay {
            Text(isSelecting ? "\(selectedPhotoIDs.count) Selected" : "Vault")
                .font(.headline)
                .allowsHitTesting(false)
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
    }

    private var selectionActionBar: some View {
        HStack {
            Button {
                saveSelectedPhotos()
            } label: {
                Label("Save to Photos", systemImage: "square.and.arrow.down")
            }
            .disabled(selectedPhotoIDs.isEmpty || isWorking)

            Spacer()

            Button(role: .destructive) {
                showingDeleteSelectionConfirmation = true
            } label: {
                Label("Delete", systemImage: "trash")
            }
            .disabled(selectedPhotoIDs.isEmpty || isWorking)
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
        .background(.bar)
    }

    @ViewBuilder
    private func thumbnailCell(_ record: VaultPhotoRecord) -> some View {
        Button {
            if isSelecting {
                toggleSelection(record.id)
            } else {
                open(record)
            }
        } label: {
            GeometryReader { proxy in
                ZStack(alignment: .topTrailing) {
                    Rectangle()
                        .fill(.secondary.opacity(0.12))

                    if let image = thumbnails[record.id] {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: proxy.size.width, height: proxy.size.height)
                            .clipped()
                    } else {
                        Image(systemName: "photo")
                            .foregroundStyle(.secondary)
                            .frame(width: proxy.size.width, height: proxy.size.height)
                    }

                    if isSelecting {
                        Image(systemName: selectedPhotoIDs.contains(record.id) ? "checkmark.circle.fill" : "circle")
                            .font(.title2)
                            .foregroundStyle(
                                selectedPhotoIDs.contains(record.id) ? Color.accentColor : Color.white,
                                Color.white
                            )
                            .padding(8)
                            .shadow(radius: 2)
                    }
                }
            }
            .aspectRatio(1, contentMode: .fit)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Vault photo")
        .accessibilityValue(
            isSelecting && selectedPhotoIDs.contains(record.id) ? "Selected" : "Not selected"
        )
        .contextMenu {
            Button {
                savePhotos([record])
            } label: {
                Label("Save to Photos", systemImage: "square.and.arrow.down")
            }

            Button {
                isSelecting = true
                selectedPhotoIDs = [record.id]
            } label: {
                Label("Select", systemImage: "checkmark.circle")
            }

            Button("Delete from Vault", role: .destructive) {
                delete(record)
            }
        }
        .task(id: record.id) {
            await loadThumbnailIfNeeded(record)
        }
    }

    private func initializeStore() async {
        guard store == nil,
              let context = session.activeVaultContext() else { return }

        do {
            let createdStore = try VaultPhotoStore(vaultID: context.id, access: context.access)
            store = createdStore
            try await reload(using: createdStore)
        } catch {
            message = "The encrypted photo store could not be opened."
        }
    }

    private func reload(using store: VaultPhotoStore) async throws {
        let manifest = try await store.loadManifest()

        records = manifest.photos
        let validIDs = Set(manifest.photos.map(\.id))
        thumbnails = thumbnails.filter { validIDs.contains($0.key) }
        selectedPhotoIDs.formIntersection(Set(manifest.photos.map(\.id)))

        if records.isEmpty {
            leaveSelectionMode()
        }
    }

    @MainActor
    private func handleImportEvent(_ event: PickedVaultPhotoEvent) async {
        switch event {
        case .started(let total):
            guard !isWorking else { return }
            isWorking = true
            importProgress = VaultImportProgress(mode: importMode, total: total)

        case .photo(let photo):
            guard var progress = importProgress,
                  let store,
                  session.isUnlocked,
                  !Task.isCancelled else { return }
            do {
                _ = try await store.importPhoto(
                    originalData: photo.originalData,
                    thumbnailData: photo.thumbnailData
                )
                progress.importedCount += 1
                if progress.mode == .move, let identifier = photo.sourceAssetIdentifier {
                    progress.identifiersToDelete.append(identifier)
                }
            } catch {
                progress.failedCount += 1
            }
            importProgress = progress

        case .failed:
            importProgress?.failedCount += 1

        case .finished:
            showingPicker = false
            guard let progress = importProgress else {
                isWorking = false
                return
            }
            importProgress = nil
            await finishImport(progress)
        }
    }

    @MainActor
    private func finishImport(_ progress: VaultImportProgress) async {
        guard let store, session.isUnlocked, !Task.isCancelled else {
            isWorking = false
            return
        }

        do {
            try await reload(using: store)
        } catch {
            message = "Photos were encrypted, but the gallery could not be refreshed."
        }

        if progress.mode == .move, progress.importedCount > 0 {
            let allImportedPhotosAreDeletable =
                progress.identifiersToDelete.count == progress.importedCount
            let result: PhotoMoveResult
            if allImportedPhotosAreDeletable {
                session.beginSystemPhotoOperation()
                result = await PhotoLibraryDeletionService.deleteOriginals(
                    localIdentifiers: progress.identifiersToDelete
                )
                session.endSystemPhotoOperation()
            } else {
                result = .copiedOnly
            }

            switch result {
            case .deleted:
                message = importResultMessage(
                    action: "Moved",
                    importedCount: progress.importedCount,
                    failedCount: progress.failedCount
                )
            case .copiedOnly:
                let base = importResultMessage(
                    action: "Encrypted",
                    importedCount: progress.importedCount,
                    failedCount: progress.failedCount
                )
                message = "\(base) iOS did not delete every original, so KeyHollow treats this batch as copied."
            }
        } else if progress.importedCount > 0 {
            message = importResultMessage(
                action: "Copied",
                importedCount: progress.importedCount,
                failedCount: progress.failedCount
            )
        } else if progress.failedCount > 0 {
            message = unreadableSelectionMessage(count: progress.failedCount)
        }
        isWorking = false
    }

    @MainActor
    private func loadThumbnailIfNeeded(_ record: VaultPhotoRecord) async {
        guard thumbnails[record.id] == nil,
              let store,
              session.isUnlocked else { return }
        guard let data = try? await store.loadThumbnail(record),
              !Task.isCancelled,
              let image = UIImage(data: data) else { return }

        if thumbnails.count >= maximumCachedThumbnails,
           let eviction = thumbnails.keys.first(where: { $0 != record.id }) {
            thumbnails.removeValue(forKey: eviction)
        }
        thumbnails[record.id] = image
    }

    private func importResultMessage(action: String, importedCount: Int, failedCount: Int) -> String {
        let noun = importedCount == 1 ? "photo" : "photos"
        if failedCount > 0 {
            let failedNoun = failedCount == 1 ? "photo" : "photos"
            return "\(action) \(importedCount) \(noun) into KeyHollow. \(failedCount) \(failedNoun) could not be imported."
        }
        return "\(action) \(importedCount) \(noun) into KeyHollow."
    }

    private func unreadableSelectionMessage(count: Int) -> String {
        let noun = count == 1 ? "photo" : "photos"
        return "No photos were imported. \(count) selected \(noun) could not be read."
    }

    private func open(_ record: VaultPhotoRecord) {
        guard let store, !isWorking else { return }
        isWorking = true

        session.startSensitiveTask { _ in
            defer { isWorking = false }
            do {
                let data = try await store.loadPhoto(record)
                guard !Task.isCancelled else { return }
                guard let image = UIImage(data: data) else {
                    message = "The decrypted photo data could not be displayed."
                    return
                }
                decryptedPhoto = DecryptedPhoto(
                    id: record.id,
                    record: record,
                    originalData: data,
                    image: image
                )
            } catch is CancellationError {
                return
            } catch {
                message = "The photo could not be authenticated and decrypted."
            }
        }
    }

    private func delete(_ record: VaultPhotoRecord) {
        guard let store, !isWorking else { return }
        decryptedPhoto = nil
        isWorking = true

        session.startSensitiveTask { _ in
            defer { isWorking = false }
            do {
                try await store.delete(record)
                try await reload(using: store)
            } catch is CancellationError {
                return
            } catch {
                message = "The photo could not be deleted from the vault."
            }
        }
    }

    private var selectedRecords: [VaultPhotoRecord] {
        records.filter { selectedPhotoIDs.contains($0.id) }
    }

    private var allPhotosSelected: Bool {
        !records.isEmpty && selectedPhotoIDs.count == records.count
    }

    private var deleteSelectionButtonTitle: String {
        let noun = selectedPhotoIDs.count == 1 ? "Photo" : "Photos"
        return "Delete \(selectedPhotoIDs.count) \(noun) from Vault"
    }

    private func toggleSelection(_ id: UUID) {
        if selectedPhotoIDs.contains(id) {
            selectedPhotoIDs.remove(id)
        } else {
            selectedPhotoIDs.insert(id)
        }
    }

    private func toggleSelectAll() {
        if allPhotosSelected {
            selectedPhotoIDs.removeAll()
        } else {
            selectedPhotoIDs = Set(records.map(\.id))
        }
    }

    private func leaveSelectionMode() {
        isSelecting = false
        selectedPhotoIDs.removeAll()
    }

    private func saveSelectedPhotos() {
        savePhotos(selectedRecords)
    }

    private func savePhotos(_ photos: [VaultPhotoRecord]) {
        guard let store, !photos.isEmpty, !isWorking else { return }
        isWorking = true

        session.startSensitiveTask { _ in
            var savedCount = 0
            var failedCount = 0
            var permissionDenied = false

            session.beginSystemPhotoOperation()
            defer {
                session.endSystemPhotoOperation()
                isWorking = false
            }

            for photo in photos {
                guard !Task.isCancelled else { return }
                do {
                    // One decrypted original is resident at a time and is
                    // released before the next record is loaded.
                    let decryptedPhoto = try await store.loadPhoto(photo)
                    let result = await PhotoLibrarySaveService.savePhoto(decryptedPhoto)
                    switch result {
                    case .saved:
                        savedCount += 1
                    case .permissionDenied:
                        permissionDenied = true
                    case .failed:
                        failedCount += 1
                    }
                } catch {
                    failedCount += 1
                }
                if permissionDenied { break }
            }

            guard !Task.isCancelled else { return }
            if permissionDenied {
                message = "Allow KeyHollow to add photos in iPhone Settings, then try again."
            } else if savedCount > 0 {
                let noun = savedCount == 1 ? "photo" : "photos"
                if failedCount > 0 {
                    message = "Saved \(savedCount) \(noun) to Photos. \(failedCount) selected photos could not be decrypted or saved."
                } else {
                    message = "Saved \(savedCount) \(noun) to Photos. The encrypted vault copies were kept."
                }
                leaveSelectionMode()
            } else {
                message = "The selected photos could not be authenticated, decrypted, or saved."
            }
        }
    }

    private func deleteSelectedPhotos() {
        guard let store, !selectedRecords.isEmpty, !isWorking else { return }
        let photos = selectedRecords
        isWorking = true

        session.startSensitiveTask { _ in
            defer { isWorking = false }
            do {
                try await store.delete(photos)
                try await reload(using: store)
                guard !Task.isCancelled else { return }
                let noun = photos.count == 1 ? "photo" : "photos"
                message = "Deleted \(photos.count) \(noun) from this vault."
                leaveSelectionMode()
            } catch is CancellationError {
                return
            } catch {
                message = "The selected photos could not be deleted from the vault."
            }
        }
    }
}

private struct DecryptedPhotoView: View {
    let photo: DecryptedPhoto
    let onDelete: () -> Void

    @EnvironmentObject private var session: VaultSession
    @Environment(\.dismiss) private var dismiss
    @State private var isSaving = false
    @State private var message: String?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            Image(uiImage: photo.image)
                .resizable()
                .scaledToFit()

            VStack {
                HStack {
                    Button("Done") { dismiss() }

                    Spacer()

                    if isSaving {
                        ProgressView()
                    } else {
                        Button {
                            saveToPhotos()
                        } label: {
                            Image(systemName: "square.and.arrow.down")
                        }
                        .accessibilityLabel("Save to Photos")
                    }

                    Button(role: .destructive) {
                        dismiss()
                        onDelete()
                    } label: {
                        Image(systemName: "trash")
                    }
                }
                .padding()
                .background(.ultraThinMaterial)

                Spacer()
            }
        }
        .alert("KeyHollow", isPresented: Binding(
            get: { message != nil },
            set: { if !$0 { message = nil } }
        )) {
            Button("OK") { message = nil }
        } message: {
            Text(message ?? "")
        }
    }

    private func saveToPhotos() {
        guard !isSaving else { return }
        isSaving = true

        session.startSensitiveTask { _ in
            session.beginSystemPhotoOperation()
            defer {
                session.endSystemPhotoOperation()
                isSaving = false
            }
            let result = await PhotoLibrarySaveService.savePhoto(photo.originalData)
            guard !Task.isCancelled else { return }
            switch result {
            case .saved:
                message = "Saved to Photos. The encrypted vault copy was kept."
            case .permissionDenied:
                message = "Allow KeyHollow to add photos in iPhone Settings, then try again."
            case .failed:
                message = "This photo could not be saved to Photos."
            }
        }
    }
}

