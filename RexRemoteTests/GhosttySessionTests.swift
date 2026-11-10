import XCTest
@testable import RexRemote

final class GhosttySessionTests: XCTestCase {
    private func makeSession(cols: Int = 40, rows: Int = 10) throws -> GhosttySession {
        try XCTUnwrap(GhosttySession(cols: cols, rows: rows, cellWidthPx: 7, cellHeightPx: 14))
    }

    func testWritesBytesIntoTheGrid() throws {
        let session = try makeSession()
        session.write(Array("hello rex\r\nsecond".utf8)[...])
        let text = session.plainText()
        XCTAssertTrue(text.contains("hello rex"), "grid stayed empty: \(text)")
        XCTAssertTrue(text.contains("second"), "second line missing: \(text)")
    }

    func testFrameCarriesCellsAndCursor() throws {
        let session = try makeSession()
        session.write(Array("$ ls -l".utf8)[...])
        let frame = session.frame
        XCTAssertEqual(frame.rows.count, 10, "row count")
        XCTAssertEqual(frame.cols, 40, "col count")
        let row = frame.rows[0]
        let line = row.map(\.text).joined()
        XCTAssertTrue(line.hasPrefix("$ ls -l"), "row 0 was \(line)")
        XCTAssertTrue(frame.cursorVisible, "cursor hidden")
        XCTAssertEqual(frame.cursor?.x, 7)
    }

    func testResizeKeepsContent() throws {
        let session = try makeSession(cols: 40, rows: 10)
        session.write(Array("keep me".utf8)[...])
        session.resize(cols: 20, rows: 6, cellWidthPx: 7, cellHeightPx: 14)
        XCTAssertEqual(session.frame.cols, 20)
        XCTAssertEqual(session.frame.rows.count, 6)
        XCTAssertTrue(session.plainText().contains("keep me"))
    }

    func testColorsAreAppliedWithoutLosingText() throws {
        let session = try makeSession()
        let fg = GhosttySession.RGB(hex: "#38342E")!
        let bg = GhosttySession.RGB(hex: "#FAF8F3")!
        session.setColors(foreground: fg, background: bg, cursor: fg, palette: RexTheme.terminalPalette)
        session.write(Array("colored".utf8)[...])
        XCTAssertTrue(session.plainText().contains("colored"))
    }
}
