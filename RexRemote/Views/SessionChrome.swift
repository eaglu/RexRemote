import SwiftUI

/// The floating chrome above the panes: back, the session label (which doubles
/// as the session switcher), refresh, and the session actions menu.
///
/// Kept out of `SessionScreen` so the screen itself is only state and layout;
/// the menu content alone used to be eighty lines inline.
struct SessionChrome: View {
    @EnvironmentObject private var connection: ConnectionStore
    @EnvironmentObject private var store: SessionViewModel
    let title: String
    let currentSessionID: String
    let window: WindowInfo?
    let onBack: () -> Void
    let onRefresh: () -> Void
    let onRenameWindow: (WindowInfo) -> Void
    let onSwitchSession: (String) -> Void
    let onAllSessions: () -> Void

    var body: some View {
        GlassEffectContainer(spacing: 10) {
            // The label is centred against the screen, not against the two
            // clusters, so a narrow action strip is what actually centres it.
            ZStack {
                SessionSwitcher(
                    title: title,
                    currentSessionID: currentSessionID,
                    sessions: store.sessions,
                    onSwitch: onSwitchSession,
                    onAllSessions: onAllSessions
                )

                HStack(spacing: 10) {
                    Button(action: onBack) {
                        Image(systemName: "chevron.left")
                            .font(RexTheme.text(.title3, weight: .semibold))
                            .foregroundStyle(RexTheme.ink)
                            .frame(width: RexTheme.tapTarget, height: RexTheme.tapTarget)
                            .glassEffect(RexTheme.glass(interactive: true), in: .circle)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Back to sessions")
                    .accessibilityIdentifier("backButton")

                    Spacer(minLength: 0)

                    HStack(spacing: 0) {
                        Button(action: onRefresh) {
                            glyph("arrow.clockwise")
                        }
                        .accessibilityLabel("Refresh")
                        .accessibilityIdentifier("refreshButton")

                        SessionActionsMenu(
                            window: window,
                            onRenameWindow: onRenameWindow,
                            onDisconnect: { connection.disconnect() }
                        )
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
}

/// The session label as a menu, so switching sessions no longer means popping
/// back to the list and drilling in again.
private struct SessionSwitcher: View {
    let title: String
    let currentSessionID: String
    let sessions: [SessionRef]
    let onSwitch: (String) -> Void
    let onAllSessions: () -> Void

    var body: some View {
        Menu {
            ForEach(sessions) { candidate in
                Button {
                    onSwitch(candidate.id)
                } label: {
                    if candidate.id == currentSessionID {
                        Label(candidate.label, systemImage: "checkmark")
                    } else {
                        Text(candidate.label)
                    }
                }
            }
            if !sessions.isEmpty { Divider() }
            Button("All sessions", systemImage: "list.bullet", action: onAllSessions)
        } label: {
            HStack(spacing: 5) {
                Text(title)
                    .font(RexTheme.text(.headline, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(RexTheme.secondaryInk)
                    .accessibilityHidden(true)
            }
            .foregroundStyle(RexTheme.ink)
            .padding(.horizontal, 14)
            .frame(minHeight: 40)
            .glassEffect(RexTheme.glass(interactive: true), in: .capsule)
            .padding(.horizontal, 74)
        }
        .accessibilityLabel("Session \(title), switch session")
        .accessibilityIdentifier("sessionSwitcher")
    }
}

/// Everything the session can do to windows, focus and layers. Split out of the
/// top bar so the menu reads like a list of intents instead of layout code.
private struct SessionActionsMenu: View {
    @EnvironmentObject private var store: SessionViewModel
    let window: WindowInfo?
    let onRenameWindow: (WindowInfo) -> Void
    let onDisconnect: () -> Void

    var body: some View {
        Menu {
            Button("New window", systemImage: "plus.rectangle.on.rectangle") {
                Task { await store.newWindow() }
            }
            if let window {
                Button("Rename window…") { onRenameWindow(window) }
                Button("Close window", systemImage: "xmark.rectangle", role: .destructive) {
                    Task { await store.closeWindow(window.id) }
                }
            }
            Divider()
            focusMenu
            if let view = store.view, view.windows.count > 1 {
                Menu("Focus window") {
                    ForEach(view.windows) { candidate in
                        Button(candidate.label) {
                            Task { await store.focusWindow(candidate.id) }
                        }
                    }
                }
            }
            Divider()
            layersMenu
            Divider()
            Button("Disconnect", systemImage: "bolt.slash", role: .destructive, action: onDisconnect)
        } label: {
            Image(systemName: "ellipsis")
                .font(RexTheme.text(.body, weight: .medium))
                .foregroundStyle(RexTheme.ink)
                .frame(width: RexTheme.tapTarget, height: RexTheme.tapTarget)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("Session actions")
        .accessibilityIdentifier("sessionMenuButton")
    }

    private var focusMenu: some View {
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
    }

    @ViewBuilder
    private var layersMenu: some View {
        Button("New floating layer") { Task { await store.newFloatingLayer() } }
        if let floating = window?.floatingLayers, !floating.isEmpty {
            Menu("Floating layers") {
                ForEach(floating) { layer in
                    Button(layer.isMinimized ? "Restore \(layer.id.suffix(6))" : "Minimize \(layer.id.suffix(6))") {
                        Task {
                            await store.setLayerState(
                                layer.id,
                                state: layer.isMinimized ? "normal" : "minimized"
                            )
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
    }
}

/// A dropped connection is a state, not an event: it stays on screen with the
/// action that fixes it, instead of the dismissible error strip.
struct ConnectionBanner: View {
    enum Kind {
        case offline(String?)
        case error(String)
    }

    let kind: Kind
    let onReconnect: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(RexTheme.text(.footnote, weight: .semibold))
                Text(message)
                    .font(.caption2)
                    .lineLimit(2)
            }
            Spacer(minLength: 4)
            if case .offline = kind {
                Button("Reconnect", action: onReconnect)
                    .font(RexTheme.text(.footnote, weight: .semibold))
                    .foregroundStyle(RexTheme.ink)
                    .padding(.horizontal, 12)
                    .frame(minHeight: RexTheme.tapTarget)
                    .accessibilityIdentifier("reconnectButton")
            } else {
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.caption)
                        .frame(width: RexTheme.tapTarget, height: RexTheme.tapTarget)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Dismiss")
                .accessibilityIdentifier("dismissErrorButton")
            }
        }
        .foregroundStyle(RexTheme.warning)
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(RexTheme.strip)
    }

    private var icon: String {
        switch kind {
        case .offline: return "bolt.horizontal.circle"
        case .error: return "exclamationmark.triangle.fill"
        }
    }

    private var title: String {
        switch kind {
        case .offline: return "Disconnected"
        case .error: return "Something went wrong"
        }
    }

    private var message: String {
        switch kind {
        case .offline(let reason): return reason ?? "The server stopped responding."
        case .error(let message): return message
        }
    }
}
