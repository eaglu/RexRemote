import SwiftUI

/// Scans a pairing code, and accepts a pasted address for devices without a
/// camera (or when the code is on the same screen).
struct QRScannerSheet: View {
    var onAddress: (String) -> Void
    var onCancel: () -> Void

    @StateObject private var scanner = QRScannerModel()
    @State private var pasted: String = ""
    @State private var problem: String?

    var body: some View {
        VStack(spacing: 0) {
            titleBar
            viewfinder
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black)
            footer
        }
        .background(RexTheme.paper)
        .onAppear {
            scanner.onCode = { payload in accept(payload) }
            scanner.start()
        }
        .onDisappear { scanner.stop() }
    }

    private var titleBar: some View {
        HStack {
            Button("Cancel", action: onCancel)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(RexTheme.secondaryInk)
                .accessibilityIdentifier("scanCancelButton")
            Spacer()
            Text("Pair a server")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(RexTheme.ink)
            Spacer()
            Color.clear.frame(width: 52, height: 1)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(RexTheme.paper)
    }

    @ViewBuilder
    private var viewfinder: some View {
        switch scanner.status {
        case .denied:
            message(
                icon: "camera.fill",
                title: "Camera access is off",
                detail: "Allow the camera in Settings, or paste the address below."
            )
        case .unavailable:
            message(
                icon: "camera.metering.unknown",
                title: "No camera here",
                detail: "Run `rex server tailscale pair` on the Mac and paste the address below."
            )
        case .idle, .scanning:
            ZStack {
                QRCameraPreview(session: scanner.session)
                    .ignoresSafeArea(edges: .horizontal)

                Color.black.opacity(scanner.status == .scanning ? 0.18 : 0.5)

                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .strokeBorder(RexTheme.mint, lineWidth: 3)
                    .frame(width: 236, height: 236)

                VStack {
                    Spacer()
                    Text("Point at the QR code from\n`rex server tailscale pair`")
                        .multilineTextAlignment(.center)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.85))
                        .padding(.bottom, 28)
                }
            }
        }
    }

    private func message(icon: String, title: String, detail: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 34))
                .foregroundStyle(.white.opacity(0.7))
            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
            Text(detail)
                .font(.footnote)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.7))
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var footer: some View {
        VStack(spacing: 10) {
            if let problem {
                Text(problem)
                    .font(.caption)
                    .foregroundStyle(RexTheme.warning)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(spacing: 8) {
                Image(systemName: "link")
                    .font(.system(size: 13))
                    .foregroundStyle(RexTheme.secondaryInk)
                TextField("rex-abc.tail1234.ts.net", text: $pasted)
                    .font(RexTheme.mono(13))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .accessibilityIdentifier("pairAddressField")
                Button("Use") { accept(pasted) }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(RexTheme.mintDeep)
                    .accessibilityIdentifier("pairUseButton")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(RexTheme.card, in: .rect(cornerRadius: 12, style: .continuous))
        }
        .padding(16)
        .background(RexTheme.paper)
    }

    private func accept(_ payload: String) {
        guard let address = HostLink.address(from: payload) else {
            problem = "That code is not a server address."
            return
        }
        problem = nil
        onAddress(address)
    }
}
