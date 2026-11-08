import Foundation

/// A lossless JSON value. Used for node attributes and to preserve unknown fields so that
/// files written by newer Draft versions (or other implementations, e.g. a future Windows
/// app) never lose data when round-tripped through this version.
public enum JSONValue: Codable, Hashable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let b = try? c.decode(Bool.self) { self = .bool(b) }
        else if let n = try? c.decode(Double.self) { self = .number(n) }
        else if let s = try? c.decode(String.self) { self = .string(s) }
        else if let a = try? c.decode([JSONValue].self) { self = .array(a) }
        else { self = .object(try c.decode([String: JSONValue].self)) }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let b): try c.encode(b)
        case .number(let n):
            if n.rounded() == n, abs(n) < 1e15 { try c.encode(Int64(n)) } else { try c.encode(n) }
        case .string(let s): try c.encode(s)
        case .array(let a): try c.encode(a)
        case .object(let o): try c.encode(o)
        }
    }

    public var string: String? { if case .string(let s) = self { return s }; return nil }
    public var double: Double? { if case .number(let n) = self { return n }; return nil }
    public var int: Int? { double.map { Int($0) } }
    public var bool: Bool? { if case .bool(let b) = self { return b }; return nil }
    public var object: [String: JSONValue]? { if case .object(let o) = self { return o }; return nil }
    public var items: [JSONValue]? { if case .array(let a) = self { return a }; return nil }
}

extension JSONValue: ExpressibleByStringLiteral, ExpressibleByIntegerLiteral, ExpressibleByBooleanLiteral, ExpressibleByFloatLiteral {
    public init(stringLiteral value: String) { self = .string(value) }
    public init(integerLiteral value: Int) { self = .number(Double(value)) }
    public init(booleanLiteral value: Bool) { self = .bool(value) }
    public init(floatLiteral value: Double) { self = .number(value) }
}

/// Coding key that accepts any string, for collecting unknown keys.
struct AnyKey: CodingKey {
    var stringValue: String
    var intValue: Int? { nil }
    init(_ s: String) { stringValue = s }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { return nil }
}

extension Decoder {
    /// Returns every top-level key not in `known`, as raw JSON.
    func unknownFields(known: Set<String>) throws -> [String: JSONValue] {
        let c = try container(keyedBy: AnyKey.self)
        var out: [String: JSONValue] = [:]
        for k in c.allKeys where !known.contains(k.stringValue) {
            out[k.stringValue] = try c.decode(JSONValue.self, forKey: k)
        }
        return out
    }
}

extension Encoder {
    func encodeUnknown(_ extra: [String: JSONValue]) throws {
        guard !extra.isEmpty else { return }
        var c = container(keyedBy: AnyKey.self)
        for (k, v) in extra { try c.encode(v, forKey: AnyKey(k)) }
    }
}

// Building the tree from JSONSerialization output is several times faster than JSONDecoder's
// keyed containers for large documents (a 2,000-block note spent ~90% of its open time decoding).
// It stays on NSDictionary/NSArray: bridging each level to Swift collections cost as much again.
extension JSONValue {
    public init(foundation v: Any) {
        switch v {
        case let n as NSNumber:
            self = CFGetTypeID(n) == CFBooleanGetTypeID() ? .bool(n.boolValue) : .number(n.doubleValue)
        case let s as NSString: self = .string(s as String)
        case let a as NSArray: self = .array(a.map(JSONValue.init(foundation:)))
        case let o as NSDictionary: self = .object(Self.object(o))
        default: self = .null
        }
    }

    static func object(_ o: NSDictionary) -> [String: JSONValue] {
        var d = [String: JSONValue](minimumCapacity: o.count)
        o.forEach { k, v in if let k = k as? String { d[k] = JSONValue(foundation: v) } }
        return d
    }
}

extension Node {
    /// nil when the value is not a node (the caller then falls back to the Codable path).
    public init?(foundation v: Any) {
        guard let o = v as? NSDictionary, let type = o["type"] as? String else { return nil }
        self.init(type)
        if let a = o["attrs"], !(a is NSNull) { guard let d = a as? NSDictionary else { return nil }; attrs = JSONValue.object(d) }
        if let c = o["content"], !(c is NSNull) {
            guard let arr = c as? NSArray else { return nil }
            var kids: [Node] = []; kids.reserveCapacity(arr.count)
            for k in arr { guard let n = Node(foundation: k) else { return nil }; kids.append(n) }
            content = kids
        }
        if let m = o["marks"], !(m is NSNull) {
            guard let arr = m as? NSArray else { return nil }
            var marks: [Mark] = []
            for x in arr {
                guard let d = x as? NSDictionary, let t = d["type"] as? String else { return nil }
                marks.append(Mark(t, attrs: (d["attrs"] as? NSDictionary).map(JSONValue.object)))
            }
            self.marks = marks
        }
        if let t = o["text"], !(t is NSNull) { guard let s = t as? String else { return nil }; text = s }
    }
}
