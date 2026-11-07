import AppKit
import DraftCore

/// The `/` insert menu: filterable with typed text, ↑/↓ to move, Return/Tab to choose,
/// Esc to dismiss (the typed text stays). Unavailable commands are listed with their version.
public final class SlashMenu: NSView {
    unowned let controller: EditorController
    public private(set) var isOpen = false
    var anchor = 0
    var query = ""
    var results: [EditorCommand] = []
    var index = 0
    let rowH: CGFloat = 30

    init(controller: EditorController) {
        self.controller = controller
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 14
        layer?.borderWidth = 0.5
        layer?.shadowOpacity = 0.2
        layer?.shadowRadius = 16
        layer?.masksToBounds = false
        setAccessibilityRole(.menu)
        setAccessibilityLabel("Insert block")
    }
    required init?(coder: NSCoder) { fatalError() }
    public override var isFlipped: Bool { true }

    func textChanged(typed: String?, at loc: Int) {
        let c = controller
        if !isOpen, typed == "/" {
            let pr = c.paragraphRange(at: loc)
            let b = c.block(at: pr)
            let before = loc > pr.location ? c.ns.character(at: loc - 1) : 32
            guard b.kind != .code, !b.kind.isAttachment, before == 32 || loc == pr.location else { return }
            anchor = loc
            open()
        }
        guard isOpen else { return }
        let caret = c.textView.selectedRange().location
        guard caret > anchor, caret <= c.storage.length, c.ns.character(at: anchor) == 47 else { close(); return }
        query = c.ns.substring(with: NSRange(location: anchor + 1, length: caret - anchor - 1))
        if query.contains("\n") || query.count > 24 || query.hasPrefix(" ") { close(); return }
        refresh()
    }

    func selectionChanged() {
        guard isOpen else { return }
        let caret = controller.textView.selectedRange()
        // Text changes re-validate the query; here we only close when the caret leaves it.
        if caret.length > 0 || caret.location <= anchor || controller.paragraphRange(at: caret.location).location != controller.paragraphRange(at: anchor).location { close() }
    }

    func open() {
        isOpen = true
        query = ""
        index = 0
        controller.overlayHost?.addSubview(self)
        refresh()
    }

    public func close() {
        isOpen = false
        removeFromSuperview()
    }

    func refresh() {
        results = EditorCommands.slashCommands.filter { $0.matches(query) }
        if results.isEmpty && query.count > 2 { close(); return }
        index = min(index, max(0, results.count - 1))
        if let i = results.indices.first(where: { results[$0].plannedFor == nil }), results[index].plannedFor != nil { index = i }
        position()
        needsDisplay = true
    }

    func position() {
        guard let host = controller.overlayHost else { return }
        let tv = controller.textView
        let gr = controller.layout.glyphRange(forCharacterRange: NSRange(location: anchor, length: 1), actualCharacterRange: nil)
        var r = controller.layout.boundingRect(forGlyphRange: gr, in: controller.container)
        r = tv.convert(r.offsetBy(dx: tv.textContainerOrigin.x, dy: tv.textContainerOrigin.y), to: host)
        // Open below the caret, or above when there is more room; shrink (the list scrolls) so the
        // menu always stays inside the visible area, including in short windows.
        let vis = host.visibleRect
        let want = min(CGFloat(results.count) * rowH + 12, 320)
        let below = vis.maxY - 8 - (r.maxY + 6)
        let above = (r.minY - 6) - (vis.minY + 8)
        let useBelow = below >= want || below >= above
        let h = max(min(want, useBelow ? below : above), min(want, rowH * 2 + 12))
        var y = useBelow ? r.maxY + 6 : r.minY - 6 - h
        y = min(max(y, vis.minY + 8), max(vis.minY + 8, vis.maxY - 8 - h))
        let x = min(max(r.minX - 8, vis.minX + 8), vis.maxX - 264 - 8)
        frame = NSRect(x: x, y: y, width: 264, height: h)
        scrollOffset = min(scrollOffset, max(0, CGFloat(results.count) * rowH + 12 - h))
    }

    func move(_ d: Int) {
        guard !results.isEmpty else { return }
        var i = index
        for _ in 0..<results.count {
            i = (i + d + results.count) % results.count
            if results[i].plannedFor == nil { break }
        }
        index = i
        needsDisplay = true
        scrollToIndex()
    }

    func scrollToIndex() {
        // Keep the highlighted row visible when the list is taller than the menu.
        let top = CGFloat(index) * rowH + 6
        if top + rowH > bounds.height + scrollOffset { scrollOffset = top + rowH - bounds.height + 6 }
        if top < scrollOffset { scrollOffset = max(0, top - 6) }
        needsDisplay = true
    }
    var scrollOffset: CGFloat = 0

    func choose() {
        guard results.indices.contains(index) else { close(); return }
        let cmd = results[index]
        guard cmd.plannedFor == nil else { NSSound.beep(); return }
        let c = controller
        let caret = c.textView.selectedRange().location
        close()
        c.replace(NSRange(location: anchor, length: caret - anchor), with: NSAttributedString(), select: NSRange(location: anchor, length: 0))
        cmd.run(c)
    }

    public override func scrollWheel(with event: NSEvent) {
        scrollOffset = min(max(0, scrollOffset - event.scrollingDeltaY), max(0, CGFloat(results.count) * rowH + 12 - bounds.height))
        needsDisplay = true
    }

    public override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        let i = Int((p.y + scrollOffset - 6) / rowH)
        if results.indices.contains(i) { index = i; choose() }
    }

    public override func draw(_ dirtyRect: NSRect) {
        let dark = controller.theme.isDarkPage
        layer?.backgroundColor = (dark ? NSColor(white: 0.16, alpha: 0.97) : NSColor(white: 0.995, alpha: 0.97)).cgColor
        layer?.borderColor = NSColor(white: dark ? 1 : 0, alpha: 0.1).cgColor
        let fg = dark ? NSColor(white: 0.94, alpha: 1) : NSColor(white: 0.13, alpha: 1)
        let accent = NSColor(hex: controller.theme.accent)
        (dark ? NSColor(white: 0.16, alpha: 1) : NSColor(white: 0.995, alpha: 1)).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 14, yRadius: 14).fill()
        layer?.shadowPath = CGPath(roundedRect: bounds, cornerWidth: 14, cornerHeight: 14, transform: nil)
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: bounds).addClip()
        for (i, cmd) in results.enumerated() {
            let r = NSRect(x: 6, y: 6 + CGFloat(i) * rowH - scrollOffset, width: bounds.width - 12, height: rowH)
            guard r.maxY > 0, r.minY < bounds.height else { continue }
            let disabled = cmd.plannedFor != nil
            if i == index && !disabled {
                accent.withAlphaComponent(dark ? 0.4 : 0.14).setFill()
                NSBezierPath(roundedRect: r, xRadius: 8, yRadius: 8).fill()
            }
            let color = disabled ? fg.withAlphaComponent(0.35) : fg
            if let img = NSImage(systemSymbolName: cmd.symbol, accessibilityDescription: nil)?.withSymbolConfiguration(.init(pointSize: 13, weight: .regular).applying(.init(paletteColors: [color]))) {
                img.draw(in: NSRect(x: r.minX + 8 + (18 - img.size.width) / 2, y: r.midY - img.size.height / 2, width: img.size.width, height: img.size.height), from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
            }
            (cmd.title as NSString).draw(at: NSPoint(x: r.minX + 36, y: r.minY + 7), withAttributes: [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: color])
            let right = cmd.plannedFor.map { "Planned \($0)" } ?? cmd.shortcut
            if let right {
                let a: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: fg.withAlphaComponent(0.4)]
                let w = (right as NSString).size(withAttributes: a).width
                (right as NSString).draw(at: NSPoint(x: r.maxX - w - 8, y: r.minY + 8), withAttributes: a)
            }
        }
        NSGraphicsContext.restoreGraphicsState()
    }
}
