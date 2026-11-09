import Foundation
import CryptoKit

public enum AgentEditError: LocalizedError {
    case invalid(String)
    public var errorDescription: String? {
        if case .invalid(let message) = self { return message }
        return nil
    }
}

/// A proposed edit is data, not a command to write a document. Draft reviews and applies it.
public struct AgentEdit: Codable, Sendable, Hashable {
    public var action: String
    public var blockId: String
    public var value: String?
    public var text: String?
    public var expectedText: String?
    /// For move_block: the block to move next to. For move_document: the destination Space.
    public var target: String?
    /// "before" or "after" (insert_blocks, move_block); default after.
    public var position: String?

    public init(action: String, blockId: String, value: String? = nil, text: String? = nil, expectedText: String? = nil, target: String? = nil, position: String? = nil) {
        self.action = action; self.blockId = blockId; self.value = value; self.text = text; self.expectedText = expectedText
        self.target = target; self.position = position
    }

    /// Actions that change the library (a new note, its title or place), applied by the app.
    public static let documentActions: Set<String> = ["create_document", "rename_document", "move_document", "create_folder", "delete_document"]
    /// Actions that stand alone in a proposal.
    static let standalone: Set<String> = documentActions.union(["replace_document", "document_style"])
    static let idPattern = "^[A-Za-z0-9_-]{1,64}$"

    public func validate() throws {
        guard blockId.range(of: "^[A-Za-z0-9_-]{1,64}$", options: .regularExpression) != nil else { throw AgentEditError.invalid("Invalid block ID.") }
        switch action {
        case "replace_document":
            guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, text.utf8.count <= 100_000 else {
                throw AgentEditError.invalid("replace_document needs Markdown under 100 KB.")
            }
        case "document_style":
            guard let value, value.range(of: "^[A-Za-z0-9_-]{1,64}$", options: .regularExpression) != nil else {
                throw AgentEditError.invalid("document_style needs a style ID.")
            }
        case "replace_text":
            guard let text, let expectedText, !text.contains("\n"), text.utf16.count <= 20_000, expectedText.utf16.count <= 20_000 else {
                throw AgentEditError.invalid("replace_text needs one line of Markdown and the exact current block text.")
            }
        case "heading": guard ["body", "title", "subtitle", "heading", "strong", "caption"].contains(value ?? "") else { throw AgentEditError.invalid("Unknown heading style.") }
        case "insert_separator", "separator_style":
            guard ["default", "line", "strong", "dotted", "dots", "wave", "tape", "page_break"].contains(value ?? "") else {
                throw AgentEditError.invalid("Unknown separator style.")
            }
        case "block_kind": guard ["body", "quote", "callout", "code"].contains(value ?? "") else { throw AgentEditError.invalid("Unknown block kind.") }
        case "decoration": guard ["none", "focus", "block"].contains(value ?? "") else { throw AgentEditError.invalid("Unknown decoration.") }
        case "list": guard ["bullet", "numbered", "task", "none"].contains(value ?? "") else { throw AgentEditError.invalid("Unknown list style.") }
        case "font": guard ["document", "system", "serif", "mono", "rounded"].contains(value ?? "") else { throw AgentEditError.invalid("Unknown font.") }
        case "align": guard ["left", "center", "right", "justify"].contains(value ?? "") else { throw AgentEditError.invalid("Unknown alignment.") }
        case "block_color", "highlight", "text_color":
            guard let value, value.range(of: "^#[0-9A-Fa-f]{6}$", options: .regularExpression) != nil else { throw AgentEditError.invalid("Color must be a six-digit hex value.") }
            if action != "block_color" { try validatePhrase() }
        case "bold", "italic", "underline", "strike", "code", "unlink": try validatePhrase()
        case "text_effect":
            guard TextEffects.kinds.contains(value ?? "") || value == "none" else { throw AgentEditError.invalid("text_effect needs one of: \(TextEffects.kinds.joined(separator: ", ")), none.") }
            try validatePhrase()
        case "link":
            try validatePhrase()
            guard let value, value.count <= 2_000, ["https://", "http://", "mailto:", "draft://"].contains(where: { value.lowercased().hasPrefix($0) }) else {
                throw AgentEditError.invalid("A link needs an http(s), mailto or draft:// address.")
            }
        case "task_checked": guard ["true", "false"].contains(value ?? "") else { throw AgentEditError.invalid("task_checked needs true or false.") }
        case "append", "insert_blocks":
            guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, text.utf8.count <= 50_000 else {
                throw AgentEditError.invalid("\(action) needs Markdown text under 50 KB.")
            }
            if action == "insert_blocks" { try validatePosition() }
        case "delete_block": break
        case "move_block":
            guard let target, target.range(of: Self.idPattern, options: .regularExpression) != nil, target != blockId else { throw AgentEditError.invalid("move_block needs a different target block ID.") }
            try validatePosition()
        case "create_document":
            guard !(title ?? "").trimmingCharacters(in: .whitespaces).isEmpty || !(text ?? "").isEmpty else { throw AgentEditError.invalid("create_document needs a title or Markdown text.") }
            guard (self.text ?? "").utf8.count <= 100_000, (title ?? "").count <= 300 else { throw AgentEditError.invalid("The new note is too large.") }
            try validateFolder()
        case "table_set_cell", "table_insert_row", "table_delete_row", "table_move_row", "table_insert_column", "table_delete_column", "table_move_column":
            guard let target, target.range(of: Self.idPattern, options: .regularExpression) != nil else { throw AgentEditError.invalid("\(action) needs the row or cell ID in target.") }
            if ["table_move_row", "table_move_column"].contains(action) {
                guard let value, value.range(of: Self.idPattern, options: .regularExpression) != nil else { throw AgentEditError.invalid("\(action) needs the anchor row or cell ID in value.") }
            }
            guard (text ?? "").utf16.count <= 20_000, !(text ?? "").contains("\n") else { throw AgentEditError.invalid("Table text must be one line under 20,000 characters.") }
            try validatePosition()
        case "collection_add_item", "collection_update_item", "collection_delete_item", "collection_move_item",
             "collection_add_field", "collection_rename_field", "collection_delete_field", "collection_set_view", "collection_add_view":
            guard (value ?? "").utf8.count <= 20_000, (text ?? "").utf16.count <= 2_000 else { throw AgentEditError.invalid("A collection edit is limited to 20 KB.") }
            if ["collection_update_item", "collection_delete_item", "collection_move_item", "collection_rename_field", "collection_delete_field", "collection_set_view"].contains(action) {
                guard let target, target.range(of: Self.idPattern, options: .regularExpression) != nil else { throw AgentEditError.invalid("\(action) needs the item, field or view ID in target.") }
            }
            try validatePosition()
        case "collection_create":
            guard !(text ?? "").trimmingCharacters(in: .whitespaces).isEmpty, (text ?? "").count <= 120 else { throw AgentEditError.invalid("A new collection needs a name of 1–120 characters.") }
            try validatePosition()
        case "insert_image", "insert_file":
            // A full path as proposed, or the vault asset id Draft puts there after copying the file.
            let asset = value?.range(of: "^[a-f0-9]{16,64}\\.[a-z0-9]{1,10}$", options: .regularExpression) != nil
            guard let value, value.hasPrefix("/") || asset, value.count <= 1_024 else { throw AgentEditError.invalid("\(action) needs the file's full path in value.") }
            guard (text ?? "").count <= 1_000 else { throw AgentEditError.invalid("Alt text or caption is limited to 1,000 characters.") }
            try validatePosition()
        case "delete_document": break
        case "create_folder":
            try Library.checkFolderName(title ?? "")
            if let value { guard value.range(of: Self.idPattern, options: .regularExpression) != nil else { throw AgentEditError.invalid("Invalid parent folder ID.") } }
            if let target { guard target.range(of: Self.idPattern, options: .regularExpression) != nil else { throw AgentEditError.invalid("Invalid Space ID.") } }
        case "rename_document":
            guard let title, !title.trimmingCharacters(in: .whitespaces).isEmpty, title.count <= 300, !title.contains("\n") else { throw AgentEditError.invalid("rename_document needs a one-line title.") }
        case "move_document":
            try validateFolder()
            if let target { guard target.range(of: Self.idPattern, options: .regularExpression) != nil else { throw AgentEditError.invalid("Invalid Space ID.") } }
            guard value != nil || target != nil else { throw AgentEditError.invalid("move_document needs a folder (or \"unsorted\") or a Space.") }
        default: throw AgentEditError.invalid("Unknown edit action: \(action).")
        }
    }

    /// The new note's or renamed note's title (create_document, rename_document); stored in
    /// `expectedText`, which those actions don't otherwise use, so older readers keep decoding.
    public var title: String? { ["create_document", "rename_document", "create_folder"].contains(action) ? expectedText : nil }

    private func validatePosition() throws {
        guard position == nil || ["before", "after"].contains(position!) else { throw AgentEditError.invalid("position must be before or after.") }
    }

    private func validateFolder() throws {
        if let value, value != "unsorted" { guard value.range(of: Self.idPattern, options: .regularExpression) != nil else { throw AgentEditError.invalid("Invalid folder ID.") } }
    }

    private func validatePhrase() throws {
        guard let text, !text.isEmpty, text.utf16.count <= 1_000 else { throw AgentEditError.invalid("An inline format edit needs the exact text to format.") }
    }
}

public struct AgentProposal: Codable, Sendable, Identifiable {
    public var id: String
    public var documentId: String
    public var documentTitle: String
    public var instruction: String
    public var expectedRevision: String
    public var edits: [AgentEdit]
    public var createdAt: Double
    public var status: String
    public var result: String?
    /// The MCP client that sent it (its `clientInfo.name`), for permissions and the review sheet.
    public var client: String?
    /// A multi-note proposal (documentId "multi"): each note's own revision and edits, applied
    /// all-or-nothing.
    public var parts: [AgentNoteChange]?

    public init(documentId: String, documentTitle: String, instruction: String, expectedRevision: String, edits: [AgentEdit]) throws {
        guard !edits.isEmpty, edits.count <= 100 else { throw AgentEditError.invalid("Provide 1–100 edits.") }
        guard !instruction.isEmpty, instruction.count <= 2_000 else { throw AgentEditError.invalid("Provide a short description of the proposed change.") }
        guard documentId.range(of: "^[A-Za-z0-9_-]{1,64}$", options: .regularExpression) != nil,
              expectedRevision.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil else { throw AgentEditError.invalid("Invalid document ID or revision.") }
        if edits.contains(where: { AgentEdit.standalone.contains($0.action) }), edits.count != 1 {
            throw AgentEditError.invalid("Creating, renaming or moving a note, whole-note replacement and document style must each be their own proposal.")
        }
        if let first = edits.first, AgentEdit.standalone.contains(first.action) || first.action == "append", first.blockId != documentId {
            throw AgentEditError.invalid("\(first.action) must target the document ID (\"new\" for create_document).")
        }
        if (documentId == "new") != ["create_document", "create_folder"].contains(edits.first?.action ?? "") {
            throw AgentEditError.invalid("Only create_document and create_folder use the document ID \"new\".")
        }
        for edit in edits { try edit.validate() }
        id = newId("request_"); self.documentId = documentId; self.documentTitle = documentTitle
        self.instruction = instruction; self.expectedRevision = expectedRevision; self.edits = edits
        createdAt = nowMs(); status = "pending"
    }
}

extension Library {
    static func checkFolderName(_ name: String) throws {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !n.isEmpty, n.count <= 120 else { throw AgentEditError.invalid("A folder name needs 1–120 characters.") }
        guard !n.contains("/"), !n.contains("\n"), n != ".", n != ".." else { throw AgentEditError.invalid("A folder name can't contain “/” or line breaks, or be “.” or “..”. Create nested folders one level at a time.") }
    }

    /// “Space › Parent › Child” for showing where a folder is (or will be).
    public func folderPath(_ id: String?, space: String? = nil) -> String {
        var names: [String] = [], seen = Set<String>(), cur = id
        while let c = cur, !seen.contains(c), let f = folders.first(where: { $0.id == c }) { names.insert(f.name, at: 0); seen.insert(c); cur = f.parentId }
        let sp = space ?? id.flatMap { i in folders.first { $0.id == i }?.spaceId } ?? self.space.id
        return ([spaces.first { $0.id == sp }?.name ?? self.space.name] + names).joined(separator: " › ")
    }

    /// Checks a new folder against its Space and parent: the parent must exist there and no sibling
    /// may already have the name (ignoring case).
    public func checkNewFolder(name: String, parent: String?, space: String) throws {
        try Self.checkFolderName(name)
        guard spaces.contains(where: { $0.id == space }) else { throw AgentEditError.invalid("That Space doesn't exist.") }
        let inSpace = folders.filter { ($0.spaceId ?? spaces.first?.id) == space }
        if let parent { guard inSpace.contains(where: { $0.id == parent }) else { throw AgentEditError.invalid("The parent folder doesn't exist in that Space.") } }
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if inSpace.contains(where: { $0.parentId == parent && $0.name.compare(n, options: .caseInsensitive) == .orderedSame }) {
            throw AgentEditError.invalid("“\(folderPath(parent, space: space)) › \(n)” already exists.")
        }
    }
}

extension AgentProposal {
    /// Proposals whose one-step Undo is Edit › Undo Agent Change rather than the note's own ⌘Z:
    /// library changes, several notes, collections and copied files.
    public var usesAgentUndo: Bool {
        changesLibrary || parts != nil || (!edits.isEmpty && edits.allSatisfy { CollectionData.agentActions.contains($0.action) })
            || edits.contains { ["insert_image", "insert_file"].contains($0.action) }
    }

    /// Applied by the app to the library rather than through a note's editor.
    public var changesLibrary: Bool { edits.count == 1 && AgentEdit.documentActions.contains(edits[0].action) }
}

/// What a client may do. Destructive covers removing content or moving notes (with their nested
/// pages) — the changes a user would most regret applying by accident.
public enum AgentAccess: String, Sendable { case read, propose, destructive }

public struct AgentPermission: Codable, Hashable, Sendable {
    public var read = true
    public var propose = true
    public var destructive = false
    public init(read: Bool = true, propose: Bool = true, destructive: Bool = false) { self.read = read; self.propose = propose; self.destructive = destructive }
    public func allows(_ a: AgentAccess) -> Bool {
        switch a { case .read: return read; case .propose: return propose; case .destructive: return propose && destructive }
    }
}

extension AgentProposal {
    public static let destructiveActions: Set<String> = ["delete_block", "replace_document", "move_document", "delete_document", "table_delete_row", "table_delete_column", "collection_delete_item", "collection_delete_field"]
    public var requiredAccess: AgentAccess { allEdits.contains { Self.destructiveActions.contains($0.action) } ? .destructive : .propose }
}

/// A local list of what agents read and proposed — tool, document id and time, never note text.
public enum AgentActivity {
    public struct Entry: Codable, Hashable, Sendable {
        public var time: Double; public var client: String; public var tool: String; public var document: String?
        public init(time: Double, client: String, tool: String, document: String?) { self.time = time; self.client = client; self.tool = tool; self.document = document }
    }
    static let keep = 1_000

    public static func url(_ vault: URL) -> URL { AgentProposalStore.directory(vault).appendingPathComponent("activity.jsonl") }

    public static func record(_ e: Entry, vault: URL) {
        let u = url(vault)
        try? FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard var line = try? JSONEncoder().encode(e) else { return }
        line.append(10)
        if let h = try? FileHandle(forWritingTo: u) { h.seekToEndOfFile(); h.write(line); try? h.close() } else { try? line.write(to: u) }
        // Trim now and then rather than on every call.
        if let size = try? FileManager.default.attributesOfItem(atPath: u.path)[.size] as? Int, size > 400_000 {
            let kept = entries(vault).suffix(keep)
            let data = kept.compactMap { try? JSONEncoder().encode($0) }.reduce(into: Data()) { $0.append($1); $0.append(10) }
            try? data.write(to: u, options: .atomic)
        }
    }

    public static func entries(_ vault: URL) -> [Entry] {
        guard let data = try? Data(contentsOf: url(vault)) else { return [] }
        return data.split(separator: 10).compactMap { try? JSONDecoder().decode(Entry.self, from: Data($0)) }
    }

    public static func clear(_ vault: URL) { try? FileManager.default.removeItem(at: url(vault)) }
}

public struct AgentNoteChange: Codable, Sendable, Hashable {
    public var documentId: String
    public var documentTitle: String
    public var expectedRevision: String
    public var edits: [AgentEdit]
    public init(documentId: String, documentTitle: String, expectedRevision: String, edits: [AgentEdit]) {
        self.documentId = documentId; self.documentTitle = documentTitle; self.expectedRevision = expectedRevision; self.edits = edits
    }
}

extension AgentProposal {
    /// Several notes in one review and one Undo. Note edits only (no create/rename/move/delete):
    /// each part keeps the single-note rules.
    public init(instruction: String, parts: [AgentNoteChange]) throws {
        guard (2...20).contains(parts.count) else { throw AgentEditError.invalid("A multi-note proposal covers 2–20 notes.") }
        guard Set(parts.map(\.documentId)).count == parts.count else { throw AgentEditError.invalid("Each note may appear once; put all its edits in one part.") }
        guard parts.reduce(0, { $0 + $1.edits.count }) <= 300 else { throw AgentEditError.invalid("A multi-note proposal has at most 300 edits.") }
        for part in parts {
            if part.edits.contains(where: { ["insert_image", "insert_file"].contains($0.action) }) {
                throw AgentEditError.invalid("Inserting files goes in a single-note proposal.")
            }
            if part.edits.contains(where: { CollectionData.agentActions.contains($0.action) }) {
                throw AgentEditError.invalid("Collection changes go in a single-note proposal of their own.")
            }
            if part.edits.contains(where: { AgentEdit.documentActions.contains($0.action) }) {
                throw AgentEditError.invalid("Creating, renaming, moving or deleting notes must be its own proposal.")
            }
            _ = try AgentProposal(documentId: part.documentId, documentTitle: part.documentTitle, instruction: instruction, expectedRevision: part.expectedRevision, edits: part.edits)
        }
        id = newId("request_"); documentId = "multi"; documentTitle = "\(parts.count) notes"
        self.instruction = instruction; expectedRevision = ""; edits = []; self.parts = parts
        createdAt = nowMs(); status = "pending"
    }

    /// Every edit, across parts.
    public var allEdits: [AgentEdit] { edits + (parts ?? []).flatMap(\.edits) }
}

public enum AgentProposalStore {
    /// What a create or move proposal depends on: the Spaces and folders that exist.
    public static func libraryRevision(_ library: Library) -> String {
        let shape = library.spaces.map { "s:\($0.id)" }.sorted() + library.folders.map { "f:\($0.id):\($0.spaceId ?? "")" }.sorted()
        return SHA256.hash(data: Data(shape.joined(separator: "\n").utf8)).map { String(format: "%02x", $0) }.joined()
    }

    public static func revision(_ document: DocFile) throws -> String {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(document)
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    public static func directory(_ vaultURL: URL) -> URL { vaultURL.appendingPathComponent("agent-requests", isDirectory: true) }

    public static func save(_ proposal: AgentProposal, vaultURL: URL) throws {
        let dir = directory(vaultURL)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(proposal)
        guard data.count <= 150_000 else { throw AgentEditError.invalid("The proposal is too large.") }
        try data.write(to: dir.appendingPathComponent("\(proposal.id).json"), options: .atomic)
    }

    public static func load(_ id: String, vaultURL: URL) throws -> AgentProposal {
        guard id.range(of: "^request_[A-Za-z0-9_-]{1,64}$", options: .regularExpression) != nil else { throw AgentEditError.invalid("Invalid request ID.") }
        let data = try Data(contentsOf: directory(vaultURL).appendingPathComponent("\(id).json"))
        guard data.count <= 150_000 else { throw AgentEditError.invalid("The proposal is too large.") }
        return try JSONDecoder().decode(AgentProposal.self, from: data)
    }

    public static func pending(vaultURL: URL) -> [AgentProposal] {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory(vaultURL), includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "json" }.compactMap { try? load($0.deletingPathExtension().lastPathComponent, vaultURL: vaultURL) }
            .filter { $0.status == "pending" }.sorted { $0.createdAt < $1.createdAt }
    }
}
