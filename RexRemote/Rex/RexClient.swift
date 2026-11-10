import Foundation

struct RexError: LocalizedError {
    let code: String
    let message: String

    var errorDescription: String? {
        message.isEmpty ? code : "\(message) (\(code))"
    }
}

/// One control connection: `GET /api/control`, subprotocol `rex.control.v1`.
@MainActor
final class RexClient {
    let host: HostConfig

    private let socket = WebSocketConnection()
    private var nextRequestID = 1
    private var pending: [String: CheckedContinuation<JSONObject, Error>] = [:]
    private var welcomeWaiter: CheckedContinuation<JSONObject, Error>?
    private var lastSeq = 0
    private var closedReason: String?

    private(set) var clientID: String?
    private(set) var reconnectToken: String?
    private(set) var serverRevision: Int?

    var onEvent: ((JSONObject) -> Void)?
    var onDisconnect: ((String?) -> Void)?

    init(host: HostConfig) {
        self.host = host
    }

    var isConnected: Bool { socket.isOpen }

    // MARK: - Lifecycle

    /// Opens the socket and completes once the server's `welcome` arrives.
    func connect() async throws -> JSONObject {
        let url = try host.controlURL()
        let headers = host.handshakeHeaders
        socket.onOpen = { [weak self] in
            // The server closes the connection if `hello` does not arrive within 5s.
            self?.sendHello()
        }
        socket.onMessage = { [weak self] message in
            guard let self, case .text(let data) = message else { return }
            self.receive(data)
        }
        socket.onClose = { [weak self] reason in
            self?.handleClose(reason)
        }
        socket.onProblem = { _ in
            // Waiting states are transient (DNS, unreachable host); the close
            // path reports the final failure.
        }

        return try await withCheckedThrowingContinuation { continuation in
            self.welcomeWaiter = continuation
            self.closedReason = nil
            self.socket.connect(url: url, subprotocols: [RexProtocol.controlSubprotocol], headers: headers)

            // Guard against a handshake that never answers.
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: 12_000_000_000)
                guard let self, self.welcomeWaiter != nil else { return }
                self.failAll(RexError(code: "timeout", message: "The server did not answer the handshake."))
            }
        }
    }

    func disconnect() {
        socket.close()
        failAll(RexError(code: "closed", message: "Disconnected"))
        onDisconnect?(nil)
    }

    // MARK: - Requests

    func call(_ method: String, _ payload: JSONObject? = nil) async throws -> JSONObject {
        guard socket.isOpen else {
            throw RexError(code: "closed", message: "Not connected")
        }
        let id = String(nextRequestID)
        nextRequestID += 1
        var message: JSONObject = ["type": "request", "id": id, "method": method]
        if let payload { message["payload"] = payload }
        let text = try JSONCoding.text(message)

        return try await withCheckedThrowingContinuation { continuation in
            self.pending[id] = continuation
            self.socket.send(text: text)
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: 25_000_000_000)
                guard let self, let waiter = self.pending.removeValue(forKey: id) else { return }
                waiter.resume(throwing: RexError(code: "timeout", message: "\(method) timed out."))
            }
        }
    }

    // MARK: - Inbound

    private func sendHello() {
        var client: JSONObject = [
            "kind": "app",
            "platform": "ios",
            "name": "Rex Remote",
            "version": (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "0.1"
        ]
        client["label"] = "Rex Remote"
        var hello: JSONObject = [
            "type": "hello",
            "api_revision": RexProtocol.apiRevision,
            "api_min_revision": RexProtocol.apiMinRevision,
            "client": client
        ]
        if let reconnectToken { hello["reconnect_token"] = reconnectToken }
        if let text = try? JSONCoding.text(hello) {
            socket.send(text: text)
        }
    }

    private func receive(_ data: Data) {
        guard let message = JSONCoding.object(from: data) else { return }
        switch message.string("type") {
        case "welcome":
            lastSeq = 0
            clientID = message.object("client")?.string("id")
            reconnectToken = message.object("client")?.string("reconnect_token")
            serverRevision = message.int("api_server_revision")
            let waiter = welcomeWaiter
            welcomeWaiter = nil
            if waiter != nil {
                waiter?.resume(returning: message)
            } else {
                // A resumed connection: re-bootstrap from the caller's side.
                onEvent?(["type": "event", "payload": ["type": "resumed"]])
            }
        case "response":
            if let seq = message.int("seq") { lastSeq = max(lastSeq, seq) }
            guard let id = message.string("id"), let waiter = pending.removeValue(forKey: id) else { return }
            if let error = message.object("error") {
                waiter.resume(throwing: RexError(
                    code: error.string("code") ?? "error",
                    message: error.string("message") ?? "Request failed"
                ))
            } else {
                waiter.resume(returning: message.object("payload") ?? [:])
            }
        case "event":
            let seq = message.int("seq") ?? 0
            if seq <= lastSeq { return }
            lastSeq = seq
            onEvent?(message)
        default:
            break
        }
    }

    private func handleClose(_ reason: String?) {
        if let waiter = welcomeWaiter {
            welcomeWaiter = nil
            waiter.resume(throwing: RexError(code: "closed", message: reason ?? "Connection closed"))
        }
        failAll(RexError(code: "closed", message: reason ?? "Connection closed"))
        onDisconnect?(reason)
    }

    private func failAll(_ error: Error) {
        let waiters = pending
        pending.removeAll()
        for waiter in waiters.values {
            waiter.resume(throwing: error)
        }
    }
}

enum RexProtocol {
    static let apiRevision = 11
    static let apiMinRevision = 0
    static let controlSubprotocol = "rex.control.v1"
    static let terminalSubprotocol = "rex.data.terminal.v1"
}
