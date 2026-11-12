import Foundation

// Everything the phone never called before: layout surgery, keyboard
// navigation, session administration, server introspection and the terminal
// block methods. The UI stays thin — it asks for one of these.
extension SessionViewModel {
    // MARK: - Layout

    /// Drag a border. `ratio` is the share the block before the border keeps.
    func resizeSplit(_ divider: SplitDivider, ratio: Double) async {
        let clamped = min(max(ratio, 0.08), 0.92)
        await perform("session.resize_pane", [
            "direction": divider.direction,
            "before_block_id": divider.beforeBlockID,
            "after_block_id": divider.afterBlockID,
            "ratio": clamped
        ])
    }

    /// The server's own zoom, so the Mac and the phone agree on what is zoomed.
    func zoomOnServer(blockID: String, zoom: Bool) async {
        localZoomBlockID = nil
        await perform("session.zoom_block", ["block_id": blockID, "zoom": zoom])
    }

    func swapBlocks(_ blockID: String, with otherID: String) async {
        await perform("session.swap_blocks", ["block_id": blockID, "other_block_id": otherID])
    }

    func moveBlock(_ blockID: String, to anchorID: String, direction: String, side: String, ratio: Double = 0.5) async {
        await perform("session.move_block", [
            "block_id": blockID,
            "anchor_block_id": anchorID,
            "direction": direction,
            "side": side,
            "ratio": ratio
        ])
    }

    func moveWindow(_ windowID: String, before otherID: String) async {
        await perform("session.move_window", ["window_id": windowID, "before_window_id": otherID])
    }

    /// A block created outside any layout, then placed next to `anchorID`.
    /// A block with nothing to anchor to — used by an empty window's call to
    /// action, where there is no sibling to split.
    func createBlock() async {
        _ = await perform("session.new_block", [
            "flavor": "com.superlogical.terminal.shell",
            "label": "pane"
        ])
    }

    func newBlock(beside anchorID: String, direction: String) async {
        guard let created = await perform("session.new_block", [
            "flavor": "com.superlogical.terminal.shell",
            "label": "pane"
        ]), let blockID = created.string("block_id") else { return }
        await moveBlock(blockID, to: anchorID, direction: direction, side: "after")
    }

    // MARK: - Floating layers

    func floatBlock(_ blockID: String) async {
        await perform("session.float_block", [
            "block_id": blockID,
            "bounds": [0.08, 0.1, 0.84, 0.62]
        ])
    }

    func newFloatingLayer() async {
        await perform("session.new_layer", [
            "bounds": [0.08, 0.1, 0.84, 0.62],
            "layout": ["block": ["flavor": "com.superlogical.terminal.shell"]],
            "focus": true
        ])
    }

    func setLayerState(_ layerID: String, state: String) async {
        await perform("session.set_layer_state", ["layer_id": layerID, "state": state, "focus": true])
    }

    func raiseLayer(_ layerID: String) async {
        await perform("session.raise_layer", ["layer_id": layerID])
    }

    func lowerLayer(_ layerID: String) async {
        await perform("session.lower_layer", ["layer_id": layerID])
    }

    func resizeLayer(_ layerID: String, bounds: [Double]) async {
        await perform("session.resize_layer", ["layer_id": layerID, "bounds": bounds])
    }

    func closeLayer(_ layerID: String) async {
        await perform("session.close_layer", ["layer_id": layerID])
    }

    // MARK: - Focus

    func focusDirection(_ direction: String) async {
        await perform("session.focus_direction", ["direction": direction, "wrap": true])
    }

    func focusStep(forward: Bool, pane: Bool) async {
        let method: String
        if pane {
            method = forward ? "session.focus_next_pane" : "session.focus_previous_pane"
        } else {
            method = forward ? "session.focus_next_window" : "session.focus_previous_window"
        }
        await perform(method, ["wrap": true])
    }

    func focusWindow(_ windowID: String) async {
        await perform("session.focus_window", ["window_id": windowID])
    }

    // MARK: - Session administration

    @discardableResult
    func createSession(label: String) async -> String? {
        guard let payload = await perform("session.create", [
            "label": label,
            "initial_windows": [["layout": ["block": ["flavor": "com.superlogical.terminal.shell"]]]]
        ]) else { return nil }
        await refreshSessions()
        return payload.string("session_id")
    }

    func destroySession(_ sessionID: String) async {
        guard let client else { return }
        do {
            _ = try await client.call("session.destroy", ["session_id": sessionID])
            if currentSessionID == sessionID { currentSessionID = nil }
            await refreshSessions()
        } catch {
            report(error)
        }
    }

    func renameBlock(_ blockID: String, label: String) async {
        await perform("session.set_block_label", ["block_id": blockID, "label": label])
    }

    func detachSession() async {
        guard let sessionID = currentSessionID else { return }
        _ = await perform("session.detach", ["session_id": sessionID])
        currentSessionID = nil
    }

    func attachAllSessions() async {
        await perform("session.attach_all", ["event_scope": "all"])
        await refreshSessions()
    }

    func moveSession(_ sessionID: String, before otherID: String) async {
        await perform("session.move", ["session_id": sessionID, "before_session_id": otherID])
        await refreshSessions()
    }

    /// Every block in the session, including ones no window holds.
    func listBlocks() async -> [BlockInfo] {
        guard let payload = await perform("session.list_blocks", [:]) else { return [] }
        return payload.objects("blocks").compactMap(BlockInfo.init)
    }

    func describeBlock(_ blockID: String) async -> JSONObject? {
        await perform("session.describe_block", ["block_id": blockID])
    }

    func sessionHelp() async -> String? {
        guard let payload = await perform("session.help", [:]) else { return nil }
        return try? JSONCoding.text(payload)
    }

    // MARK: - Server and hosts

    // MARK: - Terminal block methods

    func terminalInfo(_ method: String, blockID: String) async -> JSONObject? {
        await performBlock(method, blockID: blockID, [:])
    }

    func clearBlock(_ blockID: String) async {
        _ = await performBlock("clear", blockID: blockID, [:])
    }

    func resetBlock(_ blockID: String) async {
        _ = await performBlock("reset", blockID: blockID, [:])
    }

    /// The Mac's clipboard, which the phone cannot read any other way.
    func readRemoteClipboard(blockID: String, maxBytes: Int = 64 * 1024) async -> String? {
        guard let first = await performBlock("clipboard_read", blockID: blockID, [
            "max_bytes": maxBytes
        ]) else { return nil }
        if let text = first.string("content"), !text.isEmpty { return text }
        guard let id = first.int("id") else { return nil }
        guard let rest = await performBlock("blob_read", blockID: blockID, [
            "id": id,
            "offset": 0,
            "max_bytes": maxBytes
        ]) else { return nil }
        return rest.string("content")
    }

    func listDirectory(blockID: String, path: String, prefix: String = "") async -> [String] {
        guard let payload = await performBlock("list_dir", blockID: blockID, [
            "path": path,
            "prefix": prefix,
            "limit": 200
        ]) else { return [] }
        return payload.strings("matches").isEmpty ? payload.strings("entries") : payload.strings("matches")
    }

    /// A theme change for one block, so a phone can make a pane easier to read
    /// without touching the Mac's configuration.
    func setBlockTheme(blockID: String, foreground: String, background: String) async {
        _ = await performBlock("set_theme", blockID: blockID, [
            "foreground": foreground,
            "background": background,
            "scheme": "light"
        ])
    }

    // MARK: - Plumbing

    /// A block method needs both ids; forgetting `block_id` gets you
    /// `block_id is required`, which is how this helper came to exist.
    @discardableResult
    func performBlock(_ method: String, blockID: String, _ payload: JSONObject) async -> JSONObject? {
        guard let client, let sessionID = currentSessionID else { return nil }
        var body = payload
        body["session_id"] = sessionID
        body["block_id"] = blockID
        do {
            return try await client.call(blockMethod(method, blockID: blockID), body)
        } catch {
            report(error)
            return nil
        }
    }

    /// One session-scoped call, reporting failures instead of throwing so the
    /// callers stay linear.
    @discardableResult
    func perform(_ method: String, _ payload: JSONObject) async -> JSONObject? {
        guard let client, let sessionID = currentSessionID else { return nil }
        var body = payload
        body["session_id"] = sessionID
        do {
            let result = try await client.call(method, body)
            if method.hasPrefix("session.") || method.hasPrefix("block.") {
                await refreshView()
            }
            return result
        } catch {
            report(error)
            return nil
        }
    }
}
