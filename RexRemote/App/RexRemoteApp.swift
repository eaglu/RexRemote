import SwiftUI
import UIKit

@main
struct RexRemoteApp: App {
    @StateObject private var store = AppStore()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .preferredColorScheme(.light)
        }
        .onChange(of: scenePhase) { _ in
            guard scenePhase == .active else { return }
            switch store.connection {
            case .connected:
                Task { await store.refreshView() }
            case .disconnected, .connecting:
                if !store.host.address.isEmpty, store.connection != .connecting {
                    Task { await store.connect() }
                }
            }
        }
    }
}
