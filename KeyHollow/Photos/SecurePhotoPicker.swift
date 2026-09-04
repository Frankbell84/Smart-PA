import SwiftUI
@preconcurrency import PhotosUI
@preconcurrency import UIKit
import KeyHollowPhotosAdapter

enum PickedVaultPhotoEvent: @unchecked Sendable {
    case started(total: Int)
    case photo(PickedVaultPhoto)
    case failed
    case finished
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
                    load: ApplePhotoPickerItemLoader.loadPhoto,
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
    }
}

