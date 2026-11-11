import SwiftUI

/// One pane: chrome plus the live terminal. The store owns the controller, so
/// this view only looks it up; `PaneContent` observes it so phase and title
/// changes redraw immediately.
struct PaneContainer: View {
    @EnvironmentObject private var store: AppStore
    let sessionID: String
    let placement: PanePlacement
    let isFocused: Bool
    let isZoomed: Bool
    /// False while the compose field owns the keyboard.
    let keepKeyboard: Bool
    let onRenamePane: (PanePlacement) -> Void
    let onNotice: (String) -> Void

    var body: some View {
        PaneContent(
            controller: store.controller(sessionID: sessionID, blockID: placement.block.id),
            placement: placement,
            isFocused: isFocused,
            keepKeyboard: keepKeyboard,
            isZoomed: isZoomed,
            onRenamePane: onRenamePane,
            onNotice: onNotice
        )
    }
}

struct PaneContent: View {
    @EnvironmentObject private var store: AppStore
    @ObservedObject var controller: TerminalController
    let placement: PanePlacement
    let isFocused: Bool
    let keepKeyboard: Bool
    let isZoomed: Bool
    var onRenamePane: (PanePlacement) -> Void = { _ in }
    var onNotice: (String) -> Void = { _ in }

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
                        TerminalSurface(controller: controller, keepKeyboard: keepKeyboard)
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

    /// Rex's header shows the shell's directory; fall back to the terminal title
    /// and then to `~`.
    private var paneLocation: String {
        let path = controller.workingDirectory
        if !path.isEmpty {
            // `/Users/name` is a home directory; Rex draws that as `~`.
            let parts = path.split(separator: "/", omittingEmptySubsequences: true)
            if parts.count == 2, parts[0] == "Users" { return "~" }
            let name = (path as NSString).lastPathComponent
            return name.isEmpty ? "/" : name
        }
        return controller.terminalTitle.isEmpty ? "~" : controller.terminalTitle
    }

    private var ownWindow: WindowInfo? {
        store.view?.windows.first { $0.panes.contains { $0.id == placement.id } }
    }

    private var siblings: [PanePlacement] {
        (ownWindow?.panes ?? []).filter { $0.id != placement.id }
    }

    private var otherWindows: [WindowInfo] {
        (store.view?.windows ?? []).filter { window in
            window.id != ownWindow?.id && !window.panes.isEmpty
        }
    }

    private var header: some View {
        HStack(spacing: 5) {
            Text(">_")
                .font(RexTheme.mono(12, weight: .bold))
                .foregroundStyle(isFocused ? RexTheme.mintDeep : RexTheme.secondaryInk.opacity(0.55))
            Text(placement.block.label)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(isFocused ? RexTheme.ink : RexTheme.secondaryInk)
                .lineLimit(1)
                .layoutPriority(1)
            Text(paneLocation)
                .font(RexTheme.mono(11))
                .foregroundStyle(RexTheme.secondaryInk.opacity(0.8))
                .lineLimit(1)
                .layoutPriority(0.5)
            Spacer(minLength: 2)
            Button {
                Task { await store.focus(blockID: placement.block.id) }
            } label: {
                Image(systemName: "scope")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(RexTheme.secondaryInk)
                    .frame(width: 26, height: 30)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("focusPaneButton")
            Button {
                store.toggleZoom(blockID: placement.block.id)
            } label: {
                Image(systemName: isZoomed ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(RexTheme.secondaryInk)
                    .frame(width: 26, height: 30)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("zoomPaneButton")
            PaneMenu(
                blockID: placement.block.id,
                siblings: siblings,
                windows: otherWindows,
                isZoomed: isZoomed,
                onRename: { onRenamePane(placement) },
                onNotice: onNotice
            )
        }
        .padding(.horizontal, 10)
        .frame(height: 32)
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
