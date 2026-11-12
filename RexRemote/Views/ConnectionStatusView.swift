import SwiftUI

/// The state line under the connect button. Its own view so `ConnectView`
/// stays about the form, and so the three states stay next to the banners a
/// session shows for the same conditions.
struct ConnectionStatusView: View {
    let state: ConnectionState

    var body: some View {
            switch state {
            case .connecting:
                Label("Handshaking with the server…", systemImage: "ellipsis.circle")
                    .font(.footnote)
                    .foregroundStyle(RexTheme.secondaryInk)
            case .disconnected(let reason):
                if let reason {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("Not connected", systemImage: "exclamationmark.triangle")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(RexTheme.warning)
                        Text(reason)
                            .font(.caption)
                            .foregroundStyle(RexTheme.secondaryInk)
                    }
                }
            case .connected:
                Label("Connected", systemImage: "checkmark.circle.fill")
                    .font(.footnote)
                    .foregroundStyle(RexTheme.mintDeep)
            }
    }
}
