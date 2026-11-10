import SwiftUI

/// The session's windows as tabs, the pane canvas, and the input bars.
///
/// The chrome follows Rex on the Mac: a warm paper page, one capsule holding the
/// tabs, the active tab as a dark chip with the mint `>_` glyph, and panes as
/// white cards whose header mimics Rex's `>_ zsh ~` row.
struct SessionScreen: View {
    let session: SessionRef
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: AppStore
    @State private var selectedWindowID: String?
    @State private var composeText = ""
    @State private var showKeys = true
    @State private var renamingWindowID: String?
    @State private var renameText = ""
    @Namespace private var tabNamespace

    private var view: SessionView? { store.view }
    private var window: WindowInfo? {
        guard let view else { return nil }
        if let selectedWindowID, let match = view.windows.first(where: { $0.id == selectedWindowID }) {
            return match
        }
        return view.activeWindow
    }

    private var focusedBlockID: String? {
        if let zoomed = store.localZoomBlockID,
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
            if let message = store.errorMessage {
                banner(message)
            }
            bottomBar
        }
        .background(RexTheme.paper.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
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
    }

    // MARK: - Top bar

    /// Rex keeps its chrome floating above the terminal; on iOS that becomes
    /// three glass islands (back, the session label, the action cluster) instead
    /// of a full-width bar, so the paper stays visible between them.
    private var topBar: some View {
        GlassEffectContainer(spacing: 10) {
        HStack(spacing: 10) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(RexTheme.ink)
                    .frame(width: 34, height: 34)
                    .glassEffect(RexTheme.glass(interactive: true), in: .circle)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("backButton")

            Spacer(minLength: 0)

            Text(view?.label ?? session.label)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(RexTheme.ink)
                .lineLimit(1)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .glassEffect(RexTheme.glass(), in: .capsule)

            Spacer(minLength: 0)

            HStack(spacing: 2) {
                Button {
                    Task { await store.newWindow() }
                } label: {
                    glyph("plus.rectangle.on.rectangle")
                }
                .accessibilityIdentifier("newTabButton")
                Button {
                    Task { await store.refreshView() }
                } label: {
                    glyph("arrow.clockwise")
                }
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
                    Button("Disconnect", role: .destructive) { store.disconnect() }
                } label: {
                    glyph("ellipsis")
                }
                .accessibilityIdentifier("sessionMenuButton")
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 3)
            .glassEffect(RexTheme.glass(), in: .capsule)
        }
        }
        .padding(.horizontal, 12)
        .padding(.top, 4)
        .padding(.bottom, 10)
    }

    private func glyph(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(RexTheme.ink)
            .frame(width: 30, height: 26)
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
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(RexTheme.ink)
                        .frame(width: 32, height: 32)
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
            HStack(spacing: 5) {
                Text(">_")
                    .font(RexTheme.mono(11, weight: .bold))
                    .foregroundStyle(isActive ? RexTheme.mint : RexTheme.secondaryInk.opacity(0.7))
                Text(candidate.label)
                    .font(.system(size: 12, weight: isActive ? .semibold : .regular))
                    .foregroundStyle(isActive ? RexTheme.chipInk : RexTheme.secondaryInk)
                    .lineLimit(1)
                Text("\(candidate.panes.count)")
                    .font(RexTheme.mono(10))
                    .foregroundStyle(isActive ? RexTheme.chipInk.opacity(0.6) : RexTheme.secondaryInk.opacity(0.7))
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
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
                    if let zoomed = store.localZoomBlockID,
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
                            isZoomed: store.localZoomBlockID == placement.id
                        )
                        .frame(width: frame.width, height: frame.height)
                        .offset(x: frame.minX, y: frame.minY)
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
            Text("No panes").font(.system(size: 14, weight: .semibold)).foregroundStyle(RexTheme.ink)
            Text("This window has no blocks. Create one from Rex on your Mac.")
                .font(.footnote)
                .foregroundStyle(RexTheme.secondaryInk)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
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
                        .font(.system(size: 15))
                        .foregroundStyle(RexTheme.secondaryInk)
                        .frame(width: 34, height: 34)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("toggleKeysButton")

                TextField(
                    focusedPane.map { "Type to \($0.block.label)…" } ?? "No pane focused",
                    text: $composeText
                )
                .font(RexTheme.mono(12))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.send)
                .onSubmit { sendCompose() }
                .disabled(focusedBlockID == nil)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .glassEffect(RexTheme.glass(), in: .capsule)
                .accessibilityIdentifier("composeField")

                Button(action: sendCompose) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(canSend ? RexTheme.mint : RexTheme.chipInk.opacity(0.4))
                        .frame(width: 36, height: 36)
                        .glassEffect(
                            canSend
                                ? RexTheme.glass(RexTheme.chipGlass.opacity(0.95), interactive: true)
                                : RexTheme.glass(),
                            in: .circle
                        )
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
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

    private func banner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
            Text(message).font(.footnote).lineLimit(3)
            Spacer()
            Button {
                store.errorMessage = nil
            } label: {
                Image(systemName: "xmark").font(.caption)
            }
            .buttonStyle(.plain)
        }
        .foregroundStyle(RexTheme.warning)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(RexTheme.strip)
    }
}

/// One pane: chrome plus the live terminal. The store owns the controller, so
/// this view only looks it up; `PaneContent` observes it so phase and title
/// changes redraw immediately.
struct PaneContainer: View {
    @EnvironmentObject private var store: AppStore
    let sessionID: String
    let placement: PanePlacement
    let isFocused: Bool
    let isZoomed: Bool

    var body: some View {
        PaneContent(
            controller: store.controller(sessionID: sessionID, blockID: placement.block.id),
            placement: placement,
            isFocused: isFocused,
            isZoomed: isZoomed
        )
    }
}

struct PaneContent: View {
    @EnvironmentObject private var store: AppStore
    @ObservedObject var controller: TerminalController
    let placement: PanePlacement
    let isFocused: Bool
    let isZoomed: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            // The terminal fills the slot via an overlay so its UIKit view can
            // never propose a size larger than the pane and ride over the header.
            GeometryReader { proxy in
                // The grid is sized explicitly: a bare UIViewRepresentable has no
                // intrinsic size and SwiftUI would centre an oversized view, which
                // cuts the first column off against the card edge.
                Color.clear
                    .overlay(alignment: .topLeading) {
                        TerminalSurface(controller: controller)
                            .frame(
                                width: max(1, proxy.size.width - 4),
                                height: max(1, proxy.size.height)
                            )
                            .offset(x: 2)
                    }
                    .overlay(alignment: .bottomTrailing) {
                        statusOverlay
                    }
            }
        }
        .background(RexTheme.card)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(
                    isFocused ? RexTheme.mintDeep.opacity(0.55) : RexTheme.hairline,
                    lineWidth: isFocused ? 1.2 : 0.8
                )
        )
    }

    private var header: some View {
        HStack(spacing: 6) {
            Text(">_")
                .font(RexTheme.mono(10, weight: .bold))
                .foregroundStyle(isFocused ? RexTheme.mintDeep : RexTheme.secondaryInk.opacity(0.55))
            Text(placement.block.label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(isFocused ? RexTheme.ink : RexTheme.secondaryInk)
                .lineLimit(1)
            Text(controller.terminalTitle.isEmpty ? "~" : controller.terminalTitle)
                .font(RexTheme.mono(10))
                .foregroundStyle(RexTheme.secondaryInk.opacity(0.8))
                .lineLimit(1)
            Spacer(minLength: 4)
            Button {
                Task { await store.focus(blockID: placement.block.id) }
            } label: {
                Image(systemName: "scope")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(RexTheme.secondaryInk)
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("focusPaneButton")
            Button {
                store.toggleZoom(blockID: placement.block.id)
            } label: {
                Image(systemName: isZoomed ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(RexTheme.secondaryInk)
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("zoomPaneButton")
            Menu {
                Button("Split right") {
                    Task { await store.split(blockID: placement.block.id, direction: "horizontal") }
                }
                Button("Split down") {
                    Task { await store.split(blockID: placement.block.id, direction: "vertical") }
                }
                Divider()
                Button("Close pane", role: .destructive) {
                    Task { await store.closeBlock(placement.block.id) }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(RexTheme.secondaryInk)
                    .frame(width: 20, height: 20)
            }
            .accessibilityIdentifier("paneMenuButton")
        }
        .padding(.horizontal, 8)
        .frame(height: 24)
        .background(RexTheme.card)
        .overlay(alignment: .bottom) {
            Rectangle().fill(RexTheme.hairline).frame(height: 0.8)
        }
        .onTapGesture {
            Task { await store.focus(blockID: placement.block.id) }
        }
    }

    @ViewBuilder
    private var statusOverlay: some View {
        switch controller.phase {
        case .failed(let reason):
            HStack(spacing: 6) {
                Image(systemName: "wifi.exclamationmark")
                Text(reason).lineLimit(2)
            }
            .font(.caption2)
            .foregroundStyle(RexTheme.warning)
            .padding(6)
            .background(RexTheme.card.opacity(0.92), in: RoundedRectangle(cornerRadius: 6))
            .padding(6)
        case .priming:
            HStack(spacing: 6) {
                ProgressView().controlSize(.mini).tint(RexTheme.secondaryInk)
                Text("Opening stream…")
            }
            .font(.caption2)
            .foregroundStyle(RexTheme.secondaryInk)
            .padding(6)
            .background(RexTheme.card.opacity(0.92), in: RoundedRectangle(cornerRadius: 6))
            .padding(6)
        case .idle, .live:
            EmptyView()
        }
    }
}
