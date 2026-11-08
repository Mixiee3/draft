import Foundation

/// One slide of Present mode: a heading and the blocks under it until the next heading of
/// level 1 or 2. Anything before the first heading goes on a title slide.
public struct Slide: Hashable, Sendable {
    public var title: String
    public var lines: [SlideLine]
}

public struct SlideLine: Hashable, Sendable {
    public enum Kind: String, Sendable { case text, bullet, task, done, quote, subheading, code }
    public var kind: Kind
    public var text: String
    public var depth = 0
}

public func slides(_ root: Node, title: String) -> [Slide] {
    var out = [Slide(title: title, lines: [])]
    func add(_ l: SlideLine) { if !l.text.isEmpty { out[out.count - 1].lines.append(l) } }
    func list(_ n: Node, depth: Int) {
        for item in n.content ?? [] {
            let checked = item.attrs?["checked"]?.bool
            let kind: SlideLine.Kind = n.type == "taskList" ? (checked == true ? .done : .task) : .bullet
            for c in item.content ?? [] {
                if ["bulletList", "orderedList", "taskList"].contains(c.type) { list(c, depth: depth + 1) }
                else { add(SlideLine(kind: kind, text: nodeText(c), depth: depth)) }
            }
        }
    }
    for b in root.content ?? [] {
        switch b.type {
        case "heading":
            let level = b.attrs?["level"]?.int ?? 1
            if level <= 2 { out.append(Slide(title: nodeText(b), lines: [])) } else { add(SlideLine(kind: .subheading, text: nodeText(b))) }
        case "bulletList", "orderedList", "taskList": list(b, depth: 0)
        case "blockquote", "callout": add(SlideLine(kind: .quote, text: nodeText(b)))
        case "codeBlock": add(SlideLine(kind: .code, text: nodeText(b)))
        case "paragraph": add(SlideLine(kind: .text, text: nodeText(b)))
        default: break // images, tables and cards stay in the document
        }
    }
    return out
}
