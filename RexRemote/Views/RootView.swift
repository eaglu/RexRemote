import SwiftUI

struct RootView: View {
    @EnvironmentObject private var connection: ConnectionStore
    @EnvironmentObject private var store: SessionViewModel
    /// Shared by the session cards and the screen they open, so the push is a
    /// zoom out of the card instead of a slide.
    @Namespace private var sessionZoom

    var body: some View {
        NavigationStack {
            Group {
                if connection.connection.isConnected {
                    SessionListView(zoomNamespace: sessionZoom)
                } else {
                    ConnectView()
                }
            }
            .background(RexTheme.paper.ignoresSafeArea())
            .transition(.opacity)
            .animation(.easeInOut(duration: 0.22), value: connection.connection.isConnected)
        }
        .tint(RexTheme.mintDeep)
    }
}
