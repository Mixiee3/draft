import AppKit
import DraftCore

/// Original Draft color sets. Pastels are highlights; saturated ones are text colors.
public enum DraftPalette {
    public static let highlights: [(String, String)] = [
        ("Butter", "#fff3a3"), ("Lime", "#e3f7a8"), ("Mint", "#c6f1d6"), ("Sky", "#c9ecf7"), ("Cornflower", "#cfdcfb"),
        ("Lilac", "#e2d6fb"), ("Rose", "#fbd3e9"), ("Peach", "#ffd9c7"), ("Stone", "#e4e2dd"),
        ("Gold", "#ffe08a"), ("Coral", "#ffb8a8"), ("Teal", "#b2e5e0"),
    ]
    public static let textColors: [(String, String)] = [
        ("Ink blue", "#2f5bd3"), ("Violet", "#7b4fd6"), ("Berry", "#c2366b"), ("Rust", "#c75a1d"), ("Moss", "#4f7d33"),
    ]
    public static let blockColors: [(String, String)] = [
        ("Graphite", "#8f8e8a"), ("Silver", "#b9bcc2"), ("Fog", "#d3d6db"), ("Iris", "#9d9bf2"), ("Cornflower", "#a8c1f5"), ("Glacier", "#a9dde8"),
        ("Mint", "#a9e2c0"), ("Orchid", "#dcaaf0"), ("Rose", "#f0a8b3"), ("Apricot", "#f5cfa0"), ("Sand", "#d9c7a8"), ("Butter", "#f5e48f"),
    ]
}

/// The floating formatting bar shown above a text selection.
///
/// - Anchors to the selection rectangle, flips below near the top, clamps horizontally.
/// - Clicking never takes focus from the text, so the selection is preserved while the color
///   palette or link field is open.
/// - Keyboard: ⌥F10 focuses the bar; ←/→ move, Return/Space activate, Esc returns to the text.
public final class SelectionToolbar: NSView {
    public override func resetCursorRects() { addCursorRect(bounds, cursor: .arrow) }
    public override func cursorUpdate(with event: NSEvent) { NSCursor.arrow.set() }
    public enum Mode { case main, palette, effects, spectrum, link }
    struct Item {
        var id: String
        var label: String
        var symbol: String?
        var swatch: String? = nil
        var swatchIsText = false
        var width: CGFloat = 32
        var isSeparator = false
        var action: (() -> Void)?
        var isActive: Bool = false
        var isEnabled: Bool = true
        /// Text shown on the control (chips), or the text of a section label.
        var title: String? = nil
        /// A section heading inside the bar (not a control).
        var isLabel = false
        /// Starts a new row.
        var isBreak = false
        /// A multi-color swatch (a palette's stops) drawn before the title.
        var gradient: [String]? = nil
    }

    unowned let controller: EditorController
    var mode: Mode = .main
    var items: [Item] = []
    var frames: [NSRect] = []
    var keyboardIndex: Int? = nil
    var dismissedSelection: NSRange? = nil
    var linkRange = NSRange(location: 0, length: 0)
    let linkField = NSTextField()
    var hoverIndex: Int? = nil
    /// The blurred material behind the bar (a sibling just below it, so the bar's icons stay on top).
    let glass = NSVisualEffectView()
    static let height: CGFloat = 46
    static let radius: CGFloat = 23
    public private(set) var isVisible = false
    /// True while a context menu is open over the selection.
    public var suspended = false

    init(controller: EditorController) {
        self.controller = controller
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = Self.radius
        layer?.cornerCurve = .continuous
        layer?.borderWidth = 0.5
        layer?.shadowOpacity = 0.16
        layer?.shadowRadius = 18
        layer?.shadowOffset = CGSize(width: 0, height: -8)
        layer?.masksToBounds = false
        glass.material = .popover
        glass.blendingMode = .withinWindow
        glass.state = .active
        glass.wantsLayer = true
        glass.layer?.cornerRadius = Self.radius
        glass.layer?.cornerCurve = .continuous
        glass.layer?.masksToBounds = true
        glass.isHidden = true
        isHidden = true
        setAccessibilityRole(.toolbar)
        setAccessibilityLabel("Text formatting")
        linkField.placeholderString = "Paste or type a link, then press Return"
        linkField.isBordered = false
        linkField.drawsBackground = false
        linkField.focusRingType = .none
        linkField.font = .systemFont(ofSize: 13)
        linkField.target = self
        linkField.action = #selector(commitLink)
        linkField.delegate = self
        linkField.isHidden = true
        addSubview(linkField)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect], owner: self))
    }
    required init?(coder: NSCoder) { fatalError() }

    public override var isFlipped: Bool { true }
    public override var acceptsFirstResponder: Bool { keyboardIndex != nil }
    public override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    var dark: Bool { controller.theme.isDarkPage }

    // MARK: Model

    func buildItems() {
        let c = controller
        let code = c.currentBlock.kind == .code
        func back(_ to: Mode, _ title: String) -> Item {
            Item(id: "back", label: "Back to \(title.lowercased())", symbol: "chevron.left", action: { [weak self] in self?.setMode(to) }, title: title)
        }
        func label(_ t: String) -> Item { Item(id: "label-" + t, label: t, symbol: nil, isEnabled: false, title: t, isLabel: true) }
        let sep = { (n: Int) in Item(id: "sep\(n)", label: "", symbol: nil, width: 9, isSeparator: true) }
        let rowBreak = Item(id: "break", label: "", symbol: nil, width: 0, isSeparator: true, isBreak: true)
        switch mode {
        case .main:
            // Inline marks | link and code | color | effects | more. The right-click menu keeps the
            // clipboard, look-up and block actions, so the two never repeat each other.
            let hl = c.value(of: .draftHighlight)
            let fx = c.value(of: .draftEffect)
            items = [
                Item(id: "bold", label: "Bold (⌘B)", symbol: "bold", action: { c.toggleMark(.bold) }, isActive: c.isMarkActive(.bold), isEnabled: !code),
                Item(id: "italic", label: "Italic (⌘I)", symbol: "italic", action: { c.toggleMark(.italic) }, isActive: c.isMarkActive(.italic), isEnabled: !code),
                Item(id: "underline", label: "Underline (⌘U)", symbol: "underline", action: { c.toggleMark(.underline) }, isActive: c.isMarkActive(.underline), isEnabled: !code),
                Item(id: "strike", label: "Strikethrough (⌘⇧X)", symbol: "strikethrough", action: { c.toggleMark(.strike) }, isActive: c.isMarkActive(.strike), isEnabled: !code),
                sep(1),
                Item(id: "link", label: "Link (⌘K)", symbol: "link", action: { [weak self] in self?.openLink() }, isActive: c.value(of: .draftLink) != nil, isEnabled: !code),
                Item(id: "code", label: "Inline code (⌘E)", symbol: "chevron.left.forwardslash.chevron.right", action: { c.toggleMark(.code) }, isActive: c.isMarkActive(.code), isEnabled: !code),
                sep(2),
                Item(id: "highlight", label: hl == nil ? "Highlight (⌥⌘H reapplies the last color)" : "Remove highlight", symbol: "highlighter", swatch: hl, action: { [weak self] in
                    guard let self else { return }
                    let last = self.controller.lastColor?.kind == "highlight" ? self.controller.lastColor?.hex : DraftPalette.highlights.first?.1
                    self.controller.setHighlight(self.controller.value(of: .draftHighlight) != nil ? nil : last)
                }, isActive: hl != nil, isEnabled: !code),
                Item(id: "palette", label: "Text color and highlight colors", symbol: "chevron.down", width: 20, action: { [weak self] in self?.setMode(.palette) }, isEnabled: !code),
                sep(3),
                Item(id: "effects", label: "Text effects", symbol: "sparkles", action: { [weak self] in self?.setMode(.effects) }, isActive: fx != nil, isEnabled: !code, title: "Effects"),
                sep(4),
                Item(id: "more", label: "More: clear formatting and block options", symbol: "ellipsis", action: { [weak self] in self?.showMore() }),
            ]
        case .palette:
            let current = c.value(of: .draftHighlight)
            let currentText = c.value(of: .draftTextColor)
            items = [back(.main, "Format"), label("Highlight")]
            for (name, hex) in DraftPalette.highlights {
                items.append(Item(id: "h" + hex, label: "Highlight \(name)", symbol: nil, swatch: hex, width: 26, action: { [weak self] in self?.controller.setHighlight(hex); self?.setMode(.main) }, isActive: current == hex))
            }
            items.append(rowBreak)
            items.append(label("Text"))
            for (name, hex) in DraftPalette.textColors {
                items.append(Item(id: "t" + hex, label: "Text color \(name)", symbol: nil, swatch: hex, swatchIsText: true, width: 26, action: { [weak self] in self?.controller.setTextColor(hex); self?.setMode(.main) }, isActive: currentText == hex))
            }
            items.append(sep(1))
            items.append(Item(id: "none", label: "Remove colors", symbol: "nosign", action: { [weak self] in
                self?.controller.setHighlight(nil); self?.controller.setTextColor(nil); self?.setMode(.main)
            }, isEnabled: current != nil || currentText != nil, title: "None"))
        case .effects:
            let current = c.value(of: .draftEffect)
            let currentKind = current.flatMap(EffectSpec.init)?.kind
            items = [back(.main, "Format"), label("Effects")]
            for e in TextEffects.all where e.kind != "spectrum" {
                // Picking the effect already on the text keeps its colors; another one starts fresh.
                items.append(Item(id: "fx" + e.kind, label: "\(e.name) effect: \(e.use)", symbol: nil, action: { [weak self] in
                    if currentKind != e.kind { self?.controller.setEffect(e.kind) }; self?.setMode(.main)
                }, isActive: currentKind == e.kind, title: e.name))
            }
            items.append(Item(id: "fxspectrum", label: "Spectrum: a moving color gradient for a title or label", symbol: "chevron.right", action: { [weak self] in self?.setMode(.spectrum) },
                              isActive: current.flatMap(Spectrum.init) != nil, title: "Spectrum"))
            items.append(sep(1))
            if c.theme.plainEffects { items += simplifiedNotice(rowBreak) }
            items.append(Item(id: "fxcustom", label: "Customize colors and strength in the Format panel", symbol: "slider.horizontal.3", action: { [weak self] in
                self?.controller.onCustomizeEffect?(); self?.setMode(.main)
            }, isEnabled: current != nil, title: "Customize…"))
            items.append(Item(id: "fxnone", label: "Remove the effect", symbol: "nosign", action: { [weak self] in self?.controller.setEffect(nil); self?.setMode(.main) }, isEnabled: current != nil, title: "None"))
        case .spectrum:
            let currentSpec = c.value(of: .draftEffect).flatMap(Spectrum.init)
            let current = currentSpec ?? Spectrum()
            let on = currentSpec != nil
            items = [back(.effects, "Effects"), label("Spectrum")]
            for p in Spectrum.palettes {
                var s = current; s.palette = p.id
                items.append(Item(id: "sp" + p.id, label: "Spectrum \(p.name)", symbol: nil, action: { [weak self] in self?.controller.setEffect(s.value); self?.buildItems(); self?.position() },
                                  isActive: on && current.palette == p.id, title: p.name.components(separatedBy: " ").first, gradient: p.colors))
            }
            items.append(rowBreak)
            items.append(label("Speed"))
            for sp in Spectrum.speeds {
                var s = current; s.speed = sp.id
                items.append(Item(id: "sps" + sp.id, label: "Speed \(sp.name)", symbol: nil, action: { [weak self] in self?.controller.setEffect(s.value); self?.buildItems() }, isActive: on && current.speed == sp.id, isEnabled: on, title: sp.name))
            }
            if c.theme.plainEffects { items += simplifiedNotice(rowBreak) }
            var flipped = current; flipped.direction = current.direction == "forward" ? "backward" : "forward"
            items.append(sep(1))
            items.append(Item(id: "spdir", label: "Direction: \(current.direction); press to reverse", symbol: current.direction == "forward" ? "arrow.right" : "arrow.left",
                              action: { [weak self] in self?.controller.setEffect(flipped.value); self?.buildItems() }, isEnabled: on))
        case .link:
            let has = c.value(of: .draftLink) != nil
            items = [Item(id: "linkicon", label: "Link", symbol: "link", width: 30, isEnabled: false)]
            items.append(Item(id: "field", label: "", symbol: nil, width: 250, isSeparator: true))
            if has { items.append(Item(id: "unlink", label: "Remove link", symbol: "link.badge.plus", width: 32, action: { [weak self] in self?.removeLink() })) }
            items.append(Item(id: "done", label: "Apply link", symbol: "return", width: 32, action: { [weak self] in self?.commitLink() }))
        }
        layoutItems()
    }

    /// Increase Contrast simplifies effects to a still, readable color; say so where effects are
    /// picked, with a way to show them in full.
    func simplifiedNotice(_ rowBreak: Item) -> [Item] {
        [rowBreak, Item(id: "label-simplified", label: "Simplified: Increase Contrast is on", symbol: nil, isEnabled: false, title: "Simplified · Increase Contrast", isLabel: true),
         Item(id: "fxfull", label: "Show full effects anyway (a Draft setting)", symbol: "eye", action: { [weak self] in self?.controller.onShowFullEffects?(); self?.buildItems() }, title: "Show Full Effects")]
    }

    static let chipFont = NSFont.systemFont(ofSize: 13, weight: .medium)
    static let labelFont = NSFont.systemFont(ofSize: 11, weight: .semibold)

    func width(of it: Item) -> CGFloat {
        if it.isSeparator { return it.width }
        if it.isLabel { return ceil((it.title!.uppercased() as NSString).size(withAttributes: [.font: Self.labelFont]).width) + 14 }
        if let t = it.title {
            let text = ceil((t as NSString).size(withAttributes: [.font: Self.chipFont]).width)
            return text + 20 + (it.gradient != nil ? 30 : it.symbol != nil || it.swatch != nil ? 18 : 0)
        }
        return it.swatch != nil || it.id == "field" ? it.width : max(it.width, 34)
    }

    /// Lays controls out in rows no wider than the editor allows; a narrow window gets two rows
    /// instead of a bar that runs off the side.
    func layoutItems() {
        let rowH = Self.height - 10
        let maxWidth = max(280, min(640, (controller.overlayHost?.visibleRect.width ?? 640) - 20))
        var x: CGFloat = 9, row = 0, widest: CGFloat = 0
        frames = items.map { it in
            let w = width(of: it)
            if it.isBreak || (x + w > maxWidth - 6 && x > 9 && !it.isSeparator) {
                widest = max(widest, x); x = 9; row += 1
                if it.isBreak { return NSRect(x: 0, y: 0, width: 0, height: 0) }
            }
            let r = NSRect(x: x, y: 5 + CGFloat(row) * (rowH + 2), width: w, height: rowH)
            x += w + (it.isSeparator ? 0 : 3)
            return r
        }
        widest = max(widest, x)
        let rows = CGFloat(row + 1)
        setFrameSize(NSSize(width: widest + 6, height: rows * rowH + (rows - 1) * 2 + 10))
        let radius = rows > 1 ? 16 : Self.radius
        layer?.cornerRadius = radius; glass.layer?.cornerRadius = radius
        if mode == .link, let i = items.firstIndex(where: { $0.id == "field" }) {
            linkField.frame = frames[i].insetBy(dx: 2, dy: 7)
        }
        rebuildAccessibility()
        needsDisplay = true
    }

    /// Clear formatting and the block options, as a menu under the More button.
    func showMore() {
        let menu = NSMenu()
        let clear = ClosureMenuItem(title: "Clear Formatting") { [weak self] in self?.controller.clearFormatting() }
        clear.image = NSImage(systemSymbolName: "eraser", accessibilityDescription: nil)
        menu.addItem(clear)
        menu.addItem(.separator())
        for item in controller.blockMenu().items { item.menu?.removeItem(item); menu.addItem(item) }
        guard let i = items.firstIndex(where: { $0.id == "more" }) else { return }
        menu.popUp(positioning: nil, at: NSPoint(x: frames[i].minX, y: frames[i].maxY + 6), in: self)
    }

    public func setMode(_ m: Mode) {
        mode = m
        linkField.isHidden = m != .link
        if keyboardIndex != nil { keyboardIndex = items.isEmpty ? nil : 0 }
        buildItems()
        position()
        if keyboardIndex != nil { keyboardIndex = items.firstIndex { !$0.isSeparator && $0.isEnabled } }
    }

    // MARK: Visibility & positioning

    var shouldShow: Bool {
        let tv = controller.textView
        let sel = tv.selectedRange()
        guard sel.length > 0, controller.overlayHost != nil, !controller.isBlockMode, !suspended else { return false }
        if let d = dismissedSelection, d == sel { return false }
        // Pure attachment selections (one image/card) have no text to format.
        if sel.length == 1, controller.storage.attribute(.attachment, at: sel.location, effectiveRange: nil) != nil { return false }
        let fr = tv.window?.firstResponder
        return fr === tv || fr === self || mode != .main || (fr as? NSView)?.isDescendant(of: self) == true
    }

    public func update() {
        let sel = controller.textView.selectedRange()
        if let d = dismissedSelection, d != sel { dismissedSelection = nil }
        if mode == .link && linkField.currentEditor() != nil { return }
        if !shouldShow {
            hide(); return
        }
        if superview !== controller.overlayHost { controller.overlayHost?.addSubview(self) }
        if !isVisible || mode != .main && (window?.firstResponder === controller.textView) && mode != .palette && mode != .effects && mode != .spectrum { mode = .main; linkField.isHidden = true }
        buildItems()
        position()
        if !isVisible {
            isVisible = true
            isHidden = false
            syncGlass()
            if !(controller.host == nil) && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion && controller.theme.animateEffects {
                alphaValue = 0; glass.alphaValue = 0
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = 0.14
                    animator().alphaValue = 1; glass.animator().alphaValue = 1
                }
            }
        }
    }

    func hide() {
        guard isVisible || !isHidden else { return }
        isVisible = false
        isHidden = true
        glass.isHidden = true
        mode = .main
        keyboardIndex = nil
        linkField.isHidden = true
        hoverIndex = nil
        window?.invalidateCursorRects(for: controller.textView)
    }

    public func dismissForCurrentSelection() {
        dismissedSelection = controller.textView.selectedRange()
        if window?.firstResponder !== controller.textView { window?.makeFirstResponder(controller.textView) }
        hide()
    }

    /// Selection rectangles (first line / last line) in overlay-host coordinates.
    func selectionRects() -> (first: NSRect, last: NSRect)? {
        guard let host = controller.overlayHost else { return nil }
        let tv = controller.textView
        let sel = mode == .link ? linkRange : tv.selectedRange()
        let gr = controller.layout.glyphRange(forCharacterRange: sel, actualCharacterRange: nil)
        var rects: [NSRect] = []
        controller.layout.enumerateEnclosingRects(forGlyphRange: gr, withinSelectedGlyphRange: gr, in: controller.container) { r, _ in rects.append(r) }
        guard let f = rects.first, let l = rects.last else { return nil }
        let o = tv.textContainerOrigin
        let conv = { (r: NSRect) in tv.convert(r.offsetBy(dx: o.x, dy: o.y), to: host) }
        return (conv(f), conv(l))
    }

    func position() {
        guard let host = controller.overlayHost, let (first, last) = selectionRects() else { return }
        let size = frame.size
        let visible = host.visibleRect
        let topSafe = visible.minY + 8 // the scroll area already starts below the document controls
        var y = first.minY - size.height - 12
        if y < topSafe { y = last.maxY + 12 } // flip below the selection
        if y + size.height > visible.maxY - 8 { y = max(topSafe, min(first.minY - size.height - 12, visible.maxY - size.height - 8)) } // never off the bottom
        var x = first.midX - size.width / 2
        if first.width < 4 { x = first.minX - size.width / 2 }
        x = min(max(x, visible.minX + 10), visible.maxX - size.width - 10)
        setFrameOrigin(NSPoint(x: x.rounded(), y: y.rounded()))
    }

    // MARK: Drawing

    public override func updateLayer() { super.updateLayer() }

    func syncGlass() {
        if let sv = superview, glass.superview !== sv { sv.addSubview(glass, positioned: .below, relativeTo: self) }
        glass.frame = frame
        glass.isHidden = isHidden
        glass.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
    }
    public override func setFrameOrigin(_ p: NSPoint) { super.setFrameOrigin(p); glass.setFrameOrigin(p) }
    public override func setFrameSize(_ s: NSSize) { super.setFrameSize(s); glass.setFrameSize(s) }
    public override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        if superview == nil { glass.removeFromSuperview() } else { syncGlass() }
    }

    public override func draw(_ dirtyRect: NSRect) {
        // A light tint over the blur keeps icons readable over any page; a hairline and an inner
        // highlight give the glass its edge.
        let tint = dark ? NSColor(white: 0.12, alpha: 0.55) : NSColor(white: 1, alpha: 0.62)
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.borderColor = (dark ? NSColor(white: 1, alpha: 0.14) : NSColor(white: 0, alpha: 0.09)).cgColor
        layer?.shadowPath = CGPath(roundedRect: bounds, cornerWidth: Self.radius, cornerHeight: Self.radius, transform: nil)
        let fg = dark ? NSColor(white: 0.96, alpha: 1) : NSColor(white: 0.1, alpha: 1)
        let accent = NSColor(hex: controller.theme.accent)
        tint.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: Self.radius, yRadius: Self.radius).fill()
        let rim = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: Self.radius - 1, yRadius: Self.radius - 1)
        NSColor(white: 1, alpha: dark ? 0.08 : 0.55).setStroke(); rim.lineWidth = 1; rim.stroke()
        for (i, it) in items.enumerated() {
            let r = frames[i]
            if it.isSeparator {
                if it.id != "field" {
                    fg.withAlphaComponent(0.15).setFill()
                    NSBezierPath(rect: NSRect(x: r.midX - 0.5, y: r.minY + 8, width: 1, height: r.height - 16)).fill()
                } else {
                    fg.withAlphaComponent(0.06).setFill()
                    NSBezierPath(roundedRect: r.insetBy(dx: 0, dy: 3), xRadius: 8, yRadius: 8).fill()
                }
                continue
            }
            if it.isLabel {
                let a: [NSAttributedString.Key: Any] = [.font: Self.labelFont, .foregroundColor: fg.withAlphaComponent(0.55)]
                let t = (it.title ?? "").uppercased() as NSString
                let sz = t.size(withAttributes: a)
                t.draw(at: NSPoint(x: r.minX + 4, y: r.midY - sz.height / 2), withAttributes: a)
                continue
            }
            let hovered = hoverIndex == i && it.isEnabled
            if it.isActive || hovered {
                (it.isActive ? accent.withAlphaComponent(dark ? 0.35 : 0.16) : fg.withAlphaComponent(0.07)).setFill()
                NSBezierPath(roundedRect: r.insetBy(dx: 1, dy: 2), xRadius: 11, yRadius: 11).fill()
            }
            if keyboardIndex == i {
                accent.setStroke()
                let p = NSBezierPath(roundedRect: r.insetBy(dx: 1, dy: 2), xRadius: 11, yRadius: 11); p.lineWidth = 2; p.stroke()
            }
            let color = it.isEnabled ? (it.isActive ? (dark ? .white : accent) : fg) : fg.withAlphaComponent(0.3)
            if let t = it.title {
                // A chip with words: a quiet fill (it's a button), an optional icon or color dot, then
                // the label; effect chips show their own effect.
                if !it.isActive && !hovered && it.isEnabled {
                    fg.withAlphaComponent(dark ? 0.08 : 0.045).setFill()
                    NSBezierPath(roundedRect: r.insetBy(dx: 1, dy: 2), xRadius: 11, yRadius: 11).fill()
                }
                var x = r.minX + 10
                if let stops = it.gradient, let g = NSGradient(colors: stops.map { NSColor(hex: $0) }) {
                    let sw = NSRect(x: x, y: r.midY - 6, width: 24, height: 12)
                    g.draw(in: NSBezierPath(roundedRect: sw, xRadius: 6, yRadius: 6), angle: 0)
                    x += 30
                } else if let hex = it.swatch {
                    NSColor(hex: hex).setFill(); NSBezierPath(ovalIn: NSRect(x: x, y: r.midY - 6, width: 12, height: 12)).fill(); x += 18
                } else if let s = it.symbol, let img = NSImage(systemSymbolName: s, accessibilityDescription: nil),
                          let im = img.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 12, weight: .medium).applying(.init(paletteColors: [color]))) {
                    let sz = im.size
                    im.draw(in: NSRect(x: x + (14 - sz.width) / 2, y: r.midY - sz.height / 2, width: sz.width, height: sz.height), from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
                    x += 18
                }
                var a: [NSAttributedString.Key: Any] = [.font: Self.chipFont, .foregroundColor: color]
                var perChar: [NSColor]? = nil
                if it.id.hasPrefix("fx"), it.isEnabled, let kind = Optional(String(it.id.dropFirst(2))), TextEffects.kinds.contains(kind) {
                    var fgc = color
                    if kind == "spectrum" { perChar = Spectrum().colors(page: controller.theme.pageColor).map { NSColor(hex: $0) } }
                    else if kind == "gradient" { let c = TextEffects.colors(accent: controller.theme.accent, text: controller.theme.textColor, page: controller.theme.pageColor); perChar = [NSColor(hex: c.start), NSColor(hex: c.end)] }
                    else { Styler.applyEffect(kind, &a, &fgc, theme: controller.theme) }
                    a[.foregroundColor] = fgc
                }
                let s = NSMutableAttributedString(string: t, attributes: a)
                if let cs = perChar, s.length > 1 {
                    for i in 0..<s.length {
                        let f = CGFloat(i) / CGFloat(s.length - 1) * CGFloat(cs.count - 1)
                        let lo = cs[Int(f)], hi = cs[min(cs.count - 1, Int(f) + 1)]
                        s.addAttribute(.foregroundColor, value: lo.blended(withFraction: f - floor(f), of: hi) ?? lo, range: NSRange(location: i, length: 1))
                    }
                }
                let sz = s.size()
                s.draw(at: NSPoint(x: x, y: r.midY - sz.height / 2))
                continue
            }
            if it.symbol == nil, let hex = it.swatch {
                let d: CGFloat = 18
                let sr = NSRect(x: r.midX - d / 2, y: r.midY - d / 2, width: d, height: d)
                if it.swatchIsText {
                    NSColor(hex: hex).setFill(); NSBezierPath(ovalIn: sr).fill()
                } else {
                    NSColor(hex: hex).setFill()
                    let p = NSBezierPath(roundedRect: sr, xRadius: 5, yRadius: 5); p.fill()
                    fg.withAlphaComponent(0.12).setStroke(); p.lineWidth = 0.5; p.stroke()
                }
                if it.isActive {
                    fg.setStroke(); let p = NSBezierPath(roundedRect: sr.insetBy(dx: -3, dy: -3), xRadius: 7, yRadius: 7); p.lineWidth = 1.5; p.stroke()
                }
                continue
            }
            if let s = it.symbol, let img = NSImage(systemSymbolName: s, accessibilityDescription: it.label) {
                let cfg = NSImage.SymbolConfiguration(pointSize: it.id == "palette" ? 9 : 15.5, weight: it.id == "palette" ? .bold : .regular)
                    .applying(.init(paletteColors: [color]))
                if let im = img.withSymbolConfiguration(cfg) {
                    let sz = im.size
                    im.draw(in: NSRect(x: r.midX - sz.width / 2, y: r.midY - sz.height / 2, width: sz.width, height: sz.height), from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
                }
                if it.id == "highlight" {
                    NSColor(hex: it.swatch ?? "#fff3a3").setFill()
                    NSBezierPath(roundedRect: NSRect(x: r.midX - 7, y: r.maxY - 7, width: 14, height: 3), xRadius: 1.5, yRadius: 1.5).fill()
                }
            }
        }
    }

    // MARK: Probe (automation and tests)

    public var modeName: String { "\(mode)" }
    public var debugState: String { "suspended=\(suspended) dismissed=\(dismissedSelection.map { "\($0)" } ?? "nil") shouldShow=\(shouldShow) fr=\(String(describing: window?.firstResponder.map { Swift.type(of: $0) }))" }
    public var buttonLabels: [String] { items.filter { !$0.isSeparator && $0.action != nil }.map(\.label) }
    public var focusedLabel: String? { keyboardIndex.flatMap { items.indices.contains($0) ? items[$0].label : nil } }
    /// Window coordinates of the first control whose id starts with `prefix`.
    public func center(ofItem prefix: String) -> NSPoint? {
        guard let i = items.firstIndex(where: { $0.id.hasPrefix(prefix) }) else { return nil }
        return convert(NSPoint(x: frames[i].midX, y: frames[i].midY), to: nil)
    }

    // MARK: Mouse

    func index(at p: NSPoint) -> Int? { frames.firstIndex { $0.contains(p) } }

    public override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        guard let i = index(at: p), items[i].isEnabled, let a = items[i].action else { return }
        a()
    }
    public override func mouseMoved(with event: NSEvent) {
        let i = index(at: convert(event.locationInWindow, from: nil))
        if i != hoverIndex { hoverIndex = i; needsDisplay = true; toolTip = i.map { items[$0].label } }
    }
    public override func mouseExited(with event: NSEvent) { hoverIndex = nil; needsDisplay = true }

    // MARK: Keyboard

    public func focusForKeyboard() {
        keyboardIndex = items.firstIndex { !$0.isSeparator && $0.isEnabled }
        window?.makeFirstResponder(self)
        needsDisplay = true
    }

    public override func keyDown(with event: NSEvent) {
        guard var i = keyboardIndex else { return super.keyDown(with: event) }
        switch event.keyCode {
        case 48 where event.modifierFlags.contains(.shift), 123: // shift-tab, left
            repeat { i = (i - 1 + items.count) % items.count } while items[i].isSeparator || !items[i].isEnabled
        case 48, 124: // tab, right
            repeat { i = (i + 1) % items.count } while items[i].isSeparator || !items[i].isEnabled
        case 36, 49: // return, space
            items[i].action?()
            if mode == .link { return }
            keyboardIndex = min(i, items.count - 1)
            needsDisplay = true
            return
        case 53: // escape
            if mode != .main { setMode(.main); return }
            keyboardIndex = nil
            window?.makeFirstResponder(controller.textView)
            needsDisplay = true
            return
        default:
            return super.keyDown(with: event)
        }
        keyboardIndex = i
        needsDisplay = true
        NSAccessibility.post(element: self, notification: .focusedUIElementChanged)
    }

    public override func resignFirstResponder() -> Bool {
        keyboardIndex = nil
        needsDisplay = true
        return true
    }

    // MARK: Link

    public func openLink() {
        linkRange = controller.textView.selectedRange()
        linkField.stringValue = controller.value(of: .draftLink) ?? ""
        setMode(.link)
        window?.makeFirstResponder(linkField)
    }

    @objc func commitLink() {
        controller.setLink(linkField.stringValue, range: linkRange)
        mode = .main
        linkField.isHidden = true
        window?.makeFirstResponder(controller.textView)
        controller.textView.setSelectedRange(linkRange)
        update()
    }

    func removeLink() {
        controller.setLink(nil, range: linkRange)
        mode = .main
        window?.makeFirstResponder(controller.textView)
        update()
    }

    // MARK: Accessibility

    func rebuildAccessibility() {
        var children: [NSAccessibilityElement] = []
        for (i, it) in items.enumerated() where !it.isSeparator {
            let el = NSAccessibilityElement()
            el.setAccessibilityRole(it.isLabel ? .staticText : .button)
            el.setAccessibilityLabel(it.label)
            el.setAccessibilityParent(self)
            el.setAccessibilityEnabled(it.isEnabled)
            el.setAccessibilityFrameInParentSpace(frames[i])
            if it.isActive { el.setAccessibilityValue("on") }
            children.append(el)
        }
        setAccessibilityChildren(children)
    }
}

extension SelectionToolbar: NSTextFieldDelegate {
    public func control(_ control: NSControl, textView: NSTextView, doCommandBy sel: Selector) -> Bool {
        if sel == #selector(NSResponder.cancelOperation(_:)) {
            mode = .main
            linkField.isHidden = true
            window?.makeFirstResponder(controller.textView)
            controller.textView.setSelectedRange(linkRange)
            update()
            return true
        }
        return false
    }
}
