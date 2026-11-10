import Foundation
import GhosttyTerminal
import UIKit

/// Owns the live terminal stream for one block and mirrors it into a libghostty
/// surface. The stream starts with a Ghostty snapshot, which this class skips in
/// favor of a `terminal.format` VT dump so both paths agree.
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

    /// The libghostty session. It exists before the view does so early bytes are
    /// buffered by the library until the surface attaches.
    private(set) var terminal: InMemoryTerminalSession!

    private weak var terminalView: TerminalView?
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
    private var themeApplied = false

    init(sessionID: String, blockID: String, store: AppStore) {
        self.sessionID = sessionID
        self.blockID = blockID
        self.store = store
        super.init()
        // These closures run on libghostty's threads. Input goes through the same
        // coalescing path as the key row, otherwise every keystroke becomes its
        // own RPC and the shell sees the letters out of order.
        terminal = InMemoryTerminalSession(
            write: { [weak self] data in
                Task { @MainActor in
                    self?.handleTyped([UInt8](data))
                }
            },
            resize: { [weak self] viewport in
                Task { @MainActor in
                    self?.handleViewport(
                        cols: Int(viewport.columns),
                        rows: Int(viewport.rows),
                        cellSize: CGSize(
                            width: Int(viewport.cellWidthPixels),
                            height: Int(viewport.cellHeightPixels)
                        )
                    )
                }
            }
        )
    }

    // MARK: - View wiring

    func attach(_ view: TerminalView) {
        terminalView = view
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

    /// Hand a key to libghostty's encoder instead of guessing bytes: only the
    /// encoder knows whether the running application wants legacy keys, SS3 or
    /// kitty-keyboard sequences.
    func sendKey(_ press: TerminalKeyPress) {
        if let surface = terminalView?.surface, surface.sendKey(press) { return }
        if let bytes = Self.legacyBytes(for: press) { enqueue(bytes) }
    }

    /// The selection libghostty drew, if the user has one.
    func selectedText() -> String? {
        guard let text = terminalView?.surface?.readSelection() else { return nil }
        return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : text
    }

    /// Paste through the surface so bracketed-paste mode is honoured.
    func paste(_ text: String) {
        guard !text.isEmpty else { return }
        if terminalView?.surface?.paste(text: text) == true { return }
        enqueue(Array(text.utf8))
    }

    /// What a dumb terminal would have received, for the moment before the
    /// surface exists.
    private static func legacyBytes(for press: TerminalKeyPress) -> [UInt8]? {
        switch (press.key, press.modifiers) {
        case (.escape, []): return [0x1B]
        case (.tab, []): return [0x09]
        case (.enter, []): return [0x0D]
        case (.backspace, []): return [0x7F]
        case (.arrowUp, []): return [0x1B, 0x5B, 0x41]
        case (.arrowDown, []): return [0x1B, 0x5B, 0x42]
        case (.arrowRight, []): return [0x1B, 0x5B, 0x43]
        case (.arrowLeft, []): return [0x1B, 0x5B, 0x44]
        case (.c, .ctrl): return [0x03]
        case (.d, .ctrl): return [0x04]
        case (.z, .ctrl): return [0x1A]
        case (.l, .ctrl): return [0x0C]
        default: return nil
        }
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
            // Drain everything that piled up, one write at a time. The task stays
            // non-nil until the queue is empty, so a keystroke arriving mid-write
            // can never start a second, competing flush.
            while !self.pendingInput.isEmpty {
                let outgoing = self.pendingInput
                self.pendingInput = []
                await self.store.write(bytes: outgoing, sessionID: self.sessionID, blockID: self.blockID)
            }
            self.inputFlushTask = nil
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
            // RIS clears whatever the surface kept from an earlier attach before
            // the dump redraws the screen.
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
                // WELCOME layout: 0x81, 16-byte token, 3 zero bytes,
                // u32 resume window, then the u64 channel nonce at offset 24.
                let nonce = Self.uint64(bytes, at: 24)
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
        guard !bytes.isEmpty else { return }
        terminal.receive(Data(bytes))
    }

    private func applyDirectives(_ directives: [RexStreamParser.Directive]) {
        for directive in directives {
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
    /// window on the Mac instead of libghostty's default palette.
    private func applyTheme(_ body: JSONObject) {
        guard let foreground = body.string("foreground"),
              let background = body.string("background"),
              !themeApplied
        else { return }
        let cursor = body.string("cursor")
        let palette = body.strings("palette")
        themeApplied = true

        let configuration = TerminalConfiguration { builder in
            builder.withBackground(background)
            builder.withForeground(foreground)
            if let cursor { builder.withCursorColor(cursor) }
            for (index, colour) in palette.enumerated() where index < 256 {
                builder.withPalette(index, color: colour)
            }
        }
        let theme = TerminalTheme(light: configuration, dark: configuration)
        NSLog("REXDBG theme fg=%@ bg=%@ palette=%d", foreground, background, palette.count)
        Task { @MainActor in
            let ok = GhosttyTerminal.TerminalController.shared.setTheme(theme)
            NSLog("REXDBG setTheme -> %@", ok ? "ok" : "no-change")
        }
    }

    // MARK: - Input

    private func handleTyped(_ bytes: [UInt8]) {
        guard !bytes.isEmpty else { return }
        type(bytes: bytes)
    }

    /// The surface reported a new grid size; tell the server so the pty matches,
    /// but only while this app owns the block, otherwise the Mac window jumps.
    private func handleViewport(cols: Int, rows: Int, cellSize: CGSize) {
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
