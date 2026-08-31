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

        let passcode = "83057291"
        let passcodeField = app.secureTextFields["Enter 8-digit passcode"]
        XCTAssertTrue(passcodeField.waitForExistence(timeout: 5))
        passcodeField.tap()
        passcodeField.typeText(passcode)

        let confirmationField = app.secureTextFields["Confirm passcode"]
        confirmationField.tap()
        confirmationField.typeText(passcode)

        let doneButton = app.buttons["Done"]
        XCTAssertTrue(doneButton.waitForExistence(timeout: 5))
        doneButton.tap()
        XCTAssertFalse(app.keyboards.firstMatch.waitForExistence(timeout: 2))

        let noRecoveryAcknowledgment = app.switches["I understand this vault cannot be recovered"]
        XCTAssertTrue(noRecoveryAcknowledgment.waitForExistence(timeout: 5))
        noRecoveryAcknowledgment.tap()

        let acknowledgmentRegistered = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == '1'"),
            object: noRecoveryAcknowledgment
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [acknowledgmentRegistered], timeout: 5),
            .completed,
            "The no-recovery acknowledgment did not register."
        )

        let createButton = app.buttons["Create Encrypted Vault"]
        let createButtonEnabled = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "isEnabled == true"),
            object: createButton
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [createButtonEnabled], timeout: 5),
            .completed,
            "Vault creation did not become available after valid input and acknowledgment."
        )
        createButton.tap()

        // Production Argon2id intentionally uses 64 MiB and three passes. A
        // hosted simulator can take substantially longer than a physical
        // iPhone to finish that work, so this launch regression test verifies
        // the production UI accepts the action and remains alive. Completion,
        // persistence, and decryption are covered by the security test target.
        let creationStarted = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "isEnabled == false"),
            object: createButton
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [creationStarted], timeout: 5),
            .completed,
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

