import AppKit
import DraftCore
import DraftEditor

/// `DRAFT_AUTOMATION=ux-perf`: tab and Space switching, opening from the library, scrolling and
/// panels, each timed until the window has laid out and drawn. `idle` keeps a document open for
/// `DRAFT_IDLE_SECONDS` so CPU and GPU can be sampled from outside.
extension Automation {
    static func drawn(_ w: NSWindow) async { await settle(); w.contentView?.layoutSubtreeIfNeeded(); w.displayIfNeeded() }

    static func uxPerf() async {
        guard let w = NSApp.windows.first(where: { $0.isVisible }) else { return }
        w.setFrame(NSRect(x: 60, y: 60, width: 1440, height: 900), display: true)
        var r: [String: Any] = [:]
        var ids: [String] = []
        for i in 0..<6 {
            let id = newId("d_")
            var doc = DocFile.empty(id: id, title: "Notes \(i)")
            doc.content = bigDoc(i == 0 ? 2000 : 200)
            try? m.vault.saveDoc(doc)
            var meta = DocMeta(id: id); meta.applyDerived(from: doc); meta.spaceId = m.library.space.id
            m.library.docs[id] = meta
            ids.append(id)
        }
        for id in ids.dropFirst() { m.openView(.doc(id), newTab: true); await drawn(w) }

        var t0 = CFAbsoluteTimeGetCurrent()
        m.openView(.all); await drawn(w); r["libraryOpenMs"] = ms(t0)
        t0 = CFAbsoluteTimeGetCurrent()
        m.openView(.doc(ids[0])); await drawn(w); r["docOpenFromLibraryMs"] = ms(t0)

        var tabs: [Double] = []
        let tabIds = m.tabs.map(\.id)
        if ProcessInfo.processInfo.environment["DRAFT_UX_TABLOOP"] != nil { for k in 0..<300 { m.activateTab(tabIds[k % tabIds.count]); await drawn(w) } }
        for k in 0..<12 { t0 = CFAbsoluteTimeGetCurrent(); m.activateTab(tabIds[k % tabIds.count]); await drawn(w); tabs.append(ms(t0)) }
        r["tabSwitchMs"] = stats(tabs)
        var phases: [String: [Double]] = ["model": [], "update": [], "layout": [], "draw": []]
        for k in 0..<12 {
            var t = CFAbsoluteTimeGetCurrent(); m.activateTab(tabIds[k % tabIds.count]); phases["model"]!.append(ms(t))
            t = CFAbsoluteTimeGetCurrent(); await settle(); phases["update"]!.append(ms(t))
            t = CFAbsoluteTimeGetCurrent(); w.contentView?.layoutSubtreeIfNeeded(); phases["layout"]!.append(ms(t))
            t = CFAbsoluteTimeGetCurrent(); w.displayIfNeeded(); phases["draw"]!.append(ms(t))
        }
        r["tabSwitchPhasesMs"] = phases.mapValues { stats($0) }

        m.openView(.doc(ids[0])); await drawn(w)
        if let sv = m.editors[ids[0]]?.scrollView {
            r["scrollDebug"] = "doc \(Int(sv.documentView?.frame.height ?? -1)) clip \(Int(sv.contentView.bounds.height)) inWindow \(sv.window != nil)"
            var steps: [Double] = []
            for k in 1...120 {
                t0 = CFAbsoluteTimeGetCurrent()
                sv.contentView.scroll(to: NSPoint(x: 0, y: CGFloat(k) * 40))
                sv.reflectScrolledClipView(sv.contentView)
                w.contentView?.layoutSubtreeIfNeeded()
                if let tv = m.editors[ids[0]]?.controller.textView { tv.setNeedsDisplay(tv.visibleRect); tv.displayIfNeeded() }
                steps.append(ms(t0))
            }
            r["docScrollMs"] = stats(steps)
        }

        var panels: [String: Double] = [:]
        for p in [Panel.format, .style, .info, .share] {
            t0 = CFAbsoluteTimeGetCurrent(); m.panel = p; await drawn(w); panels[p.rawValue] = ms(t0)
            m.panel = nil; await drawn(w)
        }
        r["panelOpenMs"] = panels

        let first = m.library.space.id
        m.createSpace("Second"); await drawn(w)
        let second = m.library.space.id
        var spaces: [Double] = []
        for k in 0..<6 { t0 = CFAbsoluteTimeGetCurrent(); m.switchSpace(k % 2 == 0 ? first : second); await drawn(w); spaces.append(ms(t0)) }
        r["spaceSwitchMs"] = stats(spaces)
        m.switchSpace(first)
        m.flushAll()
        if let d = try? JSONSerialization.data(withJSONObject: r, options: [.prettyPrinted, .sortedKeys]) { try? d.write(to: out.appendingPathComponent("ux-perf.json")) }
    }

    static func idle() async {
        guard let w = NSApp.windows.first(where: { $0.isVisible }) else { return }
        w.setFrame(NSRect(x: 60, y: 60, width: 1440, height: 900), display: true)
        if let id = m.createDoc(title: "Idle") { m.openView(.doc(id)) }
        let secs = Double(ProcessInfo.processInfo.environment["DRAFT_IDLE_SECONDS"] ?? "20") ?? 20
        try? await Task.sleep(nanoseconds: UInt64(secs * 1e9))
    }
}
