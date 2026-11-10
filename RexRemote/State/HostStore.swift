import Foundation

/// A Rex server the app can connect to.
struct HostConfig: Identifiable, Hashable, Codable {
    var id: UUID = UUID()
    var name: String
    var address: String
    var token: String?
    /// Cloudflare Access service token, used when the server is published
    /// through a tunnel that sits behind Zero Trust.
    var accessClientID: String?
    var accessClientSecret: String?
    /// Claim terminal ownership so the remote pty resizes to fit the phone.
    var autoSize: Bool = true

    static let loopback = HostConfig(name: "This Mac", address: "127.0.0.1:7297")

    var displayAddress: String { address }

    /// True when the server is only reachable through Cloudflare Access.
    var usesAccessToken: Bool {
        guard let id = accessClientID, let secret = accessClientSecret else { return false }
        return !id.isEmpty && !secret.isEmpty
    }

    /// Headers sent on both the control and the data WebSocket handshake.
    var handshakeHeaders: [(name: String, value: String)] {
        var headers: [(name: String, value: String)] = []
        if let token, !token.isEmpty {
            headers.append((name: "Authorization", value: "Bearer \(token)"))
        }
        if let id = accessClientID, let secret = accessClientSecret,
           !id.isEmpty, !secret.isEmpty {
            headers.append((name: "CF-Access-Client-Id", value: id))
            headers.append((name: "CF-Access-Client-Secret", value: secret))
        }
        return headers
    }


    /// LAN hosts are written `host:port` and stay plain HTTP; a bare public
    /// name such as a Cloudflare tunnel (`rex.example.com`) gets TLS, because
    /// 443 is the only port a tunnel serves.
    private static func prefersHTTPS(_ text: String) -> Bool {
        let authority = text.split(separator: "/").first.map(String.init) ?? text
        let host = authority.split(separator: ":").first.map(String.init) ?? authority
        let lowercase = host.lowercased()
        if authority.contains(":") { return false }
        if lowercase == "localhost" || lowercase.hasSuffix(".local") { return false }
        if !lowercase.contains(".") { return false }
        let digitsAndDots = lowercase.allSatisfy { $0.isNumber || $0 == "." }
        return !digitsAndDots
    }

    /// Normalizes user input such as `mac.local:7297` into a full URL.
    func baseURL() throws -> URL {
        var text = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw HostError.invalidAddress }
        if !text.contains("://") {
            text = (Self.prefersHTTPS(text) ? "https://" : "http://") + text
        }
        guard var components = URLComponents(string: text) else { throw HostError.invalidAddress }
        if components.port == nil, let scheme = components.scheme?.lowercased(),
           scheme == "http" || scheme == "ws" {
            components.port = 80
        }
        guard let host = components.host, !host.isEmpty, let url = components.url else {
            throw HostError.invalidAddress
        }
        return url
    }

    /// True when the host is reached over HTTPS, so tickets and sockets must use wss.
    var isSecure: Bool {
        let scheme = (try? baseURL().scheme)?.lowercased()
        return scheme == "https" || scheme == "wss"
    }

    func controlURL() throws -> URL { try socketURL(path: "/api/control") }

    func dataURL() throws -> URL { try socketURL(path: "/api/data") }

    private func socketURL(path: String) throws -> URL {
        let base = try baseURL()
        guard var components = URLComponents(url: base, resolvingAgainstBaseURL: false) else {
            throw HostError.invalidAddress
        }
        switch components.scheme?.lowercased() {
        case "https", "wss":
            components.scheme = "wss"
        default:
            components.scheme = "ws"
        }
        var basePath = components.path
        while basePath.hasSuffix("/") { basePath.removeLast() }
        components.path = basePath + path
        guard let url = components.url else { throw HostError.invalidAddress }
        return url
    }
}

enum HostError: LocalizedError {
    case invalidAddress

    var errorDescription: String? {
        switch self {
        case .invalidAddress: return "Enter a server address such as 127.0.0.1:7297"
        }
    }
}

/// Persists the host list and the last selected host.
@MainActor
final class HostStore: ObservableObject {
    @Published private(set) var hosts: [HostConfig] = []
    @Published var selectedID: UUID?

    private let defaults: UserDefaults
    private let key = "rex.hosts.v1"
    private let selectedKey = "rex.selectedHost.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    func upsert(_ host: HostConfig) {
        if let index = hosts.firstIndex(where: { $0.id == host.id }) {
            hosts[index] = host
        } else {
            hosts.append(host)
        }
        if selectedID == nil { selectedID = host.id }
        save()
    }

    func remove(_ host: HostConfig) {
        hosts.removeAll { $0.id == host.id }
        if selectedID == host.id { selectedID = hosts.first?.id }
        save()
    }

    var selected: HostConfig? {
        guard let selectedID else { return hosts.first }
        return hosts.first { $0.id == selectedID } ?? hosts.first
    }

    private func load() {
        if let override = Self.launchHostOverride() {
            hosts = [HostConfig(name: "This Mac", address: override)]
            selectedID = hosts.first?.id
            save()
            return
        }
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode([HostConfig].self, from: data) else {
            hosts = [.loopback]
            selectedID = hosts.first?.id
            save()
            return
        }
        hosts = decoded
        if let raw = defaults.string(forKey: selectedKey) {
            selectedID = UUID(uuidString: raw)
        }
        if selectedID == nil { selectedID = hosts.first?.id }
    }

    /// `-rexHost 127.0.0.1:7297` pins the server, which UI tests rely on.
    private static func launchHostOverride() -> String? {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "-rexHost"), index + 1 < args.count else { return nil }
        return args[index + 1]
    }

    private func save() {
        if let data = try? JSONEncoder().encode(hosts) {
            defaults.set(data, forKey: key)
        }
        defaults.set(selectedID?.uuidString, forKey: selectedKey)
    }
}
