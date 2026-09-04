import Foundation
import Photos
@preconcurrency import PhotosUI
@preconcurrency import UIKit

public struct PickedVaultPhoto: Identifiable, @unchecked Sendable {
    public let id = UUID()
    public let sourceAssetIdentifier: String?
    public let originalData: Data
    public let thumbnailData: Data

    public init(
        sourceAssetIdentifier: String?,
        originalData: Data,
        thumbnailData: Data
    ) {
        self.sourceAssetIdentifier = sourceAssetIdentifier
        self.originalData = originalData
        self.thumbnailData = thumbnailData
    }
}

public enum SequentialPhotoBatchProcessor {
    public static let maximumConcurrentItems = 1

    @MainActor
    public static func process<Element: Sendable, Value: Sendable>(
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

public enum ApplePhotoPickerItemLoader {
    /// Full-resolution images are decoded, normalized, and returned one at a
    /// time. Plaintext image data is never written to KeyHollow storage here.
    nonisolated public static func loadPhoto(
        _ result: PHPickerResult
    ) async throws -> PickedVaultPhoto {
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

        guard let originalData = image.jpegData(compressionQuality: 0.97),
              let thumbnailData = thumbnailJPEG(from: image) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return PickedVaultPhoto(
            sourceAssetIdentifier: result.assetIdentifier,
            originalData: originalData,
            thumbnailData: thumbnailData
        )
    }

    private nonisolated static func thumbnailJPEG(from image: UIImage) -> Data? {
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

public enum PhotoMoveResult: Equatable, Sendable {
    case deleted
    case copiedOnly
}

public enum PhotoLibrarySaveResult: Equatable, Sendable {
    case saved(Int)
    case permissionDenied
    case failed
}

public enum PhotoLibrarySaveService {
    public static let maximumResidentFullSizePhotos = 1

    public static func savePhoto(_ photo: Data) async -> PhotoLibrarySaveResult {
        guard !photo.isEmpty, !Task.isCancelled else { return .failed }

        let status = await authorizationStatus()
        guard status == .authorized || status == .limited else {
            return .permissionDenied
        }
        guard !Task.isCancelled else { return .failed }

        do {
            try await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<Void, Error>) in
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

public enum PhotoLibraryDeletionService {
    public static func deleteOriginals(localIdentifiers: [String]) async -> PhotoMoveResult {
        let identifiers = Array(Set(localIdentifiers))
        guard !identifiers.isEmpty, !Task.isCancelled else { return .copiedOnly }

        let status = await authorizationStatus()
        guard status == .authorized || status == .limited else { return .copiedOnly }
        guard !Task.isCancelled else { return .copiedOnly }

        let assets = PHAsset.fetchAssets(withLocalIdentifiers: identifiers, options: nil)
        guard assets.count == identifiers.count else { return .copiedOnly }

        do {
            try await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<Void, Error>) in
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
