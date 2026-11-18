import AppKit
import DraftCore
import DraftEditor

/// `DRAFT_AUTOMATION=polish`: window chrome, cursor states and the selection bar, before/after.
extension Automation {
    static func blockActionsShots() async {
        guard let w = NSApp.windows.first(where: { $0.isVisible }), let id = m.createDoc(title: "Block actions preview") else { return }
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
        await wait(0.25)
        m.setSettings { $0.theme = "light" }
        w.setFrame(NSRect(x: 60, y: 60, width: 1120, height: 760), display: true)
        await wait(0.3)
        // Capture the document window itself; "first visible window" can be a transient helper window.
        func shot(_ name: String) async { await wait(0.7); await captureWindow(w, name) }
        guard let ed = m.editors[id] else { return }
        ed.focusBody(atStart: true)
        // Filler text sits behind both floating bars so the screenshots show whether the glass refracts real content.
        let filler = { (n: Int) in (1...n).map { "Line \($0) of filler text that runs underneath the floating glass so refraction is visible." }.joined(separator: "\n") }
        ed.controller.pastePlainForAutomation("## One clear heading\nA paragraph with room to think.\n" + filler(5) + "\nAnother paragraph for selection.\n" + filler(14))
        ed.controller.textView.setSelectedRange(NSRange(location: 0, length: 0))
        ed.layoutSubtreeIfNeeded()
        await shot("block-actions-compact")
        func buttons(in v: NSView) -> [NSButton] {
            v.subviews.flatMap { child in (child as? NSButton).map { [$0] } ?? buttons(in: child) }
        }
        buttons(in: ed.blockActionsView).first { $0.toolTip == "Select block" }?.performClick(nil)
        let selectedByButton = ed.controller.isBlockMode
        ed.layoutSubtreeIfNeeded()
        await shot("block-actions-selected")
        m.setSettings { $0.theme = "dark" }
        await wait(0.3)
        await shot("block-actions-selected-dark")
        m.setSettings { $0.theme = "light" }
        let selectedBlock = ed.controller.currentBlock.kind.rawValue
        let text = ed.controller.textView.string as NSString
        ed.controller.exitBlockMode()
        ed.controller.textView.setSelectedRange(text.range(of: "paragraph for selection"))
        ed.layoutSubtreeIfNeeded()
        await shot("block-actions-text-selection")
        m.setSettings { $0.theme = "dark" }
        await wait(0.3)
        await shot("block-actions-text-selection-dark")
        m.setSettings { $0.theme = "light" }
        m.updateAppearance(id) { $0.styleId = "apricot-grid" }
        ed.controller.textView.setSelectedRange(NSRange(location: 0, length: 0))
        await shot("block-actions-apricot-glass")
        ed.controller.textView.setSelectedRange(text.range(of: "paragraph for selection"))
        await shot("selection-apricot-glass")
        m.flushAll()
        m.freshDocs.remove(id)
        m.railShowsFolders = false
        m.docRailTab = .outline
        await shot("outline-without-hashes")
        let global = UserDefaults.standard.persistentDomain(forName: UserDefaults.globalDomain) ?? [:]
        let glassWindow = w.contentView.map { "opaque=\($0.window?.isOpaque ?? false) layer=\($0.layer != nil) appearance=\(String(describing: $0.effectiveAppearance.name))" } ?? "none"
        let runtime: [String: String] = [
            "reduceTransparency": NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency ? "on" : "off",
            "reduceMotion": NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? "on" : "off",
            "increaseContrast": NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast ? "on" : "off",
            "globalReduceTransparency": String(describing: global["reduceTransparency"] ?? global["AppleReduceTransparency"] ?? "missing"),
            "globalIncreaseContrast": String(describing: global["increaseContrast"] ?? global["AppleIncreaseContrast"] ?? "missing"),
            "os": ProcessInfo.processInfo.operatingSystemVersionString,
            "window": glassWindow,
            "windows": NSApp.windows.filter(\.isVisible).map { "\(Swift.type(of: $0)) \($0.frame) title=\($0.title)" }.joined(separator: " | "),
            "toolbar": ed.controller.toolbar.glassDiagnostic
        ]
        print("[glass-diagnostic] " + runtime.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: " "))
        save(["compactWidth": String(Int(ed.blockActionsView.frame.width)), "selectButtonWorked": selectedByButton ? "yes" : "no", "selectedBlock": selectedBlock,
              "nativeGlassAvailable": ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 26 ? "yes" : "no",
              "reduceTransparency": NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency ? "yes" : "no",
              "textSelectionBarVisible": ed.controller.toolbar.isVisible ? "yes" : "no", "blockBarHiddenOnText": ed.blockActionsView.alphaValue < 0.1 ? "yes" : "no",
              "glassDiagnostic": runtime.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: "\n")], "block-actions-checks.json")
    }

    /// `DRAFT_AUTOMATION=effects-shots`: Accent and Glow on a heading, a wrapped paragraph and list
    /// items, applied through the same controller calls the Assistant uses, on light and dark pages.
    static func effectsShots() async {
        guard let w = NSApp.windows.first(where: { $0.isVisible }), let id = m.createDoc(title: "Effects preview") else { return }
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
        w.setFrame(NSRect(x: 60, y: 60, width: 1120, height: 900), display: true)
        await wait(0.3)
        func shot(_ name: String) async { await wait(0.7); await captureWindow(w, name) }
        guard let ed = m.editors[id] else { return }
        ed.focusBody(atStart: true)
        let c = ed.controller
        c.pastePlainForAutomation("## Accent heading\nAn accent paragraph that is long enough to wrap onto a second line, so the underline placement on wrapped text is visible here.\n## Glow heading\nA glowing paragraph that is long enough to wrap onto a second line, so the halo has to follow a taller block without a box.\n- Accent list item\n- Glow list item\nPlain closing paragraph.")
        let text = c.textView.string as NSString
        for (phrase, deco) in [("Accent heading", "accent"), ("An accent paragraph", "accent"), ("Glow heading", "glow"), ("A glowing paragraph", "glow"), ("Accent list item", "accent"), ("Glow list item", "glow")] {
            c.textView.setSelectedRange(NSRange(location: text.range(of: phrase).location, length: 0))
            c.setDecoration(deco)
        }
        c.textView.setSelectedRange(NSRange(location: text.length, length: 0))
        m.setSettings { $0.theme = "light" }
        await shot("effects-light")
        m.updateAppearance(id) { $0.styleId = "nightink" }
        await shot("effects-dark-page")
        m.flushAll()
        let decos = c.document().content?.map { $0.attrs?["decoration"]?.string ?? "-" }.joined(separator: ",") ?? ""
        save(["decorations": decos], "effects-checks.json")
    }

    static func polish() async {
        guard let w = NSApp.windows.first(where: { $0.isVisible }) else { return }
        var checks: [String: String] = [:]
        checks["windows"] = NSApp.windows.map { "\(Swift.type(of: $0)) vis=\($0.isVisible) tb=\($0.toolbar != nil) style=\($0.toolbarStyle.rawValue) full=\($0.styleMask.contains(.fullSizeContentView)) \($0.frame)" }.joined(separator: " | ")
        guard let welcome = m.library.docs.values.first(where: { $0.title == "Welcome to Draft" }) else { return }
        for theme in ["light", "dark"] {
            m.setSettings { $0.theme = theme }
            for (width, height, tag) in [(1440.0, 900.0, ""), (720.0, 640.0, "narrow-")] {
                w.setFrame(NSRect(x: 60, y: 60, width: width, height: height), display: true)
                for collapsed in [false, true] where !(tag == "narrow-" && collapsed) {
                    m.setSettings { $0.railCollapsed = collapsed }
                    m.openView(.doc(welcome.id)); await wait(0.5)
                    await capture("\(tag)\(theme)-\(collapsed ? "rail-hidden" : "rail")-window")
                    if let b = w.standardWindowButton(.closeButton), let z = w.standardWindowButton(.zoomButton) {
                        let f = b.convert(b.bounds, to: nil), fz = z.convert(z.bounds, to: nil)
                        checks["\(tag)\(theme)-\(collapsed ? "hidden" : "rail").buttons"] = "x=\(Int(f.minX)) top=\(Int(w.frame.height - f.maxY)) right=\(Int(fz.maxX))"
                    }
                }
            }
        }
        m.setSettings { $0.theme = "light"; $0.railCollapsed = false }
        // The tab strip shares the title-bar band: clicks there must reach the tabs, not the title bar.
        w.setFrame(NSRect(x: 60, y: 60, width: 1440, height: 900), display: true)
        await wait(0.5)
        if let frame = w.contentView?.superview {
            let hits = [420.0, 600.0, 900.0].map { x -> String in
                let v = frame.hitTest(NSPoint(x: x, y: w.frame.height - 26))
                return String(describing: Swift.type(of: v ?? NSView()))
            }
            checks["tabStripHits"] = hits.joined(separator: ",")
        }
        w.setFrame(NSRect(x: 60, y: 60, width: 1440, height: 900), display: true)
        m.openView(.doc(welcome.id)); await wait(0.5)
        if let c = m.editors[welcome.id]?.controller {
            w.makeFirstResponder(c.textView)
            let s = c.textView.string as NSString
            c.textView.setSelectedRange(s.range(of: "Style never changes your content"))
            c.toolbar.update(); await capture("light-selection-bar")
            m.setSettings { $0.theme = "dark" }; await wait(0.3); c.toolbar.update(); await capture("dark-selection-bar")
            m.setSettings { $0.theme = "light" }
            m.updateAppearance(welcome.id) { $0.styleId = "nightink" }; await wait(0.3); c.toolbar.update(); await capture("nightink-selection-bar")
            m.updateAppearance(welcome.id) { $0.styleId = "paper" }
            checks["toolbarFrame"] = "\(c.toolbar.presentationView.frame)"
        }
        save(checks, "polish-checks.json")
    }
}
