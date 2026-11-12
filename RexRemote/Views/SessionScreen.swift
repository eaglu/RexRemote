import SwiftUI

/// The session's windows as tabs, the pane canvas, and the input bars.
///
/// The chrome follows Rex on the Mac: a warm paper page, one capsule holding the
/// tabs, the active tab as a dark chip with the mint `>_` glyph, and panes as
/// white cards whose header mimics Rex's `>_ zsh ~` row. The chrome itself lives
/// in `SessionChrome`, `WindowTabStrip` and `InputDock`; this view owns the
/// state and the geometry.
struct SessionScreen: View {
    let session: SessionRef
    /// Matches the card this screen zoomed out of.
    let zoomNamespace: Namespace.ID
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var connection: ConnectionStore
    @EnvironmentObject private var store: SessionViewModel
    @State private var selectedWindowID: String?
    @State private var composeText = ""
    /// Tracks the compose field so the panes stop pulling the keyboard back.
    @FocusState private var composeFocused: Bool
    @State private var showKeys = true
    @State private var renamingWindowID: String?
    @State private var renameText = ""
    @State private var renamingBlockID: String?
    @State private var blockRenameText = ""
    @State private var notice: String?
    @Namespace private var tabNamespace
    @AppStorage(RexTheme.terminalFontSizeKey) private var terminalFontSize =
        Double(RexTheme.preferredTerminalFontSize)

    /// What the canvas is showing, independent of live resizes: a change here
    /// (new split, zoom, other window) animates, a drag does not.
    private var paneSignature: String {
        let ids = (view?.activeWindow?.panes ?? []).map(\.id).joined(separator: ",")
        return "\(selectedWindowID ?? "")|\(zoomedBlockID ?? "")|\(ids)"
    }

    private var view: SessionView? { store.view }
    private var window: WindowInfo? {
        guard let view else { return nil }
        if let selectedWindowID, let match = view.windows.first(where: { $0.id == selectedWindowID }) {
            return match
        }
        return view.activeWindow
    }

    /// The server's zoom is the truth; the local one only covers servers too old
    /// to report it.
    private var zoomedBlockID: String? {
        if let zoomed = window?.zoomedBlockID { return zoomed }
        return store.localZoomBlockID
    }

    private var focusedBlockID: String? {
        if let zoomed = zoomedBlockID,
           window?.panes.contains(where: { $0.id == zoomed }) == true { return zoomed }
        if let focused = store.focusedBlockID, window?.panes.contains(where: { $0.id == focused }) == true {
            return focused
        }
        return window?.focusedBlockID ?? window?.panes.first?.id
    }

    private var focusedPane: PanePlacement? { window?.pane(id: focusedBlockID) }

    var body: some View {
        VStack(spacing: 0) {
            SessionChrome(
                title: view?.label ?? session.label,
                currentSessionID: view?.id ?? session.id,
                window: window,
                onBack: { dismiss() },
                onRefresh: { Task { await store.refreshView() } },
                onRenameWindow: { candidate in
                    renamingWindowID = candidate.id
                    renameText = candidate.label
                },
                onSwitchSession: switchSession(to:),
                onAllSessions: { dismiss() }
            )
            WindowTabStrip(
                windows: windowTabs,
                activeWindowID: window?.id,
                namespace: tabNamespace,
                onSelect: select(window:),
                onNew: { Task { await store.newWindow() } },
                onRename: { candidate in
                    renamingWindowID = candidate.id
                    renameText = candidate.label
                },
                onClose: { candidate in Task { await store.closeWindow(candidate.id) } }
            )
            canvas
            connectionBanner
            InputDock(
                controller: focusedController,
                prompt: focusedPane.map { "Type to \($0.block.label)…" },
                canSend: canSend,
                composeText: $composeText,
                composeFocus: $composeFocused,
                showKeys: $showKeys,
                fontSize: Binding(
                    get: { Float(terminalFontSize) },
                    set: { terminalFontSize = Double($0) }
                ),
                onSend: sendCompose
            )
        }
        .background(RexTheme.paper.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .background(InteractivePopGesture().frame(width: 0, height: 0))
        .navigationTransition(.zoom(sourceID: session.id, in: zoomNamespace))
        .onChange(of: view?.activeWindowID) { _, _ in
            // Follow the server when it switches windows (new window, or a tab
            // change made on the Mac); the local override only outlives a tap
            // while that window stays active.
            selectedWindowID = nil
        }
        .alert("Rename window", isPresented: Binding(
            get: { renamingWindowID != nil },
            set: { if !$0 { renamingWindowID = nil } }
        )) {
            TextField("Window label", text: $renameText)
            Button("Cancel", role: .cancel) { renamingWindowID = nil }
            Button("Rename") {
                if let id = renamingWindowID {
                    let label = renameText
                    Task { await store.renameWindow(id, label: label) }
                }
                renamingWindowID = nil
            }
        }
        .alert("Rename pane", isPresented: Binding(
            get: { renamingBlockID != nil },
            set: { if !$0 { renamingBlockID = nil } }
        )) {
            TextField("Pane label", text: $blockRenameText)
            Button("Cancel", role: .cancel) { renamingBlockID = nil }
            Button("Rename") {
                if let id = renamingBlockID {
                    let label = blockRenameText
                    Task { await store.renameBlock(id, label: label) }
                }
                renamingBlockID = nil
            }
        }
        .task {
            await store.openSession(session.id)
            if store.focusedBlockID == nil { store.focusedBlockID = window?.focusedBlockID }
        }
        .overlay(alignment: .bottom) {
            if let notice {
                Text(notice)
                    .font(RexTheme.text(.footnote, weight: .medium))
                    .foregroundStyle(RexTheme.chipInk)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(RexTheme.chip.opacity(0.92), in: .capsule)
                    .padding(.bottom, 132)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .task(id: notice) {
                        try? await Task.sleep(nanoseconds: 1_800_000_000)
                        withAnimation { self.notice = nil }
                    }
            }
        }
    }

    // MARK: - State changes

    private var windowTabs: [WindowInfo] { view?.windows ?? [] }

    private func switchSession(to id: String) {
        guard id != (view?.id ?? session.id) else { return }
        selectedWindowID = nil
        store.localZoomBlockID = nil
        composeText = ""
        Task { await store.openSession(id) }
    }

    private func select(window candidate: WindowInfo) {
        selectedWindowID = candidate.id
        store.localZoomBlockID = nil
        if let blockID = candidate.focusedBlockID ?? candidate.panes.first?.id {
            Task { await store.focus(blockID: blockID) }
        }
    }

    // MARK: - Panes

    @ViewBuilder
    private var canvas: some View {
        GeometryReader { geometry in
            if let view, let window {
                let panes: [PanePlacement] = {
                    if let zoomed = zoomedBlockID,
                       let match = window.panes.first(where: { $0.id == zoomed }) {
                        return [match]
                    }
                    return window.panes
                }()
                ZStack(alignment: .topLeading) {
                    ForEach(panes) { placement in
                        let frame = frame(for: placement.rect, in: geometry.size, single: panes.count == 1)
                        PaneContainer(
                            sessionID: view.id,
                            placement: placement,
                            isFocused: placement.id == focusedBlockID,
                            isZoomed: zoomedBlockID == placement.id,
                            keepKeyboard: !composeFocused,
                            onRenamePane: { pane in
                                renamingBlockID = pane.block.id
                                blockRenameText = pane.block.label
                            },
                            onNotice: { message in withAnimation { notice = message } }
                        )
                        .frame(width: frame.width, height: frame.height)
                        .offset(x: frame.minX, y: frame.minY)
                        .transition(
                            .opacity.combined(with: .scale(scale: 0.97, anchor: .center))
                        )
                    }
                    if panes.count > 1 {
                        ForEach(window.dividers) { divider in
                            SplitHandle(
                                divider: divider,
                                size: geometry.size,
                                isActive: divider.beforeBlockID == focusedBlockID
                                    || divider.afterBlockID == focusedBlockID
                            ) { ratio in
                                Task { await store.resizeSplit(divider, ratio: ratio) }
                            }
                        }
                    }
                    if panes.isEmpty {
                        emptyWindow
                            .frame(width: geometry.size.width, height: geometry.size.height)
                    }
                }
            } else {
                ProgressView()
                    .tint(RexTheme.secondaryInk)
                    .frame(width: geometry.size.width, height: geometry.size.height)
            }
        }
        .background(RexTheme.paper)
        .clipped()
    }

    private var emptyWindow: some View {
        VStack(spacing: 8) {
            Text(">_")
                .font(RexTheme.mono(22, weight: .bold))
                .foregroundStyle(RexTheme.secondaryInk.opacity(0.5))
                .accessibilityHidden(true)
            Text("No panes")
                .font(RexTheme.text(.subheadline, weight: .semibold))
                .foregroundStyle(RexTheme.ink)
            Text("This window has no blocks. Create one here or from Rex on your Mac.")
                .font(RexTheme.text(.footnote))
                .foregroundStyle(RexTheme.secondaryInk)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button("New pane") {
                Task { await store.createBlock() }
            }
            .font(RexTheme.text(.footnote, weight: .semibold))
            .padding(.horizontal, 16)
            .frame(minHeight: RexTheme.tapTarget)
            .foregroundStyle(RexTheme.ink)
            .rexCard(fill: RexTheme.strip)
            .padding(.top, 2)
        }
    }

    private func frame(for rect: CGRect, in size: CGSize, single: Bool) -> CGRect {
        let inset: CGFloat = single ? 4 : 3
        return CGRect(
            x: rect.minX * size.width + inset,
            y: rect.minY * size.height + inset,
            width: max(rect.width * size.width - inset * 2, 40),
            height: max(rect.height * size.height - inset * 2, 40)
        )
    }

    // MARK: - Connection state

    @ViewBuilder
    private var connectionBanner: some View {
        if case .disconnected(let reason) = connection.connection {
            ConnectionBanner(
                kind: .offline(reason),
                onReconnect: { Task { await connection.connect() } },
                onDismiss: {}
            )
        } else if let message = connection.errorMessage {
            ConnectionBanner(
                kind: .error(message),
                onReconnect: {},
                onDismiss: { connection.errorMessage = nil }
            )
        }
    }

    // MARK: - Input

    private var focusedController: TerminalController {
        store.controller(sessionID: view?.id ?? session.id, blockID: focusedBlockID ?? "")
    }

    private var canSend: Bool { focusedBlockID != nil }

    private func sendCompose() {
        guard let blockID = focusedBlockID, let sessionID = view?.id else { return }
        let text = composeText
        composeText = ""
        Task {
            await store.write(text + "\r", sessionID: sessionID, blockID: blockID)
        }
    }
}
