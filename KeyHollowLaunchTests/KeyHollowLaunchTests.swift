import XCTest

final class KeyHollowLaunchTests: XCTestCase {
    func testProductionAppStaysRunningAfterLaunch() {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(
            app.wait(for: .runningForeground, timeout: 5),
            "KeyHollow did not reach the foreground."
        )

        // The production app process must remain alive after SwiftUI startup
        // and secure-storage initialization have completed.
        Thread.sleep(forTimeInterval: 3)
        XCTAssertEqual(
            app.state,
            .runningForeground,
            "KeyHollow exited or crashed immediately after launch."
        )
    }

    func testFirstVaultCreationReachesGallery() {
        let app = XCUIApplication()
        app.launch()

        let passcode = "58294176"
        let passcodeField = app.secureTextFields["Enter 8-digit passcode"]
        XCTAssertTrue(passcodeField.waitForExistence(timeout: 5))
        passcodeField.tap()
        passcodeField.typeText(passcode)

        let confirmationField = app.secureTextFields["Confirm passcode"]
        confirmationField.tap()
        confirmationField.typeText(passcode)

        let createButton = app.buttons["Create Encrypted Vault"]
        XCTAssertTrue(createButton.isEnabled)
        createButton.tap()

        XCTAssertTrue(
            app.buttons["Import photos"].waitForExistence(timeout: 60),
            "The vault gallery did not become usable after first-vault creation."
        )
        Thread.sleep(forTimeInterval: 3)
        XCTAssertEqual(
            app.state,
            .runningForeground,
            "KeyHollow exited or crashed after transitioning to the vault gallery."
        )
    }
}
