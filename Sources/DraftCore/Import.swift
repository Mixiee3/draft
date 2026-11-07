import Foundation

/// What an import adds to the vault. Nothing is written until the app saves it.
public struct ImportResult {
    public var docs: [DocFile] = []
    public var metas: [DocMeta] = []
    public var folders: [Folder] = []
    public var styles: [UserStyle] = []
    public var warnings: [String] = []
    public init() {}
}

public enum Importer {
    // MARK: Markdown

    /// Title from a leading `# heading` (removed from the body) or the file name; YAML
    /// frontmatter is dropped from the text.
    static func split(_ text: String, fallback: String) -> (title: String, body: String) {
        var lines = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        if lines.first == "---", let end = lines.dropFirst().firstIndex(of: "---") { lines.removeSubrange(0...end) }
        while let f = lines.first, f.trimmingCharacters(in: .whitespaces).isEmpty { lines.removeFirst() }
        if let f = lines.first, f.hasPrefix("# ") { return (String(f.dropFirst(2)).trimmingCharacters(in: .whitespaces), lines.dropFirst().joined(separator: "\n")) }
        return (fallback, lines.joined(separator: "\n"))
    }

    /// Markdown files (paths relative to the chosen folder). Top-level subfolders become folders,
    /// links between imported files become document links, images become assets via `storeAsset`.
    public static func markdown(files: [(path: String, text: String)], spaceId: String?, storeAsset: (String, String) -> String?) -> ImportResult {
        var r = ImportResult()
        var ids: [String: String] = [:]
        for f in files { ids[normalize(f.path)] = newId("d_") }
        var folderIds: [String: String] = [:]
        for f in files {
            let comps = f.path.split(separator: "/")
            let base = (String(comps.last ?? "") as NSString).deletingPathExtension
            let (title, body) = split(f.text, fallback: base)
            var blocks = MarkdownImport.blocks(body)
            blocks = blocks.map { linkify($0, from: f.path, ids: ids) }
            blocks = blocks.flatMap { images($0, from: f.path, storeAsset: storeAsset) }
            let id = ids[normalize(f.path)]!
            var doc = DocFile.empty(id: id, title: title)
            if !blocks.isEmpty { doc.content = ensureBlockIds(Node("doc", content: blocks)) }
            var meta = DocMeta(id: id, title: title)
            meta.applyDerived(from: doc)
            meta.spaceId = spaceId
            if comps.count > 1 {
                let name = String(comps[0])
                if folderIds[name] == nil {
                    let folder = Folder(name: name, order: Double(r.folders.count), spaceId: spaceId)
                    folderIds[name] = folder.id
                    r.folders.append(folder)
                }
                meta.folderId = folderIds[name]
            }
            r.docs.append(doc); r.metas.append(meta)
        }
        return r
    }

    static func normalize(_ p: String) -> String {
        var out: [Substring] = []
        for c in p.split(separator: "/") where c != "." && !c.isEmpty { if c == ".." { if !out.isEmpty { out.removeLast() } } else { out.append(c) } }
        return out.joined(separator: "/").lowercased()
    }

    static func resolve(_ href: String, from path: String) -> String? {
        guard !href.contains("://"), !href.hasPrefix("#"), !href.hasPrefix("mailto:") else { return nil }
        let clean = (href.removingPercentEncoding ?? href).components(separatedBy: "#")[0]
        let dir = (path as NSString).deletingLastPathComponent
        return normalize(dir.isEmpty ? clean : dir + "/" + clean)
    }

    /// `[Title](other.md)` to an imported file becomes a document link.
    static func linkify(_ n: Node, from path: String, ids: [String: String]) -> Node {
        var out = n
        if n.type == "text", let marks = n.marks, let i = marks.firstIndex(where: { $0.type == "link" }),
           let href = marks[i].attrs?["href"]?.string, let target = resolve(href, from: path).flatMap({ ids[$0] }) {
            var ms = marks
            ms[i] = Mark("docLink", attrs: ["docId": .string(target)])
            out.marks = ms
        }
        out.content = n.content?.map { linkify($0, from: path, ids: ids) }
        return out
    }

    /// A paragraph that is only `![alt](file)` becomes an image block when the file can be read.
    static func images(_ n: Node, from path: String, storeAsset: (String, String) -> String?) -> [Node] {
        guard n.type == "paragraph", let c = n.content, c.count == 2, c[0].text == "!", let m = c[1].marks?.first(where: { $0.type == "link" }),
              let href = m.attrs?["href"]?.string else { return [n] }
        let dir = (path as NSString).deletingLastPathComponent
        let rel = (href.removingPercentEncoding ?? href)
        guard let asset = storeAsset(dir.isEmpty ? rel : dir + "/" + rel, (rel as NSString).pathExtension) else { return [n] }
        return [Node("image", attrs: ["id": .string(newId("b_")), "assetId": .string(asset), "alt": .string(c[1].text ?? "")])]
    }

    // MARK: OPML

    /// An OPML outline: one document, outline items as nested bullets.
    public static func opml(_ data: Data, fallbackTitle: String, spaceId: String?) throws -> ImportResult {
        final class P: NSObject, XMLParserDelegate {
            var title = ""
            var stack: [[Node]] = [[]]
            var inTitle = false
            func parser(_ p: XMLParser, didStartElement e: String, namespaceURI: String?, qualifiedName: String?, attributes a: [String: String]) {
                if e == "title" { inTitle = true }
                if e == "outline" { stack.append([]); pending.append(a["text"] ?? a["title"] ?? "") }
            }
            var pending: [String] = []
            func parser(_ p: XMLParser, foundCharacters s: String) { if inTitle { title += s } }
            func parser(_ p: XMLParser, didEndElement e: String, namespaceURI: String?, qualifiedName: String?) {
                if e == "title" { inTitle = false }
                if e == "outline" {
                    let kids = stack.removeLast()
                    let text = pending.removeLast()
                    var item = [Node("paragraph", content: text.isEmpty ? nil : MarkdownImport.inline(text))]
                    if !kids.isEmpty { item.append(Node("bulletList", content: kids)) }
                    stack[stack.count - 1].append(Node("listItem", content: item))
                }
            }
        }
        let p = P()
        let x = XMLParser(data: data)
        x.delegate = p
        guard x.parse() else { throw MigrationError(message: "This OPML file could not be read (\(x.parserError?.localizedDescription ?? "invalid XML")).") }
        var r = ImportResult()
        let title = p.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? fallbackTitle : p.title.trimmingCharacters(in: .whitespacesAndNewlines)
        var doc = DocFile.empty(id: newId("d_"), title: title)
        if let items = p.stack.first, !items.isEmpty { doc.content = ensureBlockIds(Node("doc", content: [Node("bulletList", content: items)])) }
        var meta = DocMeta(id: doc.id, title: title)
        meta.applyDerived(from: doc)
        meta.spaceId = spaceId
        r.docs = [doc]; r.metas = [meta]
        return r
    }

    // MARK: Draft JSON

    /// Draft's own `draft-export.json`: documents, metadata, folders and saved styles. Ids that
    /// already exist in the vault get new ones, and every reference follows.
    public static func draftJSON(_ data: Data, existingDocs: Set<String>, existingFolders: Set<String>, existingStyles: Set<String>, spaceId: String?) throws -> ImportResult {
        guard let root = try JSONDecoder().decode(JSONValue.self, from: data).object, root["format"]?.string == "draft-export" else {
            throw MigrationError(message: "This is not a Draft export (draft-export.json).")
        }
        func decode<T: Decodable>(_ k: String, _ t: T.Type) throws -> T? { try root[k].map { try JSONDecoder().decode(T.self, from: JSONEncoder().encode($0)) } }
        let docs = try decode("docs", [DocFile].self) ?? []
        let metas = try decode("metas", [DocMeta].self) ?? []
        let folders = try decode("folders", [Folder].self) ?? []
        let styles = try decode("styles", [UserStyle].self) ?? []
        var idMap: [String: String] = [:]
        for d in docs where existingDocs.contains(d.id) { idMap[d.id] = newId("d_") }
        var folderMap: [String: String] = [:]
        for f in folders where existingFolders.contains(f.id) { folderMap[f.id] = newId("f_") }
        func map(_ id: String?) -> String? { id.map { idMap[$0] ?? $0 } }
        func rewrite(_ n: Node) -> Node {
            var out = n
            if n.type == "pageCard", let d = n.attrs?["docId"]?.string, let m = idMap[d] { out[attr: "docId"] = .string(m) }
            if var c = CollectionData(node: n), let id = n.id {
                c.items = c.items.map { var i = $0; i.docId = idMap[i.docId] ?? i.docId; return i }
                out = c.node(id: id)
            }
            out.marks = n.marks?.map { m in
                var m = m
                if m.type == "docLink", let d = m.attrs?["docId"]?.string, let nd = idMap[d] { m.attrs?["docId"] = .string(nd) }
                return m
            }
            out.content = out.content?.map(rewrite)
            return out
        }
        var r = ImportResult()
        for var d in docs {
            d.id = map(d.id)!
            d.content = rewrite(d.content)
            r.docs.append(d)
        }
        let byId = Dictionary(metas.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        for d in docs {
            var m = byId[d.id] ?? DocMeta(id: d.id, title: d.title)
            m.id = map(d.id)!
            m.parentDocId = map(m.parentDocId)
            m.folderId = m.folderId.map { folderMap[$0] ?? $0 }
            m.spaceId = spaceId
            m.deletedAt = nil
            if let doc = r.docs.first(where: { $0.id == m.id }) { m.applyDerived(from: doc) }
            r.metas.append(m)
        }
        r.folders = folders.filter { !existingFolders.contains($0.id) || folderMap[$0.id] != nil }.map { f in var f = f; f.id = folderMap[f.id] ?? f.id; f.spaceId = spaceId; return f }
        r.styles = styles.filter { !existingStyles.contains($0.id) }
        if r.docs.count != docs.count { r.warnings.append("Some documents could not be read.") }
        return r
    }
}

/// Templates that ship with Draft (original content). Saved templates are documents with
/// `DocMeta.template` set to their category.
public enum BuiltInTemplates {
    public struct Template: Identifiable { public let id: String; public let title: String; public let category: String; public let markdown: String }
    public static let all: [Template] = [
        Template(id: "tpl_meeting", title: "Meeting notes", category: "Work", markdown: "## Attendees\n- \n\n## Agenda\n1. \n\n## Decisions\n- \n\n## Actions\n- [ ] "),
        Template(id: "tpl_brief", title: "Project brief", category: "Work", markdown: "## Why\n\n## Outcome we want\n\n## Scope\n- In:\n- Out:\n\n## Milestones\n| Milestone | Date | Owner |\n| --- | --- | --- |\n|  |  |  |\n\n## Risks\n- "),
        Template(id: "tpl_weekly", title: "Weekly review", category: "Personal", markdown: "## What went well\n- \n\n## What was hard\n- \n\n## Next week\n- [ ] \n\n## One thing to let go of\n"),
        Template(id: "tpl_reading", title: "Reading notes", category: "Learning", markdown: "**Author:** \n**Finished:** \n\n## Big ideas\n- \n\n## Quotes\n> \n\n## What I'll try\n- [ ] "),
        Template(id: "tpl_daily", title: "Daily plan", category: "Personal", markdown: "## Top three\n- [ ] \n- [ ] \n- [ ] \n\n## Notes\n\n## Grateful for\n- "),
    ]

    public static func content(_ t: Template) -> Node { ensureBlockIds(Node("doc", content: MarkdownImport.blocks(t.markdown))) }
}
