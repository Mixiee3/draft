import Foundation
import DraftCore

let args = CommandLine.arguments
let selectedVault: URL = {
    if let i = args.firstIndex(of: "--vault"), args.indices.contains(i + 1) {
        return URL(fileURLWithPath: args[i + 1], isDirectory: true)
    }
    return Vault.defaultURL()
}()

func send(_ value: [String: Any]) {
    guard JSONSerialization.isValidJSONObject(value),
          let bytes = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]) else { return }
    FileHandle.standardOutput.write(bytes + Data([10]))
}

func tool(_ name: String, _ description: String, _ properties: [String: Any], required: [String] = []) -> [String: Any] {
    ["name": name, "description": description, "inputSchema": ["type": "object", "properties": properties, "required": required, "additionalProperties": false],
     "annotations": ["readOnlyHint": true, "destructiveHint": false, "openWorldHint": false]]
}

func proposalTool(_ name: String, _ description: String, _ properties: [String: Any], required: [String]) -> [String: Any] {
    ["name": name, "description": description, "inputSchema": ["type": "object", "properties": properties, "required": required, "additionalProperties": false],
     "annotations": ["readOnlyHint": false, "destructiveHint": false, "openWorldHint": false]]
}

let textField: [String: Any] = ["type": "string"]
let intField: [String: Any] = ["type": "integer", "minimum": 1]
let toolList: [[String: Any]] = [
    tool("draft_list_spaces", "List Draft Spaces. Reads local files only.", [:]),
    tool("draft_list_documents", "List active, non-template documents in a Space. Defaults to the current Space.", ["space_id": textField, "limit": intField]),
    tool("draft_search", "Search blocks in a Draft Space. Defaults to the current Space.", ["query": textField, "space_id": textField, "limit": intField], required: ["query"]),
    tool("draft_read_document", "Read a Draft document as Markdown. Never changes it.", ["document_id": textField, "max_characters": intField], required: ["document_id"]),
    tool("draft_read_structure", "Read a document's revision, stable block IDs, types, formatting attributes and Markdown. Use this before proposing targeted edits.", ["document_id": textField], required: ["document_id"]),
    tool("draft_read_block", "Read one block from a Draft document as Markdown.", ["document_id": textField, "block_id": textField], required: ["document_id", "block_id"]),
    tool("draft_document_revision", "Get the current revision token for a document before proposing edits.", ["document_id": textField], required: ["document_id"]),
    proposalTool("draft_propose_note_edits", "Propose reviewed edits using Draft formatting. Does not change the document until the user accepts in Draft. Actions: replace_document (whole note Markdown, block_id=the document ID, text=Markdown); replace_text (one block, inline Markdown, with expected_text); heading (body/title/subtitle/heading/strong/caption); block_kind (body/quote/callout/code); list (bullet/numbered/task/none); font (document/system/serif/mono/rounded); align (left/center/right/justify); decoration (none/focus/block); block_color (#RRGGBB); bold/italic/underline/strike/code (exact phrase in text); highlight/text_color (exact phrase in text and #RRGGBB value). Use targeted block edits to preserve links and attachments. Get revision first.", [
        "document_id": textField, "expected_revision": textField, "instruction": textField,
        "edits": ["type": "array", "minItems": 1, "maxItems": 100, "items": ["type": "object", "properties": ["action": textField, "block_id": textField, "value": textField, "text": textField, "expected_text": textField], "required": ["action", "block_id"], "additionalProperties": false]]
    ], required: ["document_id", "expected_revision", "instruction", "edits"]),
    tool("draft_request_status", "Check whether a proposed edit was accepted or rejected in Draft.", ["request_id": textField], required: ["request_id"]),
]

func resultText(_ value: Any) throws -> String {
    let bytes = try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys, .fragmentsAllowed])
    return String(decoding: bytes, as: UTF8.self)
}

func call(_ name: String, _ args: [String: Any]) throws -> String {
    let draft = try DraftTools(vaultURL: selectedVault)
    switch name {
    case "draft_list_spaces":
        return try resultText(draft.spaces.map { ["id": $0.id, "name": $0.name] })
    case "draft_list_documents":
        return try resultText(try draft.documents(spaceId: args["space_id"] as? String, limit: args["limit"] as? Int ?? 100).map {
            ["id": $0.id, "title": $0.title, "updated_at": $0.updatedAt, "excerpt": $0.excerpt] as [String: Any]
        })
    case "draft_search":
        guard let query = args["query"] as? String, !query.isEmpty else { throw DraftToolError.unavailable("query is required") }
        let hits = try draft.search(query, spaceId: args["space_id"] as? String, limit: args["limit"] as? Int ?? 10)
        return try resultText(hits.map { ["document_id": $0.docId, "block_id": $0.blockId, "title": $0.title, "text": $0.text, "score": $0.score] as [String: Any] })
    case "draft_read_document":
        guard let id = args["document_id"] as? String else { throw DraftToolError.unavailable("document_id is required") }
        return try draft.markdown(id, maxCharacters: args["max_characters"] as? Int ?? 30_000)
    case "draft_read_structure":
        guard let id = args["document_id"] as? String else { throw DraftToolError.unavailable("document_id is required") }
        let data = try JSONEncoder().encode(draft.structure(id))
        return String(decoding: data, as: UTF8.self)
    case "draft_read_block":
        guard let id = args["document_id"] as? String, let block = args["block_id"] as? String else { throw DraftToolError.unavailable("document_id and block_id are required") }
        return try draft.block(docId: id, blockId: block)
    case "draft_document_revision":
        guard let id = args["document_id"] as? String else { throw DraftToolError.unavailable("document_id is required") }
        return try AgentProposalStore.revision(draft.document(id))
    case "draft_propose_note_edits":
        guard let id = args["document_id"] as? String, let revision = args["expected_revision"] as? String,
              let instruction = args["instruction"] as? String, let raw = args["edits"] as? [[String: Any]] else {
            throw DraftToolError.unavailable("document_id, expected_revision, instruction and edits are required")
        }
        let document = try draft.document(id)
        guard try AgentProposalStore.revision(document) == revision else { throw AgentEditError.invalid("The document changed. Read it again before proposing edits.") }
        let edits: [AgentEdit] = try raw.map { item in
            guard let action = item["action"] as? String, let block = item["block_id"] as? String else { throw AgentEditError.invalid("Each edit needs action and block_id.") }
            guard (action == "replace_document" && block == id) || document.content.block(block) != nil else { throw DraftToolError.missingBlock }
            return AgentEdit(action: action, blockId: block, value: item["value"] as? String, text: item["text"] as? String, expectedText: item["expected_text"] as? String)
        }
        let proposal = try AgentProposal(documentId: id, documentTitle: document.title, instruction: instruction, expectedRevision: revision, edits: edits)
        try AgentProposalStore.save(proposal, vaultURL: selectedVault)
        return try resultText(["request_id": proposal.id, "status": proposal.status, "message": "Review this proposal in Draft. No note was changed."])
    case "draft_request_status":
        guard let id = args["request_id"] as? String else { throw DraftToolError.unavailable("request_id is required") }
        let proposal = try AgentProposalStore.load(id, vaultURL: selectedVault)
        return try resultText(["request_id": proposal.id, "status": proposal.status, "result": proposal.result ?? ""])
    default: throw DraftToolError.unavailable("Unknown Draft tool: \(name)")
    }
}

while let line = readLine() {
    guard let data = line.data(using: .utf8),
          let message = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
          let method = message["method"] as? String else { continue }
    guard let id = message["id"] else { continue }
    let base: [String: Any] = ["jsonrpc": "2.0", "id": id]
    switch method {
    case "initialize":
        let requested = (message["params"] as? [String: Any])?["protocolVersion"] as? String ?? "2025-03-26"
        send(base.merging(["result": ["protocolVersion": requested, "capabilities": ["tools": [String: Any]()], "serverInfo": ["name": "draft-mcp", "version": "0.1.0"]] as [String: Any]]) { _, new in new })
    case "ping":
        send(base.merging(["result": [String: Any]()]) { _, new in new })
    case "tools/list":
        send(base.merging(["result": ["tools": toolList]]) { _, new in new })
    case "tools/call":
        let params = message["params"] as? [String: Any] ?? [:]
        let name = params["name"] as? String ?? ""
        let arguments = params["arguments"] as? [String: Any] ?? [:]
        do {
            let body = try call(name, arguments)
            send(base.merging(["result": ["content": [["type": "text", "text": body]], "isError": false]]) { _, new in new })
        } catch {
            send(base.merging(["result": ["content": [["type": "text", "text": error.localizedDescription]], "isError": true]]) { _, new in new })
        }
    default:
        send(base.merging(["error": ["code": -32601, "message": "Method not found"]]) { _, new in new })
    }
}
