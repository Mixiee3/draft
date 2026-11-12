import AppKit
import DraftCore
import DraftEditor

/// `text-audit`: native Retina crops of body text, a heading and effects; and the same paragraph with
/// the text view transparent (as shipped) versus opaque, which is what lets macOS smooth the glyphs.
extension Automation {
    static func textAudit() async {
        guard let w = NSApp.windows.first(where: { $0.isVisible }) else { return }
        let dark = ProcessInfo.processInfo.environment["AUDIT_DARK"] != nil
        let p = dark ? "dark-" : ""
        w.setFrame(NSRect(x: 40, y: 40, width: 1280, height: 860), display: true)
        m.setSettings { $0.theme = dark ? "dark" : "light" }
        var r: [String: String] = [:]
        defer { if let d = try? JSONSerialization.data(withJSONObject: r, options: [.prettyPrinted, .sortedKeys]) { try? d.write(to: out.appendingPathComponent(p + "text-audit.json")) } }
        guard let id = m.createDoc(title: "Text audit") else { return }
        let ed = m.editor(for: id), c = ed.controller
        c.load(Node("doc", content: [
            Node("heading", attrs: ["id": "b_h", "level": 2], content: [.text("A heading for comparison")]),
            Node("paragraph", attrs: ["id": "b_p"], content: [.text("Body text at the normal size, the kind people read for a long time without noticing the type.")]),
            Node("paragraph", attrs: ["id": "b_fx"], content: [.text("Spectrum", marks: [Mark("effect", attrs: ["kind": "spectrum", "palette": "prism", "speed": "still", "direction": "forward"])]), .text(" · "),
                .text("Glow", marks: [EffectSpec("glow?color=#ff4fd8&intensity=0.80")!.mark]), .text(" · "), .text("Shadow", marks: [EffectSpec("shadow")!.mark]), .text(" · "),
                .text("Outline", marks: [EffectSpec("outline")!.mark]), .text(" · "), .text("Lift", marks: [EffectSpec("lift")!.mark]), .text(" · "), .text("Emboss", marks: [EffectSpec("emboss")!.mark])]),
        ]))
        m.editorChanged(id); m.openView(.doc(id)); await wait(0.8)
        let ns = c.textView.string as NSString
        func crop(_ phrase: String, _ name: String) -> Double {
            let gr = c.layout.glyphRange(forCharacterRange: ns.range(of: phrase), actualCharacterRange: nil)
            let o = c.textView.textContainerOrigin
            let rect = c.layout.boundingRect(forGlyphRange: gr, in: c.container).offsetBy(dx: o.x, dy: o.y).insetBy(dx: -6, dy: -4)
            guard let img = grab(rect, in: c.textView) else { return 0 }
            let wr = c.textView.convert(rect, to: nil), sr = w.convertToScreen(wr)
            let screenH = NSScreen.screens[0].frame.height
            if let hi = CGWindowListCreateImage(CGRect(x: sr.minX, y: screenH - sr.maxY, width: sr.width, height: sr.height), .optionOnScreenOnly, kCGNullWindowID, [.bestResolution]),
               let png = NSBitmapImageRep(cgImage: hi).representation(using: .png, properties: [:]) { try? png.write(to: out.appendingPathComponent(p + name + ".png")) }
            // Ink: how much darker (light page) or lighter (dark page) than the page the glyphs are, summed.
            let rep = NSBitmapImageRep(cgImage: img)
            var ink = 0.0
            for x in 0..<rep.pixelsWide { for y in 0..<rep.pixelsHigh { if let col = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) { let l = Double(col.redComponent + col.greenComponent + col.blueComponent) / 3; ink += dark ? l : 1 - l } } }
            return ink
        }
        let bodyT = crop("Body text at the normal size", "body-transparent")
        let headT = crop("A heading for comparison", "heading-transparent")
        _ = crop("Spectrum · Glow · Shadow · Outline · Lift · Emboss", "effects-transparent")
        c.textView.drawsBackground = true; c.textView.backgroundColor = NSColor(hex: c.theme.pageColor); c.textView.needsDisplay = true; await wait(0.5)
        let bodyO = crop("Body text at the normal size", "body-opaque")
        let headO = crop("A heading for comparison", "heading-opaque")
        _ = crop("Spectrum · Glow · Shadow · Outline · Lift · Emboss", "effects-opaque")
        r["bodyInk"] = String(format: "transparent %.0f, opaque %.0f (%+.1f%%)", bodyT, bodyO, (bodyO - bodyT) / max(bodyT, 1) * 100)
        r["headingInk"] = String(format: "transparent %.0f, opaque %.0f (%+.1f%%)", headT, headO, (headO - headT) / max(headT, 1) * 100)
        r["font"] = (c.storage.attribute(.font, at: ns.range(of: "Body").location, effectiveRange: nil) as? NSFont).map { "\($0.fontName) \($0.pointSize)pt" } ?? "?"
        r["lineHeight"] = String(format: "%.1f", (c.storage.attribute(.paragraphStyle, at: ns.range(of: "Body").location, effectiveRange: nil) as? NSParagraphStyle)?.lineHeightMultiple ?? 0)
        r["backingScale"] = "\(w.backingScaleFactor)"
    }
}
