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
