import Foundation

/// What changed between two versions of a note, block by block (matched by block id), with word-level
/// text changes, formatting, block type, style and attachment changes. Pure; used for the Version
/// History diff and as the restore preview.
public struct VersionDiff: Sendable, Hashable {
    public struct Word: Sendable, Hashable {
        public enum Op: Sendable, Hashable { case same, added, removed }
        public var op: Op
        public var text: String
    }
    public struct Block: Sendable, Hashable, Identifiable {
        public enum Kind: String, Sendable, Hashable { case added, removed, edited, formatted, moved }
        public var id: String { blockId + ":" + kind.rawValue }
        public var blockId: String
        public var kind: Kind
        public var type: String
        public var before: String
        public var after: String
        public var notes: [String]
        public var words: [Word]
    }

    public var titleBefore: String
    public var titleAfter: String
    public var lookNotes: [String] = []
    public var assetsAdded: [String] = []
    public var assetsRemoved: [String] = []
    public var blocks: [Block] = []

    public var isEmpty: Bool { titleBefore == titleAfter && lookNotes.isEmpty && assetsAdded.isEmpty && assetsRemoved.isEmpty && blocks.isEmpty }
    public func count(_ k: Block.Kind) -> Int { blocks.filter { $0.kind == k }.count }
    public var summary: String {
        var parts: [String] = []
        if titleBefore != titleAfter { parts.append("title") }
        for (k, w) in [(Block.Kind.edited, "edited"), (.added, "added"), (.removed, "removed"), (.formatted, "reformatted"), (.moved, "moved")] where count(k) > 0 {
            parts.append("\(count(k)) \(w)")
        }
        if !lookNotes.isEmpty { parts.append("look") }
        if !assetsAdded.isEmpty || !assetsRemoved.isEmpty { parts.append("\(assetsAdded.count + assetsRemoved.count) attachment\(assetsAdded.count + assetsRemoved.count == 1 ? "" : "s")") }
        return parts.isEmpty ? "No changes" : parts.joined(separator: ", ")
    }

    static let expand: Set<String> = ["bulletList", "orderedList", "taskList", "toggleList"]
    static let names: [String: String] = [
        "paragraph": "Text", "heading": "Heading", "blockquote": "Quote", "codeBlock": "Code", "horizontalRule": "Separator", "listItem": "List item",
        "taskItem": "Task", "toggleItem": "Toggle", "callout": "Callout", "pageBreak": "Page break", "image": "Image", "file": "File", "pageCard": "Page",
        "linkPreview": "Link preview", "table": "Table", "collection": "Collection",
    ]
    public static func typeName(_ n: Node) -> String {
        if n.type == "heading" { return "Heading \(n.attrs?["level"]?.int ?? 1)" }
        return names[n.type] ?? n.type
    }

    /// The blocks a reader thinks of as one unit: top-level blocks, with list items one by one.
    static func units(_ doc: Node) -> [Node] {
        var out: [Node] = []
        for n in doc.content ?? [] {
            if expand.contains(n.type) { out += (n.content ?? []).filter { $0.id != nil } } else { out.append(n) }
        }
        return out
    }

    static func label(_ n: Node) -> String {
        switch n.type {
        case "image", "file": return n.attrs?["caption"]?.string?.nonEmpty ?? n.attrs?["name"]?.string?.nonEmpty ?? n.attrs?["assetId"]?.string ?? ""
        case "pageCard": return n.attrs?["title"]?.string ?? ""
        default: return nodeText(n)
        }
    }

    static func marks(_ n: Node) -> [String: Int] {
        var out: [String: Int] = [:]
        walk(n) { t in t.marks?.forEach { out[$0.type == "textStyle" ? "color" : $0.type, default: 0] += (t.text?.count ?? 0) } }
        return out
    }

    static let markNames: [String: String] = ["bold": "bold", "italic": "italic", "underline": "underline", "strike": "strikethrough", "code": "inline code",
                                               "highlight": "highlight", "color": "text color", "effect": "text effect", "link": "link", "docLink": "note link", "date": "date"]

    static func formatNotes(_ a: Node, _ b: Node) -> [String] {
        var notes: [String] = []
        if typeName(a) != typeName(b) { notes.append("\(typeName(a)) → \(typeName(b))") }
        let ignore: Set<String> = ["id", "level"]
        let keys = Set((a.attrs ?? [:]).keys).union((b.attrs ?? [:]).keys).subtracting(ignore)
        let attrNames = ["decoration": "block decoration", "blockColor": "block color", "align": "alignment", "font": "font", "checked": "done", "due": "due date",
                         "width": "size", "caption": "caption", "alt": "alt text", "language": "code language", "collapsed": "folded"]
        for k in keys.sorted() where a.attrs?[k] != b.attrs?[k] {
            if k == "checked" { notes.append(b.attrs?[k]?.bool == true ? "marked done" : "marked not done"); continue }
            notes.append((attrNames[k] ?? k) + " changed")
        }
        let ma = marks(a), mb = marks(b)
        for k in Set(ma.keys).union(mb.keys).sorted() {
            let name = markNames[k] ?? k
            if ma[k] == nil { notes.append("\(name) added") } else if mb[k] == nil { notes.append("\(name) removed") }
            else if ma[k] != mb[k] { notes.append("\(name) changed") }
        }
        if notes.isEmpty, a != b { notes.append("formatting changed") }
        return notes
    }

    /// Longest-common-subsequence word diff; long blocks fall back to a whole replacement.
    public static func words(_ a: String, _ b: String) -> [Word] {
        func split(_ s: String) -> [String] {
            var out: [String] = [], cur = ""
            for ch in s { if ch == " " || ch == "\n" { if !cur.isEmpty { out.append(cur) }; out.append(String(ch)); cur = "" } else { cur.append(ch) } }
            if !cur.isEmpty { out.append(cur) }
            return out
        }
        let x = split(a), y = split(b)
        if x.count * y.count > 250_000 { return [Word(op: .removed, text: a), Word(op: .added, text: b)] }
        var t = Array(repeating: Array(repeating: 0, count: y.count + 1), count: x.count + 1)
        for i in stride(from: x.count - 1, through: 0, by: -1) { for j in stride(from: y.count - 1, through: 0, by: -1) {
            t[i][j] = x[i] == y[j] ? t[i + 1][j + 1] + 1 : max(t[i + 1][j], t[i][j + 1])
        } }
        var out: [Word] = []
        func push(_ op: Word.Op, _ s: String) { if let l = out.last, l.op == op { out[out.count - 1].text += s } else { out.append(Word(op: op, text: s)) } }
        var i = 0, j = 0
        while i < x.count && j < y.count {
            if x[i] == y[j] { push(.same, x[i]); i += 1; j += 1 }
            else if t[i + 1][j] >= t[i][j + 1] { push(.removed, x[i]); i += 1 } else { push(.added, y[j]); j += 1 }
        }
        while i < x.count { push(.removed, x[i]); i += 1 }
        while j < y.count { push(.added, y[j]); j += 1 }
        return out
    }

    static func lcs(_ fullA: [String], _ fullB: [String]) -> Set<String> {
        // Usually only a few blocks move: keep the shared start and end, compare only the middle.
        var lo = 0
        while lo < min(fullA.count, fullB.count) && fullA[lo] == fullB[lo] { lo += 1 }
        var hiA = fullA.count, hiB = fullB.count
        while hiA > lo && hiB > lo && fullA[hiA - 1] == fullB[hiB - 1] { hiA -= 1; hiB -= 1 }
        let kept = Set(fullA[..<lo]).union(fullA[hiA...])
        let a = Array(fullA[lo..<hiA]), b = Array(fullB[lo..<hiB])
        return kept.union(lcsCore(a, b))
    }

    static func lcsCore(_ a: [String], _ b: [String]) -> Set<String> {
        if a.isEmpty || b.isEmpty { return [] }
        if a.count * b.count > 4_000_000 { return Set(a).intersection(b) } // shortcut: very long notes skip move detection
        var t = Array(repeating: Array(repeating: 0, count: b.count + 1), count: a.count + 1)
        for i in stride(from: a.count - 1, through: 0, by: -1) { for j in stride(from: b.count - 1, through: 0, by: -1) {
            t[i][j] = a[i] == b[j] ? t[i + 1][j + 1] + 1 : max(t[i + 1][j], t[i][j + 1])
        } }
        var out = Set<String>(), i = 0, j = 0
        while i < a.count && j < b.count {
            if a[i] == b[j] { out.insert(a[i]); i += 1; j += 1 } else if t[i + 1][j] >= t[i][j + 1] { i += 1 } else { j += 1 }
        }
        return out
    }

    /// Changes from `old` to `new`.
    public static func compute(from old: DocFile, to new: DocFile) -> VersionDiff {
        var d = VersionDiff(titleBefore: old.title, titleAfter: new.title)
        let a = units(old.content), b = units(new.content)
        let aById = Dictionary(a.compactMap { n in n.id.map { ($0, n) } }, uniquingKeysWith: { x, _ in x })
        let bById = Dictionary(b.compactMap { n in n.id.map { ($0, n) } }, uniquingKeysWith: { x, _ in x })
        let common = a.compactMap(\.id).filter { bById[$0] != nil }
        let inOrder = lcs(common, b.compactMap(\.id).filter { aById[$0] != nil })
        // Walk the new order, inserting removals where they were.
        var removedBefore: [String: [Node]] = [:] // next surviving id → removed blocks just before it
        var pending: [Node] = []
        for n in a {
            if let id = n.id, bById[id] != nil { if !pending.isEmpty { removedBefore[id] = pending; pending = [] } } else { pending.append(n) }
        }
        func removed(_ n: Node) -> Block { Block(blockId: n.id ?? "", kind: .removed, type: typeName(n), before: label(n), after: "", notes: [], words: [Word(op: .removed, text: label(n))]) }
        for n in b {
            guard let id = n.id else { continue }
            for r in removedBefore[id] ?? [] { d.blocks.append(removed(r)) }
            guard let o = aById[id] else {
                d.blocks.append(Block(blockId: id, kind: .added, type: typeName(n), before: "", after: label(n), notes: [], words: [Word(op: .added, text: label(n))]))
                continue
            }
            let ta = label(o), tb = label(n)
            if ta != tb {
                var notes = formatNotes(o, n).filter { !$0.hasPrefix("formatting") && !$0.hasSuffix("caption changed") }
                if !inOrder.contains(id) { notes.insert("moved", at: 0) }
                d.blocks.append(Block(blockId: id, kind: .edited, type: typeName(n), before: ta, after: tb, notes: notes, words: words(ta, tb)))
            } else if o != n {
                d.blocks.append(Block(blockId: id, kind: .formatted, type: typeName(n), before: ta, after: tb, notes: formatNotes(o, n), words: [Word(op: .same, text: tb)]))
            } else if !inOrder.contains(id) {
                d.blocks.append(Block(blockId: id, kind: .moved, type: typeName(n), before: ta, after: tb, notes: ["moved"], words: [Word(op: .same, text: tb)]))
            }
        }
        for r in pending { d.blocks.append(removed(r)) }
        // Look.
        let la = old.appearance, lb = new.appearance
        if la.styleId != lb.styleId { d.lookNotes.append("Style: \(Styles.all.first { $0.id == la.styleId }?.name ?? la.styleId) → \(Styles.all.first { $0.id == lb.styleId }?.name ?? lb.styleId)") }
        if la.overrides.backdrop != lb.overrides.backdrop { d.lookNotes.append(lb.overrides.backdrop == nil ? "Backdrop removed" : la.overrides.backdrop == nil ? "Backdrop added" : "Backdrop changed") }
        var o1 = la.overrides, o2 = lb.overrides; o1.backdrop = nil; o2.backdrop = nil
        if o1 != o2 { d.lookNotes.append("Colors or fonts changed") }
        if la.cover != lb.cover { d.lookNotes.append(lb.cover == nil ? "Cover removed" : la.cover == nil ? "Cover added" : "Cover changed") }
        let xa = VaultCheck.assetIds(in: old), xb = VaultCheck.assetIds(in: new)
        d.assetsAdded = xb.subtracting(xa).sorted()
        d.assetsRemoved = xa.subtracting(xb).sorted()
        return d
    }

    /// Block ids in `current` that `restored` doesn't have (links to them would break).
    public static func lostBlockIds(current: DocFile, restored: DocFile) -> Set<String> {
        var a = Set<String>(), b = Set<String>()
        walk(current.content) { if blockTypes.contains($0.type), let i = $0.id { a.insert(i) } }
        walk(restored.content) { if blockTypes.contains($0.type), let i = $0.id { b.insert(i) } }
        return a.subtracting(b)
    }
}
