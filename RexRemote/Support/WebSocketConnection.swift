import Foundation

/// A minimal RFC 6455 client on top of `URLSessionWebSocketTask`.
///
/// Network.framework's WebSocket protocol never completes the upgrade when a
/// system HTTP proxy or Cloudflare Access sits in the path (the socket sticks in
/// `in_progress`, so `hello` is never sent and the server closes the connection
/// after its five second grace). `URLSessionWebSocketTask` handles those hops,
/// honours custom handshake headers, and still hands us the negotiated
/// subprotocol and close codes.
final class WebSocketConnection: NSObject {
    enum Message {
        case text(Data)
        case binary(Data)
    }

    /// Called on the main queue once the handshake completed.
    var onOpen: (() -> Void)?
    /// Called on the main queue for every complete text or binary message.
    var onMessage: ((Message) -> Void)?
    /// Called on the main queue once, when the connection ends or fails.
    var onClose: ((String?) -> Void)?
    /// Called on the main queue for a transient problem (the connection may recover).
    var onProblem: ((String) -> Void)?

    private var session: URLSession?
    private var task: URLSessionWebSocketTask?
    private var reported = false
    private var open = false

    var isOpen: Bool { open }
    private(set) var selectedSubprotocol: String?

    func connect(url: URL, subprotocols: [String], headers: [(name: String, value: String)]) {
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        for header in headers {
            request.setValue(header.value, forHTTPHeaderField: header.name)
        }
        if let first = subprotocols.first {
            request.setValue(first, forHTTPHeaderField: "Sec-WebSocket-Protocol")
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.waitsForConnectivity = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        self.session = session

        let task = session.webSocketTask(with: request)
        task.maximumMessageSize = 8 * 1024 * 1024
        self.task = task
        task.resume()
        receiveLoop()
    }

    func send(text: String) {
        send(.string(text))
    }

    func send(binary: Data) {
        send(.data(binary))
    }

    func close(andReport reason: String? = nil) {
        finish(reason)
    }

    // MARK: - Internals

    private func send(_ message: URLSessionWebSocketTask.Message) {
        guard let task else {
            finish("connection closed")
            return
        }
        task.send(message) { [weak self] error in
            guard let error else { return }
            self?.finish(error.localizedDescription)
        }
    }

    private func receiveLoop() {
        guard let task else { return }
        task.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let message):
                switch message {
                case .string(let text):
                    self.post { $0.onMessage?(.text(Data(text.utf8))) }
                case .data(let data):
                    self.post { $0.onMessage?(.binary(data)) }
                @unknown default:
                    break
                }
                self.receiveLoop()
            case .failure(let error):
                self.finish(error.localizedDescription)
            }
        }
    }

    private func finish(_ reason: String?) {
        guard !reported else { return }
        reported = true
        open = false
        let session = self.session
        let task = self.task
        self.session = nil
        self.task = nil
        task?.cancel(with: .normalClosure, reason: nil)
        session?.invalidateAndCancel()
        post { $0.onClose?(reason) }
    }

    private func post(_ body: @escaping (WebSocketConnection) -> Void) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            body(self)
        }
    }
}

extension WebSocketConnection: URLSessionWebSocketDelegate {
    func urlSession(_ session: URLSession,
                    webSocketTask: URLSessionWebSocketTask,
                    didOpenWithProtocol protocol: String?) {
        selectedSubprotocol = `protocol`
        open = true
        post { $0.onOpen?() }
    }

    func urlSession(_ session: URLSession,
                    webSocketTask: URLSessionWebSocketTask,
                    didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
                    reason: Data?) {
        let text = reason.flatMap { String(data: $0, encoding: .utf8) }
        switch (text?.isEmpty ?? true, closeCode.rawValue) {
        case (true, 1000):
            finish(nil)
        case (true, let code):
            finish("closed (\(code))")
        case (false, let code):
            finish("closed (\(code)): \(text ?? "")")
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        finish(error?.localizedDescription)
    }
}
