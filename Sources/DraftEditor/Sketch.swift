import AppKit
import DraftCore

// MARK: - Model

/// A sketch is an `image` node that also carries its strokes as vectors in `attrs.sketch`.
/// The image asset is a rendered PNG, so exports, search and vault checks treat it like any image,
/// while the editor draws the vectors: sharp at any size, ink that follows light and dark.
struct Sketch: Equatable {
    struct Stroke: Equatable {
        var tool: String          // pen | marker | highlighter
        var color: String         // "ink" (follows the page's text colour) or #rrggbb
        var width: Double
        var points: [Double]      // x, y, pressure triples in canvas units
    }
    var width: Double = 800
    var height: Double = 500
    var strokes: [Stroke] = []

    init(width: Double = 800, height: Double = 500, strokes: [Stroke] = []) {
        self.width = width; self.height = height; self.strokes = strokes
    }

    init?(_ v: JSONValue?) {
        guard let o = v?.object else { return nil }
        width = o["w"]?.double ?? 800
        height = o["h"]?.double ?? 500
        strokes = (o["strokes"]?.items ?? []).compactMap { s in
            guard let so = s.object, let pts = so["p"]?.items?.compactMap(\.double), pts.count >= 3 else { return nil }
            return Stroke(tool: so["t"]?.string ?? "pen", color: so["c"]?.string ?? "ink", width: so["s"]?.double ?? 3, points: pts)
        }
    }

    var json: JSONValue {
        .object(["w": .number(width), "h": .number(height), "strokes": .array(strokes.map { s in
            // One decimal is plenty at canvas scale and keeps notes small.
            .object(["t": .string(s.tool), "c": .string(s.color), "s": .number(s.width), "p": .array(s.points.map { .number(($0 * 10).rounded() / 10) })])
        })])
    }
}

// MARK: - Drawing

enum SketchRenderer {
    /// Draws `sketch` scaled into `rect` (a flipped context: y grows downward).
    static func draw(_ sketch: Sketch, in rect: NSRect, ink: NSColor, extra: Sketch.Stroke? = nil) {
        let sx = rect.width / sketch.width, sy = rect.height / sketch.height
        let scale = min(sx, sy)
        for s in sketch.strokes + (extra.map { [$0] } ?? []) {
            let base = s.color == "ink" ? ink : NSColor(hex: s.color)
            let (alpha, factor, cap): (CGFloat, CGFloat, NSBezierPath.LineCapStyle) =
                s.tool == "highlighter" ? (0.35, 4, .square) : s.tool == "marker" ? (0.9, 2.2, .round) : (1, 1, .round)
            base.withAlphaComponent(alpha).setStroke()
            let p = s.points
            let n = p.count / 3
            func pt(_ i: Int) -> NSPoint { NSPoint(x: rect.minX + p[i * 3] * sx, y: rect.minY + p[i * 3 + 1] * sy) }
            func w(_ i: Int) -> CGFloat { max(0.6, CGFloat(s.width) * factor * scale * (s.tool == "pen" ? CGFloat(0.45 + 0.9 * p[i * 3 + 2]) : 1)) }
            if n == 1 {
                let c = pt(0), r = w(0) / 2
                base.withAlphaComponent(alpha).setFill()
                NSBezierPath(ovalIn: NSRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)).fill()
                continue
            }
            if s.tool != "pen" {
                // Even width: one smooth path, so translucent ink doesn't darken where segments overlap.
                let path = NSBezierPath(); path.lineCapStyle = cap; path.lineJoinStyle = .round; path.lineWidth = w(0)
                path.move(to: pt(0))
                for i in 1..<n { let a = pt(i - 1), b = pt(i); path.curve(to: NSPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2), controlPoint1: a, controlPoint2: a) }
                path.line(to: pt(n - 1)); path.stroke()
                continue
            }
            // Pen: width follows pressure, drawn as short smoothed segments.
            for i in 1..<n {
                let a = pt(i - 1), b = pt(i)
                let seg = NSBezierPath(); seg.lineCapStyle = .round; seg.lineWidth = (w(i - 1) + w(i)) / 2
                seg.move(to: a); seg.line(to: b); seg.stroke()
            }
        }
    }

    /// A PNG of the sketch for exports and other apps: dark ink on a transparent background, 2×.
    static func png(_ sketch: Sketch) -> Data? {
        let size = NSSize(width: sketch.width, height: sketch.height)
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * 2), pixelsHigh: Int(size.height * 2), bitsPerSample: 8,
                                         samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        rep.size = size
        NSGraphicsContext.saveGraphicsState()
        guard let ctx = NSGraphicsContext(bitmapImageRep: rep) else { NSGraphicsContext.restoreGraphicsState(); return nil }
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx.cgContext, flipped: true)
        let t = NSAffineTransform(); t.translateX(by: 0, yBy: size.height); t.scaleX(by: 1, yBy: -1); t.concat()
        draw(sketch, in: NSRect(origin: .zero, size: size), ink: NSColor(white: 0.11, alpha: 1))
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])
    }
}

// MARK: - Canvas

/// The drawing surface. Mouse, pen tablets and Force Touch clicks draw directly; in trackpad mode
/// the trackpad's surface maps onto the canvas (touch to aim, press to draw) like a small tablet.
final class SketchCanvas: NSView {
    var sketch = Sketch()
    var tool = "pen"
    var color = "ink"
    var width: Double = 3
    var ink: NSColor = .black
    var page: NSColor = .white
    var onChange: (() -> Void)?
    private var current: Sketch.Stroke?
    private var undone: [Sketch.Stroke] = []
    private var history: [[Sketch.Stroke]] = []
    private var pressure: Double = 0.5
    /// Trackpad mode state: where the finger is (canvas units) and whether the trackpad is pressed.
    private(set) var trackpadMode = false
    private var aim: NSPoint?
    var onTrackpadModeChange: ((Bool) -> Void)?

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// The sketch's drawing area, letterboxed to the canvas aspect.
    var drawRect: NSRect {
        let s = min(bounds.width / sketch.width, bounds.height / sketch.height)
        let w = sketch.width * s, h = sketch.height * s
        return NSRect(x: (bounds.width - w) / 2, y: (bounds.height - h) / 2, width: w, height: h)
    }

    override func draw(_ dirtyRect: NSRect) {
        let r = drawRect
        page.setFill(); NSBezierPath(roundedRect: r, xRadius: 14, yRadius: 14).fill()
        // A hairline edge so the page shows even when it matches the sheet (dark pages).
        let edge = NSBezierPath(roundedRect: r.insetBy(dx: 0.5, dy: 0.5), xRadius: 14, yRadius: 14)
        edge.lineWidth = 1; ink.withAlphaComponent(0.18).setStroke(); edge.stroke()
        if trackpadMode {
            // The trackpad's outline: the whole surface maps to this rectangle.
            let ring = NSBezierPath(roundedRect: r.insetBy(dx: 1.5, dy: 1.5), xRadius: 13, yRadius: 13)
            ring.lineWidth = 2; ring.setLineDash([6, 5], count: 2, phase: 0)
            NSColor.controlAccentColor.withAlphaComponent(0.7).setStroke(); ring.stroke()
        }
        SketchRenderer.draw(sketch, in: r, ink: ink, extra: current)
        if trackpadMode, let a = aim {
            let p = point(fromCanvas: a), rad = max(3, width * 1.2)
            NSColor.controlAccentColor.withAlphaComponent(0.8).setStroke()
            let dot = NSBezierPath(ovalIn: NSRect(x: p.x - rad, y: p.y - rad, width: rad * 2, height: rad * 2)); dot.lineWidth = 1.5; dot.stroke()
        }
    }

    private func toCanvas(_ p: NSPoint) -> NSPoint {
        let r = drawRect
        return NSPoint(x: (p.x - r.minX) / r.width * sketch.width, y: (p.y - r.minY) / r.height * sketch.height)
    }
    private func point(fromCanvas c: NSPoint) -> NSPoint {
        let r = drawRect
        return NSPoint(x: r.minX + c.x / sketch.width * r.width, y: r.minY + c.y / sketch.height * r.height)
    }

    // Strokes

    private func begin(at c: NSPoint) {
        if tool == "eraser" { erase(at: c); return }
        current = Sketch.Stroke(tool: tool, color: color, width: width, points: [c.x, c.y, pressure])
        needsDisplay = true
    }
    private func extend(to c: NSPoint) {
        if tool == "eraser" { erase(at: c); return }
        guard var s = current else { return }
        let n = s.points.count
        if n >= 3, hypot(c.x - s.points[n - 3], c.y - s.points[n - 2]) < 0.8 { return } // drop jitter
        s.points += [c.x, c.y, pressure]
        current = s
        needsDisplay = true
    }
    private func end() {
        guard let s = current else { return }
        current = nil
        history.append(sketch.strokes)
        sketch.strokes.append(s)
        undone = []
        needsDisplay = true
        onChange?()
    }
    private func erase(at c: NSPoint) {
        let radius = max(8, width * 2.5)
        // Distance to each segment, not just the recorded points: a fast stroke has few points.
        func near(_ s: Sketch.Stroke) -> Bool {
            let p = s.points, n = p.count / 3
            if n == 1 { return hypot(p[0] - c.x, p[1] - c.y) < radius }
            for i in 1..<n {
                let ax = p[(i - 1) * 3], ay = p[(i - 1) * 3 + 1], bx = p[i * 3], by = p[i * 3 + 1]
                let dx = bx - ax, dy = by - ay, len2 = dx * dx + dy * dy
                let t = len2 > 0 ? min(1, max(0, ((c.x - ax) * dx + (c.y - ay) * dy) / len2)) : 0
                if hypot(ax + t * dx - c.x, ay + t * dy - c.y) < radius { return true }
            }
            return false
        }
        let keep = sketch.strokes.filter { !near($0) }
        guard keep.count != sketch.strokes.count else { return }
        history.append(sketch.strokes)
        sketch.strokes = keep
        needsDisplay = true
        onChange?()
    }

    func undo() { guard let prev = history.popLast() else { return }; undone = sketch.strokes; sketch.strokes = prev; needsDisplay = true; onChange?() }
    func redo() { guard !undone.isEmpty else { return }; history.append(sketch.strokes); sketch.strokes = undone; undone = []; needsDisplay = true; onChange?() }
    func clear() { guard !sketch.strokes.isEmpty else { return }; history.append(sketch.strokes); sketch.strokes = []; needsDisplay = true; onChange?() }
    var canUndo: Bool { !history.isEmpty }

    // Mouse, pen tablet and Force Touch

    override func mouseDown(with e: NSEvent) {
        window?.makeFirstResponder(self)
        if trackpadMode { if let a = aim { pressure = 0.5; begin(at: a) }; return }
        pressure = e.pressure > 0 ? Double(e.pressure) : 0.5
        begin(at: toCanvas(convert(e.locationInWindow, from: nil)))
    }
    override func mouseDragged(with e: NSEvent) {
        if trackpadMode { return } // the finger position comes from touches
        if e.pressure > 0 { pressure = Double(e.pressure) }
        extend(to: toCanvas(convert(e.locationInWindow, from: nil)))
    }
    override func mouseUp(with e: NSEvent) { end() }
    override func pressureChange(with e: NSEvent) {
        // Force Touch: pressing harder draws a thicker line (pressure 0…1 within the click; stage 2 adds more).
        pressure = min(1, Double(e.pressure) * 0.8 + (e.stage >= 2 ? 0.25 : 0))
    }

    // Trackpad as a tablet

    func setTrackpadMode(_ on: Bool) {
        guard on != trackpadMode else { return }
        trackpadMode = on
        allowedTouchTypes = on ? [.indirect] : []
        wantsRestingTouches = on
        if on {
            NSCursor.hide()
            CGAssociateMouseAndMouseCursorPosition(0) // the pointer stays put; the finger's position is read directly
            window?.makeFirstResponder(self)
        } else {
            CGAssociateMouseAndMouseCursorPosition(1)
            NSCursor.unhide()
            if current != nil { end() }
            aim = nil
        }
        needsDisplay = true
        onTrackpadModeChange?(on)
        NSAccessibility.post(element: self, notification: .announcementRequested, userInfo: [.announcement: on ? loc("Trackpad drawing on. Touch to aim, press to draw. Escape to stop.") : loc("Trackpad drawing off."), .priority: NSAccessibilityPriorityLevel.high.rawValue])
    }

    private func handleTouches(_ e: NSEvent) {
        guard trackpadMode else { return }
        let touches = e.touches(matching: .touching, in: self)
        guard touches.count == 1, let t = touches.first else {
            // Two or more fingers: never draw (resting palm, scrolling gesture).
            if current != nil { end() }
            aim = nil; needsDisplay = true
            return
        }
        let np = t.normalizedPosition // origin at the trackpad's bottom-left
        let c = NSPoint(x: np.x * sketch.width, y: (1 - np.y) * sketch.height)
        aim = c
        if NSEvent.pressedMouseButtons & 1 != 0 {
            if current == nil { begin(at: c) } else { extend(to: c) }
        } else if current != nil {
            end()
        }
        needsDisplay = true
    }
    override func touchesBegan(with e: NSEvent) { handleTouches(e) }
    override func touchesMoved(with e: NSEvent) { handleTouches(e) }
    override func touchesEnded(with e: NSEvent) { handleTouches(e) }
    override func touchesCancelled(with e: NSEvent) { if current != nil { end() }; aim = nil; needsDisplay = true }

    override func keyDown(with e: NSEvent) {
        if e.keyCode == 53, trackpadMode { setTrackpadMode(false); return } // Esc leaves trackpad mode first
        super.keyDown(with: e)
    }
    override func viewWillMove(toWindow w: NSWindow?) {
        if w == nil { setTrackpadMode(false) } // never leave the pointer detached
        super.viewWillMove(toWindow: w)
    }
}

// MARK: - Editor sheet

/// The sketch editor: a sheet over the note with tools on a glass bar, the canvas, Cancel and Done.
final class SketchEditor: NSObject, NSWindowDelegate {
    private let panel: NSPanel
    let canvas = SketchCanvas()
    private let tools = NSSegmentedControl()
    private let colors = NSSegmentedControl()
    private let trackpadButton = NSButton()
    private var completion: ((Sketch?) -> Void)?
    private static let palette: [(String, String, NSColor?)] = [("ink", "Ink", nil), ("#e5484d", "Red", nil), ("#3e63dd", "Blue", nil), ("#30a46c", "Green", nil), ("#f5a524", "Yellow", nil), ("#8e4ec6", "Purple", nil)]

    init(sketch: Sketch, theme: EditorTheme) {
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 900, height: 660), styleMask: [.titled, .resizable, .docModalWindow], backing: .buffered, defer: false)
        super.init()
        panel.title = loc("Sketch")
        panel.minSize = NSSize(width: 620, height: 460)
        panel.delegate = self
        canvas.sketch = sketch
        canvas.ink = theme.text
        canvas.page = NSColor(hex: theme.pageColor)
        canvas.setAccessibilityLabel(loc("Sketch canvas"))
        canvas.setAccessibilityRole(.image)
        canvas.onChange = { [weak self] in self?.panel.isDocumentEdited = true }
        canvas.onTrackpadModeChange = { [weak self] on in self?.trackpadButton.state = on ? .on : .off }

        tools.segmentCount = 4
        for (i, (sym, label)) in [("pencil.tip", "Pen"), ("highlighter", "Marker"), ("paintbrush.pointed", "Highlighter"), ("eraser", "Eraser")].enumerated() {
            tools.setImage(NSImage(systemSymbolName: sym, accessibilityDescription: loc(label)), forSegment: i)
            tools.setToolTip(loc(label), forSegment: i)
            tools.setWidth(40, forSegment: i)
        }
        tools.trackingMode = .selectOne
        tools.selectedSegment = 0
        tools.target = self; tools.action = #selector(toolChanged)
        tools.setAccessibilityLabel(loc("Drawing tool"))

        colors.segmentCount = Self.palette.count
        for (i, (hex, label, _)) in Self.palette.enumerated() {
            colors.setImage(Self.swatch(hex == "ink" ? theme.text : NSColor(hex: hex), ring: hex == "ink"), forSegment: i)
            colors.setToolTip(loc(label), forSegment: i)
            colors.setWidth(30, forSegment: i)
        }
        colors.trackingMode = .selectOne
        colors.selectedSegment = 0
        colors.target = self; colors.action = #selector(colorChanged)
        colors.setAccessibilityLabel(loc("Ink colour"))

        let size = NSSlider(value: 3, minValue: 1, maxValue: 12, target: self, action: #selector(sizeChanged(_:)))
        size.widthAnchor.constraint(equalToConstant: 110).isActive = true
        size.setAccessibilityLabel(loc("Line width"))

        trackpadButton.setButtonType(.pushOnPushOff)
        trackpadButton.bezelStyle = .push
        trackpadButton.image = NSImage(systemSymbolName: "rectangle.and.hand.point.up.left", accessibilityDescription: nil)
        trackpadButton.title = loc("Draw on Trackpad")
        trackpadButton.imagePosition = .imageLeading
        trackpadButton.target = self; trackpadButton.action = #selector(toggleTrackpad)
        trackpadButton.toolTip = loc("Use the trackpad like a tablet: touch to aim, press to draw. Esc to stop.")

        func button(_ title: String, _ sym: String?, _ sel: Selector, key: String = "", mods: NSEvent.ModifierFlags = .command) -> NSButton {
            let b = NSButton(title: loc(title), target: self, action: sel)
            if let sym { b.image = NSImage(systemSymbolName: sym, accessibilityDescription: loc(title)); b.imagePosition = .imageOnly; b.toolTip = loc(title) }
            b.bezelStyle = .push
            b.keyEquivalent = key; b.keyEquivalentModifierMask = mods
            b.setAccessibilityLabel(loc(title))
            return b
        }
        let undo = button("Undo", "arrow.uturn.backward", #selector(undoStroke), key: "z")
        let redo = button("Redo", "arrow.uturn.forward", #selector(redoStroke), key: "z", mods: [.command, .shift])
        let clear = button("Clear", "trash", #selector(clearAll))
        let cancel = button("Cancel", nil, #selector(cancel), key: "\u{1b}", mods: [])
        let done = button("Done", nil, #selector(done), key: "\r", mods: .command)
        done.bezelColor = .controlAccentColor

        let bar = NSStackView(views: [tools, colors, size, trackpadButton, NSView(), undo, redo, clear])
        bar.spacing = 10
        bar.edgeInsets = NSEdgeInsets(top: 8, left: 12, bottom: 8, right: 12)
        let glassBar: NSView
        if #available(macOS 26.0, *) {
            let g = NSGlassEffectView(); g.cornerRadius = 22; g.contentView = bar; glassBar = g
        } else {
            let v = NSVisualEffectView(); v.material = .headerView; v.addSubview(bar); glassBar = v
            bar.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([bar.leadingAnchor.constraint(equalTo: v.leadingAnchor), bar.trailingAnchor.constraint(equalTo: v.trailingAnchor), bar.topAnchor.constraint(equalTo: v.topAnchor), bar.bottomAnchor.constraint(equalTo: v.bottomAnchor)])
        }
        let footer = NSStackView(views: [NSView(), cancel, done])
        let root = NSView()
        for v in [glassBar, canvas, footer] { v.translatesAutoresizingMaskIntoConstraints = false; root.addSubview(v) }
        NSLayoutConstraint.activate([
            glassBar.topAnchor.constraint(equalTo: root.topAnchor, constant: 12),
            glassBar.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 14),
            glassBar.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -14),
            canvas.topAnchor.constraint(equalTo: glassBar.bottomAnchor, constant: 12),
            canvas.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 14),
            canvas.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -14),
            footer.topAnchor.constraint(equalTo: canvas.bottomAnchor, constant: 12),
            footer.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 14),
            footer.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -14),
            footer.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -12),
        ])
        panel.contentView = root
    }

    private static func swatch(_ c: NSColor, ring: Bool) -> NSImage {
        NSImage(size: NSSize(width: 16, height: 16), flipped: false) { r in
            c.setFill(); NSBezierPath(ovalIn: r.insetBy(dx: 2, dy: 2)).fill()
            if ring { NSColor.separatorColor.setStroke(); let p = NSBezierPath(ovalIn: r.insetBy(dx: 1.5, dy: 1.5)); p.lineWidth = 1; p.stroke() }
            return true
        }
    }

    func present(over window: NSWindow, completion: @escaping (Sketch?) -> Void) {
        self.completion = completion
        window.beginSheet(panel)
        panel.makeFirstResponder(canvas)
    }
    private func finish(_ result: Sketch?) {
        canvas.setTrackpadMode(false)
        panel.sheetParent?.endSheet(panel)
        completion?(result)
        completion = nil
    }

    @objc private func toolChanged() { canvas.tool = ["pen", "marker", "highlighter", "eraser"][max(0, tools.selectedSegment)] }
    @objc private func colorChanged() { canvas.color = Self.palette[max(0, colors.selectedSegment)].0 }
    @objc private func sizeChanged(_ s: NSSlider) { canvas.width = s.doubleValue }
    @objc private func toggleTrackpad() { canvas.setTrackpadMode(!canvas.trackpadMode) }
    @objc private func undoStroke() { canvas.undo() }
    @objc private func redoStroke() { canvas.redo() }
    @objc private func clearAll() { canvas.clear() }
    @objc private func cancel() {
        if canvas.trackpadMode { canvas.setTrackpadMode(false); return } // Esc leaves trackpad mode before closing
        finish(nil)
    }
    @objc private func done() { finish(canvas.sketch) }
    func windowDidResignKey(_ notification: Notification) { canvas.setTrackpadMode(false) }
}

// MARK: - Editor integration

extension EditorController {
    /// Insert a new sketch block and open it for drawing.
    public func insertSketch() {
        guard let window = textView.window else { return }
        let editor = SketchEditor(sketch: Sketch(), theme: theme)
        activeSketchEditor = editor
        editor.present(over: window) { [weak self] result in
            guard let self else { return }
            self.activeSketchEditor = nil
            guard let s = result, !s.strokes.isEmpty, let png = SketchRenderer.png(s), let id = self.host?.storeImage(data: png, ext: "png") else { return }
            self.insertAttachmentBlock(kind: .image, node: Node("image", attrs: ["assetId": .string(id), "alt": .string(loc("Sketch")), "sketch": s.json]))
        }
    }

    /// Open the sketch at `charIndex` for editing; Done replaces its strokes and picture as one Undo step.
    @discardableResult
    func editSketch(at charIndex: Int) -> Bool {
        guard charIndex < storage.length, let a = storage.attribute(.attachment, at: charIndex, effectiveRange: nil) as? BlockAttachment,
              a.kind == .image, let s = Sketch(a.node.attrs?["sketch"]), let window = textView.window else { return false }
        let editor = SketchEditor(sketch: s, theme: theme)
        activeSketchEditor = editor
        editor.present(over: window) { [weak self] result in
            guard let self else { return }
            self.activeSketchEditor = nil
            guard let r = result, r != s, let png = SketchRenderer.png(r), let id = self.host?.storeImage(data: png, ext: "png") else { return }
            self.updateAttachment(at: charIndex) { $0[attr: "assetId"] = .string(id); $0[attr: "sketch"] = r.json }
        }
        return true
    }
}
