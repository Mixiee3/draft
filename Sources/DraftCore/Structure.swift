import Foundation

// MARK: - Simple tables

/// `table` node: rows of `tableRow`, each a list of `tableCell` holding inline content.
/// The first row is the header.
public enum Tables {
    public static func make(rows: Int = 3, columns: Int = 3) -> Node {
        Node("table", attrs: ["id": .string(newId("b_"))], content: (0..<rows).map { _ in
            Node("tableRow", attrs: ["id": .string(newId("b_"))], content: (0..<columns).map { _ in Node("tableCell", attrs: ["id": .string(newId("b_"))]) })
        })
    }

    public static func cells(_ t: Node) -> [[Node]] { (t.content ?? []).map { $0.content ?? [] } }
    public static func text(_ t: Node) -> [[String]] { cells(t).map { $0.map(nodeText) } }
    public static func columnCount(_ t: Node) -> Int { cells(t).map(\.count).max() ?? 0 }

    public static func settingCell(_ t: Node, row: Int, column: Int, inline: [Node]) -> Node {
        var out = t
        guard var rows = out.content, rows.indices.contains(row), var cs = rows[row].content else { return t }
        while cs.count <= column { cs.append(Node("tableCell", attrs: ["id": .string(newId("b_"))])) }
        cs[column].content = inline.isEmpty ? nil : inline
        rows[row].content = cs
        out.content = rows
        return out
    }

    public static func insertingRow(_ t: Node, at i: Int) -> Node {
        var out = t
        var rows = out.content ?? []
        let n = max(1, columnCount(t))
        rows.insert(Node("tableRow", attrs: ["id": .string(newId("b_"))], content: (0..<n).map { _ in Node("tableCell", attrs: ["id": .string(newId("b_"))]) }), at: max(0, min(i, rows.count)))
        out.content = rows
        return out
    }

    public static func removingRow(_ t: Node, at i: Int) -> Node {
        var out = t
        guard var rows = out.content, rows.count > 1, rows.indices.contains(i) else { return t }
        rows.remove(at: i)
        out.content = rows
        return out
    }

    public static func insertingColumn(_ t: Node, at c: Int) -> Node {
        var out = t
        out.content = (t.content ?? []).map { r in
            var r = r
            var cs = r.content ?? []
            cs.insert(Node("tableCell", attrs: ["id": .string(newId("b_"))]), at: max(0, min(c, cs.count)))
            r.content = cs
            return r
        }
        return out
    }

    public static func removingColumn(_ t: Node, at c: Int) -> Node {
        guard columnCount(t) > 1 else { return t }
        var out = t
        out.content = (t.content ?? []).map { r in
            var r = r
            var cs = r.content ?? []
            if cs.indices.contains(c) { cs.remove(at: c) }
            r.content = cs
            return r
        }
        return out
    }

    public static func movingRow(_ t: Node, from: Int, to: Int) -> Node {
        var out = t
        guard var rows = out.content, rows.indices.contains(from), rows.indices.contains(to) else { return t }
        rows.insert(rows.remove(at: from), at: to)
        out.content = rows
        return out
    }

    /// A Markdown pipe table (cells keep their marks).
    public static func markdown(_ t: Node, _ lossy: inout Set<String>) -> [String] {
        let rows = cells(t)
        guard !rows.isEmpty else { return [] }
        let n = columnCount(t)
        func line(_ r: [Node]) -> String {
            "| " + (0..<n).map { i in i < r.count ? Markdown.inline(r[i].content, &lossy) : "" }.joined(separator: " | ") + " |"
        }
        return [line(rows[0]), "| " + Array(repeating: "---", count: n).joined(separator: " | ") + " |"] + rows.dropFirst().map(line)
    }

    /// Parse consecutive `| a | b |` lines (with a `|---|` separator after the first) into a table.
    public static func parse(_ lines: [String]) -> Node? {
        func split(_ l: String) -> [String] {
            var s = l.trimmingCharacters(in: .whitespaces)
            if s.hasPrefix("|") { s.removeFirst() }
            if s.hasSuffix("|") && !s.hasSuffix("\\|") { s.removeLast() }
            var out: [String] = [], cur = "", esc = false
            for ch in s {
                if esc { cur.append(ch); esc = false; continue }
                if ch == "\\" { esc = true; continue }
                if ch == "|" { out.append(cur.trimmingCharacters(in: .whitespaces)); cur = "" } else { cur.append(ch) }
            }
            out.append(cur.trimmingCharacters(in: .whitespaces))
            return out
        }
        guard lines.count >= 2, split(lines[1]).allSatisfy({ $0.range(of: #"^:?-{3,}:?$"#, options: .regularExpression) != nil }) else { return nil }
        let body = [lines[0]] + lines.dropFirst(2)
        return Node("table", attrs: ["id": .string(newId("b_"))], content: body.map { l in
            Node("tableRow", attrs: ["id": .string(newId("b_"))], content: split(l).map { c in
                let inl = MarkdownImport.inline(c)
                return Node("tableCell", attrs: ["id": .string(newId("b_"))], content: inl.isEmpty ? nil : inl)
            })
        })
    }
}

// MARK: - Collections

public struct CollectionField: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var name: String
    /// text | number | select | multiSelect | date | checkbox | relation | url
    public var type: String
    public var options: [String]?
    public init(id: String = newId("fld_"), name: String, type: String, options: [String]? = nil) { self.id = id; self.name = name; self.type = type; self.options = options }
    public static let types = ["text", "number", "select", "multiSelect", "date", "checkbox", "relation", "url"]
}

public struct SortRule: Codable, Hashable, Sendable {
    public var field: String
    public var ascending: Bool
    public init(field: String, ascending: Bool = true) { self.field = field; self.ascending = ascending }
}

public struct FilterRule: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var field: String
    /// is | isNot | contains | isEmpty | isNotEmpty | gt | lt | before | after | checked | unchecked
    public var op: String
    public var value: String?
    public init(id: String = newId("r_"), field: String, op: String, value: String? = nil) { self.id = id; self.field = field; self.op = op; self.value = value }
}

public struct CollectionView: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var name: String
    /// table | gallery | kanban
    public var type: String
    public var sort: [SortRule] = []
    public var filters: [FilterRule] = []
    /// all | any
    public var match: String = "all"
    public var groupBy: String?
    /// Visible fields in order (nil = all).
    public var visible: [String]?
    /// Calculation per field (count, empty, filled, sum, average, min, max, checked).
    public var calc: [String: String] = [:]
    public init(id: String = newId("v_"), name: String, type: String) { self.id = id; self.name = name; self.type = type }

    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id); name = try c.decode(String.self, forKey: .name); type = try c.decode(String.self, forKey: .type)
        sort = try c.decodeIfPresent([SortRule].self, forKey: .sort) ?? []
        filters = try c.decodeIfPresent([FilterRule].self, forKey: .filters) ?? []
        match = try c.decodeIfPresent(String.self, forKey: .match) ?? "all"
        groupBy = try c.decodeIfPresent(String.self, forKey: .groupBy)
        visible = try c.decodeIfPresent([String].self, forKey: .visible)
        calc = try c.decodeIfPresent([String: String].self, forKey: .calc) ?? [:]
    }
}

public struct CollectionItem: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    /// The item's page.
    public var docId: String
    public var values: [String: JSONValue] = [:]
    public init(id: String = newId("i_"), docId: String, values: [String: JSONValue] = [:]) { self.id = id; self.docId = docId; self.values = values }
}

/// The data of a `collection` block (stored as its `data` attribute).
public struct CollectionData: Codable, Hashable, Sendable {
    public var name: String
    public var fields: [CollectionField]
    public var views: [CollectionView]
    public var activeView: String?
    public var items: [CollectionItem]
    public static let titleField = "title"

    public init(name: String = "Collection", fields: [CollectionField] = [], views: [CollectionView] = [], activeView: String? = nil, items: [CollectionItem] = []) {
        self.name = name; self.fields = fields; self.views = views; self.activeView = activeView; self.items = items
    }

    public static func starter(name: String = "Collection") -> CollectionData {
        let status = CollectionField(name: "Status", type: "select", options: ["To do", "Doing", "Done"])
        let due = CollectionField(name: "Date", type: "date")
        let tags = CollectionField(name: "Tags", type: "multiSelect", options: [])
        var board = CollectionView(name: "Board", type: "kanban"); board.groupBy = status.id
        let table = CollectionView(name: "Table", type: "table")
        return CollectionData(name: name, fields: [status, due, tags], views: [table, CollectionView(name: "Gallery", type: "gallery"), board], activeView: table.id)
    }

    public init?(node: Node) {
        guard node.type == "collection", let v = node.attrs?["data"], let d = try? JSONEncoder().encode(v), let c = try? JSONDecoder().decode(CollectionData.self, from: d) else { return nil }
        self = c
    }

    public func node(id: String) -> Node {
        let v = (try? JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(self))) ?? .null
        return Node("collection", attrs: ["id": .string(id), "data": v])
    }

    public var view: CollectionView? { views.first { $0.id == activeView } ?? views.first }
    public func field(_ id: String) -> CollectionField? { fields.first { $0.id == id } }

    // MARK: Values

    /// Text form of a value (titles come from `title`, relations from `title` of the related page).
    public func display(_ item: CollectionItem, _ fieldId: String, title: (String) -> String) -> String {
        if fieldId == Self.titleField { return title(item.docId) }
        if field(fieldId)?.type == "checkbox" { return item.values[fieldId]?.bool == true ? "Yes" : "No" }
        guard let f = field(fieldId), let v = item.values[fieldId] else { return "" }
        switch f.type {
        case "checkbox": return v.bool == true ? "Yes" : "No"
        case "number": return v.double.map { $0.rounded() == $0 && abs($0) < 1e15 ? String(Int($0)) : String($0) } ?? ""
        case "multiSelect", "relation":
            let list = v.items?.compactMap(\.string) ?? []
            return (f.type == "relation" ? list.map(title) : list).joined(separator: "; ")
        default: return v.string ?? ""
        }
    }

    // MARK: Filter, sort, group

    func matches(_ item: CollectionItem, _ r: FilterRule, title: (String) -> String) -> Bool {
        let text = display(item, r.field, title: title)
        let value = r.value ?? ""
        let num = { (s: String) in Double(s.replacingOccurrences(of: ",", with: ".")) }
        switch r.op {
        case "is": return text.caseInsensitiveCompare(value) == .orderedSame || (item.values[r.field]?.items?.compactMap(\.string).contains(value) ?? false)
        case "isNot": return !(text.caseInsensitiveCompare(value) == .orderedSame || (item.values[r.field]?.items?.compactMap(\.string).contains(value) ?? false))
        case "contains": return text.range(of: value, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        case "isEmpty": return text.isEmpty || (field(r.field)?.type == "checkbox" && item.values[r.field]?.bool != true)
        case "isNotEmpty": return !text.isEmpty && !(field(r.field)?.type == "checkbox" && item.values[r.field]?.bool != true)
        case "gt": return (num(text) ?? -.infinity) > (num(value) ?? .infinity)
        case "lt": return (num(text) ?? .infinity) < (num(value) ?? -.infinity)
        case "before": return !text.isEmpty && text < value
        case "after": return !text.isEmpty && text > value
        case "checked": return item.values[r.field]?.bool == true
        case "unchecked": return item.values[r.field]?.bool != true
        default: return true
        }
    }

    /// Items of a view: filtered (all/any rules), then sorted by each rule in turn.
    public func rows(_ v: CollectionView, title: (String) -> String) -> [CollectionItem] {
        var out = items
        if !v.filters.isEmpty {
            out = out.filter { it in v.match == "any" ? v.filters.contains { matches(it, $0, title: title) } : v.filters.allSatisfy { matches(it, $0, title: title) } }
        }
        guard !v.sort.isEmpty else { return out }
        func key(_ it: CollectionItem, _ f: String) -> (Double?, String) {
            let t = field(f)?.type
            if t == "number" { return (it.values[f]?.double, "") }
            if t == "checkbox" { return (it.values[f]?.bool == true ? 1 : 0, "") }
            return (nil, display(it, f, title: title).lowercased())
        }
        return out.enumerated().sorted { a, b in
            for r in v.sort {
                let (x, y) = (key(a.element, r.field), key(b.element, r.field))
                if let xn = x.0, let yn = y.0, xn != yn { return r.ascending ? xn < yn : xn > yn }
                if x.0 == nil, y.0 != nil { return false }
                if x.0 != nil, y.0 == nil { return true }
                if x.1 != y.1 {
                    if x.1.isEmpty { return false }
                    if y.1.isEmpty { return true }
                    return r.ascending ? x.1 < y.1 : x.1 > y.1
                }
            }
            return a.offset < b.offset
        }.map(\.element)
    }

    /// Kanban columns: one per option of the grouping field (in order), then "No value".
    public func groups(_ v: CollectionView, title: (String) -> String) -> [(key: String?, items: [CollectionItem])] {
        let rs = rows(v, title: title)
        guard let g = v.groupBy, let f = field(g) else { return [(nil, rs)] }
        var keys: [String] = f.options ?? []
        if f.type == "checkbox" { keys = ["Yes", "No"] }
        for it in rs { let k = display(it, g, title: title); if !k.isEmpty, !keys.contains(k), f.type != "multiSelect" { keys.append(k) } }
        var out: [(String?, [CollectionItem])] = keys.map { k in (k, rs.filter { display($0, g, title: title) == k || ($0.values[g]?.items?.compactMap(\.string).contains(k) ?? false) }) }
        out.append((nil, rs.filter { display($0, g, title: title).isEmpty }))
        return out
    }

    /// Kanban drag: the item's grouping value becomes `key` (nil clears it). One record changes.
    public mutating func move(_ itemId: String, to key: String?, groupBy g: String) {
        guard let i = items.firstIndex(where: { $0.id == itemId }), let f = field(g) else { return }
        switch f.type {
        case "checkbox": items[i].values[g] = .bool(key == "Yes")
        case "multiSelect": items[i].values[g] = key.map { .array([.string($0)]) }
        default: items[i].values[g] = key.map { .string($0) }
        }
    }

    // MARK: Calculations

    public static let calculations = ["count", "empty", "filled", "sum", "average", "min", "max", "checked"]

    public func calculate(_ kind: String, field f: String, rows: [CollectionItem], title: (String) -> String) -> String {
        let texts = rows.map { display($0, f, title: title) }
        let nums = rows.compactMap { $0.values[f]?.double }
        func fmt(_ d: Double) -> String { d.rounded() == d ? String(Int(d)) : String(format: "%.2f", d) }
        switch kind {
        case "count": return String(rows.count)
        case "empty": return String(field(f)?.type == "checkbox" ? rows.filter { $0.values[f]?.bool != true }.count : texts.filter(\.isEmpty).count)
        case "filled": return String(texts.filter { !$0.isEmpty }.count)
        case "sum": return fmt(nums.reduce(0, +))
        case "average": return nums.isEmpty ? "" : fmt(nums.reduce(0, +) / Double(nums.count))
        case "min": return nums.min().map(fmt) ?? ""
        case "max": return nums.max().map(fmt) ?? ""
        case "checked": return rows.isEmpty ? "" : String(format: "%.0f%%", Double(rows.filter { $0.values[f]?.bool == true }.count) / Double(rows.count) * 100)
        default: return ""
        }
    }

    // MARK: CSV and frontmatter

    static func csvField(_ s: String) -> String { s.contains(where: { ",\"\n\r".contains($0) }) ? "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\"" : s }

    public func csv(title: (String) -> String) -> String {
        let header = ["Name"] + fields.map(\.name)
        let lines = [header.map(Self.csvField).joined(separator: ",")] + items.map { it in
            ([title(it.docId)] + fields.map { f in f.type == "relation" ? (it.values[f.id]?.items?.compactMap(\.string) ?? []).joined(separator: "; ") : display(it, f.id, title: title) })
                .map(Self.csvField).joined(separator: ",")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    public static func parseCSV(_ text: String) -> [[String]] {
        var rows: [[String]] = [], row: [String] = [], cur = "", quoted = false
        var it = Array(text.replacingOccurrences(of: "\r\n", with: "\n")).makeIterator()
        var pending: Character? = nil
        while let ch = pending ?? it.next() {
            pending = nil
            if quoted {
                if ch == "\"" { if let n = it.next() { if n == "\"" { cur.append("\"") } else { quoted = false; pending = n } } else { quoted = false } }
                else { cur.append(ch) }
            } else if ch == "\"" { quoted = true }
            else if ch == "," { row.append(cur); cur = "" }
            else if ch == "\n" { row.append(cur); rows.append(row); row = []; cur = "" }
            else { cur.append(ch) }
        }
        if !cur.isEmpty || !row.isEmpty { row.append(cur); rows.append(row) }
        return rows
    }

    /// Values for one CSV row in this collection's fields (by header name); the first column is the title.
    public func values(fromCSV header: [String], _ row: [String]) -> (title: String, values: [String: JSONValue]) {
        var out: [String: JSONValue] = [:]
        for (i, h) in header.enumerated() where i > 0 && i < row.count {
            guard let f = fields.first(where: { $0.name == h }) else { continue }
            let s = row[i]
            if s.isEmpty && f.type != "checkbox" { continue }
            switch f.type {
            case "number": if let d = Double(s.replacingOccurrences(of: ",", with: ".")) { out[f.id] = .number(d) }
            case "checkbox": out[f.id] = .bool(["yes", "true", "1", "x"].contains(s.lowercased()))
            case "multiSelect", "relation": out[f.id] = .array(s.components(separatedBy: ";").map { .string($0.trimmingCharacters(in: .whitespaces)) }.filter { $0.string?.isEmpty == false })
            default: out[f.id] = .string(s)
            }
        }
        return (row.first ?? "", out)
    }

    /// YAML frontmatter for an item's Markdown page.
    public func frontmatter(_ item: CollectionItem, title: (String) -> String) -> String {
        func q(_ s: String) -> String { s.isEmpty || s.contains(where: { ":#[]{},\"'\n".contains($0) }) || s != s.trimmingCharacters(in: .whitespaces) ? "\"" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\"" : s }
        var lines = ["---", "collection: " + q(name)]
        for f in fields {
            guard let v = item.values[f.id] else { continue }
            let key = q(f.name)
            switch f.type {
            case "multiSelect", "relation":
                let list = (v.items?.compactMap(\.string) ?? []).map { f.type == "relation" ? title($0) : $0 }
                lines.append("\(key): [" + list.map(q).joined(separator: ", ") + "]")
            case "checkbox": lines.append("\(key): \(v.bool == true)")
            case "number": lines.append("\(key): " + display(item, f.id, title: title))
            default: lines.append("\(key): " + q(display(item, f.id, title: title)))
            }
        }
        return (lines + ["---", ""]).joined(separator: "\n")
    }
}

public extension Node {
    /// The tree with block `id` replaced by `node`; nil when there is no such block.
    func replacingBlock(_ id: String, with node: Node) -> Node? {
        var found = false
        func visit(_ n: Node) -> Node {
            if n.id == id { found = true; return node }
            var out = n
            out.content = n.content?.map(visit)
            return out
        }
        let r = visit(self)
        return found ? r : nil
    }

    func block(_ id: String) -> Node? {
        var hit: Node?
        walk(self) { if hit == nil, $0.id == id { hit = $0 } }
        return hit
    }
}
