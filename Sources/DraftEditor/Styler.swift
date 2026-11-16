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
    public var tagRules = TagRules()
    public var tagColors: [String: String] = [:]
    /// Settings → Advanced → Dates: chips (true) or plain text.
    public var dateChips = true
    /// Increase Contrast: effects keep their readable color but drop glow, shadow and outline.
    public var plainEffects = false
    /// Spectrum text moves only when this is on (off for Reduce Motion and Increase Contrast).
    public var animateEffects = true
    /// Reduce Transparency: glass becomes a solid card.
    public var solidGlass = false

    public init() {}
    public func tagColor(_ tag: String) -> NSColor { NSColor(hex: tagColors[tag.lowercased()] ?? Tags.defaultColor(tag)) }
    public init(tokens: StyleTokens, completedTasks: String) {
        textColor = tokens.textColor; pageColor = tokens.pageColor; accent = tokens.accent
        font = tokens.font; separator = tokens.separator; self.completedTasks = completedTasks
    }

    public var text: NSColor { NSColor(hex: textColor) }
    public var secondary: NSColor { NSColor(hex: textColor, alpha: 0.58) }
    public var accentColor: NSColor { NSColor(hex: accent) }
    public var isDarkPage: Bool { ColorMath.isDark(pageColor) }

    public var design: NSFontDescriptor.SystemDesign { Self.design(font) }
    public static func design(_ f: String) -> NSFontDescriptor.SystemDesign {
        switch f { case "serif": return .serif; case "rounded": return .rounded; case "mono": return .monospaced; default: return .default }
    }
    /// The design for a block: code is always mono, a block font wins over the document's.
    public func design(for b: BlockInfo) -> NSFontDescriptor.SystemDesign? { b.kind == .code ? .monospaced : b.font.map(Self.design) }

    nonisolated(unsafe) static let fonts = NSCache<NSString, NSFont>() // NSCache is thread-safe

    public func font(size: CGFloat, weight: NSFont.Weight, design: NSFontDescriptor.SystemDesign? = nil, bold: Bool = false, italic: Bool = false) -> NSFont {
        let w = bold ? max(weight, .bold) : weight, dz = design ?? self.design
        let key = "\(size)|\(w.rawValue)|\(dz.rawValue)|\(italic)" as NSString
        // Restyling a 2,000-block note asked for the same few fonts thousands of times.
        if let f = Self.fonts.object(forKey: key) { return f }
        let base = NSFont.systemFont(ofSize: size, weight: w)
        var d = base.fontDescriptor.withDesign(dz) ?? base.fontDescriptor
        if italic { d = d.withSymbolicTraits(.italic) }
        let f = NSFont(descriptor: d, size: size) ?? base
        Self.fonts.setObject(f, forKey: key)
        return f
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
        return font(size: m.size, weight: m.weight, design: design(for: b))
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
        if b.kind == .callout { indent = 42; tail = -14; p.paragraphSpacingBefore = 6 }
        if b.kind == .code { indent = 16; tail = -16; p.paragraphSpacingBefore = 4; p.paragraphSpacing = 12 }
        if b.decoration == "focus" { indent += 16 }
        if b.kind != .callout && (BlockEffects.isBoxed(b.decoration, heading: b.kind == .heading) || (b.blockColor != nil && b.kind != .code)) { indent += 12; tail = -12 }
        // Outlined effects need room so stacked boxes never touch (Block merges on purpose).
        if b.kind != .callout, b.decoration != "block", BlockEffects.isBoxed(b.decoration, heading: b.kind == .heading) { p.paragraphSpacingBefore += 6; p.paragraphSpacing += 6 }
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
                var font = theme.font(size: m.size, weight: m.weight, design: theme.design(for: b), bold: bold, italic: italic)
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
                if a[.draftDate] != nil && a[.draftDocLink] == nil && !theme.dateChips {
                    attrs[.underlineStyle] = nil
                } else if a[.draftDocLink] != nil || a[.draftDate] != nil {
                    let missing = a[.draftLinkMissing] != nil
                    fg = missing ? theme.secondary : theme.accentColor
                    attrs[.backgroundColor] = (missing ? theme.text : theme.accentColor).withAlphaComponent(theme.isDarkPage ? 0.22 : 0.1)
                    if missing { attrs[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
                    attrs[.underlineStyle] = nil
                }
                if let k = a[.draftEffect] as? String, a[.draftHighlight] == nil { applyEffect(k, &attrs, &fg, hasTextColor: a[.draftTextColor] != nil, theme: theme) }
                attrs[.foregroundColor] = fg
                s.setAttributes(attrs, range: r)
            }
            if b.kind != .code, ns.range(of: "#", options: .literal, range: pr).location != NSNotFound {
                for t in Tags.find(in: ns.substring(with: pr), rules: theme.tagRules) {
                    let r = NSRange(location: pr.location + t.range.location, length: t.range.length)
                    let a = s.attributes(at: r.location, effectiveRange: nil)
                    guard a[.draftCode] == nil, a[.draftLink] == nil, a[.draftDocLink] == nil else { continue }
                    let c = theme.tagColor(t.name)
                    // Tags are inline metadata, not chips. A background fill makes each
                    // tag render as a hard rectangle and becomes especially distracting
                    // when several tags sit on one line. Keep the semantic color only;
                    // chips remain reserved for document links and dates above.
                    s.addAttributes([.foregroundColor: c], range: r)
                }
            }
            loc = NSMaxRange(pr)
            if pr.length == 0 { break }
        }
    }

    /// Draws one effect. The letters keep the text color when one is set (`hasTextColor`); the
    /// effect has its own color and strength. Without a text color the effect supplies a readable
    /// default. Increase Contrast keeps the letters' color and drops the decoration.
    static func applyEffect(_ value: String, _ attrs: inout [NSAttributedString.Key: Any], _ fg: inout NSColor, hasTextColor: Bool = false, theme: EditorTheme) {
        guard let e = EffectSpec(value) else { return }
        let d = TextEffects.colors(accent: theme.accent, text: theme.textColor, page: theme.pageColor)
        let fills = e.fillColors(accent: theme.accent, text: theme.textColor, page: theme.pageColor)
        switch e.kind {
        case "accent", "gradient", "spectrum": fg = NSColor(hex: fills.first ?? d.start) // gradient and spectrum: drawn by the layout manager; this is the fallback
        default: break
        }
        guard !theme.plainEffects, !["accent", "gradient", "spectrum"].contains(e.kind) else { return }
        let k = e.intensity ?? 0.6 // 0.6 is the look before effects had a strength
        let own = e.color.map { NSColor(hex: $0) }
        let sh = NSShadow()
        switch e.kind {
        case "glow":
            sh.shadowColor = (own ?? theme.accentColor).withAlphaComponent((theme.isDarkPage ? 0.95 : 0.75) * min(1, 0.4 + k))
            sh.shadowBlurRadius = 2 + 5 * k
        case "shadow":
            sh.shadowColor = (own ?? .black).withAlphaComponent(min(1, (theme.isDarkPage ? 1.0 : 0.35) * (0.4 + k)))
            // Crisp and close: a soft, far shadow smudged the letters at reading sizes.
            sh.shadowBlurRadius = (theme.isDarkPage ? 1 : 0.5) + 1.2 * k; sh.shadowOffset = NSSize(width: 0, height: -(0.8 + (theme.isDarkPage ? 1.6 : 1.2) * k))
        case "lift":
            // A short, quiet step: a long offset in another color read as a doubled, misprinted word.
            sh.shadowColor = (own ?? NSColor(hex: d.end)).withAlphaComponent(0.18 + 0.22 * k)
            sh.shadowOffset = NSSize(width: 0.5 + 0.8 * k, height: -(0.5 + 0.8 * k))
        case "emboss":
            // Pressed in: a dark edge above on light pages, a faint light edge below on dark ones
            // (a dark edge can't show on a dark page).
            sh.shadowColor = (own ?? (theme.isDarkPage ? .white : .black)).withAlphaComponent((theme.isDarkPage ? 0.3 : 0.4) * (0.4 + k))
            sh.shadowOffset = NSSize(width: 0, height: theme.isDarkPage ? -1 : 1)
        case "outline":
            // A colored rim around letters that keep the text color.
            attrs[.strokeWidth] = -(1 + 2.5 * k); attrs[.strokeColor] = (own ?? theme.accentColor).withAlphaComponent(0.85); return
        default: return
        }
        attrs[.shadow] = sh
    }

    /// Typing attributes for an empty paragraph / caret position.
    public static func typingAttributes(block: BlockInfo, marks: [NSAttributedString.Key: Any], theme: EditorTheme) -> [NSAttributedString.Key: Any] {
        let s = NSTextStorage(string: "x", attributes: marks.merging([.draftBlock: block]) { a, _ in a })
        restyle(s, range: NSRange(location: 0, length: 1), theme: theme)
        return s.attributes(at: 0, effectiveRange: nil)
    }
}
