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

    public init(action: String, blockId: String, value: String? = nil, text: String? = nil, expectedText: String? = nil) {
        self.action = action; self.blockId = blockId; self.value = value; self.text = text; self.expectedText = expectedText
    }

    public func validate() throws {
        guard blockId.range(of: "^[A-Za-z0-9_-]{1,64}$", options: .regularExpression) != nil else { throw AgentEditError.invalid("Invalid block ID.") }
        switch action {
        case "replace_document":
            guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, text.utf8.count <= 100_000 else {
                throw AgentEditError.invalid("replace_document needs Markdown under 100 KB.")
            }
        case "replace_text":
            guard let text, let expectedText, !text.contains("\n"), text.utf16.count <= 20_000, expectedText.utf16.count <= 20_000 else {
                throw AgentEditError.invalid("replace_text needs one line of Markdown and the exact current block text.")
            }
        case "heading": guard ["body", "title", "subtitle", "heading", "strong", "caption"].contains(value ?? "") else { throw AgentEditError.invalid("Unknown heading style.") }
        case "block_kind": guard ["body", "quote", "callout", "code"].contains(value ?? "") else { throw AgentEditError.invalid("Unknown block kind.") }
        case "decoration": guard ["none", "focus", "block"].contains(value ?? "") else { throw AgentEditError.invalid("Unknown decoration.") }
        case "list": guard ["bullet", "numbered", "task", "none"].contains(value ?? "") else { throw AgentEditError.invalid("Unknown list style.") }
        case "font": guard ["document", "system", "serif", "mono", "rounded"].contains(value ?? "") else { throw AgentEditError.invalid("Unknown font.") }
        case "align": guard ["left", "center", "right", "justify"].contains(value ?? "") else { throw AgentEditError.invalid("Unknown alignment.") }
        case "block_color", "highlight", "text_color":
            guard let value, value.range(of: "^#[0-9A-Fa-f]{6}$", options: .regularExpression) != nil else { throw AgentEditError.invalid("Color must be a six-digit hex value.") }
            if action != "block_color" { try validatePhrase() }
        case "bold", "italic", "underline", "strike", "code": try validatePhrase()
        default: throw AgentEditError.invalid("Unknown edit action: \(action).")
        }
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
        if edits.contains(where: { $0.action == "replace_document" }), edits.count != 1 { throw AgentEditError.invalid("A whole-note replacement must be its own proposal.") }
        if edits.first?.action == "replace_document", edits.first?.blockId != documentId { throw AgentEditError.invalid("Whole-note replacement must target the document ID.") }
        for edit in edits { try edit.validate() }
        id = newId("request_"); self.documentId = documentId; self.documentTitle = documentTitle
        self.instruction = instruction; self.expectedRevision = expectedRevision; self.edits = edits
        createdAt = nowMs(); status = "pending"
    }
}

public enum AgentProposalStore {
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
