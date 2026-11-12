import AppKit
import DraftCore
import DraftEditor

/// `effects-live`: every text effect, highlight and block effect applied in the running editor and
/// checked from screen pixels: visible, still there after the selection goes, after scrolling away
/// and back, after a tab switch and after closing and reopening; neighbours untouched; bold kept;
/// undo/redo; export. `effects-read` (same vault, after a relaunch) checks they are still drawn.
extension Automation {
    static let effectLines: [(kind: String, line: String)] = [
        ("accent", "Accent sample words"), ("gradient", "Gradient sample words"), ("glow", "Glow sample words"), ("shadow", "Shadow sample words"),
        ("outline", "Outline sample words"), ("lift", "Lift sample words"), ("emboss", "Emboss sample words"), ("spectrum", "Spectrum sample words"),
        ("highlight", "Highlight sample words"),
        ("block:gradient", "Block gradient paragraph"), ("block:glass", "Block glass paragraph"), ("block:glow", "Block glow paragraph"),
        ("block:accent", "Block accent paragraph"), ("block:focus", "Block focus paragraph"),
    ]

    static func effectsLive(read: Bool) async {
        guard let w = NSApp.windows.first(where: { $0.isVisible }) else { return }
        if ProcessInfo.processInfo.environment["DRAFT_FULL_EFFECTS"] != nil { m.setSettings { $0.fullEffectsWithIncreaseContrast = true } }
        let env = ProcessInfo.processInfo.environment
        let dark = env["AUDIT_DARK"] != nil
        w.setFrame(NSRect(x: 40, y: 40, width: 1280, height: 900), display: true)
        m.setSettings { $0.theme = dark ? "dark" : "light" }
        var r: [String: String] = [:]
        let name = (dark ? "dark-" : "") + (read ? "effects-read" : "effects-live")
        defer { if let d = try? JSONSerialization.data(withJSONObject: r, options: [.prettyPrinted, .sortedKeys]) { try? d.write(to: out.appendingPathComponent(name + ".json")) } }
        let id: String
        if read { guard let f = m.library.docs.values.first(where: { $0.title == "Effects live" })?.id else { r["error"] = "missing"; return }; id = f }
        else {
            guard let n = m.createDoc(title: "Effects live") else { return }; id = n
            let blocks = [Node("paragraph", attrs: ["id": "b_top"], content: [.text("Neighbour line above everything.")])]
                + effectLines.enumerated().map { i, e in Node("paragraph", attrs: ["id": .string("b_\(i)")], content: [.text(e.line.components(separatedBy: " ").first! + " "), .text(e.line.components(separatedBy: " ").dropFirst().joined(separator: " "), marks: e.kind == "glow" ? [Mark("bold")] : nil)]) }
                + [Node("paragraph", attrs: ["id": "b_bottom"], content: [.text("Neighbour line below everything.")])]
                + (1...50).map { Node("paragraph", attrs: ["id": .string("b_f\($0)")], content: [.text("Filler \($0) to scroll past.")]) }
            m.editor(for: id).controller.load(Node("doc", content: blocks)); m.editorChanged(id)
        }
        m.openView(.doc(id)); await wait(0.8)
        var c = m.editor(for: id).controller
        let ns = { c.textView.string as NSString }
        w.makeFirstResponder(c.textView)
        c.textView.setSelectedRange(NSRange(location: 0, length: 0)); c.textView.scrollRangeToVisible(NSRange(location: 0, length: 0)); await wait(0.4)
        func rect(_ phrase: String) -> NSRect {
            let gr = c.layout.glyphRange(forCharacterRange: ns().range(of: phrase), actualCharacterRange: nil)
            let o = c.textView.textContainerOrigin
            return c.layout.boundingRect(forGlyphRange: gr, in: c.container).offsetBy(dx: o.x, dy: o.y).insetBy(dx: phrase.hasPrefix("Block") ? -30 : -12, dy: -8)
        }
        func shotOf(_ phrase: String) -> CGImage? { grab(rect(phrase), in: c.textView) }
        func post(_ t: NSEvent.EventType, _ p: NSPoint) {
            if let e = NSEvent.mouseEvent(with: t, location: p, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: w.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: t == .leftMouseUp ? 0 : 1) { NSApp.postEvent(e, atStart: false) }
        }
        func click(_ item: String) async { if let p = c.toolbar.center(ofItem: item) { post(.leftMouseDown, p); post(.leftMouseUp, p) }; await wait(0.3) }

        if read {
            for e in effectLines {
                let target = e.line
                let pr = c.paragraph(withId: "b_\(effectLines.firstIndex { $0.kind == e.kind }!)")
                let stored = e.kind.hasPrefix("block:") ? (pr.map { c.block(at: $0).decoration ?? "none" } ?? "?") : ((c.storage.attribute(e.kind == "highlight" ? .draftHighlight : .draftEffect, at: ns().range(of: target).location, effectiveRange: nil) as? String) ?? "none")
                r[e.kind] = stored
            }
            await shot(name + "-shot", w, settle: 0.2)
            return
        }
        let neighbourBefore = shotOf("Neighbour line above everything."), bottomBefore = shotOf("Neighbour line below everything.")
        var applied: [String: CGImage] = [:]
        for (i, e) in effectLines.enumerated() {
            let words = e.line // each line is unique
            let plain = shotOf(words)
            if e.kind.hasPrefix("block:") {
                c.textView.setSelectedRange(NSRange(location: ns().range(of: e.line).location + 2, length: 0))
                c.setDecoration(String(e.kind.dropFirst(6)))
            } else {
                c.textView.setSelectedRange(ns().range(of: words)); await wait(0.35)
                if e.kind == "highlight" { c.toolbar.setMode(.palette); await click("h#c9ecf7") }
                else {
                    await click("effects"); await click("fx" + e.kind)
                    if e.kind == "spectrum" { await click("spneon") }
                }
            }
            c.textView.setSelectedRange(NSRange(location: ns().range(of: "Filler 3 ").location, length: 0)); await wait(0.35)
            guard let a = plain, let b = shotOf(words) else { r[e.kind] = "no capture"; continue }
            applied[e.kind] = b
            let stored = e.kind.hasPrefix("block:") ? (c.paragraph(withId: "b_\(i)").map { c.block(at: $0).decoration ?? "none" } ?? "?") : ((c.storage.attribute(e.kind == "highlight" ? .draftHighlight : .draftEffect, at: ns().range(of: words).location, effectiveRange: nil) as? String) ?? "none")
            r[e.kind] = String(format: "stored=%@ visible=%.2f", stored, rgbDiff(a, b))
        }
        let glowBold = ns().range(of: "sample words", range: NSRange(location: ns().range(of: "Glow sample").location, length: 30)).location
        r["boldKeptUnderGlow"] = c.storage.attribute(.draftBold, at: glowBold, effectiveRange: nil) != nil && (c.storage.attribute(.draftEffect, at: glowBold, effectiveRange: nil) as? String) == "glow" ? "yes" : "no"
        if let a = neighbourBefore, let b = shotOf("Neighbour line above everything.") { r["neighbourAbove"] = String(format: "%.2f", rgbDiff(a, b)) }
        if let a = bottomBefore, let b = shotOf("Neighbour line below everything.") { r["neighbourBelow"] = String(format: "%.2f", rgbDiff(a, b)) }
        await shot("effects-live", w, settle: 0.1)
        func stillThere(_ label: String) async {
            var worst = 0.0, worstKind = ""
            for e in effectLines where e.kind != "spectrum" {
                let words = e.line
                if let before = applied[e.kind], let now = shotOf(words) { let d = rgbDiff(before, now); if d > worst { worst = d; worstKind = e.kind } }
            }
            r[label] = String(format: "max change %.2f (%@)", worst, worstKind)
        }
        c.textView.scrollRangeToVisible(NSRange(location: ns().length - 1, length: 0)); await wait(0.4)
        c.textView.scrollRangeToVisible(NSRange(location: 0, length: 0)); await wait(0.5)
        await stillThere("afterScroll")
        if let other = m.createDoc(title: "Other") { m.openView(.doc(other)); await wait(0.6) }
        m.openView(.doc(id)); await wait(0.8); c.textView.scrollRangeToVisible(NSRange(location: 0, length: 0)); await wait(0.4)
        await stillThere("afterTabSwitch")
        // A style change re-colors the page but keeps every effect.
        func stored() -> [String] { effectLines.enumerated().map { i, e in e.kind.hasPrefix("block:") ? (c.paragraph(withId: "b_\(i)").map { c.block(at: $0).decoration ?? "none" } ?? "?") : ((c.storage.attribute(e.kind == "highlight" ? .draftHighlight : .draftEffect, at: ns().range(of: e.line).location, effectiveRange: nil) as? String) ?? "none") } }
        let beforeStyle = stored()
        m.updateAppearance(id) { $0.styleId = "midnight-constellation" }; await wait(0.6)
        await shot("effects-midnight", w, settle: 0.1)
        m.updateAppearance(id) { $0.styleId = "paper" }; await wait(0.5)
        r["styleChangeKeepsEffects"] = stored() == beforeStyle ? "yes" : "no: \(stored())"
        if let tab = m.tabs.first(where: { $0.view.docId == id }) { m.closeTab(tab.id) }
        m.flushAll(); m.dropEditor(id); await wait(0.3)
        m.openView(.doc(id)); await wait(0.9); c = m.editor(for: id).controller; c.textView.scrollRangeToVisible(NSRange(location: 0, length: 0)); await wait(0.5)
        await stillThere("afterReopen")
        await shot("effects-after-reopen", w, settle: 0.1)
        // Undo and redo the last text effect applied through the bar (Outline), in the reopened editor: apply again first.
        let ol = ns().range(of: "Outline sample words")
        c.textView.setSelectedRange(ol); c.setEffect("glow?color=#ff4fd8&intensity=0.80")
        c.undo.undo(); r["undoRestoresOutline"] = (c.storage.attribute(.draftEffect, at: ol.location, effectiveRange: nil) as? String) == "outline" ? "yes" : "no"
        c.undo.redo(); r["redoReapplies"] = (c.storage.attribute(.draftEffect, at: ol.location, effectiveRange: nil) as? String)?.hasPrefix("glow?color=#ff4fd8") == true ? "yes" : "no"
        c.undo.undo()
        // The effect editor for a selected Glow line and a Gradient line.
        for (kind, line) in [("glow", "Glow sample words"), ("gradient", "Gradient sample words"), ("spectrum", "Spectrum sample words")] {
            c.textView.setSelectedRange(ns().range(of: line)); m.panel = .format; m.editorTick &+= 1; await wait(0.7)
            await shot("effect-editor-\(kind)", w, settle: 0.1)
        }
        m.panel = nil; await wait(0.4)
        m.flushAll()
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        if let res = try? m.writeHTML(id, useStyle: true, parent: tmp, name: "export") {
            let html = (try? String(contentsOf: res.html, encoding: .utf8)) ?? ""
            let missing = ["fx-accent", "fx-gradient", "fx-glow", "fx-shadow", "fx-outline", "fx-lift", "fx-emboss", "fx-spectrum", "<mark", "data-deco='gradient'", "data-deco='glass'", "data-deco='glow'", "data-deco='accent'", "data-deco='focus'"].filter { !html.contains($0) }
            r["export"] = missing.isEmpty ? "all present" : "missing: " + missing.joined(separator: ",")
            let dst = out.appendingPathComponent(name + "-export.png")
            var done = false
            WebRenderer.shared.render(res.html, readAccess: res.folder, to: dst, pdf: false) { ok in r["exportPNG"] = ok ? "written" : "failed"; done = true }
            for _ in 0..<60 where !done { await wait(0.25) }
        }
    }
}
