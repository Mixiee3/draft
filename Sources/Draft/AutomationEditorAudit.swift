import AppKit
import DraftCore
import DraftEditor

/// `editor-audit`: (1) selecting a heading followed by empty blocks, with mouse events; (2) opening
/// the Style panel at the top, middle and bottom of a note with a selection, measuring whether the
/// text moves. AUDIT_DARK / AUDIT_NARROW as in audit-shots.
extension Automation {
    static func editorAudit() async {
        guard let w = NSApp.windows.first(where: { $0.isVisible }) else { return }
        let env = ProcessInfo.processInfo.environment
        let narrow = env["AUDIT_NARROW"] != nil, dark = env["AUDIT_DARK"] != nil
        let p = (narrow ? "narrow-" : "") + (dark ? "dark-" : "")
        w.setFrame(NSRect(x: 40, y: 40, width: narrow ? 720 : 1440, height: narrow ? 640 : 900), display: true)
        m.setSettings { $0.theme = dark ? "dark" : "light" }
        var r: [String: String] = [:]
        defer { if let d = try? JSONSerialization.data(withJSONObject: r, options: [.prettyPrinted, .sortedKeys]) { try? d.write(to: out.appendingPathComponent(p + "editor-audit.json")) } }
        guard let id = m.createDoc(title: "Editor audit") else { return }
        let c = m.editor(for: id).controller
        // Built as blocks so the empty paragraphs really are there (pasting collapses them).
        var blocks = [Node("heading", attrs: ["id": "b_h", "level": 2], content: [.text("Three word heading")])]
        blocks += (1...3).map { Node("paragraph", attrs: ["id": .string("b_e\($0)")]) }
        blocks += [Node("paragraph", attrs: ["id": "b_a"], content: [.text("A paragraph after the empty blocks.")]), Node("paragraph", attrs: ["id": "b_t"], content: [.text("Text ending a paragraph here.")]),
                   Node("paragraph", attrs: ["id": "b_blank"]), Node("paragraph", attrs: ["id": "b_n"], content: [.text("Another paragraph after a blank one.")])]
        blocks += (1...60).map { Node("paragraph", attrs: ["id": .string("b_l\($0)")], content: [.text("Body line \($0) with enough words to wrap a little on narrow pages.")]) }
        c.load(Node("doc", content: blocks)); m.editorChanged(id)
        m.openView(.doc(id)); await wait(0.7)
        w.makeFirstResponder(c.textView)
        let ns = { c.textView.string as NSString }
        c.textView.setSelectedRange(NSRange(location: 0, length: 0)); c.textView.scrollRangeToVisible(NSRange(location: 0, length: 0)); await wait(0.4)
        func point(_ index: Int, edge: CGFloat = 0.5) -> NSPoint {
            let gr = c.layout.glyphRange(forCharacterRange: NSRange(location: index, length: 1), actualCharacterRange: nil)
            let rr = c.layout.boundingRect(forGlyphRange: gr, in: c.container), o = c.textView.textContainerOrigin
            return c.textView.convert(NSPoint(x: rr.minX + rr.width * edge + o.x, y: rr.midY + o.y), to: nil)
        }
        func post(_ t: NSEvent.EventType, _ pt: NSPoint, clicks: Int = 1) {
            if let e = NSEvent.mouseEvent(with: t, location: pt, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: w.windowNumber, context: nil, eventNumber: 0, clickCount: clicks, pressure: t == .leftMouseUp ? 0 : 1) { NSApp.postEvent(e, atStart: false) }
        }
        func describe(_ name: String) async {
            await wait(0.35)
            let sel = c.textView.selectedRange()
            let text = ns().substring(with: sel)
            r[name + ".text"] = text.replacingOccurrences(of: "\n", with: "⏎")
            // Selection highlight rectangles as the text view draws them (text-view coordinates).
            var rects: [NSRect] = []
            let gr = c.layout.glyphRange(forCharacterRange: sel, actualCharacterRange: nil)
            c.layout.enumerateEnclosingRects(forGlyphRange: gr, withinSelectedGlyphRange: gr, in: c.container) { rr, _ in rects.append(rr) }
            let headingLine = c.layout.lineFragmentUsedRect(forGlyphAt: c.layout.glyphIndexForCharacter(at: 0), effectiveRange: nil)
            r[name + ".rects"] = rects.map { "y\(Int($0.minY))-\(Int($0.maxY)) w\(Int($0.width))" }.joined(separator: " ")
            r[name + ".headingUsed"] = "y\(Int(headingLine.minY))-\(Int(headingLine.maxY))"
            await shot(p + "select-" + name, w, settle: 0)
        }
        let h = ns().range(of: "Three word heading")
        // Drag from the start of the heading to just past its end (people overshoot into the empty block).
        let start = point(h.location, edge: 0.05), end = point(NSMaxRange(h) - 1, edge: 0.95)
        post(.leftMouseDown, start); post(.leftMouseDragged, NSPoint(x: (start.x + end.x) / 2, y: start.y)); post(.leftMouseDragged, NSPoint(x: end.x + 40, y: end.y - 26)); post(.leftMouseUp, NSPoint(x: end.x + 40, y: end.y - 26))
        await describe("heading-drag-overshoot")
        post(.leftMouseDown, end, clicks: 1); post(.leftMouseUp, end, clicks: 1)
        post(.leftMouseDown, end, clicks: 2); post(.leftMouseUp, end, clicks: 2)
        post(.leftMouseDown, end, clicks: 3); post(.leftMouseUp, end, clicks: 3)
        await describe("heading-triple-click")
        c.textView.setSelectedRange(h); await describe("heading-exact")
        let endPara = ns().range(of: "Text ending a paragraph here.")
        let ep = point(NSMaxRange(endPara) - 1, edge: 0.95)
        post(.leftMouseDown, point(endPara.location, edge: 0.05)); post(.leftMouseDragged, NSPoint(x: ep.x + 60, y: ep.y - 22)); post(.leftMouseUp, NSPoint(x: ep.x + 60, y: ep.y - 22))
        await describe("paragraph-end-overshoot")
        let two = NSRange(location: ns().range(of: "A paragraph after").location, length: NSMaxRange(endPara) - ns().range(of: "A paragraph after").location)
        c.textView.setSelectedRange(two); await describe("two-paragraphs")
        // Bold on the dragged heading must stop at the heading.
        c.textView.setSelectedRange(NSRange(location: 0, length: 0))
        post(.leftMouseDown, start); post(.leftMouseDragged, NSPoint(x: end.x + 40, y: end.y - 26)); post(.leftMouseUp, NSPoint(x: end.x + 40, y: end.y - 26)); await wait(0.3)
        c.toggleMark(.bold)
        let doc = c.document()
        r["boldOnlyInHeading"] = (doc.content?.dropFirst().allSatisfy { ($0.content ?? []).allSatisfy { $0.marks?.isEmpty ?? true } } ?? false) ? "yes" : "no"
        r["emptyBlocksKept"] = "\(doc.content?.dropFirst().prefix(3).filter { ($0.content ?? []).isEmpty }.count ?? 0)"
        r["headingBold"] = doc.content?.first?.content?.first?.marks?.contains(Mark("bold")) == true ? "yes" : "no"
        c.undo.undo()

        // Opening the Style panel must not move the text.
        func firstVisible() -> (Int, CGFloat) {
            let vis = c.textView.visibleRect
            let idx = c.layout.characterIndex(for: NSPoint(x: 4, y: vis.minY + 4 - c.textView.textContainerOrigin.y), in: c.container, fractionOfDistanceBetweenInsertionPoints: nil)
            let gr = c.layout.glyphRange(forCharacterRange: NSRange(location: idx, length: 1), actualCharacterRange: nil)
            let line = c.layout.boundingRect(forGlyphRange: gr, in: c.container)
            let onScreen = c.textView.convert(NSPoint(x: line.minX + c.textView.textContainerOrigin.x, y: line.minY + c.textView.textContainerOrigin.y), to: nil)
            return (idx, onScreen.y)
        }
        func caretOnScreen() -> NSPoint {
            let gr = c.layout.glyphRange(forCharacterRange: NSRange(location: c.textView.selectedRange().location, length: 1), actualCharacterRange: nil)
            let rr = c.layout.boundingRect(forGlyphRange: gr, in: c.container), o = c.textView.textContainerOrigin
            return c.textView.convert(NSPoint(x: rr.minX + o.x, y: rr.minY + o.y), to: nil)
        }
        for (place, anchor) in [("top", "Three word heading"), ("middle", "Body line 30 "), ("bottom", "Body line 60 ")] {
            let a = ns().range(of: anchor)
            c.textView.setSelectedRange(NSRange(location: a.location, length: min(a.length, 14)))
            c.textView.scrollRangeToVisible(a); await wait(0.4)
            let before = firstVisible(), caretBefore = caretOnScreen(), selBefore = c.textView.selectedRange()
            m.panel = .style; await wait(0.8)
            let after = firstVisible(), caretAfter = caretOnScreen()
            await shot(p + "panel-\(place)", w, settle: 0)
            m.panel = nil; await wait(0.7)
            let closed = firstVisible()
            r["panel.\(place)"] = "firstChar \(before.0)->\(after.0)->\(closed.0) lineY \(Int(before.1))->\(Int(after.1)) caretY \(Int(caretBefore.y))->\(Int(caretAfter.y)) caretX \(Int(caretBefore.x))->\(Int(caretAfter.x)) selection \(selBefore == c.textView.selectedRange() ? "kept" : "changed")"
        }
        m.flushAll()
    }
}
