import SwiftUI

/// The session's windows as tabs, the pane canvas, and the input bars.
///
/// The chrome follows Rex on the Mac: a warm paper page, one capsule holding the
/// tabs, the active tab as a dark chip with the mint `>_` glyph, and panes as
/// white cards whose header mimics Rex's `>_ zsh ~` row.
struct SessionScreen: View {
    let session: SessionRef
    /// Matches the card this screen zoomed out of.
    let zoomNamespace: Namespace.ID
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: AppStore
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
            topBar
            tabStrip
            canvas
            if case .disconnected(let reason) = store.connection {
                offlineBanner(reason)
            } else if let message = store.errorMessage {
                banner(message)
            }
            bottomBar
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
        .task {
            await store.openSession(session.id)
            if store.focusedBlockID == nil { store.focusedBlockID = window?.focusedBlockID }
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
        .overlay(alignment: .bottom) {
            if let notice {
                Text(notice)
                    .font(.system(size: 12, weight: .medium))
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

    // MARK: - Top bar

    /// Rex keeps its chrome floating above the terminal; on iOS that becomes
    /// three glass islands (back, the session label, the action cluster) instead
    /// of a full-width bar, so the paper stays visible between them.
    private var topBar: some View {
        GlassEffectContainer(spacing: 10) {
            // The label is centred against the screen, not against the two
            // clusters, so a narrow action strip is what actually centres it.
            ZStack {
                Text(view?.label ?? session.label)
                    .font(RexTheme.text(.headline, weight: .semibold))
                    .foregroundStyle(RexTheme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                    .glassEffect(RexTheme.glass(), in: .capsule)
                    .padding(.horizontal, 74)

                HStack(spacing: 10) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(RexTheme.ink)
                            .frame(width: 44, height: 44)
                            .glassEffect(RexTheme.glass(interactive: true), in: .circle)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Back to sessions")
                    .accessibilityIdentifier("backButton")

                    Spacer(minLength: 0)

                    // New window lives on the tab strip, so the top bar keeps
                    // only the two things that have nowhere else to go.
                    HStack(spacing: 0) {
                        Button {
                            Task { await store.refreshView() }
                        } label: {
                            glyph("arrow.clockwise")
                        }
                        .accessibilityLabel("Refresh")
                        .accessibilityIdentifier("refreshButton")
                        Menu {
                            Button("New window") { Task { await store.newWindow() } }
                            if let window {
                                Button("Rename window…") {
                                    renamingWindowID = window.id
                                    renameText = window.label
                                }
                                Button("Close window", role: .destructive) {
                                    Task { await store.closeWindow(window.id) }
                                }
                            }
                            Divider()
                            Menu("Move focus") {
                                Button("Left") { Task { await store.focusDirection("left") } }
                                Button("Right") { Task { await store.focusDirection("right") } }
                                Button("Up") { Task { await store.focusDirection("up") } }
                                Button("Down") { Task { await store.focusDirection("down") } }
                                Divider()
                                Button("Next pane") { Task { await store.focusStep(forward: true, pane: true) } }
                                Button("Previous pane") { Task { await store.focusStep(forward: false, pane: true) } }
                                Button("Next window") { Task { await store.focusStep(forward: true, pane: false) } }
                                Button("Previous window") { Task { await store.focusStep(forward: false, pane: false) } }
                            }
                            if let view, view.windows.count > 1 {
                                Menu("Focus window") {
                                    ForEach(view.windows) { candidate in
                                        Button(candidate.label) {
                                            Task { await store.focusWindow(candidate.id) }
                                        }
                                    }
                                }
                            }
                            Divider()
                            Button("New floating layer") { Task { await store.newFloatingLayer() } }
                            if let floating = window?.floatingLayers, !floating.isEmpty {
                                Menu("Floating layers") {
                                    ForEach(floating) { layer in
                                        Button(layer.isMinimized ? "Restore \(layer.id.suffix(6))" : "Minimize \(layer.id.suffix(6))") {
                                            Task {
                                                await store.setLayerState(layer.id, state: layer.isMinimized ? "normal" : "minimized")
                                            }
                                        }
                                        Button("Raise") { Task { await store.raiseLayer(layer.id) } }
                                        Button("Lower") { Task { await store.lowerLayer(layer.id) } }
                                        Button("Close layer", role: .destructive) {
                                            Task { await store.closeLayer(layer.id) }
                                        }
                                    }
                                }
                            }
                            Divider()
                            Button("Disconnect", role: .destructive) { store.disconnect() }
                        } label: {
                            glyph("ellipsis")
                        }
                        .accessibilityLabel("Session actions")
                        .accessibilityIdentifier("sessionMenuButton")
                    }
                    .padding(.horizontal, 3)
                    .padding(.vertical, 3)
                    .glassEffect(RexTheme.glass(), in: .capsule)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 4)
        .padding(.bottom, 10)
    }

    private func glyph(_ name: String) -> some View {
        Image(systemName: name)
            .font(RexTheme.text(.body, weight: .medium))
            .foregroundStyle(RexTheme.ink)
            .frame(width: RexTheme.tapTarget, height: RexTheme.tapTarget)
            .contentShape(Rectangle())
    }

    // MARK: - Window tabs

    private var windowTabs: [WindowInfo] { view?.windows ?? [] }

    private var tabStrip: some View {
        GlassEffectContainer(spacing: 6) {
            HStack(spacing: 6) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(windowTabs) { candidate in
                            tab(candidate, isActive: candidate.id == window?.id)
                        }
                    }
                    .padding(.horizontal, 2)
                }

                Button {
                    Task { await store.newWindow() }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(RexTheme.ink)
                        .frame(width: 44, height: 44)
                        .glassEffect(RexTheme.glass(interactive: true), in: .circle)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("newWindowChip")
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
    }

    private func tab(_ candidate: WindowInfo, isActive: Bool) -> some View {
        Button {
            selectedWindowID = candidate.id
            store.localZoomBlockID = nil
            if let blockID = candidate.focusedBlockID ?? candidate.panes.first?.id {
                Task { await store.focus(blockID: blockID) }
            }
        } label: {
            HStack(spacing: 6) {
                Text(">_")
                    .font(RexTheme.mono(13, weight: .bold))
                    .foregroundStyle(isActive ? RexTheme.mint : RexTheme.secondaryInk.opacity(0.7))
                Text(candidate.label)
                    .font(RexTheme.text(.subheadline, weight: isActive ? .semibold : .regular))
                    .foregroundStyle(isActive ? RexTheme.chipInk : RexTheme.secondaryInk)
                    .lineLimit(1)
                Text("\(candidate.panes.count)")
                    .font(RexTheme.monoText(.caption2))
                    .foregroundStyle(isActive ? RexTheme.chipInk.opacity(0.6) : RexTheme.secondaryInk.opacity(0.7))
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 9)
            .glassEffect(
                isActive
                    ? RexTheme.glass(RexTheme.chipGlass.opacity(0.92), interactive: true)
                    : RexTheme.glass(interactive: true),
                in: .capsule
            )
            .glassEffectID(candidate.id, in: tabNamespace)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(candidate.label) window, \(candidate.panes.count) panes")
        .accessibilityIdentifier("windowTab-\(candidate.label)")
        .contextMenu {
            Button("Rename window…") {
                renamingWindowID = candidate.id
                renameText = candidate.label
            }
            Button("Close window", role: .destructive) {
                Task { await store.closeWindow(candidate.id) }
            }
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
            Text(">_").font(RexTheme.mono(22, weight: .bold)).foregroundStyle(RexTheme.secondaryInk.opacity(0.5))
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

    // MARK: - Input

    private var bottomBar: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(RexTheme.hairline)
                .frame(height: 0.8)
            if showKeys {
                KeyBar(controller: focusedController)
            }
            HStack(spacing: 8) {
                Button {
                    showKeys.toggle()
                } label: {
                    Image(systemName: showKeys ? "keyboard.chevron.compact.down" : "keyboard")
                        .font(RexTheme.text(.body))
                        .foregroundStyle(RexTheme.secondaryInk)
                        .frame(width: RexTheme.tapTarget, height: RexTheme.tapTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(showKeys ? "Hide key row" : "Show key row")
                .accessibilityIdentifier("toggleKeysButton")

                TextField(
                    focusedPane.map { "Type to \($0.block.label)…" } ?? "No pane focused",
                    text: $composeText
                )
                .font(RexTheme.monoText(.body))
                .focused($composeFocused)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.send)
                .onSubmit { sendCompose() }
                .disabled(focusedBlockID == nil)
                .padding(.horizontal, 13)
                .padding(.vertical, 11)
                .glassEffect(RexTheme.glass(), in: .capsule)
                .accessibilityIdentifier("composeField")

                Button(action: sendCompose) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(canSend ? RexTheme.mint : RexTheme.chipInk.opacity(0.4))
                        .frame(width: 44, height: 44)
                        .glassEffect(
                            canSend
                                ? RexTheme.glass(RexTheme.chipGlass.opacity(0.95), interactive: true)
                                : RexTheme.glass(),
                            in: .circle
                        )
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
                .accessibilityLabel("Send")
                .accessibilityIdentifier("sendButton")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .background(RexTheme.paper.opacity(0.55))
    }

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

    /// A dropped connection is a state, not an event: it stays on screen with
    /// the action that fixes it, instead of the dismissible error strip.
    private func offlineBanner(_ reason: String?) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "bolt.horizontal.circle")
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text("Disconnected")
                    .font(RexTheme.text(.footnote, weight: .semibold))
                Text(reason ?? "The server stopped responding.")
                    .font(.caption2)
                    .lineLimit(2)
            }
            Spacer(minLength: 4)
            Button("Reconnect") {
                Task { await store.connect() }
            }
            .font(RexTheme.text(.footnote, weight: .semibold))
            .foregroundStyle(RexTheme.ink)
            .padding(.horizontal, 12)
            .frame(minHeight: RexTheme.tapTarget)
            .accessibilityIdentifier("reconnectButton")
        }
        .foregroundStyle(RexTheme.warning)
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(RexTheme.strip)
    }

    private func banner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
            Text(message).font(.footnote).lineLimit(3)
            Spacer()
            Button {
                store.errorMessage = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.caption)
                    .frame(width: RexTheme.tapTarget, height: RexTheme.tapTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .foregroundStyle(RexTheme.warning)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(RexTheme.strip)
    }
}
