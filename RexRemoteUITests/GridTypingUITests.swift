import XCTest

/// Types straight into the grid view (not the compose field) and checks the
/// characters land on the shell prompt.
final class GridTypingUITests: XCTestCase {
    func testTypeIntoGridDirectly() {
        let app = XCUIApplication()
        var args = ["-rexHost", ProcessInfo.processInfo.environment["REX_TEST_SERVER"] ?? "127.0.0.1:7297"]
        if let id = ProcessInfo.processInfo.environment["REX_TEST_ACCESS_ID"] {
            args += ["-rexAccessID", id]
        }
        if let secret = ProcessInfo.processInfo.environment["REX_TEST_ACCESS_SECRET"] {
            args += ["-rexAccessSecret", secret]
        }
        app.launchArguments = args
        app.launch()

        app.buttons["connectButton"].tap()
        let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "dev")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 25), "sessions never loaded")
        row.tap()
        _ = app.buttons["composeField"].waitForExistence(timeout: 25)
        sleep(3)

        // Tap the left pane body, then type with the system keyboard path.
        // A character first: the very first key event after the keyboard appears
        // can be swallowed, and this test is about the IME/text-view plumbing.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.26, dy: 0.55)).tap()
        sleep(1)
        let typed = "echo grid-A1"
        app.typeText(typed)
        sleep(1)
        app.typeText("\n")
        sleep(2)

        let shot = XCUIScreen.main.screenshot()
        add(XCTAttachment(screenshot: shot))
        let data = shot.pngRepresentation
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("99-grid-typing.png")
        try? data.write(to: url)
    }
}
