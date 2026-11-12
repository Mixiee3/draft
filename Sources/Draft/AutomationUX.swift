import AppKit
import SwiftUI
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
        m.openView(.doc(ids[0])); r["docOpenModelMs"] = ms(t0); await drawn(w); r["docOpenFromLibraryMs"] = ms(t0)
        if ProcessInfo.processInfo.environment["DRAFT_UX_OPENLOOP"] != nil {
            for _ in 0..<60 { m.closeTab(m.activeTab.id); m.openView(.all); await drawn(w); m.dropEditor(ids[0]); m.docs[ids[0]] = nil; m.openView(.doc(ids[0])); await drawn(w) }
        }

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

        // Panels and sheets: 5 opens each. The first is cold (first build of the view); the budget is
        // checked on the warm median. Phases split our own state change and run-loop wait (automation
        // overhead) from SwiftUI's update, layout and drawing.
        var panels: [String: Double] = [:], cold: [String: Double] = [:], phasesBy: [String: [String: Double]] = [:]
        let proposal = try? JSONDecoder().decode(AgentProposal.self, from: Data("""
            {"id": "p_perf", "documentId": "\(ids[0])", "documentTitle": "Notes 0", "instruction": "Tidy the headings", "expectedRevision": "x",
             "edits": [{"action": "heading", "blockId": "b_none", "value": "heading"}], "createdAt": 0, "status": "pending"}
            """.utf8))
        let surfaces: [(String, () -> Void, () -> Void)] = [
            ("format", { m.panel = .format }, { m.panel = nil }), ("style", { m.panel = .style }, { m.panel = nil }),
            ("info", { m.panel = .info }, { m.panel = nil }), ("share", { m.panel = .share }, { m.panel = nil }),
            ("versionHistory", { m.recovery.historyDoc = HistoryTarget(id: ids[0]) }, { m.recovery.historyDoc = nil }),
            ("assistant", { m.toggleAssistant() }, { m.toggleAssistant() }),
            ("reviewSheet", { m.agentProposal = proposal }, { m.agentProposal = nil }),
            ("recovery", { m.openView(ViewRef(kind: "settings", section: "recovery")) }, { m.openView(.doc(ids[0])) }),
        ]
        for (name, open, close) in surfaces {
            var samples: [Double] = []
            var ph: [String: [Double]] = ["model": [], "update": [], "layout": [], "draw": []]
            for _ in 0..<5 {
                var t = CFAbsoluteTimeGetCurrent(); let start = t
                open(); ph["model"]!.append(ms(t))
                t = CFAbsoluteTimeGetCurrent(); await settle(); ph["update"]!.append(ms(t))
                t = CFAbsoluteTimeGetCurrent(); w.contentView?.layoutSubtreeIfNeeded(); for s in [w.attachedSheet].compactMap({ $0 }) { s.contentView?.layoutSubtreeIfNeeded() }; ph["layout"]!.append(ms(t))
                t = CFAbsoluteTimeGetCurrent(); w.displayIfNeeded(); w.attachedSheet?.displayIfNeeded(); ph["draw"]!.append(ms(t))
                samples.append(ms(start))
                close(); await drawn(w); await wait(0.15)
            }
            cold[name] = samples[0]
            let warm = Array(samples.dropFirst()).sorted()
            panels[name] = warm[warm.count / 2]
            phasesBy[name] = ph.mapValues { xs in xs.dropFirst().sorted()[xs.count / 2 - 1] }
        }
        // The sheets' own SwiftUI cost without AppKit's slide-in animation: hosted offscreen, laid out and drawn.
        let tokens = Tokens.make(dark: false, accent: m.library.settings.accent, tint: nil)
        var sheetRender: [String: Double] = [:]
        for (name, view) in [("versionHistory", AnyView(VersionHistoryView(docId: ids[0]))), ("reviewSheet", AnyView(proposal.map { AgentProposalReview(proposal: $0) }))] {
            var xs: [Double] = []
            for _ in 0..<5 {
                let t = CFAbsoluteTimeGetCurrent()
                let host = NSHostingView(rootView: view.environment(m).environment(\.tokens, tokens))
                host.frame = NSRect(x: 0, y: 0, width: 960, height: 680)
                host.layoutSubtreeIfNeeded()
                let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
                host.cacheDisplay(in: host.bounds, to: rep)
                xs.append(ms(t))
            }
            sheetRender[name] = xs.sorted()[2]
        }
        r["sheetRenderMs"] = sheetRender
        r["panelOpenMs"] = panels
        r["panelOpenColdMs"] = cold
        r["panelPhasesMs"] = phasesBy

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
