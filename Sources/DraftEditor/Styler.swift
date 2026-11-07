import AppKit
import DraftCore

public extension NSColor {
    convenience init(hex: String, alpha: CGFloat = 1) {
        let (r, g, b) = ColorMath.rgb(hex)
        self.init(srgbRed: r, green: g, blue: b, alpha: alpha)
    }
}

/// Visual tokens for the editor, derived from the document style. Changing the theme never
/// touches semantic content — the Styler re-derives display attributes.
public struct EditorTheme: Equatable {
    public var textColor: String = "#252521"
    public var pageColor: String = "#fffdf8"
    public var accent: String = "#5b6cf0"
    public var font: String = "serif"
    public var separator: String = "line"
    public var completedTasks: String = "strike"

    public init() {}
    public init(tokens: StyleTokens, completedTasks: String) {
        textColor = tokens.textColor; pageColor = tokens.pageColor; accent = tokens.accent
        font = tokens.font; separator = tokens.separator; self.completedTasks = completedTasks
    }

    public var text: NSColor { NSColor(hex: textColor) }
    public var secondary: NSColor { NSColor(hex: textColor, alpha: 0.58) }
    public var accentColor: NSColor { NSColor(hex: accent) }
    public var isDarkPage: Bool { ColorMath.isDark(pageColor) }

    public var design: NSFontDescriptor.SystemDesign {
        switch font { case "serif": return .serif; case "rounded": return .rounded; case "mono": return .monospaced; default: return .default }
    }

    public func font(size: CGFloat, weight: NSFont.Weight, design: NSFontDescriptor.SystemDesign? = nil, bold: Bool = false, italic: Bool = false) -> NSFont {
        let base = NSFont.systemFont(ofSize: size, weight: bold ? max(weight, .bold) : weight)
        var d = base.fontDescriptor.withDesign(design ?? self.design) ?? base.fontDescriptor
        if italic { d = d.withSymbolicTraits(.italic) }
        return NSFont(descriptor: d, size: size) ?? base
    }

    /// Size and weight for a block's body text.
    public func metrics(_ b: BlockInfo) -> (size: CGFloat, weight: NSFont.Weight) {
        switch b.kind {
        case .heading:
            switch b.level {
            case 1: return (30, .bold)
            case 2: return (23, .semibold)
            case 3: return (19, .semibold)
            default: return (17, .bold)
            }
        case .code: return (14, .regular)
        default: return b.variant == "caption" ? (13.5, .regular) : (font == "mono" ? 15.5 : 17, .regular)
        }
    }

    public func baseFont(_ b: BlockInfo) -> NSFont {
        let m = metrics(b)
        return font(size: m.size, weight: m.weight, design: b.kind == .code ? .monospaced : nil)
    }

    public static let listIndent: CGFloat = 26
}

/// Derives display attributes (font, colors, paragraph style) from semantic attributes.
public enum Styler {
    public static func paragraphStyle(_ b: BlockInfo, theme: EditorTheme) -> NSParagraphStyle {
        let p = NSMutableParagraphStyle()
        let size = theme.metrics(b).size
        p.lineHeightMultiple = b.kind == .heading ? 1.12 : (b.kind == .code ? 1.25 : 1.3)
        p.paragraphSpacing = b.kind.isList ? 4 : 8
        switch b.kind {
        case .heading: p.paragraphSpacingBefore = b.level == 1 ? 22 : b.level == 2 ? 18 : 12
        case .divider: p.paragraphSpacingBefore = 6; p.paragraphSpacing = 10
        case .page, .image: p.paragraphSpacingBefore = 6; p.paragraphSpacing = 12
        default: p.paragraphSpacingBefore = 0
        }
        var indent: CGFloat = 0
        var tail: CGFloat = 0
        if b.kind.isList { indent = EditorTheme.listIndent * CGFloat(b.indent + 1) }
        if b.kind == .quote { indent = 20 }
        if b.kind == .code { indent = 16; tail = -16; p.paragraphSpacingBefore = 4; p.paragraphSpacing = 12 }
        if b.decoration == "focus" { indent += 16 }
        if b.decoration == "block" || (b.blockColor != nil && b.kind != .code) { indent += 12; tail = -12 }
        p.firstLineHeadIndent = indent
        p.headIndent = indent
        p.tailIndent = tail
        switch b.align {
        case "center": p.alignment = .center
        case "right": p.alignment = .right
        case "justify": p.alignment = .justified
        default: p.alignment = .natural
        }
        _ = size
        return p
    }

    /// Re-derive display attributes for `range` (expanded to whole paragraphs by the caller).
    public static func restyle(_ s: NSTextStorage, range: NSRange, theme: EditorTheme) {
        guard range.length > 0 else { return }
        let ns = s.string as NSString
        var loc = range.location
        while loc < NSMaxRange(range) {
            let pr = ns.paragraphRange(for: NSRange(location: loc, length: 0))
            let b = (s.attribute(.draftBlock, at: pr.location, effectiveRange: nil) as? BlockInfo) ?? .paragraph()
            let ps = paragraphStyle(b, theme: theme)
            let m = theme.metrics(b)
            let isDoneTask = b.kind == .task && b.checked
            s.enumerateAttributes(in: pr, options: []) { a, r, _ in
                var attrs: [NSAttributedString.Key: Any] = [:]
                for k in semanticKeys { if let v = a[k] { attrs[k] = v } }
                attrs[.draftBlock] = a[.draftBlock] ?? b
                if let att = a[.attachment] { attrs[.attachment] = att }
                attrs[.paragraphStyle] = ps
                let bold = a[.draftBold] != nil
                let italic = a[.draftItalic] != nil
                let code = a[.draftCode] != nil
                var font = theme.font(size: m.size, weight: m.weight, design: b.kind == .code ? .monospaced : nil, bold: bold, italic: italic)
                if code && b.kind != .code { font = theme.font(size: m.size * 0.88, weight: bold ? .semibold : .regular, design: .monospaced) }
                attrs[.font] = font
                var fg = b.variant == "caption" ? theme.secondary : theme.text
                if let c = a[.draftTextColor] as? String { fg = NSColor(hex: c) }
                if let _ = a[.draftLink] { fg = theme.accentColor; attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue; attrs[.underlineColor] = theme.accentColor.withAlphaComponent(0.45) }
                if a[.draftUnderline] != nil { attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue }
                if a[.draftStrike] != nil { attrs[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
                if isDoneTask {
                    if theme.completedTasks == "strike" { attrs[.strikethroughStyle] = NSUnderlineStyle.single.rawValue; fg = theme.secondary }
                    if theme.completedTasks == "dim" { fg = theme.secondary }
                }
                if let h = a[.draftHighlight] as? String {
                    attrs[.backgroundColor] = NSColor(hex: h, alpha: theme.isDarkPage ? 0.85 : 1)
                    if a[.draftTextColor] == nil && a[.draftLink] == nil { fg = NSColor(hex: "#1d1d1b") }
                } else if code && b.kind != .code {
                    attrs[.backgroundColor] = theme.text.withAlphaComponent(0.07)
                }
                attrs[.foregroundColor] = fg
                s.setAttributes(attrs, range: r)
            }
            loc = NSMaxRange(pr)
            if pr.length == 0 { break }
        }
    }

    /// Typing attributes for an empty paragraph / caret position.
    public static func typingAttributes(block: BlockInfo, marks: [NSAttributedString.Key: Any], theme: EditorTheme) -> [NSAttributedString.Key: Any] {
        let s = NSTextStorage(string: "x", attributes: marks.merging([.draftBlock: block]) { a, _ in a })
        restyle(s, range: NSRange(location: 0, length: 1), theme: theme)
        return s.attributes(at: 0, effectiveRange: nil)
    }
}
