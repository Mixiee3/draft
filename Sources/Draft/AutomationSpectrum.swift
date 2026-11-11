import AppKit
import ImageIO
import UniformTypeIdentifiers
import DraftCore
import DraftEditor

/// `spectrum-test`: Spectrum text in a live editor. Applied through the formatting bar with mouse
/// events, then checked from the pixels on screen: it moves, it is one gradient across the phrase
/// (not one per letter), it stops off screen and under Reduce Motion, and it survives scrolling,
/// tab switches, style and theme changes, closing, undo/redo, copy/paste and export. Writes a GIF.
/// `spectrum-read` (same vault, after a relaunch) checks it is still there and moving.
extension Automation {
    @MainActor static func grab(_ rect: NSRect, in view: NSView) -> CGImage? {
        guard let w = view.window else { return nil }
        let wr = view.convert(rect, to: nil), sr = w.convertToScreen(wr)
        let screenH = NSScreen.screens[0].frame.height
        return CGWindowListCreateImage(CGRect(x: sr.minX, y: screenH - sr.maxY, width: sr.width, height: sr.height), .optionOnScreenOnly, kCGNullWindowID, [.nominalResolution])
    }

    /// Hue (0…1) of the "ink" pixels in each column; nil where a column has no glyph pixels.
    static func hueColumns(_ img: CGImage) -> [Double?] {
        let w = img.width, h = img.height
        var data = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(data: &data, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return [] }
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
        return (0..<w).map { x in
            var hs: [Double] = []
            for y in 0..<h {
                let i = (y * w + x) * 4
                let c = NSColor(srgbRed: CGFloat(data[i]) / 255, green: CGFloat(data[i + 1]) / 255, blue: CGFloat(data[i + 2]) / 255, alpha: 1)
                if c.saturationComponent > 0.35, c.brightnessComponent < 0.95 { hs.append(Double(c.hueComponent)) }
            }
            return hs.count >= 2 ? hs.sorted()[hs.count / 2] : nil
        }
    }
    /// Mean absolute RGB change per pixel (0…255), any colour.
    static func rgbDiff(_ a: CGImage, _ b: CGImage) -> Double {
        guard a.width == b.width, a.height == b.height else { return -1 }
        func px(_ img: CGImage) -> [UInt8] {
            var d = [UInt8](repeating: 0, count: img.width * img.height * 4)
            let ctx = CGContext(data: &d, width: img.width, height: img.height, bitsPerComponent: 8, bytesPerRow: img.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            ctx?.draw(img, in: CGRect(x: 0, y: 0, width: img.width, height: img.height)); return d
        }
        let x = px(a), y = px(b)
        var sum = 0
        for i in stride(from: 0, to: x.count, by: 4) { sum += abs(Int(x[i]) - Int(y[i])) + abs(Int(x[i + 1]) - Int(y[i + 1])) + abs(Int(x[i + 2]) - Int(y[i + 2])) }
        return Double(sum) / Double(x.count / 4 * 3)
    }
    static func meanDiff(_ a: CGImage, _ b: CGImage) -> Double {
        let ca = hueColumns(a), cb = hueColumns(b)
        let pairs = zip(ca, cb).compactMap { x, y -> Double? in guard let x, let y else { return nil }; let d = abs(x - y); return min(d, 1 - d) }
        return pairs.isEmpty ? 0 : pairs.reduce(0, +) / Double(pairs.count)
    }
    /// How often the hue jumps back between neighbouring inked columns: a gradient per letter jumps
    /// at every letter, one gradient across the phrase hardly ever.
    static func resets(_ cols: [Double?]) -> (resets: Int, inked: Int, span: Double) {
        let hs = cols.compactMap { $0 }
        var n = 0
        for (a, b) in zip(hs, hs.dropFirst()) { let d = abs(a - b); if min(d, 1 - d) > 0.12 { n += 1 } }
        let span = (hs.max() ?? 0) - (hs.min() ?? 0)
        return (n, hs.count, span)
    }

    static func spectrumTest(read: Bool) async {
        guard let w = NSApp.windows.first(where: { $0.isVisible }) else { return }
        w.setFrame(NSRect(x: 40, y: 40, width: 1280, height: 820), display: true)
        m.setSettings { $0.theme = "light"; $0.reduceMotion = false }
        var r: [String: String] = [:]
        let name = read ? "spectrum-read" : "spectrum-test"
        defer { if let d = try? JSONSerialization.data(withJSONObject: r, options: [.prettyPrinted, .sortedKeys]) { try? d.write(to: out.appendingPathComponent(name + ".json")) } }
        let id: String
        if read {
            guard let found = m.library.docs.values.first(where: { $0.title == "Spectrum live" })?.id else { r["error"] = "doc missing"; return }
            id = found
        } else {
            guard let new = m.createDoc(title: "Spectrum live") else { return }
            id = new
        }
        m.openView(.doc(id)); await wait(0.8)
        let c = m.editor(for: id).controller
        let ns = { c.textView.string as NSString }
        w.makeFirstResponder(c.textView)
        func rect(of phrase: String) -> NSRect {
            let gr = c.layout.glyphRange(forCharacterRange: ns().range(of: phrase), actualCharacterRange: nil)
            let o = c.textView.textContainerOrigin
            return c.layout.boundingRect(forGlyphRange: gr, in: c.container).offsetBy(dx: o.x, dy: o.y).insetBy(dx: -2, dy: 0)
        }
        func probe(_ label: String, _ phrase: String) async {
            guard let a = grab(rect(of: phrase), in: c.textView) else { r[label] = "no capture"; return }
            try? await Task.sleep(nanoseconds: 450_000_000)
            guard let b = grab(rect(of: phrase), in: c.textView) else { return }
            let rs = resets(hueColumns(a))
            r[label] = String(format: "moved=%.3f rgb=%.2f resets=%d inked=%d span=%.2f", meanDiff(a, b), rgbDiff(a, b), rs.resets, rs.inked, rs.span)
        }
        if !read {
            c.pastePlainForAutomation("# Northern lights\nA paragraph with a glowing phrase in the middle of the sentence and more words after it.\nA longer phrase that keeps going across most of the line to test the gradient spread.\n" + (1...40).map { "Line \($0) of filler to scroll past." }.joined(separator: "\n"))
            await wait(0.5)
            c.textView.setSelectedRange(NSRange(location: 0, length: 0)); c.textView.scrollRangeToVisible(NSRange(location: 0, length: 0)); await wait(0.4)
            // Apply through the bar: drag over the heading, Effects, Spectrum, Aurora (mouse events).
            func point(_ index: Int) -> NSPoint {
                let gr = c.layout.glyphRange(forCharacterRange: NSRange(location: index, length: 1), actualCharacterRange: nil)
                let rr = c.layout.boundingRect(forGlyphRange: gr, in: c.container), o = c.textView.textContainerOrigin
                return c.textView.convert(NSPoint(x: rr.minX + 1 + o.x, y: rr.midY + o.y), to: nil) // the left edge, as a person starts a drag
            }
            func post(_ t: NSEvent.EventType, _ p: NSPoint) {
                if let e = NSEvent.mouseEvent(with: t, location: p, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: w.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: t == .leftMouseUp ? 0 : 1) { NSApp.postEvent(e, atStart: false) }
            }
            func clickItem(_ prefix: String) async { if let p = c.toolbar.center(ofItem: prefix) { post(.leftMouseDown, p); post(.leftMouseUp, p) }; await wait(0.35) }
            let h = ns().range(of: "Northern lights")
            post(.leftMouseDown, point(h.location)); for k in 1...5 { post(.leftMouseDragged, point(h.location + h.length * k / 5 - (k == 5 ? 1 : 0))) }; post(.leftMouseDragged, NSPoint(x: point(NSMaxRange(h) - 1).x + 30, y: point(NSMaxRange(h) - 1).y)); post(.leftMouseUp, NSPoint(x: point(NSMaxRange(h) - 1).x + 30, y: point(NSMaxRange(h) - 1).y))
            await wait(0.4)
            r["headingSelection"] = ns().substring(with: c.textView.selectedRange())
            await clickItem("effects"); await clickItem("fxspectrum")
            await shot("spectrum-menu", w, settle: 0.3)
            await clickItem("spaurora")
            r["appliedThroughBar"] = c.storage.attribute(.draftEffect, at: h.location, effectiveRange: nil) as? String ?? "none"
            c.textView.setSelectedRange(ns().range(of: "glowing phrase")); c.setEffect("spectrum:neon:normal:forward")
            c.textView.setSelectedRange(ns().range(of: "A longer phrase that keeps going across most of the line")); c.setEffect("spectrum:prism:slow:backward")
            c.textView.setSelectedRange(NSRange(location: ns().length, length: 0)); await wait(0.5)
        }
        await probe("heading", "Northern lights")
        await probe("middle", "glowing phrase")
        await probe("long", "A longer phrase that keeps going across most of the line")
        await shot(read ? "spectrum-after-relaunch" : "spectrum-editor", w, settle: 0.2)
        if read { m.flushAll(); return }

        // A selection inside the phrase keeps the effect drawn.
        c.textView.setSelectedRange(NSRange(location: ns().range(of: "Northern").location, length: 8)); await wait(0.3)
        await probe("whileSelected", "Northern lights")
        c.textView.setSelectedRange(NSRange(location: ns().length, length: 0))
        // Off screen: no redraw work; back on screen: moving again.
        c.textView.scrollRangeToVisible(NSRange(location: ns().length - 1, length: 0)); await wait(0.4)
        r["offscreenRects"] = "\(c.layout.spectrumRects(in: c.textView.visibleRect, origin: c.textView.textContainerOrigin).count)"
        c.textView.scrollRangeToVisible(NSRange(location: 0, length: 0)); await wait(0.5)
        await probe("afterScroll", "Northern lights")
        // Another tab and back.
        if let other = m.createDoc(title: "Other note") { m.openView(.doc(other)); await wait(0.6) }
        m.openView(.doc(id)); await wait(0.8)
        await probe("afterTabSwitch", "Northern lights")
        // Style and theme changes.
        m.updateAppearance(id) { $0.styleId = "deep-ink" }; await wait(0.6)
        await probe("darkStyle", "Northern lights")
        await shot("spectrum-deep-ink", w, settle: 0.1)
        m.updateAppearance(id) { $0.styleId = "paper" }
        m.setSettings { $0.theme = "dark" }; await wait(0.7)
        await probe("darkTheme", "Northern lights")
        await shot("spectrum-dark", w, settle: 0.1)
        m.setSettings { $0.theme = "light" }; await wait(0.5)
        // Reduce Motion: still.
        m.setSettings { $0.reduceMotion = true }; m.retheme(); await wait(0.6)
        await probe("reduceMotion", "Northern lights")
        m.setSettings { $0.reduceMotion = false }; m.retheme(); await wait(0.5)
        // Undo / redo.
        c.textView.setSelectedRange(ns().range(of: "middle")); c.setEffect("spectrum:ocean:fast:forward")
        c.undo.undo(); r["undoRemoves"] = c.storage.attribute(.draftEffect, at: ns().range(of: "middle").location, effectiveRange: nil) == nil ? "yes" : "no"
        c.undo.redo(); r["redoRestores"] = (c.storage.attribute(.draftEffect, at: ns().range(of: "middle").location, effectiveRange: nil) as? String)?.hasPrefix("spectrum") == true ? "yes" : "no"
        // Copy and paste the heading text.
        c.textView.setSelectedRange(ns().range(of: "Northern lights")); c.textView.copy(nil)
        c.textView.setSelectedRange(NSRange(location: ns().length, length: 0)); c.textView.insertNewline(nil); c.textView.paste(nil); await wait(0.3)
        let pastedAt = ns().range(of: "Northern lights", options: .backwards).location
        r["pasteKeepsEffect"] = (c.storage.attribute(.draftEffect, at: pastedAt, effectiveRange: nil) as? String) ?? "none"
        // Typing while it moves.
        c.textView.setSelectedRange(NSRange(location: ns().range(of: "after it.").location, length: 0))
        var times: [Double] = []
        for ch in "typing next to a moving gradient" {
            let t0 = CACurrentMediaTime(); c.textView.insertText(String(ch), replacementRange: c.textView.selectedRange()); c.textView.displayIfNeeded()
            times.append((CACurrentMediaTime() - t0) * 1000); try? await Task.sleep(nanoseconds: 16_000_000)
        }
        times.sort(); r["typingP95ms"] = String(format: "%.1f", times[Int(Double(times.count) * 0.95)])
        // A recording: three seconds of the heading.
        let gifURL = out.appendingPathComponent("spectrum-recording.gif")
        if let dest = CGImageDestinationCreateWithURL(gifURL as CFURL, UTType.gif.identifier as CFString, 45, nil) {
            CGImageDestinationSetProperties(dest, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
            let area = rect(of: "Northern lights").insetBy(dx: -40, dy: -16)
            for _ in 0..<45 {
                if let img = grab(area, in: c.textView) { CGImageDestinationAddImage(dest, img, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 0.066]] as CFDictionary) }
                try? await Task.sleep(nanoseconds: 66_000_000)
            }
            r["recording"] = CGImageDestinationFinalize(dest) ? "spectrum-recording.gif" : "failed"
        }
        // Export: a still gradient.
        m.flushAll()
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        if let res = try? m.writeHTML(id, useStyle: true, parent: tmp, name: "export") {
            let html = (try? String(contentsOf: res.html, encoding: .utf8)) ?? ""
            r["htmlSpectrum"] = html.contains("fx-spectrum") && html.contains("linear-gradient(90deg") && !html.contains("@keyframes") ? "still gradient" : "missing"
            for (kind, pdf) in [("png", false), ("pdf", true)] {
                let dst = out.appendingPathComponent("spectrum-export.\(kind)")
                var finished = false
                WebRenderer.shared.render(res.html, readAccess: res.folder, to: dst, pdf: pdf) { ok in r["export.\(kind)"] = ok ? "written" : "failed"; finished = true }
                for _ in 0..<60 where !finished { await wait(0.25) }
            }
        }
        // Close and reopen the note.
        if let tab = m.tabs.first(where: { $0.view.docId == id }) { m.closeTab(tab.id) }
        m.dropEditor(id); await wait(0.4)
        m.openView(.doc(id)); await wait(0.8)
        let c2 = m.editor(for: id).controller
        r["afterReopen"] = (c2.storage.attribute(.draftEffect, at: (c2.textView.string as NSString).range(of: "Northern lights").location, effectiveRange: nil) as? String) ?? "none"
        m.flushAll()
    }
}
