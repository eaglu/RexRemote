import CoreGraphics
import Foundation

/// A border between two blocks, as the session view lays it out.
///
/// `session.resize_pane` needs the two blocks on either side plus a ratio, not a
/// pixel position, so the divider carries the pair it separates and keeps the
/// fraction the layout tree reported.
struct SplitDivider: Identifiable, Hashable {
    let id: String
    let windowID: String
    let layerID: String
    /// `horizontal` puts the border between left and right; `vertical` between
    /// top and bottom.
    let direction: String
    let ratio: Double
    /// The split's own rectangle, in window fractions.
    let rect: CGRect
    let beforeBlockID: String
    let afterBlockID: String
}

/// A layer inside a window: the tiled one, plus any floating ones on top.
struct LayerInfo: Identifiable, Hashable {
    let id: String
    let windowID: String
    let kind: String
    let bounds: CGRect
    let state: String
    let blockIDs: [String]

    var isFloating: Bool { kind != "tiled" }
    var isMinimized: Bool { state == "minimized" }
}

extension WindowInfo {
    var floatingLayers: [LayerInfo] { layers.filter(\.isFloating) }
}

/// `server.status`
struct ServerInfo {
    var pid: Int?
    var instanceID: String?
    var hostID: String?
    var startedAt: String?
    var sessionCount: Int?
    var apiRevision: Int?
    var tailscale: String?
    var configPath: String?

    init(_ json: JSONObject) {
        pid = json.int("pid")
        instanceID = json.string("instance_id")
        hostID = json.string("host_id")
        startedAt = json.string("started_at")
        sessionCount = json.int("session_count")
        apiRevision = json.int("api_revision")
        if let tailscaleJSON = json.object("tailscale") {
            tailscale = tailscaleJSON.string("state")
        }
        configPath = json.object("config")?.string("path")
    }
}

/// One entry of `hosts.list` — another Rex server this one can reach by label.
struct RemoteHost: Identifiable, Hashable {
    let id: String
    let label: String
    let endpoints: [String]

    init?(_ json: JSONObject) {
        guard let id = json.string("id"), let label = json.string("label") else { return nil }
        self.id = id
        self.label = label
        self.endpoints = json.strings("endpoints")
    }
}

/// One entry of `client.list` — a control connection on the server.
struct ClientInfo: Identifiable, Hashable {
    let id: String
    let label: String
    let kind: String
    let platform: String
    let isResumed: Bool

    init?(_ json: JSONObject) {
        guard let id = json.string("id") ?? json.string("client_id") else { return nil }
        self.id = id
        label = json.string("label") ?? json.string("name") ?? id
        kind = json.string("kind") ?? "client"
        platform = json.string("platform") ?? ""
        isResumed = json.bool("resumed") ?? false
    }
}
