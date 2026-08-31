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

    func testFirstVaultCreationBeginsWithoutCrashing() {
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

        // Production Argon2id intentionally uses 64 MiB and three passes. A
        // hosted simulator can take substantially longer than a physical
        // iPhone to finish that work, so this launch regression test verifies
        // the production UI accepts the action and remains alive. Completion,
        // persistence, and decryption are covered by the security test target.
        XCTAssertTrue(
            createButton.waitForNonExistence(timeout: 5),
            "Vault creation did not begin."
        )
        Thread.sleep(forTimeInterval: 5)
        XCTAssertEqual(
            app.state,
            .runningForeground,
            "KeyHollow exited or crashed after vault creation began."
        )
    }
}

