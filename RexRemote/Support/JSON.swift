import Foundation

/// Helpers for the loosely typed JSON the Rex API speaks.
typealias JSONObject = [String: Any]

enum JSONValueError: Error { case notAnObject }

extension Dictionary where Key == String, Value == Any {
    func string(_ key: String) -> String? { self[key] as? String }

    func int(_ key: String) -> Int? {
        if let number = self[key] as? NSNumber { return number.intValue }
        if let text = self[key] as? String { return Int(text) }
        return nil
    }

    func double(_ key: String) -> Double? {
        if let number = self[key] as? NSNumber { return number.doubleValue }
        if let text = self[key] as? String { return Double(text) }
        return nil
    }

    func bool(_ key: String) -> Bool? {
        if let value = self[key] as? Bool { return value }
        if let number = self[key] as? NSNumber { return number.boolValue }
        return nil
    }

    func object(_ key: String) -> JSONObject? { self[key] as? JSONObject }

    func array(_ key: String) -> [Any]? { self[key] as? [Any] }

    func objects(_ key: String) -> [JSONObject] { (self[key] as? [Any])?.compactMap { $0 as? JSONObject } ?? [] }

    func strings(_ key: String) -> [String] { (self[key] as? [Any])?.compactMap { $0 as? String } ?? [] }

    func doubles(_ key: String) -> [Double] {
        (self[key] as? [Any])?.compactMap { ($0 as? NSNumber)?.doubleValue } ?? []
    }
}

enum JSONCoding {
    static func object(from data: Data) -> JSONObject? {
        guard let value = try? JSONSerialization.jsonObject(with: data) else { return nil }
        return value as? JSONObject
    }

    static func data(_ object: JSONObject) throws -> Data {
        try JSONSerialization.data(withJSONObject: object, options: [])
    }

    static func text(_ object: JSONObject) throws -> String {
        String(decoding: try data(object), as: UTF8.self)
    }
}

/// Base64url without padding, as the Rex API uses for tickets and tokens.
enum Base64URL {
    static func decode(_ text: String) -> Data? {
        var value = text.replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = value.count % 4
        if remainder > 0 { value += String(repeating: "=", count: 4 - remainder) }
        return Data(base64Encoded: value)
    }

    static func encode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
