import CoreGraphics
import Foundation

struct SessionRef: Identifiable, Hashable {
    let id: String
    var label: String

    init?(_ json: JSONObject) {
        guard let id = json.string("session_id") else { return nil }
        self.id = id
        self.label = json.string("label") ?? id
    }
}

struct BlockInfo: Identifiable, Hashable {
    let id: String
    var label: String
    var creator: String
    var flavor: String
    var owner: String?

    init?(_ json: JSONObject) {
        guard let id = json.string("block_id") else { return nil }
        self.id = id
        let flavor = json.string("flavor") ?? ""
        self.label = json.string("label").flatMap { $0.isEmpty ? nil : $0 } ?? flavor
        self.creator = json.string("creator_name") ?? flavor
        self.flavor = flavor
        self.owner = json.string("owner")
    }

    var isTerminal: Bool { flavor.hasPrefix("com.superlogical.terminal") }
}

/// One pane placed inside a window, in unit coordinates (0...1).
struct PanePlacement: Identifiable {
    let id: String
    let block: BlockInfo
    let rect: CGRect
}

struct WindowInfo: Identifiable {
    let id: String
    let label: String
    let focusedBlockID: String?
    let zoomedBlockID: String?
    let panes: [PanePlacement]
    let layers: [LayerInfo]
    let dividers: [SplitDivider]

    func pane(id: String?) -> PanePlacement? {
        guard let id else { return nil }
        return panes.first { $0.id == id } ?? panes.first
    }
}

struct SessionView: Identifiable {
    let id: String
    let revision: Int
    var label: String
    var activeWindowID: String?
    var windows: [WindowInfo]

    init?(_ json: JSONObject) {
        guard let id = json.string("session_id") else { return nil }
        self.id = id
        self.revision = json.int("revision") ?? 0
        self.label = json.string("label") ?? id
        self.activeWindowID = json.string("active_window_id")
        self.windows = json.objects("windows").compactMap(Self.window)
    }

    var activeWindow: WindowInfo? {
        windows.first { $0.id == activeWindowID } ?? windows.first
    }

    var allBlocks: [BlockInfo] {
        windows.flatMap { $0.panes.map(\.block) }
    }

    var allDividers: [SplitDivider] {
        windows.flatMap(\.dividers)
    }

    /// The divider that separates `blockID` from a neighbour, if the block sits
    /// in a split at all.
    func divider(around blockID: String, direction: String?) -> SplitDivider? {
        guard let window = windows.first(where: { $0.panes.contains { $0.id == blockID } }) else { return nil }
        return window.dividers.first { divider in
            (divider.beforeBlockID == blockID || divider.afterBlockID == blockID)
                && (direction == nil || divider.direction == direction)
        }
    }

    private static func window(_ json: JSONObject) -> WindowInfo? {
        guard let id = json.string("window_id") else { return nil }
        let layerObjects = json.objects("layers")
        var placed: [(Int, PanePlacement)] = []
        var blocksByID: [String: BlockInfo] = [:]
        var layers: [LayerInfo] = []
        var dividers: [SplitDivider] = []
        for (layerIndex, layer) in layerObjects.enumerated() {
            var blocks: [String: BlockInfo] = [:]
            for object in layer.objects("blocks") {
                if let block = BlockInfo(object) { blocks[block.id] = block }
            }
            blocksByID.merge(blocks) { first, _ in first }
            let bounds = Self.rect(layer.doubles("bounds"), fallback: CGRect(x: 0, y: 0, width: 1, height: 1))
            let layerID = layer.string("layer_id") ?? "layer:\(layerIndex)"
            layers.append(LayerInfo(
                id: layerID,
                windowID: id,
                kind: layer.string("kind") ?? "tiled",
                bounds: bounds,
                state: layer.string("state") ?? "normal",
                blockIDs: layer.objects("blocks").compactMap { $0.string("block_id") }
            ))
            guard let layout = layer.object("layout") else { continue }
            for placement in Self.placements(in: layout, bounds: bounds, blocks: blocks) {
                placed.append((layerIndex, placement))
            }
            dividers += Self.dividers(in: layout, bounds: bounds, windowID: id, layerID: layerID, blocks: blocks)
        }
        let panes = placed.sorted { $0.0 < $1.0 }.map(\.1)
        return WindowInfo(
            id: id,
            label: json.string("label") ?? id,
            focusedBlockID: json.string("focused_block_id"),
            zoomedBlockID: json.string("zoomed_block_id"),
            panes: panes,
            layers: layers,
            dividers: dividers
        )
    }

    /// Collects every split that has a block on both sides, so the UI can offer
    /// to drag that border.
    private static func dividers(
        in node: JSONObject,
        bounds: CGRect,
        windowID: String,
        layerID: String,
        blocks: [String: BlockInfo]
    ) -> [SplitDivider] {
        var result: [SplitDivider] = []
        if let split = node.object("split") {
            let local = rect(node.doubles("rect"), fallback: bounds)
            let frame = CGRect(
                x: bounds.minX + local.minX * bounds.width,
                y: bounds.minY + local.minY * bounds.height,
                width: local.width * bounds.width,
                height: local.height * bounds.height
            )
            let before = split.object("before").flatMap { blocksUnder($0, blocks: blocks).first }
            let after = split.object("after").flatMap { blocksUnder($0, blocks: blocks).first }
            if let before, let after, let splitID = split.string("split_id") {
                result.append(SplitDivider(
                    id: splitID,
                    windowID: windowID,
                    layerID: layerID,
                    direction: split.string("direction") ?? "horizontal",
                    ratio: split.double("ratio") ?? 0.5,
                    rect: frame,
                    beforeBlockID: before,
                    afterBlockID: after
                ))
            }
            for side in ["before", "after"] {
                if let child = split.object(side) {
                    result += dividers(in: child, bounds: bounds, windowID: windowID, layerID: layerID, blocks: blocks)
                }
            }
        }
        return result
    }

    private static func blocksUnder(_ node: JSONObject, blocks: [String: BlockInfo]) -> [String] {
        if let blockID = node.string("block_id") { return blocks[blockID] == nil ? [] : [blockID] }
        guard let split = node.object("split") else { return [] }
        return ["before", "after"].flatMap { side in
            split.object(side).map { blocksUnder($0, blocks: blocks) } ?? []
        }
    }

    /// Walks the layout tree. Every node's rect is relative to its layer's bounds.
    private static func placements(in node: JSONObject, bounds: CGRect, blocks: [String: BlockInfo]) -> [PanePlacement] {
        let local = rect(node.doubles("rect"), fallback: bounds)
        let frame = CGRect(
            x: bounds.minX + local.minX * bounds.width,
            y: bounds.minY + local.minY * bounds.height,
            width: local.width * bounds.width,
            height: local.height * bounds.height
        )
        if let blockID = node.string("block_id"), let block = blocks[blockID] {
            return [PanePlacement(id: blockID, block: block, rect: frame)]
        }
        if let split = node.object("split") {
            var result: [PanePlacement] = []
            for side in ["before", "after"] {
                if let child = split.object(side) {
                    result += placements(in: child, bounds: bounds, blocks: blocks)
                }
            }
            return result
        }
        return []
    }

    /// `[x, y, width, height]` in unit coordinates.
    private static func rect(_ values: [Double], fallback: CGRect) -> CGRect {
        guard values.count >= 4 else { return fallback }
        return CGRect(x: values[0], y: values[1], width: values[2], height: values[3])
    }
}

struct ServerStatus {
    var pid: Int?
    var instanceID: String?
    var sessionCount: Int?
    var version: String?

    init(_ json: JSONObject) {
        pid = json.int("pid")
        instanceID = json.string("instance_id")
        sessionCount = json.int("session_count")
        version = nil
    }
}
