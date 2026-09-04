import Foundation
import XCTest
import KeyHollowFileRecognitionAddOn

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
        let tags = try XCTUnwrap(exportedType["UTTypeTagSpecification"] as? [String: Any])
        let extensions = try XCTUnwrap(tags["public.filename-extension"] as? [String])

        XCTAssertEqual(extensions, ["khvault"])
    }
}
