import Foundation

public enum DraftToolError: LocalizedError {
    case unavailable(String)
    case invalidDocument
    case missingDocument
    case missingBlock

    public var errorDescription: String? {
        switch self {
        case .unavailable(let reason): return reason
        case .invalidDocument: return "The document ID is invalid or belongs to another Space."
        case .missingDocument: return "The document file is missing."
        case .missingBlock: return "The block was not found in that document."
        }
    }
}

/// A fresh, read-only snapshot for external tools. It never calls Vault.loadLibrary or Vault.loadDoc,
/// because those methods may migrate and write older files.
public struct DraftTools {
    public let vaultURL: URL
    public let library: Library

    public init(vaultURL: URL) throws {
        self.vaultURL = vaultURL
        let file = vaultURL.appendingPathComponent("library.json")
        guard let data = try? Data(contentsOf: file) else { throw DraftToolError.unavailable("Draft's vault is not available at \(vaultURL.path).") }
        library = try JSONDecoder().decode(Library.self, from: data)
        guard library.schemaVersion == librarySchemaVersion else {
            throw DraftToolError.unavailable("This Draft vault schema is not supported by the tool bridge. Open it in Draft first.")
        }
    }

    public var spaces: [Space] { library.spaces.map { Space(id: $0.id, name: $0.name) } }

    public func documents(spaceId: String? = nil, limit: Int = 100) throws -> [DocMeta] {
        let selected = spaceId ?? library.space.id
        guard library.spaces.contains(where: { $0.id == selected }) else { throw DraftToolError.unavailable("Space not found.") }
        return Array(library.docs.values.filter { $0.spaceId == selected && $0.deletedAt == nil && $0.template == nil }
            .sorted { $0.updatedAt > $1.updatedAt }.prefix(max(1, min(limit, 500))))
    }

    public func document(_ id: String) throws -> DocFile {
        guard let meta = library.docs[id], meta.deletedAt == nil, meta.template == nil,
              library.spaces.contains(where: { $0.id == meta.spaceId }) else { throw DraftToolError.invalidDocument }
        guard id.range(of: "^[A-Za-z0-9_-]{1,64}$", options: .regularExpression) != nil else { throw DraftToolError.invalidDocument }
        let file = vaultURL.appendingPathComponent("docs/\(id).json")
        guard let data = try? Data(contentsOf: file) else { throw DraftToolError.missingDocument }
        let doc = try JSONDecoder().decode(DocFile.self, from: data)
        guard doc.id == id, doc.schemaVersion == docSchemaVersion else { throw DraftToolError.invalidDocument }
        return doc
    }

    public func markdown(_ id: String, maxCharacters: Int = 30_000) throws -> String {
        let doc = try document(id)
        let result = Markdown.render(doc, assetPath: { _ in "" }, pageLink: { _, _ in nil }, pageTitle: { library.docs[$0]?.title ?? "Untitled" })
        return String(result.markdown.prefix(max(100, min(maxCharacters, 100_000))))
    }

    public struct EditableBlock: Codable, Sendable {
        public var id: String
        public var type: String
        public var text: String
        public var markdown: String
        public var attrs: [String: JSONValue]
        /// For tables: row ids and each cell's id, text and Markdown, so edits can address them.
        public var rows: [TableRow]? = nil
    }

    public struct TableRow: Codable, Sendable { public var id: String; public var cells: [TableCell] }
    public struct TableCell: Codable, Sendable { public var id: String; public var text: String; public var markdown: String }

    public struct DocumentStructure: Codable, Sendable {
        public var documentId: String
        public var title: String
        public var revision: String
        public var styleId: String
        public var blocks: [EditableBlock]
    }

    public func structure(_ id: String) throws -> DocumentStructure {
        let doc = try document(id)
        var blocks: [EditableBlock] = []
        let editable: Set<String> = ["paragraph", "heading", "codeBlock", "listItem", "taskItem", "toggleItem", "image", "file", "pageCard", "table", "collection", "linkPreview", "horizontalRule", "pageBreak"]
        func visit(_ node: Node) {
            if editable.contains(node.type), let blockId = node.id {
                var fragment = DocFile.empty(id: "excerpt", title: "")
                let wrapped: Node
                switch node.type {
                case "listItem": wrapped = Node("bulletList", content: [node])
                case "taskItem": wrapped = Node("taskList", content: [node])
                case "toggleItem": wrapped = Node("toggleList", content: [node])
                default: wrapped = node
                }
                fragment.content = Node("doc", content: [wrapped])
                let markdown = Markdown.render(fragment, assetPath: { _ in "" }, pageLink: { _, _ in nil }).markdown
                var block = EditableBlock(id: blockId, type: node.type, text: docPlainText(node), markdown: markdown, attrs: node.attrs ?? [:])
                if node.type == "table" {
                    block.rows = (node.content ?? []).map { r in
                        TableRow(id: r.id ?? "", cells: (r.content ?? []).map { c in
                            var lossy = Set<String>()
                            return TableCell(id: c.id ?? "", text: nodeText(c), markdown: Markdown.inline(c.content ?? [], &lossy))
                        })
                    }
                }
                blocks.append(block)
                if node.type == "table" { return }
                if ["listItem", "taskItem", "toggleItem"].contains(node.type) { return }
            }
            for child in node.content ?? [] { visit(child) }
        }
        visit(doc.content)
        return try DocumentStructure(documentId: id, title: doc.title, revision: AgentProposalStore.revision(doc), styleId: doc.appearance.styleId, blocks: blocks)
    }

    public func block(docId: String, blockId: String) throws -> String {
        let doc = try document(docId)
        guard let block = doc.content.block(blockId) else { throw DraftToolError.missingBlock }
        var fragment = DocFile.empty(id: "excerpt", title: "")
        let rendered: Node
        switch block.type {
        case "taskItem": rendered = Node("taskList", content: [block])
        case "toggleItem": rendered = Node("toggleList", content: [block])
        case "listItem": rendered = Node("bulletList", content: [block])
        default: rendered = block
        }
        fragment.content = Node("doc", content: [rendered])
        return Markdown.render(fragment, assetPath: { _ in "" }, pageLink: { _, _ in nil }).markdown
    }

    public struct SearchHit: Codable, Sendable {
        public var docId: String
        public var blockId: String
        public var title: String
        public var text: String
        public var score: Double
    }

    public func search(_ query: String, spaceId: String? = nil, limit: Int = 10) throws -> [SearchHit] {
        let selected = spaceId ?? library.space.id
        guard library.spaces.contains(where: { $0.id == selected }) else { throw DraftToolError.unavailable("Space not found.") }
        let metas = library.docs.values.filter { $0.spaceId == selected && $0.deletedAt == nil && $0.template == nil }
        var entries: [String: DocIndexEntry] = [:]
        var titles: [String: String] = [:]
        for meta in metas {
            guard let doc = try? document(meta.id) else { continue }
            entries[meta.id] = VaultIndex.entry(for: doc, daily: meta.dailyDate, rules: library.settings.tagRules)
            titles[meta.id] = meta.title
        }
        return Retrieval.rank(query, entries: entries, titles: titles, limit: max(1, min(limit, 30))).map {
            SearchHit(docId: $0.docId, blockId: $0.blockId, title: titles[$0.docId] ?? "Untitled", text: $0.text, score: $0.score)
        }
    }
}
