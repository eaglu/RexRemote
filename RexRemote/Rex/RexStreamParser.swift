import Foundation

/// Splits a terminal byte stream into plain terminal bytes and the Rex APC
/// directives woven into it (`ESC _ rex1;<nonce>;{json} ESC \`).
///
/// Directives arrive as soon as the stream starts (resize, theme), so they also
/// mark the boundary that follows the leading Ghostty snapshot.
struct RexStreamParser {
    struct Directive {
        var type: String
        var body: JSONObject
    }

    /// `ESC _ rex1;`, the start of every Rex directive.
    static let markerPrefix: [UInt8] = Array("\u{1B}_rex1;".utf8)

    private let nonce: String
    private var pending: [UInt8] = []
    private var header: [UInt8]
    /// Directives seen so far, newest last.
    private(set) var directives: [Directive] = []

    init(nonce: String) {
        self.nonce = nonce
        self.header = Self.markerPrefix + Array((nonce + ";").utf8)
    }

    /// Feeds bytes, calling `emit` with plain terminal output in order.
    mutating func feed(_ bytes: [UInt8], emit: (ArraySlice<UInt8>) -> Void) {
        pending.append(contentsOf: bytes)
        var plain: [UInt8] = []
        while true {
            guard let start = Self.find(header, in: pending) else { break }
            guard let end = Self.findTerminator(in: pending, from: start + header.count) else { break }
            if start > 0 { plain.append(contentsOf: pending[0..<start]) }
            let body = Array(pending[(start + header.count)..<end])
            if let directive = Self.decode(body) { directives.append(directive) }
            pending.removeFirst(end + 2)
        }
        // Hold back a trailing fragment that may open the next directive.
        let holdBack = min(pending.count, header.count)
        let cut = Self.safeEmitCount(pending, holdBack: holdBack)
        if cut > 0 {
            plain.append(contentsOf: pending[0..<cut])
            pending.removeFirst(cut)
        }
        if !plain.isEmpty { emit(plain[...]) }
    }

    /// Finds `needle`, returning its offset in `bytes`.
    static func find(_ needle: [UInt8], in bytes: [UInt8]) -> Int? {
        guard !needle.isEmpty, bytes.count >= needle.count else { return nil }
        let limit = bytes.count - needle.count
        var index = 0
        while index <= limit {
            if bytes[index] == needle[0] {
                var matches = true
                for offset in 1..<needle.count where bytes[index + offset] != needle[offset] {
                    matches = false
                    break
                }
                if matches { return index }
            }
            index += 1
        }
        return nil
    }

    /// True when `bytes` ends with a partial `needle`.
    static func hasPartialSuffix(_ needle: [UInt8], in bytes: [UInt8]) -> Int? {
        let longest = min(needle.count - 1, bytes.count)
        guard longest > 0 else { return nil }
        for length in stride(from: longest, through: 1, by: -1) {
            if Array(bytes.suffix(length)) == Array(needle.prefix(length)) {
                return length
            }
        }
        return nil
    }

    private static func findTerminator(in bytes: [UInt8], from start: Int) -> Int? {
        var index = start
        while index + 1 < bytes.count {
            if bytes[index] == 0x1B, bytes[index + 1] == 0x5C { return index }
            index += 1
        }
        return nil
    }

    /// How many buffered bytes are certainly not the start of a directive.
    private static func safeEmitCount(_ bytes: [UInt8], holdBack: Int) -> Int {
        guard bytes.count > holdBack else { return 0 }
        let limit = bytes.count - holdBack
        var index = limit
        while index < bytes.count {
            let length = bytes.count - index
            var matches = true
            for offset in 0..<length where bytes[index + offset] != markerPrefix[offset] {
                matches = false
                break
            }
            if matches { return index }
            index += 1
        }
        return limit
    }

    private static func decode(_ body: [UInt8]) -> Directive? {
        guard let json = JSONCoding.object(from: Data(body)) else { return nil }
        let type = json.string("type") ?? "unknown"
        return Directive(type: type, body: json.object("payload") ?? json)
    }
}
