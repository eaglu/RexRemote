import XCTest
@testable import RexRemote

/// The layout tree is the only place the app learns which two blocks a border
/// separates, so the drag handle depends on this parsing being right.
final class LayoutModelTests: XCTestCase {
    private func viewJSON(floating: Bool = false) -> JSONObject {
        var layers: [JSONObject] = [
            [
                "layer_id": "layer:tiled",
                "kind": "tiled",
                "bounds": [0, 0, 1, 1],
                "blocks": [
                    ["block_id": "block:a", "label": "left", "flavor": "com.superlogical.terminal.shell"],
                    ["block_id": "block:b", "label": "right", "flavor": "com.superlogical.terminal.shell"]
                ],
                "layout": [
                    "rect": [0, 0, 1, 1],
                    "split": [
                        "split_id": "split:one",
                        "direction": "horizontal",
                        "ratio": 0.6,
                        "before": ["rect": [0, 0, 0.6, 1], "block_id": "block:a"],
                        "after": ["rect": [0.6, 0, 0.4, 1], "block_id": "block:b"]
                    ]
                ]
            ]
        ]
        if floating {
            layers.append([
                "layer_id": "layer:float",
                "kind": "floating",
                "state": "minimized",
                "bounds": [0.1, 0.1, 0.5, 0.4],
                "blocks": [["block_id": "block:c", "label": "float", "flavor": "com.superlogical.terminal.shell"]],
                "layout": ["rect": [0, 0, 1, 1], "block_id": "block:c"]
            ])
        }
        return [
            "session_id": "session:test",
            "revision": 7,
            "label": "test",
            "active_window_id": "window:test",
            "windows": [[
                "window_id": "window:test",
                "label": "shell",
                "focused_block_id": "block:a",
                "layers": layers
            ]]
        ]
    }

    func testSplitBecomesADraggableDivider() throws {
        let view = try XCTUnwrap(SessionView(viewJSON()))
        let divider = try XCTUnwrap(view.allDividers.first)

        XCTAssertEqual(divider.id, "split:one")
        XCTAssertEqual(divider.direction, "horizontal")
        XCTAssertEqual(divider.ratio, 0.6, accuracy: 0.0001)
        XCTAssertEqual(divider.beforeBlockID, "block:a")
        XCTAssertEqual(divider.afterBlockID, "block:b")
        XCTAssertEqual(divider.rect.width, 1, accuracy: 0.0001)
    }

    func testDividerIsFoundFromEitherSide() throws {
        let view = try XCTUnwrap(SessionView(viewJSON()))

        XCTAssertEqual(view.divider(around: "block:a", direction: nil)?.id, "split:one")
        XCTAssertEqual(view.divider(around: "block:b", direction: "horizontal")?.id, "split:one")
        XCTAssertNil(view.divider(around: "block:b", direction: "vertical"))
        XCTAssertNil(view.divider(around: "block:missing", direction: nil))
    }

    func testFloatingLayersAreReportedSeparately() throws {
        let view = try XCTUnwrap(SessionView(viewJSON(floating: true)))
        let window = try XCTUnwrap(view.activeWindow)

        XCTAssertEqual(window.layers.count, 2)
        XCTAssertEqual(window.floatingLayers.count, 1)
        XCTAssertEqual(window.floatingLayers.first?.state, "minimized")
        XCTAssertTrue(window.floatingLayers.first?.isMinimized == true)
        // A floating pane still draws; it is just not part of the tiled split.
        XCTAssertEqual(window.panes.count, 3)
        XCTAssertEqual(window.dividers.count, 1)
    }

    func testServerInfoReadsTailscaleState() throws {
        let info = ServerInfo([
            "pid": 4242,
            "instance_id": "instance:1",
            "session_count": 3,
            "api_revision": 11,
            "tailscale": ["state": "running"]
        ])

        XCTAssertEqual(info.pid, 4242)
        XCTAssertEqual(info.sessionCount, 3)
        XCTAssertEqual(info.tailscale, "running")
    }
}
