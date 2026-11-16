import AppKit
import DraftCore
import DraftEditor

/// `selection-test`: the selection toolbar and the right-click menu driven by mouse and keyboard
/// events through the app's event queue (double-click, drag, shift-click, right-click, ⌥F10, arrows,
/// Return, Escape, click away). Records where the bar sits and what it shows; AUDIT_DARK /
/// AUDIT_NARROW as in audit-shots.
extension Automation {
    static func selectionTest() async {
        guard let w = NSApp.windows.first(where: { $0.isVisible }) else { return }
        let env = ProcessInfo.processInfo.environment
        let narrow = env["AUDIT_NARROW"] != nil, dark = env["AUDIT_DARK"] != nil
        let p = (narrow ? "narrow-" : "") + (dark ? "dark-" : "")
        w.setFrame(NSRect(x: 40, y: 40, width: narrow ? 720 : 1280, height: narrow ? 640 : 820), display: true)
        m.setSettings { $0.theme = dark ? "dark" : "light" }
        var r: [String: String] = [:]
        defer { if let d = try? JSONSerialization.data(withJSONObject: r, options: [.prettyPrinted, .sortedKeys]) { try? d.write(to: out.appendingPathComponent(p + "selection.json")) } }
        guard let id = m.createDoc(title: "Selection test") else { return }
        let c = m.editor(for: id).controller
        c.pastePlainForAutomation("## Heading near the top\nA first paragraph with a [link](https://example.com) and ==a highlight== in the middle of a long sentence that wraps across the page.\n- a list item to select\n> A quote to format.\n`inline code` sits here too.\nA second paragraph that ends the first part.\n" + (1...30).map { "Filler line \($0) so the note scrolls." }.joined(separator: "\n") + "\nThe very last paragraph sits at the bottom of the note.")
        m.openView(.doc(id)); await wait(0.8)
        w.makeFirstResponder(c.textView)
        let ns = { c.textView.string as NSString }

        func point(_ index: Int, dx: CGFloat = 2) -> NSPoint {
            let gr = c.layout.glyphRange(forCharacterRange: NSRange(location: index, length: 1), actualCharacterRange: nil)
            let rect = c.layout.boundingRect(forGlyphRange: gr, in: c.container)
            let o = c.textView.textContainerOrigin
            return c.textView.convert(NSPoint(x: rect.minX + o.x + dx, y: rect.midY + o.y), to: nil)
        }
        func post(_ type: NSEvent.EventType, _ pt: NSPoint, clicks: Int = 1, flags: NSEvent.ModifierFlags = []) {
            if let e = NSEvent.mouseEvent(with: type, location: pt, modifierFlags: flags, timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: w.windowNumber,
                                          context: nil, eventNumber: 0, clickCount: clicks, pressure: [.leftMouseUp, .rightMouseUp].contains(type) ? 0 : 1) { w.sendEvent(e) }
        }
        func key(_ code: UInt16, _ chars: String, flags: NSEvent.ModifierFlags = []) {
            for t in [NSEvent.EventType.keyDown, .keyUp] {
                if let e = NSEvent.keyEvent(with: t, location: .zero, modifierFlags: flags, timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: w.windowNumber,
                                            context: nil, characters: chars, charactersIgnoringModifiers: chars, isARepeat: false, keyCode: code) { w.sendEvent(e) } // straight to the window: it may not be key while automated
            }
        }
        func scrollTo(_ index: Int) async { c.textView.scrollRangeToVisible(NSRange(location: index, length: 0)); await wait(0.3) }
        /// Where the bar is, relative to the visible editor and the selection.
        func record(_ name: String) async {
            await wait(0.45)
            let tb = c.toolbar
            guard tb.isVisible, let host = tb.presentationView.superview else { r[name] = "hidden"; await shot(p + "sel-" + name, w, settle: 0); return }
            let toolbarFrame = tb.presentationView.frame
            let inside = host.visibleRect.insetBy(dx: -1, dy: -1).contains(toolbarFrame)
            let sel = c.textView.selectedRange()
            let gr = c.layout.glyphRange(forCharacterRange: sel, actualCharacterRange: nil)
            var covers = false
            c.layout.enumerateEnclosingRects(forGlyphRange: gr, withinSelectedGlyphRange: gr, in: c.container) { rr, _ in
                let o = c.textView.textContainerOrigin
                if c.textView.convert(rr.offsetBy(dx: o.x, dy: o.y), to: host).intersects(toolbarFrame) { covers = true }
            }
            r[name] = "\(inside ? "inside" : "OUTSIDE") \(covers ? "COVERS-SELECTION" : "clear") mode=\(tb.modeName) items=\(tb.buttonLabels.count) w=\(Int(tb.frame.width))"
            await shot(p + "sel-" + name, w, settle: 0)
        }

        // A word: double-click.
        let word = ns().range(of: "first paragraph").location + 2
        post(.leftMouseDown, point(word), clicks: 1); post(.leftMouseUp, point(word), clicks: 1)
        post(.leftMouseDown, point(word), clicks: 2); post(.leftMouseUp, point(word), clicks: 2)
        await wait(0.3)
        r["wordSelected"] = ns().substring(with: c.textView.selectedRange())
        await record("word")
        // A sentence: drag.
        let s0 = ns().range(of: "A first paragraph").location, s1 = ns().range(of: "the middle").location + 10
        post(.leftMouseDown, point(s0)); for k in 1...6 { let t = CGFloat(k) / 6; let a = point(s0), b = point(s1); post(.leftMouseDragged, NSPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)) }; post(.leftMouseUp, point(s1))
        await wait(0.3)
        r["sentenceSelected"] = "\(c.textView.selectedRange().length)"
        await record("sentence")
        // Several paragraphs: shift-click.
        let m0 = ns().range(of: "A second paragraph").location + 20
        post(.leftMouseDown, point(m0), flags: .shift); post(.leftMouseUp, point(m0), flags: .shift)
        await wait(0.3)
        r["multiSelected"] = "\(c.textView.selectedRange().length)"
        await record("paragraphs")
        // Hover over the selection: nothing should change.
        if let e = NSEvent.mouseEvent(with: .mouseMoved, location: point(s0 + 5), modifierFlags: [], timestamp: 0, windowNumber: w.windowNumber, context: nil, eventNumber: 0, clickCount: 0, pressure: 0) { NSApp.postEvent(e, atStart: false) }
        await record("hover")
        // Right-click the selection: capture what is on screen while the menu is open, then Escape.
        let rc = point(s0 + 8)
        let url = out.appendingPathComponent(p + "sel-right-click.png")
        let screenH = NSScreen.screens[0].frame.height, f = w.frame.insetBy(dx: -40, dy: -40)
        let capture = CGRect(x: f.minX, y: screenH - f.maxY, width: f.width, height: f.height)
        // The menu that opens is closed with cancelTracking (what Escape does), from the main queue,
        // which AppKit keeps serving while the menu tracks.
        var opened: NSMenu?
        let token = NotificationCenter.default.addObserver(forName: NSMenu.didBeginTrackingNotification, object: nil, queue: nil) { n in opened = n.object as? NSMenu }
        Thread.detachNewThread {
            Thread.sleep(forTimeInterval: 1.0)
            if let cg = CGWindowListCreateImage(capture, .optionOnScreenOnly, kCGNullWindowID, [.bestResolution]) { try? NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])?.write(to: url) }
            DispatchQueue.main.async { opened?.cancelTracking() }
        }
        post(.rightMouseDown, rc); post(.rightMouseUp, rc)
        await wait(1.6)
        NotificationCenter.default.removeObserver(token)
        r["barBackAfterMenu"] = c.toolbar.isVisible ? "yes" : "no"
        r["stateAfterMenu"] = c.toolbar.debugState
        r["afterRightClick.selection"] = "\(c.textView.selectedRange().length)"
        if let menu = c.textView.menu(for: NSEvent.mouseEvent(with: .rightMouseDown, location: rc, modifierFlags: [], timestamp: 0, windowNumber: w.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!) {
            r["contextMenu"] = menu.items.map { $0.isSeparatorItem ? "—" : $0.title }.joined(separator: " | ")
        }
        await record("after-right-click")
        // Keyboard: ⌥F10 focuses the bar, → moves, Return applies, Escape returns to the text.
        w.makeFirstResponder(c.textView)
        c.textView.setSelectedRange(NSRange(location: s0, length: 17)); await wait(0.3)
        key(109, String(UnicodeScalar(NSF10FunctionKey)!), flags: [.option, .function]); await wait(0.3)
        r["stateBeforeF10"] = c.toolbar.debugState
        r["keyboardFocus"] = w.firstResponder === c.toolbar ? "bar" : String(describing: w.firstResponder.map { Swift.type(of: $0) })
        r["keyboardFocused"] = c.toolbar.focusedLabel ?? "none"
        key(124, String(UnicodeScalar(NSRightArrowFunctionKey)!), flags: [.function]); await wait(0.2)
        r["keyboardFocusedAfterRight"] = c.toolbar.focusedLabel ?? "none"
        key(48, "\t"); await wait(0.2)
        r["keyboardFocusedAfterTab"] = c.toolbar.focusedLabel ?? "none"
        await record("keyboard-focus")
        key(123, String(UnicodeScalar(NSLeftArrowFunctionKey)!), flags: [.function]); key(123, String(UnicodeScalar(NSLeftArrowFunctionKey)!), flags: [.function]); await wait(0.2)
        r["keyboardOnBold"] = c.toolbar.focusedLabel ?? "none"
        key(36, "\r"); await wait(0.3)
        r["returnAppliedBold"] = c.isMarkActive(.bold) ? "yes" : "no"
        key(49, " "); await wait(0.3)
        r["spaceToggledBold"] = c.isMarkActive(.bold) ? "no" : "yes"
        key(53, "\u{1b}"); await wait(0.3)
        r["escapeReturnsToText"] = w.firstResponder === c.textView ? "yes" : "no"
        r["selectionKeptAfterEscape"] = c.textView.selectedRange().length == 17 ? "yes" : "no"
        // Colors keep the selection.
        c.toolbar.setMode(.palette); await record("colors")
        if let wp = c.toolbar.center(ofItem: "h#") { post(.leftMouseDown, wp); post(.leftMouseUp, wp); await wait(0.4) }
        r["highlightApplied"] = c.value(of: .draftHighlight) != nil ? "yes" : "no"
        r["selectionKeptAfterColor"] = c.textView.selectedRange().length == 17 ? "yes" : "no"
        // Effects.
        r["effectsButtons"] = { c.toolbar.setMode(.effects); return c.toolbar.buttonLabels.joined(separator: ",") }()
        await record("effects")
        c.toolbar.setMode(.main)
        // Click away: the bar goes and the I-beam comes back.
        let away = point(ns().range(of: "A second paragraph").location + 4)
        post(.leftMouseDown, away); post(.leftMouseUp, away); await wait(0.4)
        r["clickAwayHides"] = c.toolbar.isVisible ? "no" : "yes"
        r["cursorAfterClickAway"] = c.textView.cursor(at: c.textView.convert(away, from: nil)) == .iBeam ? "iBeam" : "other"
        // Near the edges: top line, the right edge, the last line at the bottom of the window.
        await scrollTo(0)
        let h0 = ns().range(of: "Heading near").location
        c.textView.setSelectedRange(NSRange(location: h0, length: 7)); await record("top-edge")
        let rightWord = ns().range(of: "wraps").location
        c.textView.setSelectedRange(NSRange(location: rightWord, length: 5)); await record("right-side")
        let last = ns().range(of: "The very last paragraph").location
        await scrollTo(last); c.textView.setSelectedRange(NSRange(location: last, length: 22)); await record("bottom-edge")
        // Selection that starts above the visible area and ends inside it.
        let mid = ns().range(of: "Filler line 20").location
        c.textView.setSelectedRange(NSRange(location: ns().range(of: "Filler line 2 ").location, length: mid - ns().range(of: "Filler line 2 ").location)); await scrollTo(mid); await record("scrolled-start")
        await scrollTo(0)
        for (name, phrase) in [("link", "link"), ("list", "list item"), ("quote", "quote to"), ("code", "inline code")] {
            c.textView.setSelectedRange(ns().range(of: phrase)); await record(name)
        }
        m.updateAppearance(id) { $0.styleId = "midnight-constellation" }
        c.textView.setSelectedRange(ns().range(of: "first paragraph")); await record("custom-background")
        m.flushAll()
    }
}
