import Foundation

/// Inline mark on a text node (bold, italic, link, highlight…).
public struct Mark: Codable, Hashable, Sendable {
    public var type: String
    public var attrs: [String: JSONValue]?
    public init(_ type: String, attrs: [String: JSONValue]? = nil) { self.type = type; self.attrs = attrs }
}

/// A node of the portable document tree. The shape is intentionally the widely used
/// ProseMirror-style JSON (`type`, `attrs`, `content`, `marks`, `text`) so any platform can
/// read it. See docs/FORMAT.md.
public struct Node: Codable, Hashable, Sendable {
    public var type: String
    public var attrs: [String: JSONValue]?
    public var content: [Node]?
    public var marks: [Mark]?
    public var text: String?

    public init(_ type: String, attrs: [String: JSONValue]? = nil, content: [Node]? = nil, marks: [Mark]? = nil, text: String? = nil) {
        self.type = type; self.attrs = attrs; self.content = content; self.marks = marks; self.text = text
    }

    public static func text(_ s: String, marks: [Mark]? = nil) -> Node { Node("text", marks: marks, text: s) }

    public subscript(attr key: String) -> JSONValue? {
        get { attrs?[key] }
        set {
            var a = attrs ?? [:]
            a[key] = newValue
            attrs = a
        }
    }
    public var id: String? { attrs?["id"]?.string }
}

public func newId(_ prefix: String = "") -> String {
    prefix + UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased().prefix(16)
}

public func nowMs() -> Double { (Date().timeIntervalSince1970 * 1000).rounded() }
