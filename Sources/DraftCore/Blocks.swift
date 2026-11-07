import Foundation

/// Node types that are blocks and therefore carry a stable `id` attribute.
public let blockTypes: Set<String> = [
    "paragraph", "heading", "blockquote", "codeBlock", "horizontalRule", "bulletList", "orderedList",
    "listItem", "taskList", "taskItem", "toggleList", "toggleItem", "callout", "pageBreak", "image", "file", "pageCard", "linkPreview",
]
let containerListTypes: Set<String> = ["bulletList", "orderedList", "taskList", "toggleList", "callout"]

/// Give every block a unique id. Existing ids are kept; only missing ids and *duplicates* get
/// new ones, and the first occurrence of an id always wins.
public func ensureBlockIds(_ root: Node) -> Node {
    var seen = Set<String>()
    func visit(_ n: Node) -> Node {
        var out = n
        if blockTypes.contains(n.type) {
            if let id = n.id, !seen.contains(id) { seen.insert(id) }
            else { let id = newId("b_"); out[attr: "id"] = .string(id); seen.insert(id) }
        }
        out.content = n.content?.map(visit)
        return out
    }
    return visit(root)
}

/// Deep copy with a fresh id on every block (Duplicate).
public func reId(_ root: Node) -> Node {
    var out = root
    if blockTypes.contains(root.type) { out[attr: "id"] = .string(newId("b_")) }
    out.content = root.content?.map(reId)
    return out
}

public func walk(_ n: Node, _ fn: (Node) -> Void) {
    fn(n)
    n.content?.forEach { walk($0, fn) }
}

public func nodeText(_ n: Node) -> String {
    if n.type == "text" { return n.text ?? "" }
    if n.type == "hardBreak" { return "\n" }
    return (n.content ?? []).map(nodeText).joined()
}

/// Plain text, one block per line.
public func docPlainText(_ root: Node) -> String {
    var lines: [String] = []
    walk(root) { n in
        if ["paragraph", "heading", "codeBlock"].contains(n.type) { lines.append(nodeText(n)) }
        if n.type == "pageCard" { lines.append(n.attrs?["title"]?.string ?? "") }
    }
    return lines.joined(separator: "\n")
}

public struct DocStats: Equatable { public var words: Int; public var chars: Int; public var blocks: Int }

public func docStats(_ root: Node) -> DocStats {
    let text = docPlainText(root)
    var blocks = 0
    walk(root) { n in if blockTypes.contains(n.type) && !containerListTypes.contains(n.type) && n.type != "listItem" && n.type != "taskItem" && n.type != "toggleItem" { blocks += 1 } }
    let words = text.split(whereSeparator: { $0.isWhitespace }).count
    return DocStats(words: words, chars: text.replacingOccurrences(of: "\n", with: "").count, blocks: blocks)
}

public func excerptOf(_ root: Node, max: Int = 220) -> String {
    let t = docPlainText(root).split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    return t.count > max ? String(t.prefix(max - 1)) + "…" : t
}

public struct OutlineItem: Hashable, Identifiable {
    public var id: String
    public var kind: String // heading | page
    public var level: Int
    public var text: String
    public var docId: String?
}

public func outlineOf(_ root: Node) -> [OutlineItem] {
    var items: [OutlineItem] = []
    walk(root) { n in
        if n.type == "heading", !nodeText(n).trimmingCharacters(in: .whitespaces).isEmpty {
            items.append(OutlineItem(id: n.id ?? "", kind: "heading", level: n.attrs?["level"]?.int ?? 1, text: nodeText(n)))
        }
        if n.type == "pageCard" {
            let t = n.attrs?["title"]?.string ?? ""
            items.append(OutlineItem(id: n.id ?? "", kind: "page", level: 9, text: t.isEmpty ? "Untitled page" : t, docId: n.attrs?["docId"]?.string))
        }
    }
    return items
}

public struct TaskInfo: Hashable, Identifiable { public var id: String; public var text: String; public var checked: Bool }

public func tasksOf(_ root: Node) -> [TaskInfo] {
    var out: [TaskInfo] = []
    walk(root) { n in
        if n.type == "taskItem" {
            out.append(TaskInfo(id: n.id ?? "", text: n.content?.first.map(nodeText) ?? "", checked: n.attrs?["checked"]?.bool ?? false))
        }
    }
    return out
}

public struct AttachmentInfo: Hashable, Identifiable {
    public var id: String { kind + ref + blockId }
    public var blockId: String
    public var kind: String // image | link
    public var label: String
    public var ref: String
}

public func attachmentsOf(_ root: Node) -> [AttachmentInfo] {
    var out: [AttachmentInfo] = []
    var links = Set<String>()
    var current = ""
    walk(root) { n in
        if let id = n.id { current = id }
        if n.type == "file" {
            out.append(AttachmentInfo(blockId: n.id ?? "", kind: "file", label: n.attrs?["name"]?.string ?? "File", ref: n.attrs?["assetId"]?.string ?? ""))
        }
        if n.type == "linkPreview", let u = n.attrs?["url"]?.string, !links.contains(u) {
            links.insert(u)
            out.append(AttachmentInfo(blockId: n.id ?? "", kind: "link", label: n.attrs?["title"]?.string ?? u, ref: u))
        }
        if n.type == "image" {
            out.append(AttachmentInfo(blockId: n.id ?? "", kind: "image", label: n.attrs?["alt"]?.string.flatMap { $0.isEmpty ? nil : $0 } ?? "Image", ref: n.attrs?["assetId"]?.string ?? n.attrs?["src"]?.string ?? ""))
        }
        if n.type == "text", let marks = n.marks {
            for m in marks where m.type == "link" {
                if let href = m.attrs?["href"]?.string, !links.contains(href) {
                    links.insert(href)
                    out.append(AttachmentInfo(blockId: current, kind: "link", label: n.text ?? href, ref: href))
                }
            }
        }
    }
    return out
}

public extension Node {
    /// The tree without the blocks whose ids are given; lists and quotes left empty are dropped.
    func removingBlocks(_ ids: Set<String>) -> Node {
        var out = self
        out.content = content?.compactMap { child -> Node? in
            if let id = child.id, ids.contains(id) { return nil }
            let c = child.removingBlocks(ids)
            let container = ["bulletList", "orderedList", "taskList", "toggleList", "blockquote", "callout"].contains(c.type)
            return container && (c.content ?? []).isEmpty ? nil : c
        }
        return out
    }
}
