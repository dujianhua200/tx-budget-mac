import Foundation

/// 容错解码助手：旧文件里的数值可能是数字/数字字符串/null 混写，
/// 字符串数字要能读进来；缺失键一律回落默认值，不得因缺字段而拒绝打开旧文件。

extension KeyedDecodingContainer {
    /// 数值（Double / Int / 数字字符串 / null → nil）。
    func decodeLenientDouble(forKey key: Key) -> Double? {
        if let v = try? decodeIfPresent(Double.self, forKey: key), let v { return v }
        if let i = try? decodeIfPresent(Int.self, forKey: key), let i { return Double(i) }
        if let s = try? decodeIfPresent(String.self, forKey: key), let s {
            let t = s.trimmingCharacters(in: .whitespaces)
            if t.isEmpty { return nil }
            return Double(t)
        }
        return nil
    }

    func decodeLenientDouble(forKey key: Key, default defaultValue: Double) -> Double {
        decodeLenientDouble(forKey: key) ?? defaultValue
    }

    func decodeLenientString(forKey key: Key, default defaultValue: String = "") -> String {
        if let s = try? decodeIfPresent(String.self, forKey: key), let s { return s }
        if let n = try? decodeIfPresent(Double.self, forKey: key), let n { return jsNumberString(n) }
        if let i = try? decodeIfPresent(Int.self, forKey: key), let i { return String(i) }
        if let b = try? decodeIfPresent(Bool.self, forKey: key), let b { return b ? "true" : "false" }
        return defaultValue
    }

    func decodeLenientStringOptional(forKey key: Key) -> String? {
        if let s = try? decodeIfPresent(String.self, forKey: key) { return s }
        if let n = try? decodeIfPresent(Double.self, forKey: key), let n { return jsNumberString(n) }
        if let i = try? decodeIfPresent(Int.self, forKey: key), let i { return String(i) }
        return nil
    }

    func decodeLenientBool(forKey key: Key, default defaultValue: Bool) -> Bool {
        if let b = try? decodeIfPresent(Bool.self, forKey: key), let b { return b }
        if let i = try? decodeIfPresent(Int.self, forKey: key), let i { return i != 0 }
        if let s = try? decodeIfPresent(String.self, forKey: key), let s {
            let t = s.trimmingCharacters(in: .whitespaces).lowercased()
            if t == "true" || t == "1" { return true }
            if t == "false" || t == "0" { return false }
        }
        return defaultValue
    }

    func decodeLenientBoolOptional(forKey key: Key) -> Bool? {
        if let b = try? decodeIfPresent(Bool.self, forKey: key) { return b }
        if let i = try? decodeIfPresent(Int.self, forKey: key), let i { return i != 0 }
        return nil
    }
}

/// 任意 JSON 值（用于 v1Backup 等需要原样透传的字段：解码后原样再编码，不丢数据）。
public enum JSONValue: Equatable, Codable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() {
            self = .null
        } else if let b = try? c.decode(Bool.self) {
            self = .bool(b)
        } else if let n = try? c.decode(Double.self) {
            self = .number(n)
        } else if let s = try? c.decode(String.self) {
            self = .string(s)
        } else if let a = try? c.decode([JSONValue].self) {
            self = .array(a)
        } else if let o = try? c.decode([String: JSONValue].self) {
            self = .object(o)
        } else {
            self = .null
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let b): try c.encode(b)
        case .number(let n): try c.encode(n)
        case .string(let s): try c.encode(s)
        case .array(let a): try c.encode(a)
        case .object(let o): try c.encode(o)
        }
    }

    public var stringValue: String? {
        if case .string(let s) = self { return s }
        return nil
    }

    public var doubleValue: Double? {
        if case .number(let n) = self { return n }
        return nil
    }

    public var objectValue: [String: JSONValue]? {
        if case .object(let o) = self { return o }
        return nil
    }
}

public func newUID() -> String {
    let hex = "abcdefghijklmnopqrstuvwxyz0123456789"
    var s = ""
    for _ in 0..<8 { s.append(hex.randomElement()!) }
    s += String(Int(Date().timeIntervalSince1970 * 1000), radix: 36)
    return s
}

public func nowISO() -> String {
    ISO8601DateFormatter().string(from: Date())
}
