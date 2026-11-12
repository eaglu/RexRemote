import Foundation

/// Everything about reaching the server: the saved hosts, the socket, the
/// handshake, the keepalive, and the small `server.*` / `hosts.*` admin calls.
///
/// Sessions, windows and panes live in `SessionViewModel`; it reads the socket
/// through this store, and this store tells it when to reset (a new connection,
/// or a socket that went away).
@MainActor
final class ConnectionStore: ObservableObject {
    let hosts = HostStore()

    @Published private(set) var client: RexClient?
    @Published private(set) var connection: ConnectionState = .disconnected(nil)
    @Published var errorMessage: String?

    /// Identifies the current socket so callbacks from an old one are ignored.
    private(set) var generation = 0
    private var keepaliveTask: Task<Void, Never>?
    private var resumeAttempts = 0
    private var isStopping = false

    /// Weak so the store never keeps the session side alive.
    private weak var sessions: SessionViewModel?

    var host: HostConfig { hosts.selected ?? .loopback }
    var shouldOwnTerminalSizing: Bool { host.autoSize }

    func attach(sessions: SessionViewModel) {
        self.sessions = sessions
    }

    // MARK: - Lifecycle

    func connect() async {
        generation += 1
        let token = generation

        isStopping = false
        resumeAttempts = 0
        keepaliveTask?.cancel()
        keepaliveTask = nil
        client?.disconnect()
        sessions?.resetForNewConnection()
        errorMessage = nil
        connection = .connecting

        let client = RexClient(host: host)
        self.client = client
        client.onEvent = { [weak self] event in
            guard let self, self.generation == token else { return }
            self.sessions?.handle(envelope: event)
        }
        client.onDisconnect = { [weak self] reason in
            guard let self, self.generation == token else { return }
            self.sessions?.resetForDisconnect()
            self.scheduleResume(after: reason, token: token)
        }

        do {
            _ = try await client.connect()
            guard generation == token else { return }
            let payload = try await client.call("session.bootstrap", ["event_scope": "all"])
            guard generation == token else { return }
            sessions?.applyBootstrap(payload)
            connection = .connected
            startKeepalive(generation: token)
        } catch {
            guard generation == token else { return }
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            connection = .disconnected(message)
            errorMessage = message
        }
    }

    func disconnect() {
        isStopping = true
        resumeAttempts = 0
        client?.onEvent = nil
        client?.onDisconnect = nil
        keepaliveTask?.cancel()
        keepaliveTask = nil
        generation += 1
        client?.disconnect()
        client = nil
        connection = .disconnected(nil)
        sessions?.resetForDisconnect()
    }

    /// Cloudflare closes WebSockets that stay quiet for about a minute and the
    /// server's own ping is every 120s, so a connected app nudges the socket.
    private func startKeepalive(generation token: Int) {
        keepaliveTask?.cancel()
        keepaliveTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 45_000_000_000)
                guard let self else { return }
                guard self.generation == token, self.connection.isConnected else { return }
                _ = try? await self.client?.call("session.list", nil)
            }
        }
    }

    func authHeaders() -> [(name: String, value: String)] {
        var headers: [(name: String, value: String)] = []
        if let id = host.accessClientID, let secret = host.accessClientSecret {
            headers.append(("CF-Access-Client-Id", id))
            headers.append(("CF-Access-Client-Secret", secret))
        }
        if let token = host.token, !token.isEmpty {
            headers.append(("Authorization", "Bearer \(token)"))
        }
        return headers
    }

    // MARK: - Resume

    /// A dropped socket is resumed with the server's reconnect token, three
    /// times with 1s/2s/4s between attempts, before the app gives up and shows
    /// the manual reconnect button.
    private func scheduleResume(after reason: String?, token: Int) {
        guard !isStopping, let previous = client?.reconnectToken else {
            connection = .disconnected(reason)
            return
        }
        guard resumeAttempts < 3 else {
            connection = .disconnected(reason ?? "The connection was lost.")
            return
        }
        resumeAttempts += 1
        let seconds = Double(1 << (resumeAttempts - 1))
        connection = .disconnected("Reconnecting…")
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard let self, self.generation == token, !self.isStopping else { return }
            await self.resume(with: previous, token: token)
        }
    }

    private func resume(with reconnectToken: String, token: Int) async {
        let previous = client
        previous?.onEvent = nil
        previous?.onDisconnect = nil
        previous?.disconnect()

        let client = RexClient(host: host, reconnectToken: reconnectToken)
        self.client = client
        client.onEvent = { [weak self] event in
            guard let self, self.generation == token else { return }
            self.sessions?.handle(envelope: event)
        }
        client.onDisconnect = { [weak self] reason in
            guard let self, self.generation == token else { return }
            self.sessions?.resetForDisconnect()
            self.scheduleResume(after: reason, token: token)
        }

        do {
            _ = try await client.connect()
            guard generation == token else { return }
            let payload = try await client.call("session.bootstrap", ["event_scope": "all"])
            guard generation == token else { return }
            sessions?.applyBootstrap(payload)
            resumeAttempts = 0
            connection = .connected
            startKeepalive(generation: token)
        } catch {
            guard generation == token else { return }
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            scheduleResume(after: message, token: token)
        }
    }

    // MARK: - Server and host admin

    /// A connection-level call: no session scope, unlike the session calls.
    func perform(_ method: String, _ payload: JSONObject?) async -> JSONObject? {
        guard let client else { return nil }
        do {
            return try await client.call(method, payload)
        } catch {
            report(error)
            return nil
        }
    }

    func loadServerInfo() async -> ServerInfo? {
        guard let payload = await perform("server.status", nil) else { return nil }
        return ServerInfo(payload)
    }

    func loadWhoAmI() async -> String? {
        guard let payload = await perform("server.whoami", nil) else { return nil }
        let principal = payload.object("principal")
        // `{principal: {kind, transport, display, remote_addr}, account}` — the
        // whole payload is unrelated to what a person needs to see.
        let display = principal?.string("display") ?? principal?.string("kind")
        let transport = principal?.string("transport")
        let account = payload.string("account")
        return [display, transport, account].compactMap { $0 }.joined(separator: " · ")
    }

    func loadClients() async -> [ClientInfo] {
        guard let payload = await perform("client.list", nil) else { return [] }
        return payload.objects("clients").compactMap(ClientInfo.init)
    }

    func loadHosts() async -> [RemoteHost] {
        guard let payload = await perform("hosts.list", nil) else { return [] }
        return payload.objects("hosts").compactMap(RemoteHost.init)
    }

    func addHost(label: String, endpoint: String) async {
        _ = await perform("hosts.put", [
            "host": ["label": label, "endpoints": [endpoint]],
        ])
    }

    func removeHost(_ id: String) async {
        _ = await perform("hosts.remove", ["id": id])
    }

    func report(_ error: Error) {
        errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}
