import SwiftUI
import UIKit

private enum VaultImportMode {
    case copy
    case move
}

private struct DecryptedPhoto: Identifiable {
    let id: UUID
    let record: VaultPhotoRecord
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
    @State private var importMode: VaultImportMode = .copy
    @State private var isWorking = false
    @State private var message: String?

    private let columns = [
        GridItem(.adaptive(minimum: 105, maximum: 180), spacing: 3)
    ]

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
            SecurePhotoPicker(selectionLimit: 50) { batch in
                showingPicker = false
                guard !batch.photos.isEmpty else {
                    if batch.failedSelectionCount > 0 {
                        message = unreadableSelectionMessage(count: batch.failedSelectionCount)
                    }
                    return
                }
                importPhotos(
                    batch.photos,
                    pickerFailureCount: batch.failedSelectionCount
                )
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
        .sheet(item: $decryptedPhoto) { photo in
            DecryptedPhotoView(photo: photo) {
                delete(photo.record)
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
        .task(id: session.activeVaultID) {
            store = nil
            records = []
            thumbnails = [:]
            decryptedPhoto = nil
            await initializeStore()
        }
    }

    private var galleryHeader: some View {
        HStack(spacing: 18) {
            Button("Lock") { session.lock() }

            Spacer()

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
        .overlay {
            Text("Vault")
                .font(.headline)
                .allowsHitTesting(false)
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private func thumbnailCell(_ record: VaultPhotoRecord) -> some View {
        Button {
            open(record)
        } label: {
            ZStack {
                Rectangle()
                    .fill(.secondary.opacity(0.12))
                    .aspectRatio(1, contentMode: .fit)

                if let image = thumbnails[record.id] {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .aspectRatio(1, contentMode: .fill)
                        .clipped()
                } else {
                    Image(systemName: "photo")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Delete from Vault", role: .destructive) {
                delete(record)
            }
        }
    }

    private func initializeStore() async {
        guard store == nil,
              let context = session.activeVaultContext() else { return }

        do {
            let createdStore = try VaultPhotoStore(vaultID: context.id, vaultKey: context.key)
            store = createdStore
            try await reload(using: createdStore)
        } catch {
            message = "The encrypted photo store could not be opened."
        }
    }

    private func reload(using store: VaultPhotoStore) async throws {
        let manifest = try await store.loadManifest()
        var loaded: [UUID: UIImage] = [:]

        for record in manifest.photos {
            if let data = try? await store.loadThumbnail(record),
               let image = UIImage(data: data) {
                loaded[record.id] = image
            }
        }

        records = manifest.photos
        thumbnails = loaded
    }

    private func importPhotos(
        _ photos: [PickedVaultPhoto],
        pickerFailureCount: Int
    ) {
        guard let store, !isWorking else { return }
        isWorking = true

        Task {
            var importedCount = 0
            var failedCount = pickerFailureCount
            var identifiersToDelete: [String] = []

            for photo in photos {
                do {
                    _ = try await store.importPhoto(
                        originalData: photo.originalData,
                        thumbnailData: photo.thumbnailData
                    )
                    importedCount += 1
                    if importMode == .move, let identifier = photo.sourceAssetIdentifier {
                        identifiersToDelete.append(identifier)
                    }
                } catch {
                    failedCount += 1
                }
            }

            do {
                try await reload(using: store)
            } catch {
                message = "Photos were encrypted, but the gallery could not be refreshed."
            }

            if importMode == .move, importedCount > 0 {
                let allImportedPhotosAreDeletable = identifiersToDelete.count == importedCount
                let result: PhotoMoveResult
                if allImportedPhotosAreDeletable {
                    result = await PhotoLibraryDeletionService.deleteOriginals(
                        localIdentifiers: identifiersToDelete
                    )
                } else {
                    result = .copiedOnly
                }

                switch result {
                case .deleted:
                    message = importResultMessage(action: "Moved", importedCount: importedCount, failedCount: failedCount)
                case .copiedOnly:
                    let base = importResultMessage(action: "Encrypted", importedCount: importedCount, failedCount: failedCount)
                    message = "\(base) iOS did not delete every original, so KeyHollow treats this batch as copied."
                }
            } else if importedCount > 0 {
                message = importResultMessage(action: "Copied", importedCount: importedCount, failedCount: failedCount)
            } else {
                message = "No photos were imported."
            }

            isWorking = false
        }
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

        Task {
            defer { isWorking = false }
            do {
                let data = try await store.loadPhoto(record)
                guard let image = UIImage(data: data) else {
                    message = "The decrypted photo data could not be displayed."
                    return
                }
                decryptedPhoto = DecryptedPhoto(id: record.id, record: record, image: image)
            } catch {
                message = "The photo could not be authenticated and decrypted."
            }
        }
    }

    private func delete(_ record: VaultPhotoRecord) {
        guard let store, !isWorking else { return }
        decryptedPhoto = nil
        isWorking = true

        Task {
            defer { isWorking = false }
            do {
                try await store.delete(record)
                try await reload(using: store)
            } catch {
                message = "The photo could not be deleted from the vault."
            }
        }
    }
}

private struct DecryptedPhotoView: View {
    let photo: DecryptedPhoto
    let onDelete: () -> Void

    @Environment(\.dismiss) private var dismiss

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
    }
}

