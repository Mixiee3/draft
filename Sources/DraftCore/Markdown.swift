import Foundation

public struct MarkdownResult {
    public var markdown: String
    public var assets: [String]
    public var pages: [String]
    /// Human-readable notes about formatting Markdown cannot represent.
    public var lossy: [String]
}

public enum Markdown {
    static let specials = Set("\\`*_[]#<>|~=")

    static func escape(_ s: String) -> String {
        var o = ""
        for ch in s { if specials.contains(ch) { o.append("\\") }; o.append(ch) }
        return o
    }

    static func inline(_ nodes: [Node]?, _ lossy: inout Set<String>, link docPath: (String) -> String? = { _ in nil }) -> String {
        guard let nodes else { return "" }
        var out = ""
        for n in nodes {
            if n.type == "hardBreak" { out += "  \n"; continue }
            guard n.type == "text", let raw = n.text else { continue }
            let marks = n.marks ?? []
            let isCode = marks.contains { $0.type == "code" }
            let t = isCode ? raw : escape(raw)
            let lead = String(t.prefix(while: { $0 == " " }))
            let rest = t.dropFirst(lead.count)
            let trail = String(rest.reversed().prefix(while: { $0 == " " }))
            var core = String(rest.dropLast(trail.count))
            if core.isEmpty { out += t; continue }
            for m in marks {
                switch m.type {
                case "code": core = "`\(core)`"
                case "bold": core = "**\(core)**"
                case "italic": core = "*\(core)*"
                case "strike": core = "~~\(core)~~"
                case "underline": core = "<u>\(core)</u>"
                case "highlight":
                    core = "==\(core)=="
                    if m.attrs?["color"]?.string != nil { lossy.insert("Highlight colors are exported as plain ==highlight==.") }
                case "textStyle":
                    if m.attrs?["color"]?.string != nil { lossy.insert("Text colors are not representable in Markdown.") }
                default: break
                }
            }
            if let link = marks.first(where: { $0.type == "link" }) { core = "[\(core)](\(link.attrs?["href"]?.string ?? ""))" }
            if let dl = marks.first(where: { $0.type == "docLink" }), let d = dl.attrs?["docId"]?.string, let p = docPath(d) {
                core = "[\(core)](\(p.replacingOccurrences(of: " ", with: "%20")))"
            }
            if let dm = marks.first(where: { $0.type == "date" }), let d = dm.attrs?["date"]?.string { core = d.replacingOccurrences(of: "T", with: " ") }
            out += lead + core + trail
        }
        return out
    }

    public static func render(_ doc: DocFile, assetPath: (String) -> String, pageLink: (String, String) -> String?) -> MarkdownResult {
        var lossy = Set<String>()
        var assets: [String] = []
        var pages: [String] = []

        func noteStyle(_ n: Node) {
            if n.attrs?["blockColor"]?.string != nil || (n.attrs?["decoration"]?.string.map { $0 != "none" } ?? false) {
                lossy.insert("Block colors and decorations are not representable in Markdown.")
            }
            if let a = n.attrs?["textAlign"]?.string, a != "left" { lossy.insert("Text alignment is not representable in Markdown.") }
        }

        func block(_ n: Node, _ indent: String) -> [String] {
            noteStyle(n)
            switch n.type {
            case "paragraph":
                let isCaption = n.attrs?["variant"]?.string == "caption"
                let t = inline(n.content, &lossy, link: { pageLink($0, "") })
                return [indent + (isCaption && !t.isEmpty ? "<small>\(t)</small>" : t)]
            case "heading":
                let lvl = min(6, n.attrs?["level"]?.int ?? 1)
                return [indent + String(repeating: "#", count: lvl) + " " + inline(n.content, &lossy, link: { pageLink($0, "") })]
            case "blockquote":
                return blocks(n.content ?? [], "").map { indent + ($0.isEmpty ? ">" : "> " + $0) }
            case "callout":
                lossy.insert("Callouts are exported as quotes with their icon.")
                var lines = blocks(n.content ?? [], "")
                if !lines.isEmpty { lines[0] = (n.attrs?["icon"]?.string ?? "💡") + " " + lines[0] }
                return lines.map { indent + ($0.isEmpty ? ">" : "> " + $0) }
            case "pageBreak":
                return [indent + "<div style=\"page-break-after: always\"></div>"]
            case "codeBlock":
                let lang = n.attrs?["language"]?.string ?? ""
                let text = (n.content ?? []).map { $0.text ?? "" }.joined()
                return [indent + "```" + lang] + text.components(separatedBy: "\n").map { indent + $0 } + [indent + "```"]
            case "horizontalRule":
                return [indent + "---"]
            case "image":
                var src = n.attrs?["src"]?.string ?? ""
                if let a = n.attrs?["assetId"]?.string { assets.append(a); src = assetPath(a) }
                let enc = src.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.union(.init(charactersIn: ":"))) ?? src
                var lines = [indent + "![\(escape(n.attrs?["alt"]?.string ?? ""))](\(enc))"]
                if let cap = n.attrs?["caption"]?.string, !cap.isEmpty { lines.append(indent + "*\(escape(cap))*") }
                if n.attrs?["width"] != nil { lossy.insert("Image sizes are not representable in Markdown.") }
                return lines
            case "file":
                let name = n.attrs?["name"]?.string ?? "File"
                guard let a = n.attrs?["assetId"]?.string else { return [indent + escape(name)] }
                assets.append(a)
                let p = assetPath(a)
                return [indent + "[\(escape(name))](\(p.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? p))"]
            case "linkPreview":
                let u = n.attrs?["url"]?.string ?? ""
                let t = n.attrs?["title"]?.string ?? u
                return [indent + "[\(escape(t.isEmpty ? u : t))](\(u))"]
            case "pageCard":
                let t = n.attrs?["title"]?.string ?? ""
                let title = t.isEmpty ? "Untitled page" : t
                let docId = n.attrs?["docId"]?.string
                if let d = docId { pages.append(d) }
                if let d = docId, let link = pageLink(d, title) {
                    let enc = link.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? link
                    return [indent + "[\(escape(title))](\(enc))"]
                }
                return [indent + "**\(escape(title))**"]
            case "bulletList", "orderedList", "taskList", "toggleList":
                if n.type == "toggleList" { lossy.insert("Toggle lists are exported as bulleted lists (always expanded).") }
                var lines: [String] = []
                var num = n.attrs?["start"]?.int ?? 1
                for item in n.content ?? [] {
                    var marker = "- "
                    if n.type == "orderedList" { marker = "\(num). "; num += 1 }
                    if item.type == "taskItem" { marker = (item.attrs?["checked"]?.bool ?? false) ? "- [x] " : "- [ ] " }
                    noteStyle(item)
                    let children = item.content ?? []
                    let firstLines = children.first.map { block($0, "") } ?? [""]
                    lines.append(indent + marker + (firstLines.first ?? ""))
                    let pad = indent + String(repeating: " ", count: marker.count)
                    firstLines.dropFirst().forEach { lines.append(pad + $0) }
                    for c in children.dropFirst() {
                        if c.type == "paragraph" { lines.append("") }
                        lines.append(contentsOf: block(c, pad))
                    }
                }
                return lines
            default:
                if n.content == nil && n.text == nil { lossy.insert("Unknown block “\(n.type)” was skipped in Markdown (kept in .draft.json).") }
                return [indent + inline(n.content, &lossy, link: { pageLink($0, "") })]
            }
        }

        func blocks(_ nodes: [Node], _ indent: String) -> [String] {
            var res: [String] = []
            for (i, n) in nodes.enumerated() {
                if i > 0 { res.append("") }
                res.append(contentsOf: block(n, indent))
            }
            return res
        }

        var out: [String] = []
        if !doc.title.isEmpty { out += ["# " + escape(doc.title), ""] }
        out += blocks(doc.content.content ?? [], "")
        var md = out.joined(separator: "\n")
        while md.contains("\n\n\n") { md = md.replacingOccurrences(of: "\n\n\n", with: "\n\n") }
        md = md.trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
        return MarkdownResult(markdown: md, assets: assets, pages: pages, lossy: lossy.sorted())
    }

    /// File-system-safe name that keeps Unicode letters (Czech, Japanese…) intact.
    public static func safeFileName(_ title: String, fallback: String = "Untitled") -> String {
        var s = title.precomposedStringWithCanonicalMapping
        for ch in ["/", "\\", "?", "%", "*", ":", "|", "\"", "<", ">"] { s = s.replacingOccurrences(of: ch, with: "-") }
        s = s.filter { !($0.asciiValue.map { $0 < 32 } ?? false) }
        s = s.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        while s.hasPrefix(".") { s.removeFirst() }
        s = String(s.prefix(120))
        return s.isEmpty ? fallback : s
    }
}

/// Builds a portable export bundle: one `.md` per document (nested pages included and linked),
/// an `assets/` folder, and a lossless `draft-export.json` with the native documents.
public enum ExportBuilder {
    public struct Bundle {
        public var files: [(path: String, content: String)]
        public var assets: [String]
        public var lossy: [String]
    }

    public static func build(rootIds: [String], metas: [String: DocMeta], folders: [Folder], groupByFolder: Bool, load: (String) -> DocFile?) throws -> Bundle {
        var files: [(String, String)] = []
        var allAssets: [String] = []
        var lossy = Set<String>()
        var natives: [DocFile] = []
        var names: [String: String] = [:] // docId -> relative path
        var used = Set<String>()
        var queue = rootIds
        var visited = Set<String>()

        func dirFor(_ id: String) -> String {
            guard groupByFolder, let fid = metas[id]?.folderId, let f = folders.first(where: { $0.id == fid }) else { return "" }
            return Markdown.safeFileName(f.name) + "/"
        }
        func pathFor(_ id: String) -> String {
            if let p = names[id] { return p }
            let base = dirFor(id) + Markdown.safeFileName(metas[id]?.title ?? "")
            var p = base + ".md"; var i = 2
            while used.contains(p.lowercased()) { p = "\(base) \(i).md"; i += 1 }
            used.insert(p.lowercased()); names[id] = p
            return p
        }

        while let id = queue.first {
            queue.removeFirst()
            guard !visited.contains(id), let doc = load(id) else { continue }
            visited.insert(id)
            natives.append(doc)
            walk(doc.content) { if $0.type == "pageCard", let d = $0.attrs?["docId"]?.string { queue.append(d) } }
        }
        let exported = visited
        for doc in natives {
            let id = doc.id
            let myPath = pathFor(id)
            let depth = myPath.split(separator: "/").count - 1
            let up = String(repeating: "../", count: depth)
            let res = Markdown.render(doc, assetPath: { up + "assets/" + $0 }, pageLink: { pid, _ in
                guard metas[pid] != nil, exported.contains(pid) else { return nil }
                return up + pathFor(pid)
            })
            files.append((myPath, res.markdown))
            allAssets += res.assets
            lossy.formUnion(res.lossy)
            if let c = doc.appearance.cover { allAssets.append(c.assetId) }
        }
        let native: JSONValue = .object([
            "format": "draft-export",
            "formatVersion": 1,
            "docs": try JSONDecoder().decode(JSONValue.self, from: DraftJSON.encode(natives)),
            "metas": try JSONDecoder().decode(JSONValue.self, from: DraftJSON.encode(natives.compactMap { metas[$0.id] })),
        ])
        files.append(("draft-export.json", String(decoding: try DraftJSON.encode(native, pretty: true), as: UTF8.self)))
        return Bundle(files: files, assets: allAssets, lossy: lossy.sorted())
    }
}
