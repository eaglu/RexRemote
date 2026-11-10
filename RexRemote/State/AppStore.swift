import Foundation
import UIKit

enum ConnectionState: Equatable {
    case disconnected(String?)
    case connecting
    case connected

    var isConnected: Bool { self == .connected }
}

/// App-wide Rex state: one control connection, the session list, the session
/// being viewed, and one terminal controller per visible block.
@MainActor
final class AppStore: ObservableObject {
    let hosts = HostStore()

    @Published private(set) var client: RexClient?
    @Published private(set) var connection: ConnectionState = .disconnected(nil)
    @Published private(set) var sessions: [SessionRef] = []
    @Published private(set) var serverRevision: String = ""
    @Published private(set) var view: SessionView?
    @Published var currentSessionID: String?
    @Published var errorMessage: String?
    @Published var focusedBlockID: String?
    @Published var localZoomBlockID: String?

    private var controllers: [String: TerminalController] = [:]
    private var viewRefreshTask: Task<Void, Never>?
    private var sessionRefreshTask: Task<Void, Never>?
    private var generation = 0
    private var keepaliveTask: Task<Void, Never>?

    var host: HostConfig { hosts.selected ?? .loopback }

    var activeWindow: WindowInfo? { view?.activeWindow }

    var shouldOwnTerminalSizing: Bool { host.autoSize }

    func controller(sessionID: String, blockID: String) -> TerminalController {
        if let existing = controllers[blockID] { return existing }
        let controller = TerminalController(sessionID: sessionID, blockID: blockID, store: self)
        controllers[blockID] = controller
        return controller
    }

    func controller(for blockID: String) -> TerminalController? { controllers[blockID] }

    /// Copy what libghostty has selected; the selection lives in its surface,
    /// not in a UIKit text view.
    func copySelection(blockID: String) {
        guard let text = controller(for: blockID)?.selectedText() else { return }
        UIPasteboard.general.string = text
    }

    func pasteClipboard(blockID: String) {
        guard let text = UIPasteboard.general.string, !text.isEmpty else { return }
        controller(for: blockID)?.paste(text)
    }

    // MARK: - Connection

    func connect() async {
        generation += 1
        let token = generation

        keepaliveTask?.cancel()
        keepaliveTask = nil
        client?.disconnect()
        for controller in controllers.values { controller.stop() }
        controllers.removeAll()
        view = nil
        sessions = []
        focusedBlockID = nil
        currentSessionID = nil
        errorMessage = nil
        connection = .connecting

        let host = self.host
        let client = RexClient(host: host)
        self.client = client
        client.onEvent = { [weak self] event in
            guard let self, self.generation == token else { return }
            self.handle(envelope: event)
        }
        client.onDisconnect = { [weak self] reason in
            guard let self, self.generation == token else { return }
            self.connection = .disconnected(reason)
        }

        do {
            _ = try await client.connect()
            guard generation == token else { return }
            serverRevision = "api \(RexProtocol.apiRevision)"
            let payload = try await client.call("session.bootstrap", ["event_scope": "all"])
            guard generation == token else { return }
            applyBootstrap(payload)
            connection = .connected
            startKeepalive(generation: token)
        } catch {
            guard generation == token else { return }
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            connection = .disconnected(message)
            errorMessage = message
        }
    }

    /// Cloudflare closes WebSockets that stay quiet for about a minute and the
    /// server's own ping is every 120s, so a connected app nudges the socket.
    private func startKeepalive(generation token: Int) {
        keepaliveTask?.cancel()
        keepaliveTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 45_000_000_000)
                guard let self else { return }
                guard self.generation == token, self.connection.isConnected else { return }
                _ = try? await self.client?.call("session.list", nil)
            }
        }
    }

    func disconnect() {
        keepaliveTask?.cancel()
        keepaliveTask = nil
        generation += 1
        client?.disconnect()
        client = nil
        connection = .disconnected(nil)
        for controller in controllers.values { controller.stop() }
        controllers.removeAll()
        view = nil
    }

    private func applyBootstrap(_ payload: JSONObject) {
        let attachAll = payload.object("attach_all")
        let list = attachAll?.objects("sessions") ?? []
        sessions = list.compactMap(SessionRef.init)
        if sessions.isEmpty { sessions = payload.objects("attached_sessions").compactMap(SessionRef.init) }

        if let session = payload.object("selected_session") {
            if let viewJSON = session.object("view"), let parsed = SessionView(viewJSON) {
                view = parsed
                currentSessionID = parsed.id
            }
            focusedBlockID = view?.activeWindow?.focusedBlockID
        } else if let first = sessions.first {
            Task { await openSession(first.id) }
        }
    }

    // MARK: - Sessions and views

    func openSession(_ sessionID: String) async {
        guard let client else { return }
        if currentSessionID == sessionID, view != nil { return }
        do {
            let payload = try await client.call("session.attach", ["session_id": sessionID, "event_scope": "all"])
            currentSessionID = sessionID
            applyViewPayload(payload)
            localZoomBlockID = nil
        } catch {
            report(error)
        }
    }

    func refreshView() async {
        guard let client, let sessionID = currentSessionID else { return }
        do {
            let payload = try await client.call("session.view", ["session_id": sessionID])
            applyViewPayload(payload)
        } catch {
            report(error)
        }
    }

    func refreshSessions() async {
        guard let client else { return }
        do {
            let payload = try await client.call("session.list", [:])
            sessions = payload.objects("sessions").compactMap(SessionRef.init)
        } catch {
            report(error)
        }
    }

    private func applyViewPayload(_ payload: JSONObject) {
        let viewJSON = payload.object("view") ?? payload
        guard let parsed = SessionView(viewJSON) else { return }
        if let existing = view, existing.id == parsed.id, existing.revision > parsed.revision {
            return
        }
        view = parsed
        focusedBlockID = parsed.activeWindow?.focusedBlockID ?? parsed.activeWindow?.panes.first?.id
        let live = Set(parsed.allBlocks.map(\.id))
        if let zoomed = localZoomBlockID, !live.contains(zoomed) { localZoomBlockID = nil }
        pruneControllers(keeping: live)
    }

    private func pruneControllers(keeping live: Set<String>) {
        for (blockID, controller) in controllers where !live.contains(blockID) {
            controller.stop()
            controllers.removeValue(forKey: blockID)
        }
    }

    private func handle(envelope: JSONObject) {
        let payload = envelope.object("payload") ?? [:]
        switch payload.string("type") {
        case "session_event":
            handleSessionEvent(sessionID: payload.string("session_id"), event: payload.object("event") ?? [:])
        case "session_created", "session_destroyed", "session_moved":
            scheduleSessionRefresh()
            if payload.string("type") == "session_destroyed",
               let destroyed = payload.object("payload")?.string("session_id") ?? payload.string("session_id"),
               destroyed == currentSessionID {
                view = nil
                currentSessionID = nil
            }
        case "resumed":
            Task {
                await refreshSessions()
                await refreshView()
            }
        default:
            break
        }
    }

    private func handleSessionEvent(sessionID: String?, event: JSONObject) {
        let type = event.string("type") ?? ""
        switch type {
        case "session_view_changed":
            let revision = event.object("payload")?.int("revision") ?? 0
            guard sessionID == currentSessionID else { return }
            guard revision > (view?.revision ?? -1) else { return }
            scheduleViewRefresh()
        case "active_window_changed", "window_created", "window_closed", "window_label_changed":
            guard sessionID == currentSessionID else { return }
            scheduleViewRefresh()
        case "session_label_changed":
            if let label = event.object("payload")?.string("label"), let sessionID,
               let index = sessions.firstIndex(where: { $0.id == sessionID }) {
                sessions[index].label = label
            }
        case "block_owner_changed", "block_created", "block_closed":
            guard sessionID == currentSessionID else { return }
            scheduleViewRefresh()
        default:
            break
        }
    }

    private func scheduleViewRefresh() {
        viewRefreshTask?.cancel()
        viewRefreshTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 60_000_000)
            guard !Task.isCancelled else { return }
            await self?.refreshView()
        }
    }

    private func scheduleSessionRefresh() {
        sessionRefreshTask?.cancel()
        sessionRefreshTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 120_000_000)
            guard !Task.isCancelled else { return }
            await self?.refreshSessions()
        }
    }

    // MARK: - Session actions

    func newWindow(label: String = "phone") async {
        guard let client, let sessionID = currentSessionID else { return }
        do {
            _ = try await client.call("session.new_window", [
                "session_id": sessionID,
                "window_label": label,
                "layout": ["block": ["flavor": "com.superlogical.terminal.shell"]],
                "focus": true
            ])
            await refreshView()
        } catch {
            report(error)
        }
    }

    func split(blockID: String, direction: String) async {
        guard let client, let sessionID = currentSessionID else { return }
        do {
            _ = try await client.call("session.new_split", [
                "session_id": sessionID,
                "anchor_id": blockID,
                "direction": direction,
                "side": "after",
                "ratio": 0.5,
                "layout": ["block": ["flavor": "com.superlogical.terminal.shell"]],
                "focus": true
            ])
            await refreshView()
        } catch {
            report(error)
        }
    }

    func closeBlock(_ blockID: String) async {
        guard let client, let sessionID = currentSessionID else { return }
        do {
            _ = try await client.call("block.close", ["session_id": sessionID, "block_id": blockID])
            await refreshView()
        } catch {
            report(error)
        }
    }

    func closeWindow(_ windowID: String) async {
        guard let client, let sessionID = currentSessionID else { return }
        do {
            _ = try await client.call("session.close_window", ["session_id": sessionID, "window_id": windowID])
            await refreshView()
        } catch {
            report(error)
        }
    }

    func focus(blockID: String) async {
        focusedBlockID = blockID
        guard let client, let sessionID = currentSessionID else { return }
        do {
            _ = try await client.call("session.focus_block", ["session_id": sessionID, "block_id": blockID])
        } catch {
            // Focusing is cosmetic; a failure only means the server disagrees.
        }
    }

    func renameSession(_ sessionID: String, label: String) async {
        guard let client else { return }
        do {
            _ = try await client.call("session.set_label", ["session_id": sessionID, "label": label])
        } catch {
            report(error)
        }
    }

    func renameWindow(_ windowID: String, label: String) async {
        guard let client, let sessionID = currentSessionID else { return }
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        do {
            _ = try await client.call("session.set_window_label", [
                "session_id": sessionID,
                "window_id": windowID,
                "label": trimmed
            ])
            await refreshView()
        } catch {
            report(error)
        }
    }

    func toggleZoom(blockID: String) {
        localZoomBlockID = localZoomBlockID == blockID ? nil : blockID
    }

    // MARK: - Terminal plumbing

    func authHeaders() -> [(name: String, value: String)] {
        guard let token = host.token, !token.isEmpty else { return [] }
        return [(name: "Authorization", value: "Bearer \(token)")]
    }

    func requestTerminalTicket(sessionID: String, blockID: String) async throws -> String {
        guard let client else { throw RexError(code: "closed", message: "Not connected") }
        let payload = try await client.call("data.connect", [
            "session_id": sessionID,
            "block_id": blockID,
            "data_ref_id": "terminal",
            "subprotocol": RexProtocol.terminalSubprotocol
        ])
        guard let ticket = payload.string("ticket") else {
            throw RexError(code: "bad_response", message: "The server sent no stream ticket.")
        }
        return ticket
    }

    /// `terminal.format` with `format: vt` renders the current screen as escape
    /// sequences, which is how the app primes a freshly opened terminal.
    func screenDump(sessionID: String, blockID: String) async throws -> String {
        guard let client else { throw RexError(code: "closed", message: "Not connected") }
        let payload = try await client.call(blockMethod("format", blockID: blockID), [
            "session_id": sessionID,
            "block_id": blockID,
            "args": ["format": "vt", "trim": true, "unwrap": true]
        ])
        if let content = payload.string("content") { return content }
        if let blob = payload.string("id") ?? payload.string("blob_id") {
            let read = try await client.call(blockMethod("blob_read", blockID: blockID), [
                "session_id": sessionID,
                "block_id": blockID,
                "args": ["blob_id": blob]
            ])
            if let text = read.string("content") { return text }
            if let base64 = read.string("base64"), let data = Data(base64Encoded: base64) {
                return String(decoding: data, as: UTF8.self)
            }
        }
        return ""
    }

    func write(_ text: String, sessionID: String, blockID: String) async {
        guard let client else { return }
        do {
            _ = try await client.call(blockMethod("write", blockID: blockID), [
                "session_id": sessionID,
                "block_id": blockID,
                "args": ["data": text]
            ])
        } catch {
            report(error)
        }
    }

    func write(bytes: [UInt8], sessionID: String, blockID: String) async {
        await write(String(decoding: bytes, as: UTF8.self), sessionID: sessionID, blockID: blockID)
    }

    func resizeTerminal(
        sessionID: String,
        blockID: String,
        cols: Int,
        rows: Int,
        cellWidthPx: Int = 0,
        cellHeightPx: Int = 0
    ) async {
        guard let client else { return }
        do {
            _ = try await client.call("session.own_block", [
                "session_id": sessionID,
                "block_ids": [blockID],
                "mode": "take"
            ])
            var args: JSONObject = ["columns": cols, "rows": rows]
            // Cell metrics keep wrapping identical to what the pane draws; the
            // server ignores them when it has nothing to say about them.
            if cellWidthPx > 0 { args["cell_width_px"] = cellWidthPx }
            if cellHeightPx > 0 { args["cell_height_px"] = cellHeightPx }
            _ = try await client.call(blockMethod("resize", blockID: blockID), [
                "session_id": sessionID,
                "block_id": blockID,
                "args": args
            ])
        } catch {
            // A non-owner cannot resize; that is a normal, quiet failure.
        }
    }

    func paste(_ text: String, sessionID: String, blockID: String) async {
        await write(text, sessionID: sessionID, blockID: blockID)
    }

    // MARK: - Helpers

    private func blockMethod(_ method: String, blockID: String) -> String {
        let creator = view?.allBlocks.first { $0.id == blockID }?.creator
        let prefix = creator.flatMap { $0.isEmpty ? nil : $0 } ?? "com.superlogical.terminal"
        return "\(prefix).\(method)"
    }

    private func report(_ error: Error) {
        errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}
