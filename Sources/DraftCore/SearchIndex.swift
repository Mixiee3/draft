import Foundation

/// The search index, kept apart from note rendering and from library.json: `index/search.json`.
/// One entry per note with the full text of every block, its tags, dates and links. Derived data:
/// building or rebuilding it only reads notes, and deleting it is always safe.
public struct SearchIndex: Codable, Sendable, Equatable {
    public static let version = 1
    public var version = SearchIndex.version
    public var rules = ""
    public var entries: [String: Entry] = [:]
    public init() {}

    public struct Entry: Codable, Sendable, Equatable {
        public var updatedAt: Double
        public var title: String
        public var blocks: [IndexedBlock]
        /// Lowercased tag → block ids.
        public var tags: [String: [String]]
        /// `yyyy-MM-dd` → block ids (date chips, task due dates; a daily note's own day under "").
        public var dates: [String: [String]]
        /// Linked note id → block ids.
        public var links: [String: [String]]
        public var daily: String?
    }

    public static func entry(for doc: DocFile, daily: String?, rules: TagRules) -> Entry {
        let e = VaultIndex.entry(for: doc, daily: daily, rules: rules, blockTextLimit: .max)
        var dates: [String: [String]] = [:]
        for t in e.tasks { if let d = t.due { dates[String(d.prefix(10)), default: []].append(t.block) } }
        func visit(_ n: Node, block: String?) {
            let b = ["listItem", "taskItem", "toggleItem"].contains(n.type) ? n.id : (block ?? n.id)
            n.marks?.forEach { m in if m.type == "date", let d = m.attrs?["date"]?.string { dates[String(d.prefix(10)), default: []].append(b ?? "") } }
            n.content?.forEach { visit($0, block: ["paragraph", "heading", "codeBlock"].contains(n.type) ? b : (["listItem", "taskItem", "toggleItem"].contains(n.type) ? n.id : nil)) }
        }
        visit(doc.content, block: nil)
        if let daily { dates[String(daily.prefix(10)), default: []].append("") }
        return Entry(updatedAt: doc.updatedAt, title: doc.title, blocks: e.blocks.filter { !$0.text.isEmpty },
                     tags: Dictionary(grouping: e.tags, by: { $0.tag.lowercased() }).mapValues { $0.map(\.block) },
                     dates: dates, links: Dictionary(grouping: e.links, by: \.doc).mapValues { $0.map(\.block) }, daily: daily)
    }

    /// Brings the index up to date: re-indexes notes whose entry is missing or older than the note
    /// (stale), drops notes that are gone. Returns how many were (re)indexed. Never writes a note.
    @discardableResult
    public mutating func refresh(docs: [String: DocMeta], rules r: TagRules, load: (String) -> DocFile?) -> Int {
        if version != SearchIndex.version || rules != r.key { entries = [:]; version = SearchIndex.version; rules = r.key }
        for id in entries.keys where docs[id] == nil { entries[id] = nil }
        var n = 0
        for (id, m) in docs where entries[id]?.updatedAt != m.updatedAt || entries[id]?.title != m.title {
            guard let d = load(id) else { continue }
            entries[id] = SearchIndex.entry(for: d, daily: m.dailyDate, rules: r)
            n += 1
        }
        return n
    }

    public mutating func update(_ doc: DocFile, daily: String?, rules: TagRules) {
        entries[doc.id] = SearchIndex.entry(for: doc, daily: daily, rules: rules)
    }

    /// Notes (from `docs`, in that order of preference) that match `q`, with the matching blocks.
    public func search(_ q: Search.Query, in docs: [DocMeta], blockLimit: Int = 5) -> [SearchHit] {
        guard !q.isEmpty else { return [] }
        let o = Search.options
        var out: [SearchHit] = []
        for m in docs {
            guard let e = entries[m.id] else { continue }
            // Filters first: cheap and narrowing.
            if !q.tags.allSatisfy({ e.tags[$0] != nil }) || q.excludeTags.contains(where: { e.tags[$0] != nil }) { continue }
            if !q.dates.allSatisfy({ d in e.dates.keys.contains { $0.hasPrefix(d) } }) { continue }
            if let b = q.before, !e.dates.keys.contains(where: { $0 < b }) { continue }
            if let a = q.after, !e.dates.keys.contains(where: { $0 > a }) { continue }
            if !q.links.allSatisfy({ l in e.links.keys.contains { $0 == l } }) { continue }
            let title = e.title
            func matches(_ s: String, _ term: String) -> Bool { s.range(of: term, options: o) != nil }
            var blockHits: [SearchHit.BlockHit] = []
            var count = 0
            var titleMatch = false
            if let re = q.regex {
                titleMatch = re.firstMatch(in: title, range: NSRange(location: 0, length: (title as NSString).length)) != nil
                if !q.titleOnly {
                    for b in e.blocks {
                        let ms = re.matches(in: b.text, range: NSRange(location: 0, length: (b.text as NSString).length))
                        guard let f = ms.first, let r = Range(f.range, in: b.text) else { continue }
                        count += ms.count
                        if blockHits.count < blockLimit { let (s, sr) = Search.snippet(b.text, term: String(b.text[r])); blockHits.append(.init(id: b.id, snippet: s, match: sr)) }
                    }
                }
                guard titleMatch || count > 0 else { continue }
            } else {
                let excluded = q.exclude.contains { t in matches(title, t) || (!q.titleOnly && e.blocks.contains { matches($0.text, t) }) }
                if excluded { continue }
                if !q.include.isEmpty {
                    let present = q.include.allSatisfy { t in matches(title, t) || (!q.titleOnly && e.blocks.contains { matches($0.text, t) }) }
                    guard present else { continue }
                    titleMatch = q.include.contains { matches(title, $0) }
                    if !q.titleOnly {
                        for b in e.blocks {
                            let n = q.include.reduce(0) { $0 + Search.occurrences(of: $1, in: b.text) }
                            guard n > 0 else { continue }
                            count += n
                            if blockHits.count < blockLimit { let (s, sr) = Search.snippet(b.text, term: q.include.first { matches(b.text, $0) }); blockHits.append(.init(id: b.id, snippet: s, match: sr)) }
                        }
                    }
                } else {
                    // Filters only (#tag, date:, link:): show the blocks that carry them.
                    var ids = Set<String>()
                    for t in q.tags { ids.formUnion(e.tags[t] ?? []) }
                    for d in q.dates { for (k, v) in e.dates where k.hasPrefix(d) { ids.formUnion(v) } }
                    for l in q.links { ids.formUnion(e.links[l] ?? []) }
                    for b in e.blocks where ids.contains(b.id) && blockHits.count < blockLimit { blockHits.append(.init(id: b.id, snippet: String(b.text.prefix(140)), match: nil)) }
                    count = ids.count
                }
            }
            let first = blockHits.first
            out.append(SearchHit(meta: m, count: count, titleMatch: titleMatch, snippet: first?.snippet ?? "", snippetMatch: first?.match, blocks: blockHits))
        }
        return out.sorted { a, b in
            if a.titleMatch != b.titleMatch { return a.titleMatch }
            if a.count != b.count { return a.count > b.count }
            return a.meta.updatedAt > b.meta.updatedAt
        }
    }
}

public extension Vault {
    var searchIndexURL: URL { dir.appendingPathComponent("index/search.json") }

    /// The stored search index; a damaged file is copied to backups/ (so nothing is lost) and nil is
    /// returned, an older format returns nil quietly. Either way the caller rebuilds it.
    func loadSearchIndex() -> SearchIndex? {
        drain()
        guard let data = try? Data(contentsOf: searchIndexURL) else { return nil }
        if let i = try? JSONDecoder().decode(SearchIndex.self, from: data) { return i.version == SearchIndex.version ? i : nil }
        if !isReadOnly {
            let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
            try? Vault.writeAtomic(data, to: dir.appendingPathComponent("backups/\(stamp)-search.unreadable.json"))
        }
        return nil
    }

    func saveSearchIndex(_ i: SearchIndex) throws {
        guard !isReadOnly else { return }
        try Vault.writeAtomic(try JSONEncoder().encode(i), to: searchIndexURL)
    }
}
