import Foundation

/// Minimal Markdown → document nodes, used for multi-line paste (and later for Import).
/// Each non-blank line becomes its own block, which is what pasted plain text expects.
/// shortcut: marks do not nest (e.g. bold inside a link); add a real parser when Import lands (v0.5).
public enum MarkdownImport {
    struct ListLine { var indent: Int; var kind: String; var checked: Bool?; var start: Int; var inline: [Node] }

    public static func blocks(_ text: String) -> [Node] {
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        var out: [Node] = []
        var i = 0
        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { i += 1; continue }
            if trimmed.hasPrefix("```") {
                let lang = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                var code: [String] = []
                i += 1
                while i < lines.count, !lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("```") { code.append(lines[i]); i += 1 }
                i += 1
                let t = code.joined(separator: "\n")
                out.append(Node("codeBlock", attrs: lang.isEmpty ? nil : ["language": .string(lang)], content: t.isEmpty ? nil : [.text(t)]))
                continue
            }
            if ["---", "***", "___"].contains(trimmed) { out.append(Node("horizontalRule")); i += 1; continue }
            if let m = match(#"^(#{1,6})\s+(.*)$"#, trimmed) {
                out.append(Node("heading", attrs: ["level": .number(Double(min(4, m[1].count)))], content: nonEmpty(inline(m[2]))))
                i += 1; continue
            }
            if trimmed.hasPrefix(">") {
                var paras: [Node] = []
                while i < lines.count, let m = match(#"^\s*>\s?(.*)$"#, lines[i]) {
                    if !m[1].trimmingCharacters(in: .whitespaces).isEmpty { paras.append(Node("paragraph", content: nonEmpty(inline(m[1])))) }
                    i += 1
                }
                out.append(Node("blockquote", content: paras.isEmpty ? [Node("paragraph")] : paras))
                continue
            }
            if listLine(line) != nil {
                var items: [ListLine] = []
                while i < lines.count, let l = listLine(lines[i]) { items.append(l); i += 1 }
                var j = 0
                out.append(contentsOf: buildLists(items, &j, indent: items.first?.indent ?? 0))
                continue
            }
            out.append(Node("paragraph", content: nonEmpty(inline(trimmed))))
            i += 1
        }
        return out
    }

    static func listLine(_ line: String) -> ListLine? {
        guard let m = match(#"^(\s*)([-*+]|(\d{1,4})[.)])\s+(\[( |x|X)\]\s+)?(.*)$"#, line) else { return nil }
        let indent = m[1].replacingOccurrences(of: "\t", with: "  ").count / 2
        let checked: Bool? = m[4].isEmpty ? nil : m[5].lowercased() == "x"
        let kind = checked != nil ? "taskList" : (m[3].isEmpty ? "bulletList" : "orderedList")
        return ListLine(indent: indent, kind: kind, checked: checked, start: Int(m[3]) ?? 1, inline: inline(m[6]))
    }

    static func buildLists(_ items: [ListLine], _ j: inout Int, indent: Int) -> [Node] {
        var lists: [Node] = []
        while j < items.count, items[j].indent >= indent {
            let kind = items[j].kind
            var list = Node(kind, attrs: kind == "orderedList" ? ["start": .number(Double(items[j].start))] : nil, content: [])
            while j < items.count, items[j].indent == indent, items[j].kind == kind {
                let it = items[j]; j += 1
                var children = [Node("paragraph", content: nonEmpty(it.inline))]
                if j < items.count, items[j].indent > indent { children += buildLists(items, &j, indent: items[j].indent) }
                list.content!.append(Node(kind == "taskList" ? "taskItem" : "listItem", attrs: it.checked.map { ["checked": .bool($0)] }, content: children))
            }
            if list.content!.isEmpty { break }
            lists.append(list)
            if j < items.count, items[j].indent > indent { lists += buildLists(items, &j, indent: items[j].indent) }
        }
        return lists
    }

    static let inlinePattern = try! NSRegularExpression(pattern: #"\*\*(.+?)\*\*|~~(.+?)~~|==(.+?)==|`([^`]+)`|\[([^\]]+)\]\(([^)\s]+)\)|(?<![*\w])\*([^*\s](?:[^*]*?[^*\s])?)\*(?![*\w])|(?<!\w)_([^_\s](?:[^_]*?[^_\s])?)_(?!\w)"#)

    public static func inline(_ s: String) -> [Node] {
        let ns = s as NSString
        var out: [Node] = []
        var last = 0
        func plain(_ r: NSRange) { if r.length > 0 { out.append(.text(unescape(ns.substring(with: r)))) } }
        for m in inlinePattern.matches(in: s, range: NSRange(location: 0, length: ns.length)) {
            plain(NSRange(location: last, length: m.range.location - last))
            func g(_ i: Int) -> String? { m.range(at: i).location == NSNotFound ? nil : ns.substring(with: m.range(at: i)) }
            if let t = g(1) { out.append(.text(t, marks: [Mark("bold")])) }
            else if let t = g(2) { out.append(.text(t, marks: [Mark("strike")])) }
            else if let t = g(3) { out.append(.text(t, marks: [Mark("highlight")])) }
            else if let t = g(4) { out.append(.text(t, marks: [Mark("code")])) }
            else if let t = g(5), let u = g(6) { out.append(.text(t, marks: [Mark("link", attrs: ["href": .string(u)])])) }
            else if let t = g(7) ?? g(8) { out.append(.text(t, marks: [Mark("italic")])) }
            last = NSMaxRange(m.range)
        }
        plain(NSRange(location: last, length: ns.length - last))
        return out
    }

    static func unescape(_ s: String) -> String { s.replacingOccurrences(of: #"\\([\\`*_\[\]#<>|~=])"#, with: "$1", options: .regularExpression) }
    static func nonEmpty(_ n: [Node]) -> [Node]? { n.isEmpty ? nil : n }

    static func match(_ pattern: String, _ s: String) -> [String]? {
        guard let re = try? NSRegularExpression(pattern: pattern), let m = re.firstMatch(in: s, range: NSRange(location: 0, length: (s as NSString).length)) else { return nil }
        return (0..<m.numberOfRanges).map { m.range(at: $0).location == NSNotFound ? "" : (s as NSString).substring(with: m.range(at: $0)) }
    }
}
