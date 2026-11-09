import AppKit
import SwiftUI
import DraftCore

/// `backgrounds-shots`: every background preset on a sample note, the Style Gallery, and an HTML
/// export of a field background. AUDIT_DARK / AUDIT_NARROW as in audit-shots.
extension Automation {
    static func backgroundShots() async {
        guard let w = NSApp.windows.first(where: { $0.isVisible }) else { return }
        let env = ProcessInfo.processInfo.environment
        let narrow = env["AUDIT_NARROW"] != nil, dark = env["AUDIT_DARK"] != nil
        let p = (narrow ? "narrow-" : "") + (dark ? "dark-" : "")
        w.setFrame(NSRect(x: 40, y: 40, width: narrow ? 760 : 1440, height: narrow ? 720 : 900), display: true)
        m.setSettings { $0.theme = dark ? "dark" : "light" }
        var r: [String: String] = [:]
        defer { if let d = try? JSONSerialization.data(withJSONObject: r, options: [.prettyPrinted, .sortedKeys]) { try? d.write(to: out.appendingPathComponent(p + "backgrounds.json")) } }
        guard let id = m.createDoc(title: "Photosynthesis — study notes") else { return }
        let c = m.editor(for: id).controller
        c.pastePlainForAutomation("## Light reactions\nWater is split and oxygen released; ATP and NADPH are made in the thylakoids.\n- [ ] Learn the Z-scheme\n- Compare C3 and C4 plants\n> Light is the energy source; carbon comes from the air.\n## Calvin cycle\nCarbon dioxide is fixed into sugars in the stroma.")
        await wait(0.5)
        for s in Backgrounds.presets {
            m.updateAppearance(id) { $0.styleId = s.id; $0.overrides = StyleOverrides() }
            await shot(p + "bg-" + s.id, w, settle: 0.6)
        }
        m.styleGallery = true; await shot(p + "style-gallery", w, settle: 0.8); m.styleGallery = false
        m.panel = .style; await shot(p + "style-panel", w, settle: 0.7); m.panel = nil
        if !narrow, !dark {
            let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
            m.updateAppearance(id) { $0.styleId = "midnight-constellation" }
            if let res = try? m.writeHTML(id, useStyle: true, parent: tmp, name: "export") {
                let html = (try? String(contentsOf: res.html, encoding: .utf8)) ?? ""
                r["exportHasBackdrop"] = FileManager.default.fileExists(atPath: res.folder.appendingPathComponent("backdrop.png").path) && html.contains("backdrop.png") ? "yes" : "no"
                r["exportPageColor"] = html.contains("#181c35") ? "yes" : "no"
            }
        }
        r["presets"] = "\(Backgrounds.presets.count)"
        r["increaseContrast"] = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast ? "on" : "off"
        r["reduceTransparency"] = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency ? "on" : "off"
        for id in ["apricot-grid", "midnight-constellation", "soft-sunrise", "sea-glass"] {
            if let data = m.sceneImage(Styles.style(id).tokens.backdrop) { try? data.write(to: out.appendingPathComponent("render-\(id).png")) }
        }
        m.flushAll()
        r["persisted"] = (try? m.vault.loadDoc(id))?.appearance.styleId ?? ""
    }
}
