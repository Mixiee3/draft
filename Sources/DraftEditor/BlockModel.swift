import AppKit
import DraftCore

/// Semantic block kinds as edited in TextKit. Each text paragraph is exactly one block.
public enum BlockKind: String, Sendable {
    case paragraph, heading, quote, callout, code, bullet, ordered, task, toggle, divider, image, page, file, opaque
    public var isList: Bool { self == .bullet || self == .ordered || self == .task || self == .toggle }
    public var isAttachment: Bool { self == .divider || self == .image || self == .page || self == .file || self == .opaque }
}

/// Immutable block descriptor stored on every character of its paragraph (attribute
/// `.draftBlock`). Visual attributes are always *derived* from this plus inline marks.
public final class BlockInfo: NSObject, @unchecked Sendable {
    public let id: String
    public let kind: BlockKind
    public let level: Int          // heading level 1…4
    public let indent: Int         // list nesting depth
    /// Tasks: done. Toggles: expanded.
    public let checked: Bool
    public let start: Int?         // ordered list start (first item of a list)
    public let variant: String?    // "caption"
    public let blockColor: String?
    public let decoration: String? // nil | focus | block
    public let align: String?      // left | center | right | justify
    public let language: String?
    public let icon: String?       // callout
    public let continuation: Bool  // extra paragraph inside a list item (no marker)
    /// Ids of wrapper nodes that the flat representation folds away, kept so that ids are
    /// stable across save/load: listItem's inner paragraph and the list / blockquote node.
    public let innerId: String?
    public let containerId: String?
    /// Raw node for attachment-like and unknown blocks (preserved verbatim).
    public let raw: Node?

    public init(id: String = newId("b_"), kind: BlockKind = .paragraph, level: Int = 1, indent: Int = 0, checked: Bool = false, start: Int? = nil, variant: String? = nil, blockColor: String? = nil, decoration: String? = nil, align: String? = nil, language: String? = nil, icon: String? = nil, continuation: Bool = false, innerId: String? = nil, containerId: String? = nil, raw: Node? = nil) {
        self.id = id; self.kind = kind; self.level = level; self.indent = indent; self.checked = checked; self.start = start
        self.variant = variant; self.blockColor = blockColor; self.decoration = decoration; self.align = align; self.language = language; self.icon = icon
        self.continuation = continuation; self.innerId = innerId; self.containerId = containerId; self.raw = raw
    }

    public static func paragraph() -> BlockInfo { BlockInfo() }

    /// Copy with changes. `id` changes only when asked.
    public func with(id: String? = nil, kind: BlockKind? = nil, level: Int? = nil, indent: Int? = nil, checked: Bool? = nil, start: Int?? = nil, variant: String?? = nil, blockColor: String?? = nil, decoration: String?? = nil, align: String?? = nil, continuation: Bool? = nil, innerId: String?? = nil, containerId: String?? = nil, raw: Node?? = nil) -> BlockInfo {
        BlockInfo(id: id ?? self.id, kind: kind ?? self.kind, level: level ?? self.level, indent: indent ?? self.indent, checked: checked ?? self.checked,
                  start: start ?? self.start, variant: variant ?? self.variant, blockColor: blockColor ?? self.blockColor, decoration: decoration ?? self.decoration,
                  align: align ?? self.align, language: language, icon: icon, continuation: continuation ?? self.continuation, innerId: innerId ?? self.innerId,
                  containerId: containerId ?? self.containerId, raw: raw ?? self.raw)
    }

    public override func isEqual(_ object: Any?) -> Bool {
        guard let o = object as? BlockInfo else { return false }
        return id == o.id && kind == o.kind && level == o.level && indent == o.indent && checked == o.checked && start == o.start && variant == o.variant
            && blockColor == o.blockColor && decoration == o.decoration && align == o.align && language == o.language && continuation == o.continuation
            && innerId == o.innerId && containerId == o.containerId && raw == o.raw && icon == o.icon
    }
    public override var hash: Int { id.hashValue }
}

public extension NSAttributedString.Key {
    static let draftBlock = NSAttributedString.Key("draft.block")
    static let draftBold = NSAttributedString.Key("draft.bold")
    static let draftItalic = NSAttributedString.Key("draft.italic")
    static let draftUnderline = NSAttributedString.Key("draft.underline")
    static let draftStrike = NSAttributedString.Key("draft.strike")
    static let draftCode = NSAttributedString.Key("draft.code")
    static let draftHighlight = NSAttributedString.Key("draft.highlight") // hex String
    static let draftTextColor = NSAttributedString.Key("draft.textColor") // hex String
    static let draftLink = NSAttributedString.Key("draft.link")           // href String
}

/// Inline mark kinds that toggle on/off.
public enum InlineMark: String, CaseIterable, Sendable {
    case bold, italic, underline, strike, code
    public var key: NSAttributedString.Key {
        switch self {
        case .bold: return .draftBold
        case .italic: return .draftItalic
        case .underline: return .draftUnderline
        case .strike: return .draftStrike
        case .code: return .draftCode
        }
    }
}

public let semanticKeys: [NSAttributedString.Key] = [.draftBold, .draftItalic, .draftUnderline, .draftStrike, .draftCode, .draftHighlight, .draftTextColor, .draftLink]

/// Characters used inside a paragraph.
public enum Chars {
    public static let attachment = "\u{FFFC}"
    public static let lineBreak = "\u{2028}" // soft break inside a block (Shift-Enter, code lines)
}
