import GhosttyTerminal
import SwiftUI
import UIKit

@main
struct RexRemoteApp: App {
    @StateObject private var connection = ConnectionStore()
    @StateObject private var sessions: SessionViewModel
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let connection = ConnectionStore()
        let sessions = SessionViewModel(connection: connection)
        connection.attach(sessions: sessions)
        _connection = StateObject(wrappedValue: connection)
        _sessions = StateObject(wrappedValue: sessions)

        // libghostty keeps one app-wide configuration, so the Rex palette goes in
        // before the first surface is created; a `theme` directive from the
        // server replaces it later.
        GhosttyTerminal.TerminalController.shared.setTheme(RexTheme.ghosttyTheme)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(connection)
                .environmentObject(sessions)
        }
        .onChange(of: scenePhase) { _ in
            guard scenePhase == .active else { return }
            switch connection.connection {
            case .connected:
                Task { await sessions.refreshView() }
            case .disconnected, .connecting:
                if !connection.host.address.isEmpty, connection.connection != .connecting {
                    Task { await connection.connect() }
                }
            }
        }
    }
}
