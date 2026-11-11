import AppKit
import SwiftUI
import DraftCore

/// `styling-shots`: the gradient editor, text and block effects and the selection menu on a sample
/// note. AUDIT_DARK / AUDIT_NARROW as in audit-shots.
extension Automation {
    static func stylingShots() async {
        guard let w = NSApp.windows.first(where: { $0.isVisible }) else { return }
        let env = ProcessInfo.processInfo.environment
        let narrow = env["AUDIT_NARROW"] != nil, dark = env["AUDIT_DARK"] != nil
        let p = (narrow ? "narrow-" : "") + (dark ? "dark-" : "")
        w.setFrame(NSRect(x: 40, y: 40, width: narrow ? 760 : 1440, height: narrow ? 720 : 900), display: true)
        m.setSettings { $0.theme = dark ? "dark" : "light" }
        var r: [String: String] = [:]
        defer { if let d = try? JSONSerialization.data(withJSONObject: r, options: [.prettyPrinted, .sortedKeys]) { try? d.write(to: out.appendingPathComponent(p + "styling.json")) } }
        guard let id = m.createDoc(title: "Photosynthesis — study notes") else { return }
        m.editor(for: id).controller.pastePlainForAutomation("## Light reactions\nWater is split and oxygen released; ATP and NADPH are made in the thylakoids.\n- [ ] Learn the Z-scheme\n> Light is the energy source; carbon comes from the air.\n## Calvin cycle\nCarbon dioxide is fixed into sugars in the stroma.")
        m.updateAppearance(id) { $0.styleId = "quiet-lavender" }
        await wait(0.5)

        // Gradient editor: three stops, radial, then one drag of edits = one Undo step.
        m.updateAppearance(id) { $0.overrides.backdrop = { var b = Styles.style("quiet-lavender").tokens.backdrop; b.addStop(); b.radial = true; b.focusX = 0.3; b.focusY = 0.2; return b }() }
        await shotPanel(p + "gradient-editor", w, size: NSSize(width: 290, height: 640), dark: dark) { BackdropPicker(docId: id) }
        await wait(1.1) // a new drag, not a continuation of the change above
        let before = m.docs[id]?.appearance
        for a in stride(from: 0.0, through: 0.6, by: 0.1) { m.updateAppearance(id) { $0.overrides.backdrop?.updateStop(1) { $0.at = a } } }
        m.editor(for: id).controller.undo.undo()
        await wait(0.3)
        r["gradientDragIsOneUndo"] = m.docs[id]?.appearance == before ? "yes" : "no"
        m.flushAll()
        r["gradientPersisted"] = (try? m.vault.loadDoc(id))?.appearance.overrides.backdrop?.stops?.count == 4 ? "yes" : "no"
        m.updateAppearance(id) { $0.overrides.backdrop = nil }

        // Text effects on a few phrases, then the selection menu with its effects row.
        let c = m.editor(for: id).controller
        let fx: [(String, String)] = [("Light reactions", "gradient"), ("ATP and NADPH", "accent"), ("thylakoids", "glow"), ("Calvin cycle", "lift"), ("stroma", "shadow"), ("Learn the Z-scheme", "emboss"), ("energy source", "outline")]
        for (phrase, k) in fx { c.textView.setSelectedRange((c.textView.string as NSString).range(of: phrase)); c.setEffect(k) }
        c.textView.setSelectedRange(NSRange(location: 0, length: 0))
        await shot(p + "text-effects", w, settle: 0.6)
        c.textView.setSelectedRange((c.textView.string as NSString).range(of: "Carbon dioxide"))
        await shot(p + "selection-menu", w, settle: 0.7)
        c.toolbar.setMode(.effects)
        await shot(p + "selection-menu-effects", w, settle: 0.5)
        r["selectionKeptInEffects"] = c.textView.selectedRange() == (c.textView.string as NSString).range(of: "Carbon dioxide") ? "yes" : "no"
        c.toolbar.setMode(.palette)
        await shot(p + "selection-menu-colors", w, settle: 0.5)
        c.toolbar.setMode(.main)
        // Block effects, one per block, with the Format panel open.
        if let bid = m.createDoc(title: "Block effects") {
            let bc = m.editor(for: bid).controller
            bc.pastePlainForAutomation("## Key ideas\nFocus: the one paragraph to remember.\nBlock: a quiet tinted box.\nGradient: a soft wash for a summary.\nGlass: a frosted aside on a field backdrop.\nGlow: a single decision or warning.\nAccent: an outlined definition.")
            await wait(0.4)
            let ns = bc.textView.string as NSString
            for (phrase, k) in [("Key ideas", "accent"), ("Focus:", "focus"), ("Block:", "block"), ("Gradient:", "gradient"), ("Glass:", "glass"), ("Glow:", "glow"), ("Accent:", "accent")] {
                bc.textView.setSelectedRange(NSRange(location: ns.range(of: phrase).location, length: 0)); bc.setDecoration(k)
            }
            m.updateAppearance(bid) { $0.styleId = "sea-glass" }
            bc.textView.setSelectedRange(NSRange(location: ns.range(of: "Glass:").location, length: 0))
            m.panel = .format
            await shot(p + "block-effects", w, settle: 0.8)
            m.panel = nil
            m.flushAll()
            r["blockEffectsPersisted"] = "\((try? m.vault.loadDoc(bid))?.content.content?.compactMap { $0.attrs?["decoration"]?.string }.count ?? 0)"
        }
        m.flushAll()
        r["effectsPersisted"] = "\((try? m.vault.loadDoc(id)).flatMap { try? JSONEncoder().encode($0.content) }.map { String(decoding: $0, as: UTF8.self).components(separatedBy: "\"effect\"").count - 1 } ?? 0)"
        r["increaseContrast"] = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast ? "on" : "off"
    }

    /// Hosts `content` in a window beside the document (popovers cannot be captured reliably).
    static func shotPanel<V: View>(_ name: String, _ w: NSWindow, size: NSSize, dark: Bool, @ViewBuilder _ content: () -> V) async {
        let tokens = Tokens.make(dark: dark, accent: m.library.settings.accent, tint: nil)
        let host = NSHostingView(rootView: content().environment(m).environment(\.tokens, tokens).preferredColorScheme(dark ? .dark : .light).background(tokens.card))
        let panel = NSPanel(contentRect: NSRect(x: w.frame.maxX - size.width - 30, y: w.frame.maxY - size.height - 90, width: size.width, height: size.height), styleMask: [.borderless], backing: .buffered, defer: false)
        panel.contentView = host; panel.level = .floating; panel.orderFrontRegardless()
        await shot(name, w, settle: 0.8)
        panel.orderOut(nil)
    }
}
