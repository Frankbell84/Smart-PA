import SwiftUI
@preconcurrency import PhotosUI
import Photos
@preconcurrency import UIKit
import KeyHollowPhotoCore

struct PickedVaultPhoto: Identifiable, @unchecked Sendable {
    let id = UUID()
    let sourceAssetIdentifier: String?
    let originalData: Data
    let thumbnailData: Data
}

enum PickedVaultPhotoEvent: @unchecked Sendable {
    case started(total: Int)
    case photo(PickedVaultPhoto)
    case failed
    case finished
}

enum SequentialPhotoBatchProcessor {
    static let maximumConcurrentItems = 1

    @MainActor
    static func process<Element: Sendable, Value: Sendable>(
        _ elements: [Element],
        load: (Element) async throws -> Value,
        consume: (Value) async -> Void,
        didFail: () async -> Void
    ) async {
        for element in elements {
            guard !Task.isCancelled else { return }
            do {
                let value = try await load(element)
                guard !Task.isCancelled else { return }
                await consume(value)
            } catch is CancellationError {
                return
            } catch {
                await didFail()
            }
        }
    }
}

struct SecurePhotoPicker: UIViewControllerRepresentable {
    /// Full-resolution images are decoded, normalized, handed to encrypted
    /// storage, and released one at a time. Never increase this without a
    /// device-memory test and a corresponding bounded-pipeline test.
    static let maximumResidentFullSizePhotos = SequentialPhotoBatchProcessor.maximumConcurrentItems

    let selectionLimit: Int
    let onPicked: @MainActor (PickedVaultPhotoEvent) async -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onPicked: onPicked)
    }

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var configuration = PHPickerConfiguration(photoLibrary: .shared())
        configuration.filter = .images
        configuration.selectionLimit = selectionLimit
        configuration.preferredAssetRepresentationMode = .current

        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    static func dismantleUIViewController(
        _ uiViewController: PHPickerViewController,
        coordinator: Coordinator
    ) {
        coordinator.cancel()
    }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        private let onPicked: @MainActor (PickedVaultPhotoEvent) async -> Void
        private var processingTask: Task<Void, Never>?

        init(onPicked: @escaping @MainActor (PickedVaultPhotoEvent) async -> Void) {
            self.onPicked = onPicked
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            guard processingTask == nil else { return }
            picker.view.isUserInteractionEnabled = false

            processingTask = Task { @MainActor [onPicked] in
                await onPicked(.started(total: results.count))

                await SequentialPhotoBatchProcessor.process(
                    results,
                    load: Self.loadPhoto,
                    consume: { photo in
                        // Awaiting the consumer is the memory back-pressure:
                        // encrypted storage completes before the next UIImage is loaded.
                        await onPicked(.photo(photo))
                    },
                    didFail: {
                        await onPicked(.failed)
                    }
                )

                await onPicked(.finished)
                picker.dismiss(animated: true)
            }
        }

        func cancel() {
            processingTask?.cancel()
            processingTask = nil
        }

        nonisolated private static func loadPhoto(_ result: PHPickerResult) async throws -> PickedVaultPhoto {
            let provider = result.itemProvider
            guard provider.canLoadObject(ofClass: UIImage.self) else {
                throw CocoaError(.fileReadUnsupportedScheme)
            }

            let image = try await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<UIImage, Error>) in
                provider.loadObject(ofClass: UIImage.self) { object, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else if let image = object as? UIImage {
                        continuation.resume(returning: image)
                    } else {
                        continuation.resume(throwing: CocoaError(.fileReadCorruptFile))
                    }
                }
            }
            try Task.checkCancellation()

            guard let originalData = normalizedJPEG(from: image),
                  let thumbnailData = thumbnailJPEG(from: image) else {
                throw CocoaError(.fileReadCorruptFile)
            }
            return PickedVaultPhoto(
                sourceAssetIdentifier: result.assetIdentifier,
                originalData: originalData,
                thumbnailData: thumbnailData
            )
        }

        /// Re-encoding removes most source metadata and avoids writing a plaintext
        /// source file into KeyHollow storage. The resulting bytes exist in memory
        /// until encrypted by VaultPhotoStore.
        nonisolated private static func normalizedJPEG(from image: UIImage) -> Data? {
            image.jpegData(compressionQuality: 0.97)
        }

        nonisolated private static func thumbnailJPEG(from image: UIImage) -> Data? {
            let maxDimension: CGFloat = 512
            let source = image.size
            guard source.width > 0, source.height > 0 else { return nil }

            let scale = min(1, maxDimension / max(source.width, source.height))
            let size = CGSize(width: source.width * scale, height: source.height * scale)
            let renderer = UIGraphicsImageRenderer(size: size)
            let thumbnail = renderer.image { _ in
                image.draw(in: CGRect(origin: .zero, size: size))
            }
            return thumbnail.jpegData(compressionQuality: 0.82)
        }
    }
}

enum PhotoMoveResult {
    case deleted
    case copiedOnly
}

enum PhotoLibrarySaveResult {
    case saved(Int)
    case permissionDenied
    case failed
}

enum PhotoLibrarySaveService {
    static let maximumResidentFullSizePhotos = 1

    static func savePhoto(_ photo: Data) async -> PhotoLibrarySaveResult {
        guard !photo.isEmpty, !Task.isCancelled else { return .failed }

        let status = await authorizationStatus()
        guard status == .authorized || status == .limited else {
            return .permissionDenied
        }
        guard !Task.isCancelled else { return .failed }

        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                PHPhotoLibrary.shared().performChanges({
                    let request = PHAssetCreationRequest.forAsset()
                    request.addResource(with: .photo, data: photo, options: nil)
                }) { success, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else if success {
                        continuation.resume(returning: ())
                    } else {
                        continuation.resume(throwing: CocoaError(.fileWriteUnknown))
                    }
                }
            }
            return .saved(1)
        } catch {
            return .failed
        }
    }

    private static func authorizationStatus() async -> PHAuthorizationStatus {
        let current = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        guard current == .notDetermined else { return current }

        return await withCheckedContinuation { continuation in
            PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
                continuation.resume(returning: status)
            }
        }
    }
}

enum PhotoLibraryDeletionService {
    static func deleteOriginals(localIdentifiers: [String]) async -> PhotoMoveResult {
        let identifiers = Array(Set(localIdentifiers))
        guard !identifiers.isEmpty, !Task.isCancelled else { return .copiedOnly }

        let status = await authorizationStatus()
        guard status == .authorized || status == .limited else { return .copiedOnly }
        guard !Task.isCancelled else { return .copiedOnly }

        let assets = PHAsset.fetchAssets(withLocalIdentifiers: identifiers, options: nil)
        guard assets.count == identifiers.count else { return .copiedOnly }

        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                PHPhotoLibrary.shared().performChanges({
                    PHAssetChangeRequest.deleteAssets(assets)
                }) { success, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else if success {
                        continuation.resume(returning: ())
                    } else {
                        continuation.resume(throwing: CocoaError(.userCancelled))
                    }
                }
            }
            return .deleted
        } catch {
            return .copiedOnly
        }
    }

    private static func authorizationStatus() async -> PHAuthorizationStatus {
        let current = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard current == .notDetermined else { return current }

        return await withCheckedContinuation { continuation in
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
                continuation.resume(returning: status)
            }
        }
    }
}

