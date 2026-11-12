import AppKit
import DraftCore

/// `search-perf`: a 10,000-block note plus a few small ones; search index rebuilt from disk (timed),
/// a set of queries (phrase, regex, tag, date, link, exclusion) timed and saved with their results,
/// and the results screen captured. `search-read` (after relaunch, same vault) runs the same queries
/// and compares. AUDIT_DARK / AUDIT_NARROW for the capture.
extension Automation {
    static let searchQueries = ["\"Paragraph 7771:\"", "lisbon -tram", "/Task 1\\d{3}$/", "#travel", "date:2026-12", "tram in:title", "link:Work log", "budget"]

    static func searchResults() -> [String: [String]] {
        var out: [String: [String]] = [:]
        for q in searchQueries { m.librarySearch = q; out[q] = m.searchHits.map { $0.meta.title + "|" + $0.blocks.map(\.id).joined(separator: ",") } }
        return out
    }

    static func searchPerf() async {
        guard let w = NSApp.windows.first(where: { $0.isVisible }) else { return }
        let env = ProcessInfo.processInfo.environment
        let narrow = env["AUDIT_NARROW"] != nil, dark = env["AUDIT_DARK"] != nil
        let p = (narrow ? "narrow-" : "") + (dark ? "dark-" : "")
        w.setFrame(NSRect(x: 40, y: 40, width: narrow ? 720 : 1280, height: narrow ? 700 : 900), display: true)
        m.setSettings { $0.theme = dark ? "dark" : "light" }
        var r: [String: Any] = [:]
        _ = bigDocId(10_000, title: "Ten thousand blocks")
        func add(_ title: String, _ blocks: [Node]) -> String {
            let id = newId("d_"); var d = DocFile.empty(id: id, title: title); d.content = ensureBlockIds(Node("doc", content: blocks)); try? m.vault.saveDoc(d)
            var meta = DocMeta(id: id); meta.applyDerived(from: d); meta.spaceId = m.library.space.id; m.library.docs[id] = meta; return id
        }
        func para(_ t: String, _ marks: [Mark]? = nil) -> Node { Node("paragraph", content: [.text(t, marks: marks)]) }
        let work = add("Work log", [para("Shipped the release candidate #work"), para("Budget review moved"), Node("paragraph", content: [.text("Deadline "), .text("12 Dec", marks: [Mark("date", attrs: ["date": "2026-12-12"])])])])
        _ = add("Trip to Lisbon", [para("We fly to Lisbon on Monday #travel"), para("Budget: 900 euros"), para("Lisbon trams at night"), para("See the log", [Mark("docLink", attrs: ["docId": .string(work)])])])
        _ = add("Tram photos", [para("Lisbon tram photos for a zine #travel")])
        m.scheduleLibrarySave(); m.flushAll()
        try? FileManager.default.removeItem(at: m.vault.searchIndexURL)
        var t0 = CFAbsoluteTimeGetCurrent()
        m.searchIndex = SearchIndex(); m.refreshIndex()
        r["rebuildMs"] = ms(t0)
        m.vault.drain(); r["indexFileExists"] = FileManager.default.fileExists(atPath: m.vault.searchIndexURL.path)
        m.flushAll()
        var times: [Double] = []
        for _ in 0..<3 { for q in searchQueries { m.librarySearch = q; t0 = CFAbsoluteTimeGetCurrent(); _ = m.searchHits; times.append(ms(t0)) } }
        r["queryMs"] = stats(times)
        r["results"] = searchResults()
        m.openView(.all)
        m.librarySearchOpen = true
        m.librarySearch = "lisbon"
        await wait(0.8)
        await shot(p + "search-results", w)
        m.librarySearch = "#travel"
        await wait(0.5)
        await shot(p + "search-results-tag", w)
        m.librarySearch = ""
        m.flushAll()
        if let d = try? JSONSerialization.data(withJSONObject: r, options: [.prettyPrinted, .sortedKeys]) { try? d.write(to: out.appendingPathComponent(p + "search-perf.json")) }
    }

    static func searchRead() async {
        var r: [String: Any] = [:]
        r["results"] = searchResults()
        m.librarySearch = ""
        if let d = try? JSONSerialization.data(withJSONObject: r, options: [.prettyPrinted, .sortedKeys]) { try? d.write(to: out.appendingPathComponent("search-read.json")) }
    }
}
