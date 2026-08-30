import SwiftUI
import PhotosUI
import Photos
import UIKit

struct PickedVaultPhoto: Identifiable {
    let id = UUID()
    let sourceAssetIdentifier: String?
    let originalData: Data
    let thumbnailData: Data
}

struct SecurePhotoPicker: UIViewControllerRepresentable {
    let selectionLimit: Int
    let onPicked: ([PickedVaultPhoto]) -> Void

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

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        private let onPicked: ([PickedVaultPhoto]) -> Void

        init(onPicked: @escaping ([PickedVaultPhoto]) -> Void) {
            self.onPicked = onPicked
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            guard !results.isEmpty else {
                onPicked([])
                return
            }

            let group = DispatchGroup()
            let lock = NSLock()
            var photos: [PickedVaultPhoto] = []

            for result in results {
                guard result.itemProvider.canLoadObject(ofClass: UIImage.self) else { continue }
                group.enter()

                result.itemProvider.loadObject(ofClass: UIImage.self) { object, _ in
                    defer { group.leave() }
                    guard let image = object as? UIImage,
                          let originalData = Self.normalizedJPEG(from: image),
                          let thumbnailData = Self.thumbnailJPEG(from: image) else { return }

                    let photo = PickedVaultPhoto(
                        sourceAssetIdentifier: result.assetIdentifier,
                        originalData: originalData,
                        thumbnailData: thumbnailData
                    )

                    lock.lock()
                    photos.append(photo)
                    lock.unlock()
                }
            }

            group.notify(queue: .main) { [onPicked] in
                onPicked(photos)
            }
        }

        /// Re-encoding removes most source metadata and avoids writing a plaintext
        /// source file into KeyHollow storage. The resulting bytes exist in memory
        /// until encrypted by VaultPhotoStore.
        private static func normalizedJPEG(from image: UIImage) -> Data? {
            image.jpegData(compressionQuality: 0.97)
        }

        private static func thumbnailJPEG(from image: UIImage) -> Data? {
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

enum PhotoLibraryDeletionService {
    static func deleteOriginals(localIdentifiers: [String]) async -> PhotoMoveResult {
        let identifiers = Array(Set(localIdentifiers))
        guard !identifiers.isEmpty else { return .copiedOnly }

        let status = await authorizationStatus()
        guard status == .authorized || status == .limited else { return .copiedOnly }

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
