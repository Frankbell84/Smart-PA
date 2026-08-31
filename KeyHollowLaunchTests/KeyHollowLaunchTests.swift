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
}
