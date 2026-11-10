import Foundation

/// Turns a pairing payload into something `HostConfig.address` can use.
///
/// `rex server tailscale pair` puts the server's tailnet address in the code,
/// but people also paste full links, `host:port` pairs and the `--json` shape,
/// so all of those are accepted. Nothing secret is ever in the payload: the
/// code carries only an address.
enum HostLink {
    private static let allowed = CharacterSet(
        charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-:"
    )

    static func address(from payload: String) -> String? {
        let trimmed = payload
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        guard !trimmed.isEmpty, trimmed.count <= 512 else { return nil }

        if trimmed.hasPrefix("{"),
           let object = try? JSONSerialization.jsonObject(with: Data(trimmed.utf8)) as? [String: Any] {
            for key in ["address", "url", "endpoint", "host"] {
                if let value = object[key] as? String, let address = address(from: value) {
                    return address
                }
            }
            return nil
        }

        var scheme: String?
        var rest = trimmed
        if let separator = rest.range(of: "://") {
            let candidate = rest[..<separator.lowerBound].lowercased()
            rest = String(rest[separator.upperBound...])
            switch candidate {
            case "http", "https", "ws", "wss": scheme = candidate
            case "rex", "rexremote": scheme = nil
            default: return nil
            }
        }

        for separator in ["/", "?", "#"] {
            rest = rest.components(separatedBy: separator).first ?? ""
        }

        guard !rest.isEmpty, rest.unicodeScalars.allSatisfy({ allowed.contains($0) }) else {
            return nil
        }
        let parts = rest.components(separatedBy: ":")
        guard parts.count <= 2, let host = parts.first, !host.isEmpty else { return nil }
        if parts.count == 2 {
            guard let port = Int(parts[1]), (1...65535).contains(port) else { return nil }
        }
        if host.hasPrefix(".") || host.hasSuffix(".") { return nil }

        switch scheme {
        case "https", "wss": return "https://\(rest)"
        case "http", "ws": return "http://\(rest)"
        default: return rest
        }
    }
}
