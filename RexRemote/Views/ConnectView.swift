import SwiftUI

/// Paper page, white card, dark chip button — the same vocabulary as the Mac app.
struct ConnectView: View {
    @EnvironmentObject private var connection: ConnectionStore
    @EnvironmentObject private var store: SessionViewModel
    @State private var draft: HostConfig = .loopback
    @State private var editingHost: HostConfig?
    @State private var isConnecting = false
    @State private var isScanning = false
    @State private var showAccess = false

    private var host: HostConfig { connection.hosts.selected ?? .loopback }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                card
                connectButton
                ConnectionStatusView(state: connection.connection)
                if connection.hosts.hosts.count > 1 {
                    savedHosts
                }
            }
            .padding(20)
        }
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    ForEach(connection.hosts.hosts) { candidate in
                        Button {
                            connection.hosts.selectedID = candidate.id
                            connection.hosts.upsert(candidate)
                            draft = candidate
                        } label: {
                            Label(candidate.name, systemImage: candidate.id == host.id ? "checkmark" : "server.rack")
                        }
                    }
                    Divider()
                    Button("Add this server") { saveDraftAsHost() }
                } label: {
                    Image(systemName: "list.bullet")
                        .foregroundStyle(RexTheme.ink)
                        .frame(width: RexTheme.tapTarget, height: RexTheme.tapTarget)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Saved servers")
                .accessibilityIdentifier("hostMenuButton")
            }
        }
        .onAppear {
            draft = host
            showAccess = host.usesAccessToken
        }
        .sheet(isPresented: $isScanning) {
            QRScannerSheet(
                onAddress: { address in
                    isScanning = false
                    draft.address = address
                    if draft.name.isEmpty || draft.name == "This Mac" { draft.name = "Rex Server" }
                    commitDraft()
                },
                onCancel: { isScanning = false }
            )
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(">_")
                    .font(RexTheme.mono(13, weight: .bold))
                    .foregroundStyle(RexTheme.mintDeep)
                Text("remote")
                    .font(RexTheme.monoText(.body))
                    .foregroundStyle(RexTheme.secondaryInk)
            }
            Text("Rex Remote")
                .font(.system(.largeTitle, weight: .bold))
                .foregroundStyle(RexTheme.ink)
            Text(host.name)
                .font(RexTheme.text(.headline, weight: .semibold))
                .foregroundStyle(RexTheme.ink)
            Text("A remote control for your Rex sessions.")
                .font(.footnote)
                .foregroundStyle(RexTheme.secondaryInk)
        }
        .padding(.top, 8)
    }

    private var card: some View {
        VStack(spacing: 0) {
            field(label: "Server", icon: "server.rack") {
                HStack(spacing: 6) {
                    TextField("127.0.0.1:7297", text: addressBinding)
                        .font(RexTheme.monoText(.body))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .onSubmit { connect() }
                        .accessibilityIdentifier("serverAddressField")
                    Button {
                        isScanning = true
                    } label: {
                        Image(systemName: "qrcode.viewfinder")
                            .font(RexTheme.text(.body, weight: .medium))
                            .foregroundStyle(RexTheme.ink)
                            .frame(width: RexTheme.tapTarget, height: RexTheme.tapTarget)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Scan a pairing code")
                    .accessibilityIdentifier("scanButton")
                }
            }
            Rectangle().fill(RexTheme.hairline).frame(height: 0.8).padding(.leading, 12)
            field(label: "Token", icon: "key") {
                SecureField("Optional bearer token", text: tokenBinding)
                    .font(RexTheme.monoText(.body))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("tokenField")
            }
            Rectangle().fill(RexTheme.hairline).frame(height: 0.8).padding(.leading, 12)
            accessRow
            Rectangle().fill(RexTheme.hairline).frame(height: 0.8).padding(.leading, 12)
            HStack(spacing: 10) {
                Toggle("", isOn: autoSizeBinding)
                    .labelsHidden()
                    .tint(RexTheme.mintDeep)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Resize shells to fit this device")
                        .font(RexTheme.text(.subheadline, weight: .medium))
                        .foregroundStyle(RexTheme.ink)
                    Text("Takes terminal ownership while the app is open.")
                        .font(.caption2)
                        .foregroundStyle(RexTheme.secondaryInk)
                }
                Spacer(minLength: 0)
            }
            .padding(12)
        }
        .rexCard(radius: 12)
    }

    @ViewBuilder
    private var accessRow: some View {
        Button {
            withAnimation(.snappy(duration: 0.2)) { showAccess.toggle() }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "lock.shield")
                    .font(RexTheme.text(.subheadline))
                    .foregroundStyle(RexTheme.secondaryInk)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Cloudflare Access")
                        .font(RexTheme.text(.subheadline, weight: .medium))
                        .foregroundStyle(RexTheme.ink)
                    Text(draft.usesAccessToken ? "Service token saved" : "For servers behind a tunnel")
                        .font(.caption2)
                        .foregroundStyle(RexTheme.secondaryInk)
                }
                Spacer(minLength: 0)
                Image(systemName: showAccess ? "chevron.up" : "chevron.down")
                    .font(RexTheme.text(.caption, weight: .semibold))
                    .foregroundStyle(RexTheme.secondaryInk)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(12)
        .accessibilityIdentifier("accessToggleButton")

        if showAccess {
            Rectangle().fill(RexTheme.hairline).frame(height: 0.8).padding(.leading, 12)
            field(label: "Access ID", icon: "person.badge.key") {
                TextField("Client ID", text: accessIDBinding)
                    .font(RexTheme.monoText(.body))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("accessIDField")
            }
            Rectangle().fill(RexTheme.hairline).frame(height: 0.8).padding(.leading, 12)
            field(label: "Access secret", icon: "key.horizontal") {
                SecureField("Client secret", text: accessSecretBinding)
                    .font(RexTheme.monoText(.body))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("accessSecretField")
            }
        }
    }

    private func field<Content: View>(
        label: String,
        icon: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(RexTheme.text(.subheadline))
                .foregroundStyle(RexTheme.secondaryInk)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 3) {
                Text(label)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(RexTheme.secondaryInk)
                content()
                    .foregroundStyle(RexTheme.ink)
            }
        }
        .padding(12)
    }

    private var connectButton: some View {
        Button(action: connect) {
            HStack(spacing: 8) {
                if isConnecting {
                    ProgressView()
                        .controlSize(.small)
                        .tint(RexTheme.mint)
                } else {
                    Text(">_")
                        .font(RexTheme.mono(13, weight: .bold))
                        .foregroundStyle(RexTheme.mint)
                }
                Text(isConnecting ? "Connecting…" : "Connect")
                    .font(RexTheme.text(.headline, weight: .semibold))
                    .foregroundStyle(RexTheme.chipInk)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .glassEffect(RexTheme.glass(RexTheme.chipGlass.opacity(0.95), interactive: true), in: .capsule)
        }
        .buttonStyle(.plain)
        .disabled(isConnecting)
        .accessibilityIdentifier("connectButton")
    }

    private var savedHosts: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Saved servers")
                .font(.caption.weight(.semibold))
                .foregroundStyle(RexTheme.secondaryInk)
            ForEach(connection.hosts.hosts) { saved in
                HStack(spacing: 10) {
                    Image(systemName: saved.id == host.id ? "checkmark.circle.fill" : "circle")
                        .font(RexTheme.text(.subheadline))
                        .foregroundStyle(saved.id == host.id ? RexTheme.mintDeep : RexTheme.secondaryInk.opacity(0.6))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(saved.name).font(RexTheme.text(.subheadline, weight: .medium)).foregroundStyle(RexTheme.ink)
                        Text(saved.address).font(RexTheme.mono(11)).foregroundStyle(RexTheme.secondaryInk)
                    }
                    Spacer()
                    Button {
                        editHost(saved)
                    } label: {
                        Image(systemName: "pencil").font(RexTheme.text(.footnote)).foregroundStyle(RexTheme.secondaryInk)
                    }
                    .buttonStyle(.plain)
                }
                .padding(12)
                .rexCard(radius: 10)
                .contentShape(Rectangle())
                .onTapGesture {
                    connection.hosts.selectedID = saved.id
                    draft = saved
                }
            }
        }
        .sheet(item: $editingHost) { editing in
            HostEditor(host: editing) { updated in
                connection.hosts.upsert(updated)
                draft = updated
            }
        }
    }

    private var addressBinding: Binding<String> {
        Binding(
            get: { draft.address },
            set: { newValue in
                draft.address = newValue
                commitDraft()
            }
        )
    }

    private var tokenBinding: Binding<String> {
        Binding(
            get: { draft.token ?? "" },
            set: { newValue in
                draft.token = newValue.isEmpty ? nil : newValue
                commitDraft()
            }
        )
    }

    private var accessIDBinding: Binding<String> {
        Binding(
            get: { draft.accessClientID ?? "" },
            set: { newValue in
                draft.accessClientID = newValue.isEmpty ? nil : newValue
                commitDraft()
            }
        )
    }

    private var accessSecretBinding: Binding<String> {
        Binding(
            get: { draft.accessClientSecret ?? "" },
            set: { newValue in
                draft.accessClientSecret = newValue.isEmpty ? nil : newValue
                commitDraft()
            }
        )
    }

    private var autoSizeBinding: Binding<Bool> {
        Binding(
            get: { draft.autoSize },
            set: { newValue in
                draft.autoSize = newValue
                commitDraft()
            }
        )
    }

    private func commitDraft() {
        var updated = draft
        if updated.name.isEmpty { updated.name = "Rex Server" }
        connection.hosts.upsert(updated)
        draft = updated
    }

    private func saveDraftAsHost() {
        var updated = draft
        updated.name = updated.name.isEmpty ? "Rex Server" : updated.name
        connection.hosts.upsert(updated)
        draft = updated
    }

    private func editHost(_ candidate: HostConfig) {
        editingHost = candidate
    }

    private func connect() {
        guard !isConnecting else { return }
        commitDraft()
        isConnecting = true
        Task {
            await connection.connect()
            isConnecting = false
        }
    }
}
