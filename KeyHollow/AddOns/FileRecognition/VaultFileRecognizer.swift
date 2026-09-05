import Foundation

public struct RecognizedVaultFile: Equatable, Sendable {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }
}

public protocol VaultFileRecognizing: Sendable {
    func recognize(_ url: URL) -> RecognizedVaultFile?
}

public struct KHVaultFileRecognizer: VaultFileRecognizing {
    public static let filenameExtension = "khvault"

    public init() {}

    public func recognize(_ url: URL) -> RecognizedVaultFile? {
        guard url.isFileURL,
              url.pathExtension.caseInsensitiveCompare(Self.filenameExtension) == .orderedSame else {
            return nil
        }

        return RecognizedVaultFile(url: url)
    }
}

public struct StagedVaultFile: Equatable, Sendable {
    public let url: URL
    public let displayName: String
    public let byteCount: UInt64

    public init(url: URL, displayName: String, byteCount: UInt64) {
        self.url = url
        self.displayName = displayName
        self.byteCount = byteCount
    }

    public func discard(using fileManager: FileManager = .default) {
        try? fileManager.removeItem(at: url.deletingLastPathComponent())
    }
}

public enum VaultFileIngressError: Error, Equatable {
    case unsupportedFile
    case insufficientStorage
    case unavailable
}

/// Owns the short-lived Files-provider permission and immediately copies an
/// incoming vault into app-controlled, protected temporary storage.
public struct KHVaultFileIngress {
    private static let requiredHeadroom: Int64 = 67_108_864

    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func stageIfRecognized(_ sourceURL: URL) throws -> StagedVaultFile? {
        guard let recognized = KHVaultFileRecognizer().recognize(sourceURL) else {
            return nil
        }
        return try stage(recognized)
    }

    public func stage(_ recognizedFile: RecognizedVaultFile) throws -> StagedVaultFile {
        let sourceURL = recognizedFile.url
        let displayName = sourceURL.lastPathComponent
        let accessed = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if accessed {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        var coordinationError: NSError?
        var stagedResult: Result<StagedVaultFile, Error>?
        let coordinator = NSFileCoordinator()
        coordinator.coordinate(
            readingItemAt: sourceURL,
            options: .withoutChanges,
            error: &coordinationError
        ) { coordinatedURL in
            do {
                stagedResult = .success(
                    try stageCoordinatedFile(
                        at: coordinatedURL,
                        displayName: displayName
                    )
                )
            } catch {
                stagedResult = .failure(error)
            }
        }

        if coordinationError != nil {
            throw VaultFileIngressError.unavailable
        }
        guard let stagedResult else {
            throw VaultFileIngressError.unavailable
        }
        do {
            return try stagedResult.get()
        } catch let error as VaultFileIngressError {
            throw error
        } catch {
            throw VaultFileIngressError.unavailable
        }
    }

    private func stageCoordinatedFile(
        at sourceURL: URL,
        displayName: String
    ) throws -> StagedVaultFile {
        guard sourceURL.pathExtension.caseInsensitiveCompare(
            KHVaultFileRecognizer.filenameExtension
        ) == .orderedSame else {
            throw VaultFileIngressError.unsupportedFile
        }

        let attributes = try fileManager.attributesOfItem(atPath: sourceURL.path)
        guard let fileSize = attributes[.size] as? NSNumber,
              fileSize.uint64Value > 0,
              fileSize.uint64Value <= UInt64(Int64.max) else {
            throw VaultFileIngressError.unsupportedFile
        }

        let sourceSize = Int64(fileSize.uint64Value)
        let capacityValues = try fileManager.temporaryDirectory.resourceValues(
            forKeys: [
                .volumeAvailableCapacityForImportantUsageKey,
                .volumeAvailableCapacityKey
            ]
        )
        let available = capacityValues.volumeAvailableCapacityForImportantUsage ??
            Int64(capacityValues.volumeAvailableCapacity ?? 0)
        let doubled = sourceSize.multipliedReportingOverflow(by: 2)
        let withHeadroom = doubled.partialValue.addingReportingOverflow(
            Self.requiredHeadroom
        )
        guard !doubled.overflow,
              !withHeadroom.overflow,
              available >= withHeadroom.partialValue else {
            throw VaultFileIngressError.insufficientStorage
        }

        let importRoot = fileManager.temporaryDirectory
            .appendingPathComponent("KeyHollowPortableImports", isDirectory: true)
            .appendingPathComponent(UUID().uuidString.lowercased(), isDirectory: true)
        do {
            try fileManager.createDirectory(
                at: importRoot,
                withIntermediateDirectories: true,
                attributes: [.protectionKey: FileProtectionType.complete]
            )
            var protectedRoot = importRoot
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try protectedRoot.setResourceValues(values)

            let destination = importRoot.appendingPathComponent("Selected.khvault")
            try fileManager.copyItem(at: sourceURL, to: destination)
            return StagedVaultFile(
                url: destination,
                displayName: displayName,
                byteCount: fileSize.uint64Value
            )
        } catch {
            try? fileManager.removeItem(at: importRoot)
            throw error
        }
    }
}
