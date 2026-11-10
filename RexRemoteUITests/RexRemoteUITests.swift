import XCTest

/// End-to-end checks against a live Rex server on 127.0.0.1:7297.
final class RexRemoteUITests: XCTestCase {
    private let serverAddress = ProcessInfo.processInfo.environment["REX_TEST_SERVER"] ?? "127.0.0.1:7297"
    private let accessID = ProcessInfo.processInfo.environment["REX_TEST_ACCESS_ID"]
    private let accessSecret = ProcessInfo.processInfo.environment["REX_TEST_ACCESS_SECRET"]

    /// Launches the app pointed at the test server, passing Cloudflare Access
    /// service-token credentials when the tunnel test asks for them.
    /// Diagnostic: opens whatever session the server has and captures the pane
    /// before and after typing, so the render can be compared with the pty.
    /// Only runs when REX_TEST_ANY_SESSION=1, because it mutates that session.
    func testFirstSessionShowsPrompt() throws {
        guard ProcessInfo.processInfo.environment["REX_TEST_ANY_SESSION"] == "1" else {
            throw XCTSkip("set REX_TEST_ANY_SESSION=1 to run against a live session")
        }
        let app = launchedApp()
        app.buttons["connectButton"].tap()
        let row = app.buttons.matching(identifier: "sessionRow").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 25), "no session row")
        row.tap()

        Thread.sleep(forTimeInterval: 4.0)
        snapshot("diag-after-open")
        Thread.sleep(forTimeInterval: 1.0)
        snapshot("diag-before-typing")

        app.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.42)).tap()
        Thread.sleep(forTimeInterval: 1.5)
        app.typeText("echo probe-$((2+3))")
        Thread.sleep(forTimeInterval: 2.5)
        snapshot("diag-after-typing")
    }

    private func launchedApp() -> XCUIApplication {
        let app = XCUIApplication()
        var arguments = ["-rexHost", serverAddress]
        if let accessID, let accessSecret {
            arguments += ["-rexAccessID", accessID, "-rexAccessSecret", accessSecret]
        }
        app.launchArguments = arguments
        app.launch()
        return app
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testConnectOpenSessionAndTypeIntoTerminal() throws {
        let app = launchedApp()

        // 1. Connect screen.
        let serverField = app.textFields["serverAddressField"]
        XCTAssertTrue(serverField.waitForExistence(timeout: 20), "connect screen never appeared")
        XCTAssertEqual(serverField.value as? String, serverAddress)
        snapshot("01-connect")

        let connect = app.buttons["connectButton"]
        XCTAssertTrue(connect.waitForExistence(timeout: 5))
        connect.tap()

        // 2. Session list from the server.
        let sessionCell = app.buttons
            .matching(NSPredicate(format: "label BEGINSWITH %@", "dev"))
            .firstMatch
        let appeared = sessionCell.waitForExistence(timeout: 20)
        snapshot("02-sessions")
        if !appeared {
            print("=== UI DUMP START ===")
            print(app.debugDescription)
            print("=== UI DUMP END ===")
        }
        XCTAssertTrue(appeared, "session list never loaded")
        sessionCell.tap()

        // 3. Panes for the active window.
        let compose = app.textFields["composeField"]
        let hasCompose = compose.waitForExistence(timeout: 20)
        snapshot("03-session")
        if !hasCompose {
            print("=== UI DUMP START ===")
            print(app.debugDescription)
            print("=== UI DUMP END ===")
        }
        XCTAssertTrue(hasCompose, "session screen never appeared")
        let paneMenu = app.buttons["paneMenuButton"]
        XCTAssertTrue(paneMenu.waitForExistence(timeout: 10), "no pane rendered")
        XCTAssertGreaterThanOrEqual(app.buttons.matching(identifier: "paneMenuButton").count, 1)
        snapshot("03-terminal")

        // 4. Typing goes through `terminal.write`.
        focus(compose)
        compose.typeText("echo UI-TEST-$((6*7))")
        XCTAssertEqual(compose.value as? String, "echo UI-TEST-$((6*7))",
                       "compose field lost a keystroke before sending")
        app.buttons["sendButton"].tap()

        // 5. A key from the key bar does not crash the stream.
        let enterKey = app.buttons["key-esc"]
        if enterKey.waitForExistence(timeout: 5) {
            enterKey.tap()
        }

        XCTAssertTrue(paneMenu.waitForExistence(timeout: 10), "pane disappeared after input")
        snapshot("04-after-input")

        // 6. Switch to the other window; it must render its own panes.
        let shellTab = app.buttons
            .matching(NSPredicate(format: "label BEGINSWITH %@", "shell"))
            .firstMatch
        if shellTab.waitForExistence(timeout: 5) {
            shellTab.tap()
            // The stream overlay clears once the data socket's welcome lands.
            let overlay = app.staticTexts["Opening stream…"]
            if overlay.exists {
                expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: overlay)
                waitForExpectations(timeout: 20)
            }
            snapshot("05-single-pane-window")
            XCTAssertTrue(paneMenu.waitForExistence(timeout: 10), "pane vanished after switching windows")
        }

        // 7. New window: the server makes it active and the phone follows.
        let panes = app.buttons.matching(identifier: "paneMenuButton")
        let phoneTabs = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "phone"))
        let tabsBefore = phoneTabs.count
        app.buttons["newWindowChip"].tap()
        XCTAssertTrue(waitUntil(timeout: 20) { phoneTabs.count == tabsBefore + 1 },
                      "new window did not add a tab")
        XCTAssertTrue(waitUntil(timeout: 20) { panes.count == 1 },
                      "the phone did not follow the newly active window")
        snapshot("06-new-window")

        // 8. Split that pane to the right.
        panes.firstMatch.tap()
        let splitRight = app.buttons["Split right"]
        XCTAssertTrue(splitRight.waitForExistence(timeout: 5), "pane menu did not open")
        splitRight.tap()
        XCTAssertTrue(waitUntil(timeout: 20) { panes.count == 2 }, "split did not add a pane")
        snapshot("07-split-right")

        // 9. Zoom the focused pane.
        app.buttons["zoomPaneButton"].firstMatch.tap()
        XCTAssertTrue(waitUntil(timeout: 10) { panes.count == 1 }, "zoom did not collapse to one pane")
        snapshot("08-zoomed")

        // 10. Input still lands in the zoomed pane.
        focus(compose)
        compose.typeText("echo ZOOM-$((2+3))")
        app.buttons["sendButton"].tap()
        XCTAssertTrue(waitUntil(timeout: 10) { panes.count == 1 })
        snapshot("09-zoom-input")

        // 11. Close the window again, leaving the server as we found it.
        let phoneTab = phoneTabs.firstMatch
        phoneTab.press(forDuration: 1.0)
        let closeWindow = app.buttons["Close window"]
        XCTAssertTrue(closeWindow.waitForExistence(timeout: 5), "tab context menu did not open")
        closeWindow.tap()
        XCTAssertTrue(waitUntil(timeout: 20) { phoneTabs.count == tabsBefore }, "window was not closed")
        snapshot("10-window-closed")
    }

    /// The pairing sheet has to work on hardware without a camera too, so the
    /// pasted-address path is what CI and the simulator exercise.
    func testPairingSheetAcceptsPastedAddress() throws {
        let app = launchedApp()

        let scan = app.buttons["scanButton"]
        XCTAssertTrue(scan.waitForExistence(timeout: 20), "scan button missing")
        scan.tap()

        let field = app.textFields["pairAddressField"]
        XCTAssertTrue(field.waitForExistence(timeout: 10), "pairing sheet never appeared")
        snapshot("13-pair-sheet")

        focus(field)
        field.typeText("rex-abc.tail1234.ts.net")
        app.buttons["pairUseButton"].tap()

        let address = app.textFields["serverAddressField"]
        let applied = waitUntil(timeout: 8) {
            (address.value as? String) == "rex-abc.tail1234.ts.net"
        }
        snapshot("14-pair-applied")
        XCTAssertTrue(applied, "pasted address was not applied: \(String(describing: address.value))")
    }

    /// Taps a text field and lets focus settle; typing into a field that is
    /// still becoming first responder drops the first keystroke.
    private func focus(_ element: XCUIElement) {
        element.tap()
        let deadline = Date().addingTimeInterval(1.0)
        while Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
            if element.value != nil { break }
        }
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))
    }

    /// Polls a condition, since XCUITest has no built-in wait-for-property.
    private func waitUntil(timeout: TimeInterval, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        return condition()
    }

    /// Screenshots land in the runner's Documents directory so the machine can pull them.
    private func snapshot(_ name: String) {
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)

        let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let url = directory.appendingPathComponent("\(name).png")
        try? screenshot.pngRepresentation.write(to: url)
    }
}
