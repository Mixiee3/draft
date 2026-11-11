import AppKit
import DraftCore

/// An attachment that represents a whole block (divider, image, page card, unknown node).
public final class BlockAttachment: NSTextAttachment {
    public var node: Node
    public let kind: BlockKind
    public init(kind: BlockKind, node: Node) {
        self.kind = kind
        self.node = node
        super.init(data: nil, ofType: nil)
    }
    required init?(coder: NSCoder) { fatalError("not supported") }
}

/// A flattened block: one per text paragraph.
struct FlatBlock {
    var info: BlockInfo
    var inline: [Node]
}

/// Converts between the portable document tree (DraftCore.Node) and the flat, attributed
/// paragraph representation that TextKit edits. Only *semantic* attributes are produced here;
/// visual attributes are derived later by `Styler`.
public enum Converter {

    // MARK: tree -> flat

    static func flatten(_ doc: Node) -> [FlatBlock] {
        var out: [FlatBlock] = []
        for n in doc.content ?? [] { flattenNode(n, indent: 0, into: &out) }
        if out.isEmpty { out.append(FlatBlock(info: .paragraph(), inline: [])) }
        return out
    }

    static func styleAttrs(_ n: Node) -> (String?, String?, String?) {
        (n.attrs?["blockColor"]?.string, n.attrs?["decoration"]?.string.flatMap { $0 == "none" ? nil : $0 }, n.attrs?["textAlign"]?.string.flatMap { $0 == "left" ? nil : $0 })
    }

    static func flattenNode(_ n: Node, indent: Int, into out: inout [FlatBlock], quoteId: String? = nil, container: (kind: BlockKind, icon: String?)? = nil) {
        let (color, deco, align) = styleAttrs(n)
        let id = n.id ?? newId("b_")
        switch n.type {
        case "paragraph":
            let caption = n.attrs?["variant"]?.string == "caption" ? "caption" : nil
            out.append(FlatBlock(info: BlockInfo(id: id, kind: quoteId != nil ? (container?.kind ?? .quote) : .paragraph, variant: caption, blockColor: color, decoration: deco, align: align, icon: container?.icon, containerId: quoteId, font: n.attrs?["font"]?.string), inline: n.content ?? []))
        case "heading":
            out.append(FlatBlock(info: BlockInfo(id: id, kind: .heading, level: max(1, min(4, n.attrs?["level"]?.int ?? 1)), blockColor: color, decoration: deco, align: align, font: n.attrs?["font"]?.string), inline: n.content ?? []))
        case "blockquote":
            for c in n.content ?? [] { flattenNode(c, indent: indent, into: &out, quoteId: id) }
        case "callout":
            for c in n.content ?? [] { flattenNode(c, indent: indent, into: &out, quoteId: id, container: (.callout, n.attrs?["icon"]?.string ?? "💡")) }
        case "codeBlock":
            let text = (n.content ?? []).map { $0.text ?? "" }.joined()
            out.append(FlatBlock(info: BlockInfo(id: id, kind: .code, language: n.attrs?["language"]?.string), inline: text.isEmpty ? [] : [.text(text)]))
        case "horizontalRule", "pageBreak":
            out.append(FlatBlock(info: BlockInfo(id: id, kind: .divider, raw: n), inline: []))
        case "file":
            out.append(FlatBlock(info: BlockInfo(id: id, kind: .file, raw: n), inline: []))
        case "image":
            out.append(FlatBlock(info: BlockInfo(id: id, kind: .image, raw: n), inline: []))
        case "pageCard":
            out.append(FlatBlock(info: BlockInfo(id: id, kind: .page, raw: n), inline: []))
        case "linkPreview":
            out.append(FlatBlock(info: BlockInfo(id: id, kind: .bookmark, raw: n), inline: []))
        case "table":
            out.append(FlatBlock(info: BlockInfo(id: id, kind: .table, raw: n), inline: []))
        case "collection":
            out.append(FlatBlock(info: BlockInfo(id: id, kind: .collection, raw: n), inline: []))
        case "bulletList", "orderedList", "taskList", "toggleList":
            let kind: BlockKind = n.type == "bulletList" ? .bullet : n.type == "orderedList" ? .ordered : n.type == "toggleList" ? .toggle : .task
            for (i, item) in (n.content ?? []).enumerated() {
                let (ic, idc, ia) = styleAttrs(item)
                let children = item.content ?? []
                let first = children.first
                let firstIsPara = first?.type == "paragraph"
                out.append(FlatBlock(info: BlockInfo(id: item.id ?? newId("b_"), kind: kind, indent: indent, checked: kind == .toggle ? (item.attrs?["open"]?.bool ?? true) : (item.attrs?["checked"]?.bool ?? false),
                                                     start: i == 0 && kind == .ordered ? (n.attrs?["start"]?.int ?? 1) : nil, blockColor: ic, decoration: idc, align: ia ?? (firstIsPara ? styleAttrs(first!).2 : nil),
                                                     innerId: firstIsPara ? first?.id : nil, containerId: id, font: item.attrs?["font"]?.string),
                                     inline: firstIsPara ? (first?.content ?? []) : []))
                for c in children.dropFirst(firstIsPara ? 1 : 0) {
                    if c.type == "paragraph" {
                        out.append(FlatBlock(info: BlockInfo(id: c.id ?? newId("b_"), kind: kind, indent: indent, continuation: true), inline: c.content ?? []))
                    } else {
                        flattenNode(c, indent: indent + 1, into: &out)
                    }
                }
            }
        default:
            out.append(FlatBlock(info: BlockInfo(id: id, kind: .opaque, raw: n), inline: []))
        }
    }

    // MARK: flat -> attributed

    public static func attributed(from doc: Node) -> (NSAttributedString, trailing: BlockInfo) {
        attributed(flat: flatten(doc))
    }

    static func attributed(flat: [FlatBlock]) -> (NSAttributedString, trailing: BlockInfo) {
        let flat = flat.isEmpty ? [FlatBlock(info: .paragraph(), inline: [])] : flat
        let out = NSMutableAttributedString()
        for (i, b) in flat.enumerated() {
            let para = NSMutableAttributedString()
            if b.info.kind.isAttachment, let raw = b.info.raw {
                let att = BlockAttachment(kind: b.info.kind, node: raw)
                para.append(NSAttributedString(attachment: att))
            } else {
                for n in b.inline { para.append(inlineToAttributed(n, code: b.info.kind == .code)) }
            }
            let isLast = i == flat.count - 1
            if !isLast { para.append(NSAttributedString(string: "\n")) }
            para.addAttribute(.draftBlock, value: b.info, range: NSRange(location: 0, length: para.length))
            out.append(para)
        }
        // A trailing empty paragraph has no characters; its block lives in `trailing`.
        let last = flat.last!
        return (out, last.info)
    }

    static func inlineToAttributed(_ n: Node, code: Bool) -> NSAttributedString {
        if n.type == "hardBreak" { return NSAttributedString(string: Chars.lineBreak) }
        guard n.type == "text", let text = n.text else { return NSAttributedString() }
        var attrs: [NSAttributedString.Key: Any] = [:]
        for m in n.marks ?? [] {
            switch m.type {
            case "bold": attrs[.draftBold] = true
            case "italic": attrs[.draftItalic] = true
            case "underline": attrs[.draftUnderline] = true
            case "strike": attrs[.draftStrike] = true
            case "code": attrs[.draftCode] = true
            case "highlight": attrs[.draftHighlight] = m.attrs?["color"]?.string ?? "#fff3a3"
            case "textStyle": if let c = m.attrs?["color"]?.string { attrs[.draftTextColor] = c }
            case "effect":
                if m.attrs?["kind"]?.string == "spectrum" {
                    let s = Spectrum(palette: m.attrs?["palette"]?.string ?? "aurora", speed: m.attrs?["speed"]?.string ?? "slow", direction: m.attrs?["direction"]?.string ?? "forward")
                    attrs[.draftEffect] = Spectrum(s.value)?.value ?? Spectrum().value
                } else if let k = m.attrs?["kind"]?.string, TextEffects.kinds.contains(k) { attrs[.draftEffect] = k }
            case "link": if let h = m.attrs?["href"]?.string { attrs[.draftLink] = h }
            case "docLink": if let d = m.attrs?["docId"]?.string { attrs[.draftDocLink] = d + (m.attrs?["blockId"]?.string.map { "#" + $0 } ?? "") }
            case "date": if let d = m.attrs?["date"]?.string { attrs[.draftDate] = d }
            default: break
            }
        }
        let s = code ? text.replacingOccurrences(of: "\n", with: Chars.lineBreak) : text.replacingOccurrences(of: "\n", with: Chars.lineBreak)
        return NSAttributedString(string: s, attributes: attrs)
    }

    // MARK: attributed -> flat

    static func flat(from s: NSAttributedString, trailing: BlockInfo) -> [FlatBlock] {
        var out: [FlatBlock] = []
        let ns = s.string as NSString
        var loc = 0
        let len = ns.length
        if len == 0 { return [FlatBlock(info: trailing, inline: [])] }
        while loc < len {
            let pr = ns.paragraphRange(for: NSRange(location: loc, length: 0))
            var content = pr
            if content.length > 0, ns.character(at: NSMaxRange(content) - 1) == 10 { content.length -= 1 }
            let info = (s.attribute(.draftBlock, at: pr.location, effectiveRange: nil) as? BlockInfo) ?? .paragraph()
            var inline: [Node] = []
            var raw: Node? = info.raw
            if info.kind.isAttachment {
                if content.length > 0, let att = s.attribute(.attachment, at: content.location, effectiveRange: nil) as? BlockAttachment { raw = att.node }
            } else {
                inline = inlineNodes(s, range: content, code: info.kind == .code)
            }
            out.append(FlatBlock(info: raw == info.raw ? info : info.with(raw: .some(raw)), inline: inline))
            loc = NSMaxRange(pr)
        }
        if ns.character(at: len - 1) == 10 { out.append(FlatBlock(info: trailing, inline: [])) }
        return out
    }

    static func inlineNodes(_ s: NSAttributedString, range: NSRange, code: Bool) -> [Node] {
        var nodes: [Node] = []
        s.enumerateAttributes(in: range, options: []) { attrs, r, _ in
            let text = (s.string as NSString).substring(with: r)
            var marks: [Mark] = []
            if attrs[.draftBold] != nil { marks.append(Mark("bold")) }
            if attrs[.draftItalic] != nil { marks.append(Mark("italic")) }
            if attrs[.draftUnderline] != nil { marks.append(Mark("underline")) }
            if attrs[.draftStrike] != nil { marks.append(Mark("strike")) }
            if attrs[.draftCode] != nil { marks.append(Mark("code")) }
            if let c = attrs[.draftHighlight] as? String { marks.append(Mark("highlight", attrs: ["color": .string(c)])) }
            if let c = attrs[.draftTextColor] as? String { marks.append(Mark("textStyle", attrs: ["color": .string(c)])) }
            if let k = attrs[.draftEffect] as? String {
                if let s = Spectrum(k) { marks.append(Mark("effect", attrs: ["kind": "spectrum", "palette": .string(s.palette), "speed": .string(s.speed), "direction": .string(s.direction)])) }
                else { marks.append(Mark("effect", attrs: ["kind": .string(k)])) }
            }
            if let h = attrs[.draftLink] as? String { marks.append(Mark("link", attrs: ["href": .string(h)])) }
            if let v = attrs[.draftDocLink] as? String {
                let parts = v.split(separator: "#", maxSplits: 1).map(String.init)
                var a: [String: JSONValue] = ["docId": .string(parts[0])]
                if parts.count > 1 { a["blockId"] = .string(parts[1]) }
                marks.append(Mark("docLink", attrs: a))
            }
            if let d = attrs[.draftDate] as? String { marks.append(Mark("date", attrs: ["date": .string(d)])) }
            let parts = text.components(separatedBy: Chars.lineBreak)
            for (i, p) in parts.enumerated() {
                if i > 0 {
                    if code { nodes.append(.text("\n")) } else { nodes.append(Node("hardBreak")) }
                }
                if !p.isEmpty { nodes.append(.text(p, marks: code || marks.isEmpty ? nil : marks)) }
            }
        }
        // Merge adjacent text nodes with identical marks (keeps files small and diffs stable).
        var merged: [Node] = []
        for n in nodes {
            if var last = merged.last, last.type == "text", n.type == "text", last.marks == n.marks {
                last.text = (last.text ?? "") + (n.text ?? "")
                merged[merged.count - 1] = last
            } else { merged.append(n) }
        }
        return merged
    }

    // MARK: flat -> tree

    static func blockNode(_ b: FlatBlock) -> Node {
        let i = b.info
        var attrs: [String: JSONValue] = ["id": .string(i.id)]
        if let c = i.blockColor { attrs["blockColor"] = .string(c) }
        if let d = i.decoration { attrs["decoration"] = .string(d) }
        if let a = i.align { attrs["textAlign"] = .string(a) }
        if let f = i.font { attrs["font"] = .string(f) }
        let content: [Node]? = b.inline.isEmpty ? nil : b.inline
        switch i.kind {
        case .heading:
            attrs["level"] = .number(Double(i.level))
            return Node("heading", attrs: attrs, content: content)
        case .code:
            if let l = i.language { attrs["language"] = .string(l) }
            let text = b.inline.map { $0.text ?? "" }.joined()
            return Node("codeBlock", attrs: attrs, content: text.isEmpty ? nil : [.text(text)])
        case .divider, .image, .page, .file, .bookmark, .table, .collection, .opaque:
            var n = i.raw ?? Node(i.kind == .divider ? "horizontalRule" : "paragraph")
            // Unknown nodes are preserved verbatim; known attachment blocks keep a stable id.
            if i.kind != .opaque || n.id != nil { n[attr: "id"] = .string(i.id) }
            return n
        default:
            if i.variant == "caption" { attrs["variant"] = "caption" }
            return Node("paragraph", attrs: attrs, content: content)
        }
    }

    static func tree(from flat: [FlatBlock]) -> Node {
        var i = 0
        let nodes = parseSeq(flat, &i, indent: 0, top: true)
        return Node("doc", content: nodes.isEmpty ? [Node("paragraph", attrs: ["id": .string(newId("b_"))])] : nodes)
    }

    static func listType(_ k: BlockKind) -> String { k == .bullet ? "bulletList" : k == .ordered ? "orderedList" : k == .toggle ? "toggleList" : "taskList" }

    static func parseSeq(_ bs: [FlatBlock], _ i: inout Int, indent: Int, top: Bool) -> [Node] {
        var nodes: [Node] = []
        while i < bs.count {
            let b = bs[i]
            if b.info.kind.isList {
                if !top && b.info.indent < indent { return nodes }
                if !top && b.info.continuation && b.info.indent <= indent { return nodes }
                let lvl = top ? b.info.indent : max(indent, b.info.indent)
                let kind = b.info.kind
                var items: [Node] = []
                let listId = b.info.containerId ?? newId("b_")
                var listAttrs: [String: JSONValue] = ["id": .string(listId)]
                if kind == .ordered { listAttrs["start"] = .number(Double(b.info.start ?? 1)) }
                while i < bs.count, bs[i].info.kind == kind, bs[i].info.indent == lvl, !bs[i].info.continuation {
                    let item = bs[i]; i += 1
                    var pAttrs: [String: JSONValue] = ["id": .string(item.info.innerId ?? newId("b_"))]
                    if let a = item.info.align { pAttrs["textAlign"] = .string(a) }
                    var children = [Node("paragraph", attrs: pAttrs, content: item.inline.isEmpty ? nil : item.inline)]
                    while i < bs.count {
                        let n = bs[i]
                        if n.info.kind.isList && n.info.continuation && n.info.indent == lvl {
                            children.append(Node("paragraph", attrs: ["id": .string(n.info.id)], content: n.inline.isEmpty ? nil : n.inline)); i += 1
                        } else if n.info.kind.isList && n.info.indent > lvl {
                            children += parseSeq(bs, &i, indent: lvl + 1, top: false)
                        } else { break }
                    }
                    var itemAttrs: [String: JSONValue] = ["id": .string(item.info.id)]
                    if kind == .task { itemAttrs["checked"] = .bool(item.info.checked) }
                    if kind == .toggle { itemAttrs["open"] = .bool(item.info.checked) }
                    if let c = item.info.blockColor { itemAttrs["blockColor"] = .string(c) }
                    if let d = item.info.decoration { itemAttrs["decoration"] = .string(d) }
                    if let f = item.info.font { itemAttrs["font"] = .string(f) }
                    items.append(Node(kind == .task ? "taskItem" : kind == .toggle ? "toggleItem" : "listItem", attrs: itemAttrs, content: children))
                }
                if items.isEmpty { // stray continuation: treat as plain paragraph
                    nodes.append(Node("paragraph", attrs: ["id": .string(b.info.id)], content: b.inline.isEmpty ? nil : b.inline)); i += 1
                    continue
                }
                nodes.append(Node(listType(kind), attrs: listAttrs, content: items))
                if !top, i < bs.count, !(bs[i].info.kind.isList && bs[i].info.indent >= indent) { return nodes }
            } else {
                if !top { return nodes }
                if b.info.kind == .quote || b.info.kind == .callout {
                    let kind = b.info.kind
                    let qid = b.info.containerId ?? newId("b_")
                    var paras: [Node] = []
                    while i < bs.count, bs[i].info.kind == kind, (bs[i].info.containerId ?? qid) == qid {
                        let q = bs[i]; i += 1
                        var p = blockNode(FlatBlock(info: q.info.with(kind: .paragraph), inline: q.inline))
                        p.attrs?["id"] = .string(q.info.id)
                        paras.append(p)
                    }
                    var attrs: [String: JSONValue] = ["id": .string(qid)]
                    if kind == .callout { attrs["icon"] = .string(b.info.icon ?? "💡") }
                    nodes.append(Node(kind == .quote ? "blockquote" : "callout", attrs: attrs, content: paras))
                } else {
                    nodes.append(blockNode(b)); i += 1
                }
            }
        }
        return nodes
    }

    public static func document(from s: NSAttributedString, trailing: BlockInfo) -> Node {
        tree(from: flat(from: s, trailing: trailing))
    }
}
