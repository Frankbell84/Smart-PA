import Foundation
import XCTest
import KeyHollowFileRecognitionAddOn
import UIKit

final class VaultFileRecognitionAddOnTests: XCTestCase {
    private let recognizer = KHVaultFileRecognizer()

    func testRecognizesKHVaultFileURL() {
        let url = URL(fileURLWithPath: "/tmp/Family Backup.khvault")

        XCTAssertEqual(recognizer.recognize(url), RecognizedVaultFile(url: url))
    }

    func testRecognizesExtensionCaseInsensitively() {
        let url = URL(fileURLWithPath: "/tmp/Backup.KHVAULT")

        XCTAssertEqual(recognizer.recognize(url)?.url, url)
    }

    func testRejectsUnrelatedFileType() {
        let url = URL(fileURLWithPath: "/tmp/Backup.zip")

        XCTAssertNil(recognizer.recognize(url))
    }

    func testRejectsRemoteURL() {
        let url = URL(string: "https://example.com/Backup.khvault")!

        XCTAssertNil(recognizer.recognize(url))
    }

    func testRejectsFilenameThatOnlyContainsKHVaultText() {
        let url = URL(fileURLWithPath: "/tmp/Backup.khvault.txt")

        XCTAssertNil(recognizer.recognize(url))
    }

    func testApplicationDeclaresKHVaultDocumentHandler() throws {
        let documentTypes = try XCTUnwrap(
            Bundle.main.object(forInfoDictionaryKey: "CFBundleDocumentTypes")
                as? [[String: Any]]
        )
        let keyHollowType = try XCTUnwrap(documentTypes.first { declaration in
            (declaration["LSItemContentTypes"] as? [String])?
                .contains("com.keyhollow.encrypted-vault") == true
        })

        XCTAssertEqual(keyHollowType["CFBundleTypeRole"] as? String, "Viewer")
        XCTAssertEqual(keyHollowType["LSHandlerRank"] as? String, "Owner")
        XCTAssertNil(keyHollowType["CFBundleTypeIconFiles"])
        XCTAssertEqual(
            Bundle.main.object(forInfoDictionaryKey: "LSSupportsOpeningDocumentsInPlace") as? Bool,
            true
        )
    }

    func testDocumentHandlerUsesTheExportedKHVaultType() throws {
        let exportedTypes = try XCTUnwrap(
            Bundle.main.object(forInfoDictionaryKey: "UTExportedTypeDeclarations")
                as? [[String: Any]]
        )
        let exportedType = try XCTUnwrap(exportedTypes.first { declaration in
            declaration["UTTypeIdentifier"] as? String ==
                "com.keyhollow.encrypted-vault"
        })
        let conformances = try XCTUnwrap(exportedType["UTTypeConformsTo"] as? [String])
        let tags = try XCTUnwrap(exportedType["UTTypeTagSpecification"] as? [String: Any])
        let extensions = try XCTUnwrap(tags["public.filename-extension"] as? [String])
        XCTAssertNil(exportedType["UTTypeIcons"])
        XCTAssertTrue(conformances.contains("public.content"))
        XCTAssertTrue(conformances.contains("public.data"))
        XCTAssertEqual(extensions, ["khvault"])
    }
    func testDedicatedThumbnailExtensionIsEmbeddedAndNarrowlyRegistered() throws {
        let plugInsURL = try XCTUnwrap(Bundle.main.builtInPlugInsURL)
        let extensionURL = plugInsURL.appendingPathComponent(
            "KeyHollowVaultThumbnail.appex",
            isDirectory: true
        )
        let extensionBundle = try XCTUnwrap(Bundle(url: extensionURL))
        let extensionDeclaration = try XCTUnwrap(
            extensionBundle.object(forInfoDictionaryKey: "NSExtension")
                as? [String: Any]
        )
        let attributes = try XCTUnwrap(
            extensionDeclaration["NSExtensionAttributes"] as? [String: Any]
        )

        XCTAssertEqual(
            extensionDeclaration["NSExtensionPointIdentifier"] as? String,
            "com.apple.quicklook.thumbnail"
        )
        XCTAssertEqual(
            attributes["QLSupportedContentTypes"] as? [String],
            ["com.keyhollow.encrypted-vault"]
        )
        XCTAssertEqual(attributes["QLThumbnailMinimumDimension"] as? Int, 1)
        XCTAssertNotNil(
            UIImage(
                named: "KeyHollowVaultIcon",
                in: extensionBundle,
                compatibleWith: nil
            ),
            "The packaged thumbnail extension must expose the approved icon asset"
        )
    }
}
