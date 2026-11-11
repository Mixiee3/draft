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
    var isHidden: (Int) -> Bool = { _ in false }
    /// True when the current selection is shown as an outline (blocks, an image), not a fill.
    var selectionIsOutlined: () -> Bool = { false }

    public override func fillBackgroundRectArray(_ rectArray: UnsafePointer<NSRect>, count rectCount: Int, forCharacterRange charRange: NSRange, color: NSColor) {
        if selectionIsOutlined(), let s = textStorage, charRange.location < s.length,
           s.attribute(.draftHighlight, at: charRange.location, effectiveRange: nil) == nil,
           s.attribute(.draftCode, at: charRange.location, effectiveRange: nil) == nil { return }
        super.fillBackgroundRectArray(rectArray, count: rectCount, forCharacterRange: charRange, color: color)
    }

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
    public func paragraphRect(_ pr: NSRange) -> NSRect? {
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

    public func firstLineRect(_ pr: NSRange) -> (rect: NSRect, used: NSRect)? {
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

    /// Rect path with separate corner radii for the top and bottom edges (flipped coordinates).
    static func roundedRect(_ r: NSRect, top: CGFloat, bottom: CGFloat) -> NSBezierPath {
        let p = NSBezierPath()
        p.move(to: NSPoint(x: r.minX + top, y: r.minY))
        p.line(to: NSPoint(x: r.maxX - top, y: r.minY))
        p.appendArc(withCenter: NSPoint(x: r.maxX - top, y: r.minY + top), radius: top, startAngle: 270, endAngle: 360)
        p.line(to: NSPoint(x: r.maxX, y: r.maxY - bottom))
        p.appendArc(withCenter: NSPoint(x: r.maxX - bottom, y: r.maxY - bottom), radius: bottom, startAngle: 0, endAngle: 90)
        p.line(to: NSPoint(x: r.minX + bottom, y: r.maxY))
        p.appendArc(withCenter: NSPoint(x: r.minX + bottom, y: r.maxY - bottom), radius: bottom, startAngle: 90, endAngle: 180)
        p.line(to: NSPoint(x: r.minX, y: r.minY + top))
        p.appendArc(withCenter: NSPoint(x: r.minX + top, y: r.minY + top), radius: top, startAngle: 180, endAngle: 270)
        p.close()
        return p
    }

    /// Hit area of a toggle's disclosure triangle (container coordinates).
    public func toggleRect(forParagraphAt pr: NSRange) -> NSRect? {
        guard let s = textStorage, pr.location < s.length,
              let b = s.attribute(.draftBlock, at: pr.location, effectiveRange: nil) as? BlockInfo, b.kind == .toggle, !b.continuation,
              let bl = baseline(forParagraphAt: pr, block: b) else { return nil }
        let font = theme.baseFont(b)
        let x = EditorTheme.listIndent * CGFloat(b.indent + 1) - 23 + (b.decoration == "focus" ? 16 : 0)
        return NSRect(x: x, y: bl.y - font.capHeight / 2 - 8, width: 16, height: 16)
    }

    public override func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        super.drawBackground(forGlyphRange: glyphsToShow, at: origin)
        guard let s = textStorage, let container = textContainers.first else { return }
        let charRange = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)
        let ns = s.string as NSString
        let width = container.size.width
        enumerateParagraphs(ns, charRange) { pr in
            guard !isHidden(pr.location) else { return }
            let b = (s.attribute(.draftBlock, at: pr.location, effectiveRange: nil) as? BlockInfo) ?? .paragraph()
            guard let rect = paragraphRect(pr) else { return }
            let r = rect.offsetBy(dx: origin.x, dy: origin.y)
            if b.kind == .callout {
                func sameCallout(_ loc: Int) -> Bool {
                    guard loc >= 0, loc < s.length, let o = s.attribute(.draftBlock, at: loc, effectiveRange: nil) as? BlockInfo else { return false }
                    return o.kind == .callout && o.containerId == b.containerId
                }
                let first = !sameCallout(pr.location - 1)
                let last = !sameCallout(NSMaxRange(pr))
                let top = r.minY - (first ? 9 : 0), bottom = r.maxY + (last ? 9 : 0)
                let bg = NSRect(x: origin.x, y: top, width: width, height: bottom - top)
                (b.blockColor.map { NSColor(hex: $0, alpha: theme.isDarkPage ? 0.3 : 0.24) } ?? theme.accentColor.withAlphaComponent(theme.isDarkPage ? 0.2 : 0.1)).setFill()
                Self.roundedRect(bg, top: first ? 12 : 0, bottom: last ? 12 : 0).fill()
                if first, let bl = baseline(forParagraphAt: pr, block: b) {
                    let f = NSFont.systemFont(ofSize: theme.baseFont(b).pointSize * 0.95)
                    ((b.icon ?? "💡") as NSString).draw(at: NSPoint(x: origin.x + 13, y: origin.y + bl.y - f.ascender), withAttributes: [.font: f])
                }
            }
            if b.kind == .code {
                let bg = NSRect(x: origin.x, y: r.minY - 6, width: width, height: r.height + 12)
                theme.text.withAlphaComponent(theme.isDarkPage ? 0.09 : 0.055).setFill()
                NSBezierPath(roundedRect: bg, xRadius: 10, yRadius: 10).fill()
            } else if let d = b.decoration, d != "block", d != "focus", BlockEffects.kinds.contains(d) {
                drawEffect(d, b, pr: pr, rect: r, origin: origin, width: width)
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

    /// Block effects. Plain fills and strokes only (no blur), so scrolling and typing stay cheap.
    private func drawEffect(_ d: String, _ b: BlockInfo, pr: NSRange, rect r: NSRect, origin: NSPoint, width: CGFloat) {
        let tint = b.blockColor.map { NSColor(hex: $0) } ?? theme.accentColor
        let dark = theme.isDarkPage
        if d == "accent" && b.kind == .heading {
            let line = NSRect(x: origin.x, y: r.maxY - 2, width: min(width, 64), height: 3)
            tint.setFill(); NSBezierPath(roundedRect: line, xRadius: 1.5, yRadius: 1.5).fill()
            return
        }
        // Line fragments carry paragraph spacing unevenly (none after the last paragraph), so the
        // box is measured from the first and last baselines instead.
        let font = theme.baseFont(b)
        var top = r.minY - 5, bottom = r.maxY + 5
        let gr = glyphRange(forCharacterRange: NSRange(location: pr.location, length: max(0, pr.length - (NSMaxRange(pr) > pr.location && (textStorage?.string as NSString?)?.character(at: NSMaxRange(pr) - 1) == 10 ? 1 : 0))), actualCharacterRange: nil)
        if gr.length > 0 {
            let first = lineFragmentRect(forGlyphAt: gr.location, effectiveRange: nil), last = lineFragmentRect(forGlyphAt: NSMaxRange(gr) - 1, effectiveRange: nil)
            top = origin.y + first.minY + location(forGlyphAt: gr.location).y - font.ascender - 7
            bottom = origin.y + last.minY + location(forGlyphAt: NSMaxRange(gr) - 1).y - font.descender + 7
        }
        let bg = NSRect(x: origin.x, y: top, width: width, height: max(0, bottom - top))
        let path = NSBezierPath(roundedRect: bg, xRadius: 10, yRadius: 10)
        switch d {
        case "gradient":
            if theme.plainEffects { tint.withAlphaComponent(dark ? 0.22 : 0.12).setFill(); path.fill() }
            else { NSGradient(starting: tint.withAlphaComponent(dark ? 0.32 : 0.2), ending: tint.withAlphaComponent(dark ? 0.06 : 0.03))?.draw(in: path, angle: 0) }
        case "glass":
            let solid = theme.plainEffects || theme.solidGlass
            (dark ? NSColor.white.withAlphaComponent(solid ? 0.1 : 0.07) : NSColor.white.withAlphaComponent(solid ? 0.9 : 0.6)).setFill(); path.fill()
            if !solid { NSGradient(starting: NSColor.white.withAlphaComponent(dark ? 0.08 : 0.5), ending: .clear)?.draw(in: path, angle: -90) }
            (dark ? NSColor.white.withAlphaComponent(0.18) : theme.text.withAlphaComponent(solid ? 0.25 : 0.1)).setStroke()
            path.lineWidth = solid ? 1 : 0.5; path.stroke()
        case "glow":
            NSGraphicsContext.saveGraphicsState()
            if !theme.plainEffects { let sh = NSShadow(); sh.shadowColor = tint.withAlphaComponent(dark ? 0.7 : 0.45); sh.shadowBlurRadius = 10; sh.set() }
            tint.withAlphaComponent(dark ? 0.16 : 0.07).setFill(); path.fill()
            NSGraphicsContext.restoreGraphicsState()
            tint.withAlphaComponent(0.6).setStroke(); path.lineWidth = 1; path.stroke()
        default: // accent
            tint.withAlphaComponent(dark ? 0.08 : 0.04).setFill(); path.fill()
            tint.setStroke(); path.lineWidth = 1.5; path.stroke()
        }
    }

    // MARK: Spectrum text

    /// Whole runs of spectrum text being drawn (view coordinates), so one gradient spans each run
    /// even when it is drawn in pieces.
    private var spectrumRuns: [(rect: NSRect, colors: [NSColor], spec: Spectrum, angle: Double)] = []

    /// Spectrum runs that intersect `visible`, as view rects (used by the editor's clock).
    public func spectrumRects(in visible: NSRect, origin: NSPoint) -> [NSRect] {
        guard let s = textStorage, let tc = textContainers.first, !theme.plainEffects, theme.animateEffects else { return [] }
        let gr = glyphRange(forBoundingRect: visible.offsetBy(dx: -origin.x, dy: -origin.y), in: tc)
        let cr = characterRange(forGlyphRange: gr, actualGlyphRange: nil)
        var out: [NSRect] = []
        s.enumerateAttribute(.draftEffect, in: cr) { v, r, _ in
            guard let v = v as? String, let sp = Spectrum(v), sp.seconds > 0 else { return }
            out.append(boundingRect(forGlyphRange: glyphRange(forCharacterRange: r, actualCharacterRange: nil), in: tc).offsetBy(dx: origin.x, dy: origin.y).insetBy(dx: -2, dy: -2))
        }
        return out
    }

    private func collectSpectrumRuns(_ glyphsToShow: NSRange, origin: NSPoint) {
        spectrumRuns = []
        guard !theme.plainEffects, let s = textStorage, let tc = textContainers.first else { return }
        let cr = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)
        s.enumerateAttribute(.draftEffect, in: cr) { v, r, _ in
            guard let v = v as? String, let (colors, sp) = gradientRun(v) else { return }
            var full = NSRange()
            _ = s.attribute(.draftEffect, at: r.location, longestEffectiveRange: &full, in: NSRange(location: 0, length: s.length))
            let rect = boundingRect(forGlyphRange: glyphRange(forCharacterRange: full, actualCharacterRange: nil), in: tc).offsetBy(dx: origin.x, dy: origin.y)
            spectrumRuns.append((rect, colors, sp, gradientAngle(v)))
        }
    }

    /// Effects drawn as one gradient across the run: Spectrum (moving) and Gradient (still, accent
    /// to a darker or lighter tone).
    func gradientRun(_ v: String) -> ([NSColor], Spectrum)? {
        guard let e = EffectSpec(v), ["gradient", "spectrum"].contains(e.kind) else { return nil }
        let colors = e.fillColors(accent: theme.accent, text: theme.textColor, page: theme.pageColor).map { NSColor(hex: $0) }
        return (colors, e.spectrum ?? Spectrum(palette: "aurora", speed: "still"))
    }

    /// Gradient direction for a run: Spectrum runs left to right; Gradient follows its angle.
    func gradientAngle(_ v: String) -> Double { EffectSpec(v)?.spectrum == nil ? (EffectSpec(v)?.angle ?? 0) : 0 }

    public override func showCGGlyphs(_ glyphs: UnsafePointer<CGGlyph>, positions: UnsafePointer<CGPoint>, count: Int, font: NSFont,
                                      textMatrix: CGAffineTransform, attributes: [NSAttributedString.Key: Any] = [:], in ctx: CGContext) {
        guard count > 0, let v = attributes[.draftEffect] as? String, let ek = EffectSpec(v)?.kind, ek == "gradient" || ek == "spectrum",
              let run = spectrumRuns.first(where: { $0.rect.insetBy(dx: -4, dy: -4).contains(positions[0]) }) else {
            super.showCGGlyphs(glyphs, positions: positions, count: count, font: font, textMatrix: textMatrix, attributes: attributes, in: ctx)
            return
        }
        ctx.saveGState()
        ctx.textMatrix = textMatrix
        ctx.setTextDrawingMode(.clip)
        CTFontDrawGlyphs(font, glyphs, positions, count, ctx)
        // One gradient period spans the whole run; it slides by the phase, so the colours move
        // without any layout or attribute change.
        let colors = run.colors.map(\.cgColor) as CFArray
        if let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors, locations: nil), run.spec.seconds == 0 {
            // A still gradient: once across the run, along its angle (0° left to right, 90° top to bottom; flipped view).
            let r = run.rect, a = run.angle * .pi / 180
            let half = (abs(cos(a)) * r.width + abs(sin(a)) * r.height) / 2
            let c = CGPoint(x: r.midX, y: r.midY), d = CGPoint(x: cos(a) * half, y: sin(a) * half)
            ctx.drawLinearGradient(g, start: CGPoint(x: c.x - d.x, y: c.y - d.y), end: CGPoint(x: c.x + d.x, y: c.y + d.y), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        } else if let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors, locations: nil) {
            let w = max(run.rect.width, 40)
            var phase = run.spec.seconds > 0 && theme.animateEffects ? (CACurrentMediaTime() / run.spec.seconds).truncatingRemainder(dividingBy: 1) : 0
            if run.spec.direction == "backward" { phase = -phase }
            let x0 = run.rect.minX - CGFloat(phase) * w - w
            for k in 0..<3 {
                let a = x0 + CGFloat(k) * w
                ctx.drawLinearGradient(g, start: CGPoint(x: a, y: 0), end: CGPoint(x: a + w, y: 0), options: [])
            }
        }
        ctx.restoreGState()
    }

    public override func drawGlyphs(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        collectSpectrumRuns(glyphsToShow, origin: origin)
        super.drawGlyphs(forGlyphRange: glyphsToShow, at: origin)
        guard let s = textStorage else { return }
        let charRange = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)
        let ns = s.string as NSString
        enumerateParagraphs(ns, charRange) { pr in
            guard !isHidden(pr.location) else { return }
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
        case .toggle:
            guard let box = toggleRect(forParagraphAt: pr)?.offsetBy(dx: origin.x, dy: origin.y) else { return }
            let tri = NSBezierPath()
            let c = NSPoint(x: box.midX, y: box.midY), h: CGFloat = 4.6
            if b.checked {
                tri.move(to: NSPoint(x: c.x - h, y: c.y - h * 0.55)); tri.line(to: NSPoint(x: c.x + h, y: c.y - h * 0.55)); tri.line(to: NSPoint(x: c.x, y: c.y + h * 0.75))
            } else {
                tri.move(to: NSPoint(x: c.x - h * 0.55, y: c.y - h)); tri.line(to: NSPoint(x: c.x + h * 0.75, y: c.y)); tri.line(to: NSPoint(x: c.x - h * 0.55, y: c.y + h))
            }
            tri.close()
            theme.text.withAlphaComponent(0.7).setFill(); tri.fill()
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
