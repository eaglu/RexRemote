import XCTest
@testable import RexRemote

final class InputCompositionTests: XCTestCase {
    func testMarkedTextIsHeldUntilCommit() {
        let field = TerminalInputField()
        var committed: [String] = []
        field.onCommit = { committed.append($0) }

        field.becomeFirstResponder()
        field.setMarkedText("ni", selectedRange: NSRange(location: 2, length: 0))
        XCTAssertTrue(committed.isEmpty, "pre-edit text must not reach the pty")

        field.insertText("你")
        XCTAssertEqual(committed, ["你"])
        XCTAssertEqual(field.text, "", "the host view keeps no text of its own")
    }

    func testPlainTypingForwardsEachCommit() {
        let field = TerminalInputField()
        var committed: [String] = []
        field.onCommit = { committed.append($0) }
        field.becomeFirstResponder()
        for character in ["e", "c", "h", "o"] {
            field.insertText(character)
        }
        XCTAssertEqual(committed, ["e", "c", "h", "o"])
        XCTAssertEqual(field.text, "")
    }

    func testDeleteBackwardFallsBackToTheTerminal() {
        let field = TerminalInputField()
        var deletes = 0
        field.onDelete = { deletes += 1 }
        field.becomeFirstResponder()
        field.deleteBackward()
        XCTAssertEqual(deletes, 1)
    }

    func testCJKWritesLandOnTwoColumns() {
        let session = GhosttySession(cols: 20, rows: 3, cellWidthPx: 0, cellHeightPx: 0)
        session?.write(Array("你好".utf8)[...])
        guard let row = session?.frame.rows.first else { return XCTFail("no row") }
        XCTAssertEqual(row[0].text, "你")
        XCTAssertEqual(row[1].text, "", "wide characters are followed by a spacer cell")
        XCTAssertEqual(row[2].text, "好")
    }
}
