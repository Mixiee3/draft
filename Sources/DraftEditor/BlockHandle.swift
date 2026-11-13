import AppKit
import DraftCore

/// The ⋮⋮ gutter handle shown beside the hovered block. Click selects the block; dragging
/// shows an insertion line and moves the selected blocks there on release.
final class BlockHandleView: NSView {
    weak var owner: DocumentEditorView?
    var blockIndex = 0
    private var dragStart: NSPoint?
    private var dragging = false
    private var dropBoundary: Int?
    let indicator = NSView()

    override init(frame: NSRect) {
        super.init(frame: frame)
        isHidden = true
        indicator.wantsLayer = true
        indicator.layer?.cornerRadius = 1.5
        indicator.isHidden = true
        setAccessibilityRole(.button)
        setAccessibilityLabel(loc("Block handle: click to select, drag to move"))
        toolTip = loc("Click to select · drag to move")
    }
    required init?(coder: NSCoder) { fatalError() }
    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        guard let t = owner?.controller.theme else { return }
        t.text.withAlphaComponent(dragging ? 0.6 : 0.32).setFill()
        for row in 0..<3 { for col in 0..<2 {
            NSBezierPath(ovalIn: NSRect(x: 5 + CGFloat(col) * 6, y: 5 + CGFloat(row) * 6, width: 3.2, height: 3.2)).fill()
        } }
    }

    override func resetCursorRects() { addCursorRect(bounds, cursor: .openHand) }

    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.control) { showMenu(event); return }
        guard let c = owner?.controller else { return }
        dragStart = event.locationInWindow
        let flat = c.flatBlocks()
        guard flat.indices.contains(blockIndex) else { return }
        // Keep an existing multi-block selection when the handle belongs to it.
        if !c.blockSelectionIds.contains(flat[blockIndex].info.id) { c.selectBlocks(ids: [flat[blockIndex].info.id]) }
        window?.makeFirstResponder(c.textView)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let o = owner, let s = dragStart else { return }
        if !dragging && hypot(event.locationInWindow.x - s.x, event.locationInWindow.y - s.y) < 3 { return }
        dragging = true
        NSCursor.closedHand.set()
        o.controller.textView.autoscroll(with: event)
        let p = o.controller.textView.convert(event.locationInWindow, from: nil)
        if let (boundary, y) = o.boundary(atTextViewY: p.y) {
            dropBoundary = boundary
            let tv = o.controller.textView
            let lineY = tv.convert(NSPoint(x: 0, y: y), to: o.paper).y
            indicator.layer?.backgroundColor = o.controller.theme.accentColor.cgColor
            indicator.frame = NSRect(x: tv.frame.minX - 4, y: lineY - 1.5, width: tv.frame.width + 8, height: 3)
            indicator.isHidden = false
        }
        needsDisplay = true
    }

    override func rightMouseDown(with event: NSEvent) { showMenu(event) }
    override func menu(for event: NSEvent) -> NSMenu? { selectForMenu(); return owner?.controller.blockMenu() }

    func selectForMenu() {
        guard let c = owner?.controller else { return }
        let flat = c.flatBlocks()
        guard flat.indices.contains(blockIndex) else { return }
        if !c.blockSelectionIds.contains(flat[blockIndex].info.id) { c.selectBlocks(ids: [flat[blockIndex].info.id]) }
        window?.makeFirstResponder(c.textView)
    }

    func showMenu(_ event: NSEvent) {
        selectForMenu()
        guard let menu = owner?.controller.blockMenu() else { return }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    override func mouseUp(with event: NSEvent) {
        defer { dragging = false; dragStart = nil; dropBoundary = nil; indicator.isHidden = true; needsDisplay = true }
        guard dragging, let o = owner, let b = dropBoundary else { return }
        o.controller.moveBlocks(o.controller.selectedBlockRange, to: b)
    }
}

extension DocumentEditorView {
    /// Show the handle next to the block under `p` (paper coordinates).
    public func updateHandle(at p: NSPoint) {
        let tv = controller.textView
        guard !handle.isDragging else { return }
        let local = tv.convert(p, from: paper)
        guard local.y >= 0, local.y <= tv.bounds.height, local.x >= -60, local.x <= tv.bounds.width + 10, controller.storage.length > 0 else { handle.isHidden = true; return }
        let cp = NSPoint(x: max(0, local.x), y: local.y - tv.textContainerOrigin.y)
        let idx = controller.layout.characterIndex(for: cp, in: controller.container, fractionOfDistanceBetweenInsertionPoints: nil)
        let pr = controller.paragraphRange(at: idx)
        guard let rect = controller.layout.paragraphRect(pr) ?? controller.layout.firstLineRect(pr)?.rect else { handle.isHidden = true; return }
        let line = controller.layout.firstLineRect(pr)?.rect ?? rect
        handle.blockIndex = controller.blockIndex(at: pr.location)
        let y = tv.convert(NSPoint(x: 0, y: line.minY + tv.textContainerOrigin.y), to: paper).y
        handle.frame = NSRect(x: tv.frame.minX - 30, y: y + max(0, (min(line.height, 34) - 24) / 2), width: 18, height: 24)
        handle.isHidden = false
    }

    /// Nearest block boundary for a drop at text-view y: (boundary index, line y in text view).
    func boundary(atTextViewY y: CGFloat) -> (Int, CGFloat)? {
        let c = controller
        let flatCount = c.flatBlocks().count
        var loc = 0, i = 0
        var best: (Int, CGFloat)? = nil
        let origin = c.textView.textContainerOrigin.y
        while i < flatCount {
            let pr = c.paragraphRange(at: loc)
            guard let r = c.layout.paragraphRect(pr) else { break }
            let top = r.minY + origin, bottom = r.maxY + origin
            if y < (top + bottom) / 2 { return (i, top) }
            best = (i + 1, bottom)
            if pr.length == 0 { break }
            loc = NSMaxRange(pr); i += 1
            if loc >= c.storage.length && c.ns.character(at: c.storage.length - 1) != 10 { break }
        }
        return best
    }
}

extension BlockHandleView { var isDragging: Bool { dragging } }
