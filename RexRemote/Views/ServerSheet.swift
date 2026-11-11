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
                VStack(alignment: .leading, spacing: 18) {
                    header
                    aboutCard
                    clientsCard
                    hostsCard
                }
                .padding(.horizontal, 18)
                .padding(.top, 6)
                .padding(.bottom, 28)
            }
            .scrollIndicators(.hidden)
            .background(RexTheme.paper.ignoresSafeArea())
            .navigationTitle("Server")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(RexTheme.mintDeep)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await reload() }
                    } label: {
                        if isLoading {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "arrow.clockwise")
                                .foregroundStyle(RexTheme.mintDeep)
                        }
                    }
                    .accessibilityIdentifier("serverRefresh")
                }
            }
            .task { await reload() }
        }
    }

    // MARK: - Header

    /// The address is the one fact worth reading at a glance, so it gets its own
    /// block instead of a label/value row.
    private var header: some View {
        VStack(alignment: .leading, spacing: 7) {
            sectionLabel("This server")
            Text(store.host.address)
                .font(RexTheme.mono(17, weight: .semibold))
                .foregroundStyle(RexTheme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if let whoami {
                Text(whoami)
                    .font(.system(size: 12))
                    .foregroundStyle(RexTheme.secondaryInk)
                    .lineLimit(1)
            }
            HStack(spacing: 6) {
                statPill(
                    "square.split.2x1",
                    value: info?.sessionCount.map(String.init) ?? "—",
                    unit: info?.sessionCount == 1 ? "session" : "sessions"
                )
                statPill("iphone.gen3", value: "\(clients.count)", unit: clients.count == 1 ? "client" : "clients")
                statPill("link", value: tailscaleLabel, unit: "tailscale")
            }
            .padding(.top, 3)
        }
    }

    private var tailscaleLabel: String {
        guard let state = info?.tailscale, !state.isEmpty else { return "—" }
        switch state {
        case "running": return "on"
        case "disabled", "off": return "off"
        default: return state
        }
    }

    private func statPill(_ symbol: String, value: String, unit: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(RexTheme.secondaryInk)
            Text(value)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(RexTheme.ink)
            Text(unit)
                .font(.system(size: 11))
                .foregroundStyle(RexTheme.secondaryInk)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(RexTheme.card, in: .capsule)
        .overlay(Capsule().stroke(RexTheme.hairline, lineWidth: 0.8))
    }

    // MARK: - About

    private var aboutCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("About")
            if let info {
                HStack(spacing: 14) {
                    fact("api", info.apiRevision.map(String.init) ?? "—")
                    fact("pid", info.pid.map(String.init) ?? "—")
                    if let started = startedLabel {
                        fact("up since", started)
                    }
                }
            } else {
                Text("server.status unavailable on this server.")
                    .font(.footnote)
                    .foregroundStyle(RexTheme.secondaryInk)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .rexCard()
    }

    private func fact(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(RexTheme.secondaryInk)
            Text(value)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(RexTheme.ink)
        }
    }

    /// `started_at` is ISO-8601 with fractional seconds; a wall clock time is
    /// friendlier than the raw stamp.
    private var startedLabel: String? {
        guard let raw = info?.startedAt else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = formatter.date(from: raw) ?? ISO8601DateFormatter().date(from: raw) else {
            return nil
        }
        let clock = DateFormatter()
        clock.dateFormat = "HH:mm"
        return clock.string(from: date)
    }

    // MARK: - Clients

    private var clientsCard: some View {
        VStack(alignment: .leading, spacing: 11) {
            sectionLabel("Connected clients")
            if clients.isEmpty {
                Text("None reported.")
                    .font(.system(size: 12))
                    .foregroundStyle(RexTheme.secondaryInk)
            }
            ForEach(clients) { client in
                HStack(spacing: 9) {
                    Text(">_")
                        .font(RexTheme.mono(11, weight: .bold))
                        .foregroundStyle(RexTheme.mintDeep)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(clientName(client))
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(RexTheme.ink)
                                .lineLimit(1)
                            if isUs(client) {
                                Text("this phone")
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundStyle(RexTheme.chipInk)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(RexTheme.chip, in: .capsule)
                            }
                        }
                        Text(clientDetail(client))
                            .font(RexTheme.mono(10.5))
                            .foregroundStyle(RexTheme.secondaryInk)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    if client.isResumed {
                        Text("resumed")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(RexTheme.mintDeep)
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .rexCard()
    }

    private func isUs(_ client: ClientInfo) -> Bool {
        store.client?.clientID == client.id
    }

    /// `client:01a1c804-…` is not a name; the tail of the id is enough to tell
    /// two connections apart.
    private func clientName(_ client: ClientInfo) -> String {
        if isUs(client) { return "Rex Remote" }
        let short = client.id.split(separator: ":").last.map(String.init) ?? client.id
        let kind = client.kind.isEmpty ? "Client" : client.kind.capitalized
        return "\(kind) \(short.prefix(6))"
    }

    private func clientDetail(_ client: ClientInfo) -> String {
        [client.platform, String(client.id.suffix(8))]
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }

    // MARK: - Hosts

    private var hostsCard: some View {
        VStack(alignment: .leading, spacing: 11) {
            sectionLabel("Other Rex hosts")
            if hosts.isEmpty {
                Text("This server reaches no other hosts.")
                    .font(.system(size: 12))
                    .foregroundStyle(RexTheme.secondaryInk)
            }
            ForEach(hosts) { host in
                HStack(spacing: 9) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(host.label)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(RexTheme.ink)
                        Text(host.endpoints.first ?? host.id)
                            .font(RexTheme.mono(10.5))
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
                            .font(.system(size: 15))
                            .foregroundStyle(RexTheme.secondaryInk)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("removeHost-\(host.label)")
                }
            }
            addHostForm
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .rexCard()
    }

    private var addHostForm: some View {
        HStack(spacing: 7) {
            hostField("label", text: $newLabel, identifier: "hostLabelField")
                .frame(width: 92)
            hostField("host:port", text: $newEndpoint, identifier: "hostEndpointField")
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
                Image(systemName: "arrow.up")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(RexTheme.mint)
                    .frame(width: 30, height: 30)
                    .background(RexTheme.chip, in: .circle)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("addHostButton")
        }
        .padding(.top, 2)
    }

    private func hostField(
        _ prompt: String,
        text: Binding<String>,
        identifier: String
    ) -> some View {
        TextField(prompt, text: text)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .font(RexTheme.mono(12))
            .foregroundStyle(RexTheme.ink)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(RexTheme.strip, in: .rect(cornerRadius: 9))
            .overlay(
                RoundedRectangle(cornerRadius: 9)
                    .strokeBorder(RexTheme.hairline, lineWidth: 1)
            )
            .accessibilityIdentifier(identifier)
    }

    // MARK: - Plumbing

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .textCase(.uppercase)
            .tracking(0.6)
            .foregroundStyle(RexTheme.secondaryInk)
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
