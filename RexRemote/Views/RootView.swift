import SwiftUI

struct RootView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        NavigationStack {
            Group {
                if store.connection.isConnected {
                    SessionListView()
                } else {
                    ConnectView()
                }
            }
            .background(RexTheme.paper.ignoresSafeArea())
        }
        .tint(RexTheme.mintDeep)
    }
}

/// Paper page, white card, dark chip button — the same vocabulary as the Mac app.
struct ConnectView: View {
    @EnvironmentObject private var store: AppStore
    @State private var draft: HostConfig = .loopback
    @State private var editingHost: HostConfig?
    @State private var isConnecting = false

    private var host: HostConfig { store.hosts.selected ?? .loopback }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                card
                connectButton
                statusView
                if store.hosts.hosts.count > 1 {
                    savedHosts
                }
            }
            .padding(20)
        }
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    ForEach(store.hosts.hosts) { candidate in
                        Button {
                            store.hosts.selectedID = candidate.id
                            store.hosts.upsert(candidate)
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
                }
                .accessibilityIdentifier("hostMenuButton")
            }
        }
        .onAppear { draft = host }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(">_")
                    .font(RexTheme.mono(13, weight: .bold))
                    .foregroundStyle(RexTheme.mintDeep)
                Text("remote")
                    .font(RexTheme.mono(13))
                    .foregroundStyle(RexTheme.secondaryInk)
            }
            Text("Rex Remote")
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(RexTheme.ink)
            Text(host.name)
                .font(.system(size: 17, weight: .semibold))
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
                TextField("127.0.0.1:7297", text: addressBinding)
                    .font(RexTheme.mono(13))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .onSubmit { connect() }
                    .accessibilityIdentifier("serverAddressField")
            }
            Rectangle().fill(RexTheme.hairline).frame(height: 0.8).padding(.leading, 12)
            field(label: "Token", icon: "key") {
                SecureField("Optional bearer token", text: tokenBinding)
                    .font(RexTheme.mono(13))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("tokenField")
            }
            Rectangle().fill(RexTheme.hairline).frame(height: 0.8).padding(.leading, 12)
            HStack(spacing: 10) {
                Toggle("", isOn: autoSizeBinding)
                    .labelsHidden()
                    .tint(RexTheme.mintDeep)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Resize shells to fit this device")
                        .font(.system(size: 13, weight: .medium))
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

    private func field<Content: View>(
        label: String,
        icon: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13))
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
                    .font(.system(size: 15, weight: .semibold))
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

    @ViewBuilder
    private var statusView: some View {
        switch store.connection {
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

    private var savedHosts: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Saved servers")
                .font(.caption.weight(.semibold))
                .foregroundStyle(RexTheme.secondaryInk)
            ForEach(store.hosts.hosts) { saved in
                HStack(spacing: 10) {
                    Image(systemName: saved.id == host.id ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 14))
                        .foregroundStyle(saved.id == host.id ? RexTheme.mintDeep : RexTheme.secondaryInk.opacity(0.6))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(saved.name).font(.system(size: 13, weight: .medium)).foregroundStyle(RexTheme.ink)
                        Text(saved.address).font(RexTheme.mono(11)).foregroundStyle(RexTheme.secondaryInk)
                    }
                    Spacer()
                    Button {
                        editHost(saved)
                    } label: {
                        Image(systemName: "pencil").font(.system(size: 12)).foregroundStyle(RexTheme.secondaryInk)
                    }
                    .buttonStyle(.plain)
                }
                .padding(12)
                .rexCard(radius: 10)
                .contentShape(Rectangle())
                .onTapGesture {
                    store.hosts.selectedID = saved.id
                    draft = saved
                }
            }
        }
        .sheet(item: $editingHost) { editing in
            HostEditor(host: editing) { updated in
                store.hosts.upsert(updated)
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
        store.hosts.upsert(updated)
        draft = updated
    }

    private func saveDraftAsHost() {
        var updated = draft
        updated.name = updated.name.isEmpty ? "Rex Server" : updated.name
        store.hosts.upsert(updated)
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
            await store.connect()
            isConnecting = false
        }
    }
}

struct HostEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var address: String
    let host: HostConfig
    let onSave: (HostConfig) -> Void

    init(host: HostConfig, onSave: @escaping (HostConfig) -> Void) {
        self.host = host
        self.onSave = onSave
        _name = State(initialValue: host.name)
        _address = State(initialValue: host.address)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                    TextField("Address", text: $address)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.body.monospaced())
                }
            }
            .navigationTitle("Server")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        var updated = host
                        updated.name = name.trimmingCharacters(in: .whitespaces)
                        updated.address = address.trimmingCharacters(in: .whitespaces)
                        onSave(updated)
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium])
        .tint(RexTheme.mintDeep)
    }
}
