import XCTest
@testable import RexRemote

/// Replays a real `/api/data` capture: the Ghostty snapshot, the Rex `resize`
/// and `theme` directives, then the shell's own output. Chunk boundaries are
/// varied because every bug so far showed up only for some chunk sizes.
final class StreamReplayTests: XCTestCase {
    private static let fixtureBase64 =
        "R0hPU1RTTlABAAEAlwMAABG4SWo9ADEAAQUAAHcHAAAAADAAAAA8AAAAAAEAcwAAAAEBAQEAAAAACAAEIgBk" +
        "EAAAAAQiAGQAAAAABCIAZAAAAAAB+/PdAAAAAAFNPzMAAAAAAdFgPQAAAAAAAAAEAAAAAP//////////AAEB" +
        "AQEBAQFNPzPIQy9cijysfBQ/dKiiU4w4hXrs38KKemjgVT9vokrHkyBQib+5aKJHnpH//PIAAAAAAF8AAIcA" +
        "AK8AANcAAP8AXwAAX18AX4cAX68AX9cAX/8AhwAAh18Ah4cAh68Ah9cAh/8ArwAAr18Ar4cAr68Ar9cAr/8A" +
        "1wAA118A14cA168A19cA1/8A/wAA/18A/4cA/68A/9cA//9fAABfAF9fAIdfAK9fANdfAP9fXwBfX19fX4df" +
        "X69fX9dfX/9fhwBfh19fh4dfh69fh9dfh/9frwBfr19fr4dfr69fr9dfr/9f1wBf119f14df169f19df1/9f" +
        "/wBf/19f/4df/69f/9df//+HAACHAF+HAIeHAK+HANeHAP+HXwCHX1+HX4eHX6+HX9eHX/+HhwCHh1+Hh4eH" +
        "h6+Hh9eHh/+HrwCHr1+Hr4eHr6+Hr9eHr/+H1wCH11+H14eH16+H19eH1/+H/wCH/1+H/4eH/6+H/9eH//+v" +
        "AACvAF+vAIevAK+vANevAP+vXwCvX1+vX4evX6+vX9evX/+vhwCvh1+vh4evh6+vh9evh/+vrwCvr1+vr4ev" +
        "r6+vr9evr/+v1wCv11+v14ev16+v19ev1/+v/wCv/1+v/4ev/6+v/9ev///XAADXAF/XAIfXAK/XANfXAP/X" +
        "XwDXX1/XX4fXX6/XX9fXX//XhwDXh1/Xh4fXh6/Xh9fXh//XrwDXr1/Xr4fXr6/Xr9fXr//X1wDX11/X14fX" +
        "16/X19fX1//X/wDX/1/X/4fX/6/X/9fX////AAD/AF//AIf/AK//ANf/AP//XwD/X1//X4f/X6//X9f/X///" +
        "hwD/h1//h4f/h6//h9f/h///rwD/r1//r4f/r6//r9f/r///1wD/11//14f/16//19f/1////wD//1///4f/" +
        "/6///9f///8ICAgSEhIcHBwmJiYwMDA6OjpEREROTk5YWFhiYmJsbGx2dnaAgICKioqUlJSenp6oqKiysrK8" +
        "vLzGxsbQ0NDa2trk5OTu7u4AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAgA2AAAA" +
        "rZyyFQAAAgAAAAAAAAAAABoAAQABAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAgAAAAAAAAAAAAAAAAAAAMA8gAA" +
        "ALbX2SE9AC8AAAAAAIAAwAAAIAAAAAgAAAAzAExhc3QgbG9naW46IFR1ZSBOb3YgMTAgMjE6NTc6MjcgZnJv" +
        "bSAxOTIuMTY4LjEwMC41MAAaAGZheWVARmF5ZWRlTWFjLU1pbmkgfiAlIGxzAAAAAAAAAAAAAAAAAAAAAAAA" +
        "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA" +
        "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAMAHgAA" +
        "ANhkMAY9AAIAAAAAAIAAwAAAIAAAAAgAAAAAAAAAAAAAAAAHAAAAAAAngGPRBQAAAAAA5CDvCgQABgAAAKER" +
        "il4AAAAAAAAGAAAAAAA+61M+G19yZXgxOzE3Nzc0MjE3MzM2MjMzMTM1NTczO3sidHlwZSI6InJlc2l6ZSIs" +
        "ImNvbHMiOjYxLCJyb3dzIjo0OSwiY2VsbF93aWR0aF9weCI6MjEsImNlbGxfaGVpZ2h0X3B4IjozOSwib3du" +
        "ZXIiOm51bGx9G1wbX3JleDE7MTc3NzQyMTczMzYyMzMxMzU1NzM7eyJ0eXBlIjoidGhlbWUiLCJmb3JlZ3Jv" +
        "dW5kIjoiIzREM0YzMyIsImJhY2tncm91bmQiOiIjRkJGM0REIiwiY3Vyc29yIjoiI0QxNjAzRCIsInBhbGV0" +
        "dGUiOlsiMD0jNEQzRjMzIiwiMT0jQzg0MzJGIiwiMj0jNUM4QTNDIiwiMz0jQUM3QzE0IiwiND0jM0Y3NEE4" +
        "IiwiNT0jQTI1MzhDIiwiNj0jMzg4NTdBIiwiNz0jRUNERkMyIiwiOD0jOEE3QTY4IiwiOT0jRTA1NTNGIiwi" +
        "MTA9IzZGQTI0QSIsIjExPSNDNzkzMjAiLCIxMj0jNTA4OUJGIiwiMTM9I0I5NjhBMiIsIjE0PSM0NzlFOTEi" +
        "LCIxNT0jRkZGQ0YyIl0sInNjaGVtZSI6ImxpZ2h0In0bXGVjaG8gcmVwbGF5LTEbWz8yMDA0bA0NCnpzaDog" +
        "Y29tbWFuZCBub3QgZm91bmQ6IGxzZWNobw0KG1sxbRtbN20lG1syN20bWzFtG1swbSAgICAgICAgICAgICAg" +
        "ICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIA0gDQ0bWzBtG1syN20bWzI0" +
        "bRtbSmZheWVARmF5ZWRlTWFjLU1pbmkgfiAlIBtbSxtbPzIwMDRo"

    private func fixture() -> [UInt8] {
        [UInt8](Data(base64Encoded: Self.fixtureBase64) ?? Data())
    }

    /// The nonce lives in the directive header: `ESC _ rex1;<nonce>;{json} ESC \`.
    private func nonce(in bytes: [UInt8]) throws -> String {
        let marker = RexStreamParser.markerPrefix
        guard let start = RexStreamParser.find(marker, in: bytes) else {
            throw XCTSkip("fixture has no directive")
        }
        var digits: [UInt8] = []
        var index = start + marker.count
        while index < bytes.count, bytes[index] != UInt8(ascii: ";") {
            digits.append(bytes[index])
            index += 1
        }
        return String(decoding: digits, as: UTF8.self)
    }

    /// What a data connection hands to the parser: everything from the first
    /// directive on, because the leading binary snapshot is dropped.
    private func afterSnapshot(_ bytes: [UInt8]) -> [UInt8] {
        guard let start = RexStreamParser.find(RexStreamParser.markerPrefix, in: bytes) else {
            return []
        }
        return Array(bytes[start...])
    }

    private func replay(chunk: Int) throws -> (plain: [UInt8], parser: RexStreamParser) {
        let bytes = fixture()
        let stream = afterSnapshot(bytes)
        var parser = RexStreamParser(nonce: try nonce(in: bytes))
        var plain: [UInt8] = []
        var index = 0
        while index < stream.count {
            let end = min(index + chunk, stream.count)
            parser.feed(Array(stream[index..<end])) { plain.append(contentsOf: $0) }
            index = end
        }
        return (plain, parser)
    }

    func testSnapshotIsDroppedAndDirectivesAreParsed() throws {
        let bytes = fixture()
        XCTAssertEqual(Array(bytes.prefix(8)), Array("GHOSTSNP".utf8))

        let (plain, parser) = try replay(chunk: 4096)
        XCTAssertFalse(plain.isEmpty, "nothing was emitted")
        let text = String(decoding: plain, as: UTF8.self)
        XCTAssertFalse(text.contains("rex1;"), "a directive leaked as text")
        XCTAssertFalse(text.contains("\"palette\""), "a directive body leaked as text")
        XCTAssertTrue(text.contains("echo replay-1"), text.debugDescription)

        let names = parser.directives.map(\.type)
        XCTAssertTrue(names.contains("resize"), "\(names)")
        XCTAssertTrue(names.contains("theme"), "\(names)")
        let resize = parser.directives.first { $0.type == "resize" }
        XCTAssertEqual(resize?.body.int("cols"), 61)
        XCTAssertEqual(resize?.body.int("rows"), 49)
        let theme = parser.directives.first { $0.type == "theme" }
        XCTAssertNotNil(theme?.body.string("background"))
    }

    /// The old parser held back too little and printed half directives as text,
    /// which is what shredded the prompt on screen.
    func testEveryChunkSizeEmitsTheSameBytes() throws {
        let reference = try replay(chunk: 4096)
        let referenceText = String(decoding: reference.plain, as: UTF8.self)
        for chunk in [1, 2, 3, 5, 7, 13, 64, 500] {
            let (plain, parser) = try replay(chunk: chunk)
            let text = String(decoding: plain, as: UTF8.self)
            XCTAssertFalse(text.contains("rex1;"), "chunk \(chunk) leaked a directive")
            XCTAssertTrue(text.contains("echo replay-1"), "chunk \(chunk): \(text.debugDescription)")
            XCTAssertEqual(text, referenceText, "chunk \(chunk) produced different bytes")
            XCTAssertEqual(parser.directives.count, reference.parser.directives.count, "chunk \(chunk)")
        }
    }

    func testReplayRendersTheShellOutput() throws {
        let (plain, _) = try replay(chunk: 5)
        let session = GhosttySession(cols: 61, rows: 49, cellWidthPx: 21, cellHeightPx: 39)
        XCTAssertNotNil(session)
        session?.write(plain[...])
        let screen = session?.plainText() ?? ""
        XCTAssertTrue(screen.contains("echo replay-1"), screen.debugDescription)
    }
}
