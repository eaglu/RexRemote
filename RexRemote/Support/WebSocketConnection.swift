import Foundation
import Network

/// A minimal RFC 6455 client on top of Network.framework.
///
/// Network.framework owns the framing (fragmentation, ping/pong, close codes);
/// this class owns the connection lifecycle and marshals messages to the main
/// actor so callers can stay UI-shaped.
final class WebSocketConnection {
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

    private let queue = DispatchQueue(label: "com.faye.RexRemote.ws")
    private var connection: NWConnection?
    private var reported = false
    private var open = false

    var isOpen: Bool { open }
    private(set) var selectedSubprotocol: String?

    func connect(url: URL, subprotocols: [String], headers: [(name: String, value: String)]) {
        let tcp = NWProtocolTCP.Options()
        tcp.noDelay = true
        let tls = NWProtocolTLS.Options()
        let parameters: NWParameters
        switch url.scheme?.lowercased() {
        case "wss", "https":
            parameters = NWParameters(tls: tls, tcp: tcp)
        default:
            parameters = NWParameters(tls: nil, tcp: tcp)
        }

        let options = NWProtocolWebSocket.Options()
        options.autoReplyPing = true
        options.maximumMessageSize = 8 * 1024 * 1024
        if !subprotocols.isEmpty { options.setSubprotocols(subprotocols) }
        if !headers.isEmpty {
            options.setAdditionalHeaders(headers.map { (name: $0.name, value: $0.value) })
        }
        parameters.defaultProtocolStack.applicationProtocols.insert(options, at: 0)

        let connection = NWConnection(to: .url(url), using: parameters)
        self.connection = connection
        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                self.open = true
                self.selectedSubprotocol = self.websocketMetadata()?.selectedSubprotocol
                self.onOpenOnMain()
            case .waiting(let error):
                self.onProblemOnMain(Self.describe(error))
            case .failed(let error):
                self.finish(Self.describe(error))
            case .cancelled:
                self.finish(nil)
            default:
                break
            }
        }
        connection.start(queue: queue)
    }

    func send(text: String) {
        send(data: Data(text.utf8), opcode: .text)
    }

    func send(binary: Data) {
        send(data: binary, opcode: .binary)
    }

    func close(andReport reason: String? = nil) {
        guard let connection else {
            finish(reason)
            return
        }
        let metadata = NWProtocolWebSocket.Metadata(opcode: .close)
        metadata.closeCode = .protocolCode(.normalClosure)
        let context = NWConnection.ContentContext(identifier: "close", metadata: [metadata])
        connection.send(content: nil, contentContext: context, isComplete: true, completion: .contentProcessed { _ in
            connection.cancel()
        })
        finish(reason)
    }

    // MARK: - Internals

    private func send(data: Data, opcode: NWProtocolWebSocket.Opcode) {
        guard let connection, open else { return }
        let metadata = NWProtocolWebSocket.Metadata(opcode: opcode)
        let context = NWConnection.ContentContext(identifier: "ws-message", metadata: [metadata])
        connection.send(content: data, contentContext: context, isComplete: true, completion: .contentProcessed { [weak self] error in
            guard let error else { return }
            self?.finish(Self.describe(error))
        })
    }

    private func websocketMetadata() -> NWProtocolWebSocket.Metadata? {
        connection?.metadata(definition: NWProtocolWebSocket.definition) as? NWProtocolWebSocket.Metadata
    }

    private func receiveLoop() {
        guard let connection else { return }
        connection.receiveMessage { [weak self] data, context, _, error in
            guard let self else { return }
            if let error {
                self.finish(Self.describe(error))
                return
            }
            let metadata = context?.protocolMetadata(definition: NWProtocolWebSocket.definition) as? NWProtocolWebSocket.Metadata
            switch metadata?.opcode {
            case .text:
                if let data { self.post { $0.onMessage?(.text(data)) } }
            case .binary:
                if let data { self.post { $0.onMessage?(.binary(data)) } }
            case .close:
                var reason: String?
                if case .protocolCode(let code)? = metadata?.closeCode { reason = "closed (\(code))" }
                self.finish(reason)
                return
            default:
                break
            }
            self.receiveLoop()
        }
    }

    private func finish(_ reason: String?) {
        guard !reported else { return }
        reported = true
        open = false
        let connection = self.connection
        self.connection = nil
        connection?.stateUpdateHandler = nil
        connection?.cancel()
        post { $0.onClose?(reason) }
    }

    private func post(_ body: @escaping (WebSocketConnection) -> Void) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            body(self)
        }
    }

    private func onOpenOnMain() {
        post { connection in
            connection.onOpen?()
            connection.receiveLoop()
        }
    }

    private func onProblemOnMain(_ message: String) {
        post { $0.onProblem?(message) }
    }

    private static func describe(_ error: NWError) -> String {
        switch error {
        case .posix(let code): return "network error: \(code)"
        case .dns(let code): return "dns error: \(code)"
        case .tls(let status): return "tls error: \(status)"
        @unknown default: return "network error"
        }
    }
}
