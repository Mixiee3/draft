import AppKit
import DraftCore

/// Draws block chrome that is not text: list markers, task checkboxes, quote bars,
/// focus bars, code/callout backgrounds. Markers are never characters in the text, so
/// copying text or exporting never picks them up.
public final class DraftLayoutManager: NSLayoutManager {
    var theme = EditorTheme()
    /// Ordinal per paragraph start (ordered lists); rebuilt lazily after edits.
    private var numbers: [Int: Int] = [:]
    private var numbersValid = false
    /// Block for the trailing empty paragraph (has no characters).
    var trailingBlock: BlockInfo = .paragraph()
    /// Block ids shown as selected units.
    var selectedBlockIds: () -> [String] = { [] }

    func invalidateNumbers() { numbersValid = false }

    func ordinal(at paragraphStart: Int) -> Int {
        if !numbersValid { rebuildNumbers() }
        return numbers[paragraphStart] ?? 1
    }

    private func rebuildNumbers() {
        numbers = [:]
        guard let s = textStorage else { return }
        let ns = s.string as NSString
        var counters: [Int: Int] = [:] // indent -> next number
        var loc = 0
        while loc < ns.length {
            let pr = ns.paragraphRange(for: NSRange(location: loc, length: 0))
            let b = (s.attribute(.draftBlock, at: pr.location, effectiveRange: nil) as? BlockInfo) ?? .paragraph()
            if b.kind == .ordered && !b.continuation {
                if let st = b.start, counters[b.indent] == nil { counters[b.indent] = st }
                let n = counters[b.indent] ?? (b.start ?? 1)
                numbers[pr.location] = n
                counters[b.indent] = n + 1
                counters = counters.filter { $0.key <= b.indent }
            } else if b.kind.isList {
                if !b.continuation { counters = counters.filter { $0.key < b.indent || ($0.key == b.indent && false) } }
            } else {
                counters = [:]
            }
            loc = NSMaxRange(pr)
        }
        numbersValid = true
    }

    /// Union of line fragment rects for a paragraph, in container coordinates.
    func paragraphRect(_ pr: NSRange) -> NSRect? {
        let gr = glyphRange(forCharacterRange: pr, actualCharacterRange: nil)
        if gr.length == 0 {
            return extraLineFragmentTextContainer != nil ? extraLineFragmentRect : nil
        }
        var rect = NSRect.null
        enumerateLineFragments(forGlyphRange: gr) { r, used, _, _, _ in
            rect = rect.union(NSRect(x: r.minX, y: r.minY, width: r.width, height: r.height))
        }
        return rect.isNull ? nil : rect
    }

    func firstLineRect(_ pr: NSRange) -> (rect: NSRect, used: NSRect)? {
        let gr = glyphRange(forCharacterRange: pr, actualCharacterRange: nil)
        if gr.length == 0 { return nil }
        var eff = NSRange()
        let r = lineFragmentRect(forGlyphAt: gr.location, effectiveRange: &eff)
        let u = lineFragmentUsedRect(forGlyphAt: gr.location, effectiveRange: nil)
        return (r, u)
    }

    /// Baseline y (container coordinates) of the first line of a paragraph.
    func baseline(forParagraphAt pr: NSRange, block b: BlockInfo) -> (line: NSRect, y: CGFloat)? {
        let gr = glyphRange(forCharacterRange: pr, actualCharacterRange: nil)
        if gr.length > 0 {
            let line = lineFragmentRect(forGlyphAt: gr.location, effectiveRange: nil)
            return (line, line.minY + location(forGlyphAt: gr.location).y)
        }
        guard extraLineFragmentTextContainer != nil else { return nil }
        let line = extraLineFragmentRect
        let font = theme.baseFont(b)
        let ps = Styler.paragraphStyle(b, theme: theme)
        let natural = (font.ascender - font.descender + font.leading) * ps.lineHeightMultiple
        return (line, line.minY + ps.paragraphSpacingBefore + natural - (font.leading - font.descender) - (natural - (font.ascender - font.descender)) * 0)
    }

    public func checkboxRect(forParagraphAt pr: NSRange) -> NSRect? {
        guard let s = textStorage, pr.location <= s.length else { return nil }
        let b: BlockInfo = pr.location < s.length ? ((s.attribute(.draftBlock, at: pr.location, effectiveRange: nil) as? BlockInfo) ?? .paragraph()) : trailingBlock
        guard b.kind == .task, !b.continuation, let bl = baseline(forParagraphAt: pr, block: b) else { return nil }
        let size: CGFloat = 16
        let font = theme.baseFont(b)
        let x = EditorTheme.listIndent * CGFloat(b.indent + 1) - 23 + (b.decoration == "focus" ? 16 : 0)
        let cy = bl.y - font.capHeight / 2
        return NSRect(x: x, y: cy - size / 2, width: size, height: size)
    }

    public override func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        super.drawBackground(forGlyphRange: glyphsToShow, at: origin)
        guard let s = textStorage, let container = textContainers.first else { return }
        let charRange = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)
        let ns = s.string as NSString
        let width = container.size.width
        enumerateParagraphs(ns, charRange) { pr in
            let b = (s.attribute(.draftBlock, at: pr.location, effectiveRange: nil) as? BlockInfo) ?? .paragraph()
            guard let rect = paragraphRect(pr) else { return }
            let r = rect.offsetBy(dx: origin.x, dy: origin.y)
            if b.kind == .code {
                let bg = NSRect(x: origin.x, y: r.minY - 6, width: width, height: r.height + 12)
                theme.text.withAlphaComponent(theme.isDarkPage ? 0.09 : 0.055).setFill()
                NSBezierPath(roundedRect: bg, xRadius: 10, yRadius: 10).fill()
            } else if b.decoration == "block" || b.blockColor != nil {
                let bg = NSRect(x: origin.x, y: r.minY - 5, width: width, height: r.height + 10)
                let color = b.blockColor.map { NSColor(hex: $0, alpha: theme.isDarkPage ? 0.28 : 0.22) } ?? theme.text.withAlphaComponent(0.06)
                color.setFill()
                NSBezierPath(roundedRect: bg, xRadius: 10, yRadius: 10).fill()
            }
            if selectedBlockIds().contains(b.id) {
                let bg = NSRect(x: origin.x - 8, y: r.minY - 3, width: width + 16, height: r.height + 6)
                theme.accentColor.withAlphaComponent(theme.isDarkPage ? 0.3 : 0.14).setFill()
                NSBezierPath(roundedRect: bg, xRadius: 8, yRadius: 8).fill()
            }
            if b.decoration == "focus" {
                let x = origin.x + (b.kind.isList ? EditorTheme.listIndent * CGFloat(b.indent) : 0) + 2
                (b.blockColor.map { NSColor(hex: $0) } ?? theme.accentColor).setFill()
                NSBezierPath(roundedRect: NSRect(x: x, y: r.minY + 2, width: 3, height: r.height - 4), xRadius: 1.5, yRadius: 1.5).fill()
            }
            if b.kind == .quote {
                theme.text.withAlphaComponent(0.28).setFill()
                NSBezierPath(roundedRect: NSRect(x: origin.x + 3, y: r.minY + 1, width: 3, height: r.height - 2), xRadius: 1.5, yRadius: 1.5).fill()
            }
        }
    }

    public override func drawGlyphs(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        super.drawGlyphs(forGlyphRange: glyphsToShow, at: origin)
        guard let s = textStorage else { return }
        let charRange = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)
        let ns = s.string as NSString
        enumerateParagraphs(ns, charRange) { pr in
            let b = (s.attribute(.draftBlock, at: pr.location, effectiveRange: nil) as? BlockInfo) ?? .paragraph()
            drawMarker(b, pr: pr, origin: origin, line: firstLineRect(pr)?.rect)
        }
        // Trailing empty paragraph (no characters) still shows its list marker.
        if trailingBlock.kind.isList, (ns.length == 0 || ns.character(at: ns.length - 1) == 10), extraLineFragmentTextContainer != nil {
            drawMarker(trailingBlock, pr: NSRange(location: ns.length, length: 0), origin: origin, line: extraLineFragmentRect)
        }
    }

    private func drawMarker(_ b: BlockInfo, pr: NSRange, origin: NSPoint, line: NSRect?) {
        guard b.kind.isList, !b.continuation, let bl = baseline(forParagraphAt: pr, block: b) else { return }
        let font = theme.baseFont(b)
        let baseX = origin.x + EditorTheme.listIndent * CGFloat(b.indent + 1) + (b.decoration == "focus" ? 16 : 0)
        let baseY = origin.y + bl.y
        let color = (b.kind == .task && b.checked) ? theme.secondary : theme.text
        switch b.kind {
        case .bullet:
            let d: CGFloat = max(5, font.pointSize * 0.33)
            let cy = baseY - font.xHeight / 2
            let rect = NSRect(x: baseX - 16, y: cy - d / 2, width: d, height: d)
            color.setFill(); color.setStroke()
            switch b.indent % 3 {
            case 0: NSBezierPath(ovalIn: rect).fill()
            case 1: let p = NSBezierPath(ovalIn: rect.insetBy(dx: 0.6, dy: 0.6)); p.lineWidth = 1.2; p.stroke()
            default: NSBezierPath(rect: rect.insetBy(dx: 0.5, dy: 0.5)).fill()
            }
        case .ordered:
            let n = ordinal(at: pr.location)
            let label = b.indent % 2 == 1 ? "\(letters(n))." : "\(n)."
            let f = theme.font(size: font.pointSize, weight: .regular).withMonospacedDigits()
            let attrs: [NSAttributedString.Key: Any] = [.font: f, .foregroundColor: color]
            let w = (label as NSString).size(withAttributes: attrs).width
            // NSString drawing in a flipped view: point is the top-left of the line box.
            (label as NSString).draw(at: NSPoint(x: baseX - 7 - w, y: baseY - f.ascender), withAttributes: attrs)
        case .task:
            guard let box = checkboxRect(forParagraphAt: pr)?.offsetBy(dx: origin.x, dy: origin.y) else { return }
            let path = NSBezierPath(roundedRect: box, xRadius: 4.5, yRadius: 4.5)
            if b.checked {
                theme.accentColor.setFill(); path.fill()
                let check = NSBezierPath()
                check.move(to: NSPoint(x: box.minX + 4, y: box.midY))
                check.line(to: NSPoint(x: box.minX + 7, y: box.maxY - 4.5))
                check.line(to: NSPoint(x: box.maxX - 3.5, y: box.minY + 4.5))
                check.lineWidth = 2; check.lineCapStyle = .round; check.lineJoinStyle = .round
                NSColor.white.setStroke(); check.stroke()
            } else {
                theme.text.withAlphaComponent(0.45).setStroke(); path.lineWidth = 1.4
                path.stroke()
            }
        default: break
        }
    }

    private func letters(_ n: Int) -> String {
        var n = n, s = ""
        repeat { n -= 1; s = String(UnicodeScalar(97 + n % 26)!) + s; n /= 26 } while n > 0
        return s
    }

    private func enumerateParagraphs(_ ns: NSString, _ range: NSRange, _ fn: (NSRange) -> Void) {
        guard ns.length > 0 else { return }
        var loc = min(range.location, ns.length - 1)
        let end = min(NSMaxRange(range), ns.length)
        repeat {
            let pr = ns.paragraphRange(for: NSRange(location: loc, length: 0))
            fn(pr)
            loc = NSMaxRange(pr)
        } while loc < end
    }
}

extension NSFont {
    func withMonospacedDigits() -> NSFont {
        let d = fontDescriptor.addingAttributes([.featureSettings: [[NSFontDescriptor.FeatureKey.typeIdentifier: kNumberSpacingType, NSFontDescriptor.FeatureKey.selectorIdentifier: kMonospacedNumbersSelector]]])
        return NSFont(descriptor: d, size: pointSize) ?? self
    }
}
