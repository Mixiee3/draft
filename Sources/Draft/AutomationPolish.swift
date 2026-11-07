import AppKit
import DraftCore
import DraftEditor

/// `DRAFT_AUTOMATION=polish`: window chrome, cursor states and the selection bar, before/after.
extension Automation {
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
            checks["toolbarFrame"] = "\(c.toolbar.frame)"
        }
        save(checks, "polish-checks.json")
    }
}
