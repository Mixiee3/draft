import AppKit
import DraftCore
import DraftEditor

/// `presets-shots`: every text preset on its own line (its name, styled with it) and every block
/// preset as a block, captured page by page; AUDIT_DARK for dark mode.
extension Automation {
    static func presetsShots() async {
        guard let w = NSApp.windows.first(where: { $0.isVisible }) else { return }
        let dark = ProcessInfo.processInfo.environment["AUDIT_DARK"] != nil
        let p = dark ? "dark-" : ""
        w.setFrame(NSRect(x: 40, y: 40, width: 1280, height: 900), display: true)
        m.setSettings { $0.theme = dark ? "dark" : "light" }
        guard let id = m.createDoc(title: "Presets") else { return }
        var blocks: [Node] = []
        var n = 0
        for kind in ["spectrum", "gradient", "glow", "shadow", "outline", "lift", "emboss", "accent"] {
            blocks.append(Node("heading", attrs: ["id": .string("b_h_\(kind)"), "level": 3], content: [.text(kind.capitalized)]))
            for pr in EffectPresets.text(for: kind) {
                n += 1
                blocks.append(Node("paragraph", attrs: ["id": .string("b_\(n)")], content: [.text(pr.name, marks: [EffectSpec(pr.value)!.mark]), .text("  · \(pr.group)")]))
            }
        }
        blocks.append(Node("heading", attrs: ["id": "b_h_blocks", "level": 3], content: [.text("Blocks")]))
        for pr in EffectPresets.blocks {
            n += 1
            let parts = pr.value.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
            var attrs: [String: JSONValue] = ["id": .string("b_\(n)"), "decoration": .string(parts[0])]
            if !parts[1].isEmpty { attrs["blockColor"] = .string(parts[1]) }
            blocks.append(Node("paragraph", attrs: attrs, content: [.text("\(pr.name) · \(pr.group)")]))
        }
        let c = m.editor(for: id).controller
        c.load(Node("doc", content: blocks)); m.editorChanged(id)
        m.openView(.doc(id)); await wait(0.8)
        let sv = m.editors[id]!.scrollView
        var page = 0, y: CGFloat = 0
        let docH = sv.documentView?.frame.height ?? 0
        repeat {
            sv.contentView.scroll(to: NSPoint(x: 0, y: y)); sv.reflectScrolledClipView(sv.contentView); await wait(0.5)
            await shot(p + "presets-\(page + 1)", w, settle: 0.1)
            page += 1; y += sv.contentView.bounds.height - 80
        } while y < docH && page < 12
        m.flushAll()
    }
}
