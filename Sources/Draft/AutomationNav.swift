import AppKit
import DraftCore

/// `nav-test`: tab navigation with real clicks on the tab strip. A document tab must activate from
/// a folder, All Docs, Settings, Calendar, Tasks, Recently Deleted, another document and a nested
/// page, keeping unsaved text, scroll and caret, without duplicate tabs.
extension Automation {
    static func navTest() async {
        guard let w = NSApp.windows.first(where: { $0.isVisible }) else { return }
        w.setFrame(NSRect(x: 60, y: 60, width: 1280, height: 820), display: true)
        var r: [String: String] = [:]
        defer { if let d = try? JSONSerialization.data(withJSONObject: r, options: [.prettyPrinted, .sortedKeys]) { try? d.write(to: out.appendingPathComponent("nav-test.json")) } }
        guard let a = m.createDoc(title: "Finance k maturitě"), let b = m.createDoc(title: "Second note") else { return }
        let ca = m.editor(for: a).controller
        m.openView(.doc(a)); await wait(0.6)
        ca.pastePlainForAutomation((1...120).map { "Line \($0) of the finance note." }.joined(separator: "\n"))
        await wait(0.3)
        let caret = NSRange(location: 900, length: 0)
        ca.textView.setSelectedRange(caret)
        ca.textView.scrollRangeToVisible(caret); await wait(0.3)
        let scrollY = m.editors[a]!.scrollView.contentView.bounds.origin.y
        ca.textView.insertText(" UNSAVED", replacementRange: ca.textView.selectedRange()) // not yet flushed
        let caretAfter = ca.textView.selectedRange()
        let docTab = m.activeTab.id
        let tabCount = { m.tabs.count }
        await shot("nav-0-doc", w, settle: 0.4)
        r["tabCentersFound"] = "\(tabCenters().count) of \(m.tabs.count)"

        func clickTab(_ id: String) async {
            // Tab items sit in the tab strip; find this one's frame through the strip's order.
            guard let i = m.tabs.firstIndex(where: { $0.id == id }) else { return }
            if let p = tabCenters()[safe: i] { await click(p, w) }
            await wait(0.6)
        }
        func check(_ name: String) async {
            await shot("nav-\(name)", w, settle: 0.3)
            let e = m.editors[a]
            let ok = m.activeTab.id == docTab && m.activeDocId == a
                && e?.controller.textView.string.contains("UNSAVED") == true
                && e?.controller.textView.selectedRange() == caretAfter
                && abs((e?.scrollView.contentView.bounds.origin.y ?? -1) - scrollY) < 2
            r[name] = ok ? "ok" : "FAIL active=\(m.activeTab.view.kind)/\(m.activeDocId ?? "-") sel=\(e?.controller.textView.selectedRange().location ?? -1) y=\(Int(e?.scrollView.contentView.bounds.origin.y ?? -1))/\(Int(scrollY))"
        }

        // Probe: in a folder view, do a title-bar button (+) and a content button (List view) respond?
        m.openView(ViewRef(kind: "unsorted")); await wait(0.6)
        let docsBefore = m.library.docs.count
        if let p = center(of: "New document (⌘N)") { r["probePlusAt"] = "\(Int(p.x)),\(Int(p.y))"; await click(p, w); await wait(0.6) }
        r["probePlusWorked"] = m.library.docs.count > docsBefore ? "yes" : "no"
        m.openView(ViewRef(kind: "unsorted")); await wait(0.6)
        m.openView(ViewRef(kind: "unsorted")); await wait(0.8)
        await click(NSPoint(x: 434, y: 514), w); await wait(0.8)
        r["probeCardWorked"] = m.activeTab.view.kind == "doc" ? "yes (\(m.activeTab.view.docId ?? ""))" : "no (\(m.activeTab.view.kind))"
        m.openView(.doc(a)); await wait(0.6)

        let starts: [(String, () -> Void)] = [
            ("folder", { m.openView(ViewRef(kind: "unsorted")) }),
            ("all", { m.activateTab(m.tabs[0].id) }),
            ("settings", { m.openView(ViewRef(kind: "settings", section: "appearance")) }),
            ("calendar", { m.openView(ViewRef(kind: "calendar")) }),
            ("tasks", { m.openView(ViewRef(kind: "tasks")) }),
            ("trash", { m.openView(ViewRef(kind: "trash")) }),
            ("quickopen", { m.quickOpen = true }),
            ("otherdoc", { m.openView(.doc(b)) }),
            ("nested", { if let child = m.createDoc(parentDocId: b, open: false, title: "Nested page") { m.openView(.doc(child)) } }),
        ]
        for (name, go) in starts {
            go(); await wait(0.6)
            let before = tabCount()
            if name == "quickopen" { m.quickOpen = false; await wait(0.2) }
            await clickTab(docTab)
            await check(name)
            r[name + "Tabs"] = tabCount() == before ? "same" : "changed \(before)→\(tabCount())"
        }
        r["docTabs"] = "\(m.tabs.filter { $0.view.docId == a }.count)"
        r["breadcrumb"] = m.folderName(m.library.docs[a]?.folderId)
        r["textKept"] = m.editors[a]?.controller.textView.string.contains("UNSAVED") == true ? "yes" : "no"
        r["backAvailable"] = m.canGoBack ? "yes" : "no"
        // A tab whose note went to Recently Deleted shows a clear state with Restore.
        for t in m.tabs.dropFirst() where t.view.docId != a && t.view.docId != b { m.closeTab(t.id) }
        m.openView(.doc(b)); await wait(0.5)
        let bTab = m.activeTab.id
        _ = m.library.trash(b); m.activateTab(m.tabs[0].id); await wait(0.4)
        await clickTab(bTab); await shot("nav-deleted", w, settle: 0.4)
        r["deletedTabState"] = m.activeTab.id == bTab && m.library.docs[b]?.deletedAt != nil ? "shown" : "FAIL"

    }

    static func center(of label: String) -> NSPoint? {
        guard let w = NSApp.windows.first(where: { $0.isVisible }), let content = w.contentView else { return nil }
        var found: NSPoint?
        func visit(_ e: Any, depth: Int) {
            guard depth < 40, found == nil else { return }
            if let o = e as? NSObject, let l = o.value(forKey: "accessibilityLabel") as? String, l == label, let f = o.value(forKey: "accessibilityFrame") as? NSRect {
                found = w.convertPoint(fromScreen: NSPoint(x: f.midX, y: f.midY)); return
            }
            for c in ((e as? NSObject)?.value(forKey: "accessibilityChildren") as? [Any]) ?? [] { visit(c, depth: depth + 1) }
        }
        visit(content, depth: 0)
        return found
    }

    /// Centres of the tab items in window coordinates, left to right.
    static func tabCenters() -> [NSPoint] {
        guard let w = NSApp.windows.first(where: { $0.isVisible }), let content = w.contentView else { return [] }
        // SwiftUI exposes the tab buttons to accessibility as "Tab <title>" elements.
        var out: [(CGFloat, NSPoint)] = []
        func visit(_ e: Any, depth: Int) {
            guard depth < 40 else { return }
            if let el = e as? NSAccessibilityElementProtocol, let label = (el as? NSObject)?.value(forKey: "accessibilityLabel") as? String, label.hasPrefix("Tab ") {
                let f = (el as? NSObject)?.value(forKey: "accessibilityFrame") as? NSRect ?? .zero
                let p = w.convertPoint(fromScreen: NSPoint(x: f.midX, y: f.midY))
                out.append((p.x, p))
            }
            for c in ((e as? NSObject)?.value(forKey: "accessibilityChildren") as? [Any]) ?? [] { visit(c, depth: depth + 1) }
        }
        visit(content, depth: 0)
        return out.sorted { $0.0 < $1.0 }.map(\.1)
    }
}

extension Array { subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil } }
