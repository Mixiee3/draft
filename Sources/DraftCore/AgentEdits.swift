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
    public static let documentActions: Set<String> = ["create_document", "rename_document", "move_document"]
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
    public var title: String? { action == "create_document" || action == "rename_document" ? expectedText : nil }

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
        if (documentId == "new") != (edits.first?.action == "create_document") {
            throw AgentEditError.invalid("Only create_document uses the document ID \"new\".")
        }
        for edit in edits { try edit.validate() }
        id = newId("request_"); self.documentId = documentId; self.documentTitle = documentTitle
        self.instruction = instruction; self.expectedRevision = expectedRevision; self.edits = edits
        createdAt = nowMs(); status = "pending"
    }
}

extension AgentProposal {
    /// Applied by the app to the library rather than through a note's editor.
    public var changesLibrary: Bool { edits.count == 1 && AgentEdit.documentActions.contains(edits[0].action) }
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
