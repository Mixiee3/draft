import AppKit
import DraftCore

/// Original Draft color sets. Pastels are highlights; saturated ones are text colors.
public enum DraftPalette {
    public static let highlights: [(String, String)] = [
        ("Butter", "#fff3a3"), ("Lime", "#e3f7a8"), ("Mint", "#c6f1d6"), ("Sky", "#c9ecf7"), ("Cornflower", "#cfdcfb"),
        ("Lilac", "#e2d6fb"), ("Rose", "#fbd3e9"), ("Peach", "#ffd9c7"), ("Stone", "#e4e2dd"),
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
    public enum Mode { case main, palette, link }
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
    public private(set) var isVisible = false

    init(controller: EditorController) {
        self.controller = controller
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 20
        layer?.borderWidth = 0.5
        layer?.shadowOpacity = 0.22
        layer?.shadowRadius = 14
        layer?.shadowOffset = CGSize(width: 0, height: -4)
        layer?.masksToBounds = false
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
        switch mode {
        case .main:
            let hl = c.value(of: .draftHighlight)
            items = [
                Item(id: "highlight", label: "Highlight", symbol: "highlighter", swatch: hl, action: { [weak self] in
                    if let last = DraftPalette.highlights.first?.1 { self?.controller.setHighlight(self?.controller.value(of: .draftHighlight) != nil ? nil : (self?.controller.lastColor?.kind == "highlight" ? self?.controller.lastColor?.hex : last)) }
                }, isActive: hl != nil, isEnabled: !code),
                Item(id: "palette", label: "Colors", symbol: "chevron.down", width: 20, action: { [weak self] in self?.setMode(.palette) }, isEnabled: !code),
                Item(id: "sep1", label: "", symbol: nil, width: 9, isSeparator: true),
                Item(id: "bold", label: "Bold (⌘B)", symbol: "bold", action: { c.toggleMark(.bold) }, isActive: c.isMarkActive(.bold), isEnabled: !code),
                Item(id: "italic", label: "Italic (⌘I)", symbol: "italic", action: { c.toggleMark(.italic) }, isActive: c.isMarkActive(.italic), isEnabled: !code),
                Item(id: "underline", label: "Underline (⌘U)", symbol: "underline", action: { c.toggleMark(.underline) }, isActive: c.isMarkActive(.underline), isEnabled: !code),
                Item(id: "strike", label: "Strikethrough (⌘⇧X)", symbol: "strikethrough", action: { c.toggleMark(.strike) }, isActive: c.isMarkActive(.strike), isEnabled: !code),
                Item(id: "code", label: "Inline code (⌘E)", symbol: "chevron.left.forwardslash.chevron.right", action: { c.toggleMark(.code) }, isActive: c.isMarkActive(.code), isEnabled: !code),
                Item(id: "link", label: "Link (⌘K)", symbol: "link", action: { [weak self] in self?.openLink() }, isActive: c.value(of: .draftLink) != nil, isEnabled: !code),
                Item(id: "sep2", label: "", symbol: nil, width: 9, isSeparator: true),
                Item(id: "clear", label: "Clear formatting", symbol: "eraser", action: { c.clearFormatting() }, isEnabled: !code),
            ]
        case .palette:
            let current = c.value(of: .draftHighlight)
            let currentText = c.value(of: .draftTextColor)
            items = [Item(id: "none", label: "No color", symbol: "nosign", width: 30, action: { [weak self] in
                self?.controller.setHighlight(nil); self?.controller.setTextColor(nil); self?.setMode(.main)
            }, isActive: current == nil && currentText == nil)]
            for (name, hex) in DraftPalette.highlights {
                items.append(Item(id: "h" + hex, label: "Highlight \(name)", symbol: nil, swatch: hex, width: 26, action: { [weak self] in self?.controller.setHighlight(hex); self?.setMode(.main) }, isActive: current == hex))
            }
            items.append(Item(id: "sepp", label: "", symbol: nil, width: 9, isSeparator: true))
            for (name, hex) in DraftPalette.textColors {
                items.append(Item(id: "t" + hex, label: "Text \(name)", symbol: nil, swatch: hex, swatchIsText: true, width: 26, action: { [weak self] in self?.controller.setTextColor(hex); self?.setMode(.main) }, isActive: currentText == hex))
            }
        case .link:
            let has = c.value(of: .draftLink) != nil
            items = [Item(id: "linkicon", label: "Link", symbol: "link", width: 30, isEnabled: false)]
            items.append(Item(id: "field", label: "", symbol: nil, width: 250, isSeparator: true))
            if has { items.append(Item(id: "unlink", label: "Remove link", symbol: "link.badge.plus", width: 32, action: { [weak self] in self?.removeLink() })) }
            items.append(Item(id: "done", label: "Apply link", symbol: "return", width: 32, action: { [weak self] in self?.commitLink() }))
        }
        layoutItems()
    }

    func layoutItems() {
        var x: CGFloat = 6
        frames = items.map { it in
            let r = NSRect(x: x, y: 4, width: it.width, height: 32)
            x += it.width + (it.isSeparator ? 0 : 2)
            return r
        }
        let width = x + 4
        setFrameSize(NSSize(width: width, height: 40))
        if mode == .link, let i = items.firstIndex(where: { $0.id == "field" }) {
            linkField.frame = frames[i].insetBy(dx: 2, dy: 7)
        }
        rebuildAccessibility()
        needsDisplay = true
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
        guard sel.length > 0, controller.overlayHost != nil, !controller.isBlockMode else { return false }
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
        if !isVisible || mode != .main && (window?.firstResponder === controller.textView) && mode != .palette { mode = .main; linkField.isHidden = true }
        buildItems()
        position()
        if !isVisible {
            isVisible = true
            isHidden = false
            if !(controller.host == nil) && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                alphaValue = 0
                NSAnimationContext.runAnimationGroup { $0.duration = 0.12; animator().alphaValue = 1 }
            }
        }
    }

    func hide() {
        guard isVisible || !isHidden else { return }
        isVisible = false
        isHidden = true
        mode = .main
        keyboardIndex = nil
        linkField.isHidden = true
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
        var y = first.minY - size.height - 10
        if y < topSafe { y = last.maxY + 10 } // flip below the selection
        var x = first.midX - size.width / 2
        if first.width < 4 { x = first.minX - size.width / 2 }
        x = min(max(x, visible.minX + 10), visible.maxX - size.width - 10)
        setFrameOrigin(NSPoint(x: x.rounded(), y: y.rounded()))
    }

    // MARK: Drawing

    public override func updateLayer() { super.updateLayer() }

    public override func draw(_ dirtyRect: NSRect) {
        let bg = dark ? NSColor(white: 0.16, alpha: 0.96) : NSColor(white: 0.995, alpha: 0.95)
        layer?.backgroundColor = bg.cgColor
        layer?.borderColor = (dark ? NSColor(white: 1, alpha: 0.12) : NSColor(white: 0, alpha: 0.10)).cgColor
        layer?.shadowPath = CGPath(roundedRect: bounds, cornerWidth: 20, cornerHeight: 20, transform: nil)
        let fg = dark ? NSColor(white: 0.95, alpha: 1) : NSColor(white: 0.12, alpha: 1)
        let accent = NSColor(hex: controller.theme.accent)
        bg.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 20, yRadius: 20).fill()
        for (i, it) in items.enumerated() {
            let r = frames[i]
            if it.isSeparator {
                if it.id != "field" {
                    fg.withAlphaComponent(0.15).setFill()
                    NSBezierPath(rect: NSRect(x: r.midX - 0.5, y: r.minY + 7, width: 1, height: r.height - 14)).fill()
                } else {
                    fg.withAlphaComponent(0.06).setFill()
                    NSBezierPath(roundedRect: r.insetBy(dx: 0, dy: 3), xRadius: 8, yRadius: 8).fill()
                }
                continue
            }
            let hovered = hoverIndex == i && it.isEnabled
            if it.isActive || hovered {
                (it.isActive ? accent.withAlphaComponent(dark ? 0.35 : 0.16) : fg.withAlphaComponent(0.07)).setFill()
                NSBezierPath(roundedRect: r.insetBy(dx: 1, dy: 1), xRadius: 9, yRadius: 9).fill()
            }
            if keyboardIndex == i {
                accent.setStroke()
                let p = NSBezierPath(roundedRect: r.insetBy(dx: 1, dy: 1), xRadius: 9, yRadius: 9); p.lineWidth = 2; p.stroke()
            }
            let color = it.isEnabled ? (it.isActive ? (dark ? .white : accent) : fg) : fg.withAlphaComponent(0.3)
            if mode == .palette, let hex = it.swatch {
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
                let cfg = NSImage.SymbolConfiguration(pointSize: it.id == "palette" ? 9 : 14, weight: it.id == "palette" ? .bold : .medium)
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
        case 123: // left
            repeat { i = (i - 1 + items.count) % items.count } while items[i].isSeparator || !items[i].isEnabled
        case 124: // right
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
            el.setAccessibilityRole(.button)
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
