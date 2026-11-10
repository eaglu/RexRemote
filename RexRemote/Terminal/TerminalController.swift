import Foundation
import UIKit

/// Owns the live terminal stream for one block and mirrors it into a
/// `GhosttyGridView`. The stream starts with a Ghostty snapshot, which this class
/// skips in favor of a `terminal.format` VT dump so both paths agree.
@MainActor
final class TerminalController: NSObject, ObservableObject {
    enum Phase: Equatable {
        case idle
        case priming
        case live
        case failed(String)
    }

    let sessionID: String
    let blockID: String
    private unowned let store: AppStore

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var terminalTitle: String = ""
    @Published private(set) var gridSize: String = ""

    /// The terminal core. It exists before the view does so early bytes are kept.
    let terminal: GhosttySession?

    private weak var gridView: GhosttyGridView?
    private var themeApplied = false
    private var socket: WebSocketConnection?
    private var parser: RexStreamParser?
    private var gotWelcome = false
    private var snapshotSkipped = false
    private var snapshotTail: [UInt8] = []
    private var primed = false
    private var liveBuffer: [UInt8] = []
    private var reconnectToken: Data?
    private var bytesReceived: UInt64 = 0
    private var startTask: Task<Void, Never>?
    private var resizeTask: Task<Void, Never>?
    private var pendingInput: [UInt8] = []
    private var inputFlushTask: Task<Void, Never>?
    private var lastRequestedGrid: (cols: Int, rows: Int) = (0, 0)

    init(sessionID: String, blockID: String, store: AppStore) {
        self.sessionID = sessionID
        self.blockID = blockID
        self.store = store
        self.terminal = GhosttySession(cols: 80, rows: 24, cellWidthPx: 0, cellHeightPx: 0)
        super.init()
        // The core resolves every cell colour against its own defaults, so the
        // app's ink-on-paper palette has to be in place before the first byte or
        // the screen dump is drawn in the library's white-on-black default.
        self.terminal?.setColors(
            foreground: GhosttySession.RGB(hex: "#38342E") ?? GhosttySession.RGB.black,
            background: GhosttySession.RGB(hex: "#FAF8F3") ?? GhosttySession.RGB.black,
            cursor: GhosttySession.RGB(hex: "#38342E"),
            palette: RexTheme.terminalPalette
        )
    }

    // MARK: - View wiring

    func attach(_ view: GhosttyGridView) {
        gridView = view
        view.session = terminal
        view.onInput = { [weak self] bytes in
            self?.handleTyped(bytes)
        }
        view.onGridChange = { [weak self] cols, rows, cell in
            self?.handleGridChange(cols: cols, rows: rows, cellSize: cell)
        }
        if case .idle = phase {
            start()
        }
    }

    func start() {
        guard startTask == nil else { return }
        startTask = Task { [weak self] in
            await self?.primeAndOpen()
        }
    }

    func stop() {
        startTask?.cancel()
        startTask = nil
        resizeTask?.cancel()
        resizeTask = nil
        inputFlushTask?.cancel()
        inputFlushTask = nil
        pendingInput = []
        socket?.close()
        socket = nil
        phase = .idle
        primed = false
        gotWelcome = false
        snapshotSkipped = false
        snapshotTail = []
        liveBuffer = []
        parser = nil
    }

    /// Type into the shell the way the Mac app does: straight bytes.
    func type(_ text: String) {
        enqueue(Array(text.utf8))
    }

    func type(bytes: [UInt8]) {
        enqueue(bytes)
    }

    /// Keystrokes arrive faster than an RPC round trip, and every request is its
    /// own task, so sending them one by one lets them overtake each other and the
    /// shell sees the letters out of order. Coalesce a frame's worth of input
    /// into a single write instead.
    private func enqueue(_ bytes: [UInt8]) {
        guard !bytes.isEmpty else { return }
        pendingInput.append(contentsOf: bytes)
        guard inputFlushTask == nil else { return }
        inputFlushTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 8_000_000)
            guard let self else { return }
            let outgoing = self.pendingInput
            self.pendingInput = []
            self.inputFlushTask = nil
            guard !outgoing.isEmpty else { return }
            await self.store.write(bytes: outgoing, sessionID: self.sessionID, blockID: self.blockID)
        }
    }

    // MARK: - Startup

    private func primeAndOpen() async {
        phase = .priming
        do {
            // Ask for the stream ticket first so the server-side stream starts
            // right after we draw the screen dump; the dump then covers
            // everything up to the moment the socket goes live.
            let ticket = try await store.requestTerminalTicket(sessionID: sessionID, blockID: blockID)
            let dump = try await store.screenDump(sessionID: sessionID, blockID: blockID)
            // RIS clears whatever the core kept from an earlier attach before the
            // dump redraws the screen.
            feedToTerminal(Array("\u{1B}c".utf8))
            feedToTerminal(Array(dump.utf8))

            primed = true
            flushLiveBuffer()
            openSocket(ticket: ticket)
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            phase = .failed(message)
            startTask = nil
        }
    }

    private func openSocket(ticket: String) {
        let socket = WebSocketConnection()
        self.socket = socket
        gotWelcome = false
        snapshotSkipped = false
        snapshotTail = []
        liveBuffer = []
        parser = nil
        bytesReceived = 0

        socket.onOpen = { [weak socket] in
            guard let socket, let ticketBytes = Base64URL.decode(ticket) else { return }
            var hello = Data([0x01])
            hello.append(ticketBytes)
            socket.send(binary: hello)
        }
        socket.onMessage = { [weak self] message in
            guard case .binary(let data) = message else { return }
            self?.handleBinary(data)
        }
        socket.onClose = { [weak self] reason in
            self?.handleClose(reason)
        }

        do {
            socket.connect(
                url: try store.host.dataURL(),
                subprotocols: [RexProtocol.terminalSubprotocol],
                headers: store.authHeaders()
            )
        } catch {
            handleClose(error.localizedDescription)
        }
    }

    // MARK: - Inbound stream

    private func handleBinary(_ data: Data) {
        let bytes = [UInt8](data)
        if !gotWelcome {
            guard let opcode = bytes.first else { return }
            if opcode == 0x81, bytes.count >= 32 {
                gotWelcome = true
                reconnectToken = Data(bytes[1..<17])
                let nonce = Self.uint64(bytes, at: 21)
                parser = RexStreamParser(nonce: String(nonce))
                phase = .live
            } else if opcode == 0x82 {
                let reason = bytes.count > 1 ? bytes[1] : 0
                phase = .failed("Stream refused (code \(reason))")
                socket?.close()
            }
            return
        }
        bytesReceived += UInt64(bytes.count)
        ingest(bytes)
    }

    private func ingest(_ bytes: [UInt8]) {
        guard var parser else { return }
        var payload: [UInt8] = bytes
        if !snapshotSkipped {
            var buffer = snapshotTail + bytes
            if let index = RexStreamParser.find(RexStreamParser.markerPrefix, in: buffer) {
                buffer.removeFirst(index)
                snapshotSkipped = true
                snapshotTail = []
                payload = buffer
            } else {
                let keep = RexStreamParser.hasPartialSuffix(RexStreamParser.markerPrefix, in: buffer) ?? 0
                snapshotTail = keep > 0 ? Array(buffer.suffix(keep)) : []
                return
            }
        }
        parser.feed(payload) { [weak self] slice in
            self?.appendLive(Array(slice))
        }
        self.parser = parser
        applyDirectives(parser.directives)
    }

    private func appendLive(_ bytes: [UInt8]) {
        guard !bytes.isEmpty else { return }
        if primed {
            feedToTerminal(bytes)
        } else {
            liveBuffer.append(contentsOf: bytes)
        }
    }

    private func flushLiveBuffer() {
        guard !liveBuffer.isEmpty else { return }
        feedToTerminal(liveBuffer)
        liveBuffer.removeAll(keepingCapacity: true)
    }

    private func feedToTerminal(_ bytes: [UInt8]) {
        guard !bytes.isEmpty, let terminal else { return }
        terminal.write(bytes[...])

        gridView?.setNeedsDisplay()
    }

    private func applyDirectives(_ directives: [RexStreamParser.Directive]) {
        for directive in directives.suffix(1) {
            switch directive.type {
            case "resize":
                let cols = directive.body.int("columns") ?? directive.body.int("cols") ?? 0
                let rows = directive.body.int("rows") ?? 0
                if cols > 0, rows > 0 { gridSize = "\(cols)×\(rows)" }
            case "theme":
                applyTheme(directive.body)
            default:
                break
            }
        }
    }

    /// Rex sends the Mac app's theme with the stream, so the pane looks like the
    /// window on the Mac instead of a hard-coded palette.
    private func applyTheme(_ body: JSONObject) {
        guard let terminal else { return }
        let foreground = GhosttySession.RGB(hex: body.string("foreground")) ?? GhosttySession.RGB(hex: "#1F2328")!
        let background = GhosttySession.RGB(hex: body.string("background")) ?? GhosttySession.RGB(hex: "#FBFCFD")!
        let cursor = GhosttySession.RGB(hex: body.string("cursor"))
        let palette = body.strings("palette").compactMap { GhosttySession.RGB(hex: $0) }
        terminal.setColors(
            foreground: foreground,
            background: background,
            cursor: cursor,
            palette: palette
        )
        themeApplied = true
        gridView?.theme = GhosttyGridView.Theme(
            background: Self.uiColor(background),
            foreground: Self.uiColor(foreground),
            cursor: Self.uiColor(cursor ?? foreground),
            palette: palette.map(Self.uiColor)
        )
        gridView?.setNeedsDisplay()
    }

    private static func uiColor(_ rgb: GhosttySession.RGB) -> UIColor {
        UIColor(
            red: CGFloat(rgb.red) / 255,
            green: CGFloat(rgb.green) / 255,
            blue: CGFloat(rgb.blue) / 255,
            alpha: 1
        )
    }

    // MARK: - Input

    private func handleTyped(_ bytes: [UInt8]) {
        guard !bytes.isEmpty else { return }
        type(bytes: bytes)
    }

    /// The view fitted itself to the pane; tell the server so the pty matches,
    /// but only while this app owns the block, otherwise the Mac window jumps.
    private func handleGridChange(cols: Int, rows: Int, cellSize: CGSize) {
        guard cols > 0, rows > 0 else { return }
        gridSize = "\(cols)×\(rows)"
        guard store.shouldOwnTerminalSizing else { return }
        guard lastRequestedGrid.cols != cols || lastRequestedGrid.rows != rows else { return }
        lastRequestedGrid = (cols, rows)
        resizeTask?.cancel()
        resizeTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard let self, !Task.isCancelled else { return }
            await self.store.resizeTerminal(
                sessionID: self.sessionID,
                blockID: self.blockID,
                cols: cols,
                rows: rows,
                cellWidthPx: Int(cellSize.width),
                cellHeightPx: Int(cellSize.height)
            )
        }
    }

    // MARK: - Teardown

    private func handleClose(_ reason: String?) {
        socket = nil
        gotWelcome = false
        phase = .failed(reason ?? "Stream closed")
        startTask = nil
    }

    private static func uint64(_ bytes: [UInt8], at index: Int) -> UInt64 {
        guard bytes.count >= index + 8 else { return 0 }
        var value: UInt64 = 0
        for offset in 0..<8 {
            value |= UInt64(bytes[index + offset]) << (8 * UInt64(offset))
        }
        return value
    }
}
