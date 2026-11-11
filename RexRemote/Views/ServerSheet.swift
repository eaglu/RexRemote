import SwiftUI

/// What the server knows about itself: identity, who is connected, and the other
/// Rex hosts it can reach. Everything here comes from methods the app never
/// called before (`server.status`, `server.whoami`, `client.list`, `hosts.*`).
struct ServerSheet: View {
    @ObservedObject var store: AppStore

    @Environment(\.dismiss) private var dismiss

    @State private var info: ServerInfo?
    @State private var whoami: String?
    @State private var clients: [ClientInfo] = []
    @State private var hosts: [RemoteHost] = []
    @State private var newLabel = ""
    @State private var newEndpoint = ""
    @State private var isLoading = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    statusCard
                    clientsCard
                    hostsCard
                }
                .padding(16)
            }
            .background(RexTheme.paper.ignoresSafeArea())
            .navigationTitle("Server")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await reload() }
                    } label: {
                        if isLoading { ProgressView() } else { Image(systemName: "arrow.clockwise") }
                    }
                    .accessibilityIdentifier("serverRefresh")
                }
            }
            .task { await reload() }
        }
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("This server")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(RexTheme.ink)
            row("Address", store.host.address)
            if let whoami { row("You are", whoami) }
            if let info {
                row("Version", info.apiRevision.map { "api \($0)" } ?? "—")
                row("PID", info.pid.map(String.init) ?? "—")
                row("Sessions", info.sessionCount.map(String.init) ?? "—")
                row("Host", info.hostID ?? "—")
                row("Tailscale", info.tailscale ?? "—")
            }
            if info == nil {
                Text("server.status unavailable on this server.")
                    .font(.footnote)
                    .foregroundStyle(RexTheme.secondaryInk)
            }
        }
        .rexCard()
    }

    private var clientsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Connected clients")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(RexTheme.ink)
            if clients.isEmpty {
                Text("None reported.")
                    .font(.footnote)
                    .foregroundStyle(RexTheme.secondaryInk)
            }
            ForEach(clients) { client in
                HStack(spacing: 8) {
                    Text(">_")
                        .font(RexTheme.mono(11, weight: .bold))
                        .foregroundStyle(RexTheme.mintDeep)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(client.label)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(RexTheme.ink)
                            .lineLimit(1)
                        Text([client.kind, client.platform].filter { !$0.isEmpty }.joined(separator: " · "))
                            .font(.system(size: 11))
                            .foregroundStyle(RexTheme.secondaryInk)
                    }
                    Spacer(minLength: 0)
                    if client.isResumed {
                        Text("resumed")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(RexTheme.mintDeep)
                    }
                }
            }
        }
        .rexCard()
    }

    private var hostsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Other Rex hosts")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(RexTheme.ink)
            if hosts.isEmpty {
                Text("This server reaches no other hosts.")
                    .font(.footnote)
                    .foregroundStyle(RexTheme.secondaryInk)
            }
            ForEach(hosts) { host in
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(host.label)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(RexTheme.ink)
                        Text(host.endpoints.first ?? host.id)
                            .font(.system(size: 11))
                            .foregroundStyle(RexTheme.secondaryInk)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    Button {
                        Task {
                            await store.removeHost(host.id)
                            await reloadHosts()
                        }
                    } label: {
                        Image(systemName: "minus.circle")
                            .font(.system(size: 14))
                            .foregroundStyle(RexTheme.secondaryInk)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("removeHost-\(host.label)")
                }
            }
            HStack(spacing: 8) {
                TextField("label", text: $newLabel)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.system(size: 13))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(RexTheme.fill, in: .rect(cornerRadius: 9))
                    .accessibilityIdentifier("hostLabelField")
                TextField("host:port", text: $newEndpoint)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.system(size: 13))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(RexTheme.fill, in: .rect(cornerRadius: 9))
                    .accessibilityIdentifier("hostEndpointField")
                Button {
                    let label = newLabel.trimmingCharacters(in: .whitespaces)
                    let endpoint = newEndpoint.trimmingCharacters(in: .whitespaces)
                    guard !label.isEmpty, !endpoint.isEmpty else { return }
                    Task {
                        await store.addHost(label: label, endpoint: endpoint)
                        newLabel = ""
                        newEndpoint = ""
                        await reloadHosts()
                    }
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(RexTheme.mintDeep)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("addHostButton")
            }
        }
        .rexCard()
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(RexTheme.secondaryInk)
                .frame(width: 78, alignment: .leading)
            Text(value)
                .font(RexTheme.mono(12))
                .foregroundStyle(RexTheme.ink)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
        }
    }

    private func reload() async {
        isLoading = true
        async let status = store.loadServerInfo()
        async let me = store.loadWhoAmI()
        async let peers = store.loadClients()
        async let remotes = store.loadHosts()
        info = await status
        whoami = await me
        clients = await peers
        hosts = await remotes
        isLoading = false
    }

    private func reloadHosts() async {
        hosts = await store.loadHosts()
    }
}
