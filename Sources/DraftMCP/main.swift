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
    tool("draft_formatting_guide", "Read Draft's visual formatting options and guidance for making a note clear and attractive.", [:]),
    proposalTool("draft_propose_note_edits", "Propose reviewed edits to one note. Nothing changes until the user applies them in Draft, which rechecks the revision, keeps a backup, updates the index and makes the whole proposal one Undo step. Get expected_revision from draft_read_structure. Read draft_formatting_guide first and format with restraint. Actions — text: replace_text (one block, inline Markdown, expected_text = exact current text); append (block_id = the document ID, text = Markdown blocks added at the end); insert_blocks (text = Markdown blocks, block_id = anchor, position before/after); delete_block (text blocks and separators only; images, files, tables and page cards are kept); move_block (block_id, target = another block ID, position before/after). Structure: heading (body/title/subtitle/heading/strong/caption); block_kind (body/quote/callout/code); list (bullet/numbered/task/none); task_checked (value true/false). Inline, on an exact phrase given in text that occurs once in the block: bold/italic/underline/strike/code; highlight and text_color (value #RRGGBB); link (value https/http/mailto/draft:// URL); unlink. Block look: block_color (#RRGGBB), decoration (none/focus/block), font (document/system/serif/mono/rounded), align (left/center/right/justify). Separators: insert_separator after block_id and separator_style on an existing one (default/line/strong/dotted/dots/wave/tape/page_break). Standalone proposals: replace_document (block_id = document ID, text = whole-note Markdown; refused for notes with images, files or page cards) and document_style (block_id = document ID, value = style ID). Tags are #words in text and links to other notes are draft:// links; use replace_text, append or link for them.", [
        "document_id": textField, "expected_revision": textField, "instruction": textField,
        "edits": ["type": "array", "minItems": 1, "maxItems": 100, "items": ["type": "object", "properties": ["action": textField, "block_id": textField, "value": textField, "text": textField, "expected_text": textField, "target": textField, "position": ["type": "string", "enum": ["before", "after"]]], "required": ["action", "block_id"], "additionalProperties": false]]
    ], required: ["document_id", "expected_revision", "instruction", "edits"]),
    proposalTool("draft_propose_create_document", "Propose a new note. Draft shows it for review and creates it only when the user applies it, with fresh block IDs, in the given folder (or Unsorted) and Space (default: the current one). One Undo moves it to Recently Deleted.", [
        "title": textField, "markdown": textField, "folder_id": textField, "space_id": textField, "instruction": textField
    ], required: ["title", "instruction"]),
    proposalTool("draft_propose_rename_document", "Propose a new title for a note. Applied only after review; one Undo restores the old title.", [
        "document_id": textField, "expected_revision": textField, "title": textField, "instruction": textField
    ], required: ["document_id", "expected_revision", "title", "instruction"]),
    proposalTool("draft_propose_move_document", "Propose moving a note (with its nested pages) to a folder (folder_id, or \"unsorted\") and/or another Space (space_id). Applied only after review; one Undo moves it back.", [
        "document_id": textField, "expected_revision": textField, "folder_id": textField, "space_id": textField, "instruction": textField
    ], required: ["document_id", "expected_revision", "instruction"]),
    proposalTool("draft_propose_multi_note_edits", "Propose edits to 2–20 notes in the open Space as one change: the user reviews them together, Draft applies all of them or none (if any note changed since it was read, nothing is applied), and one Undo reverts every note. Each note uses the same edit actions as draft_propose_note_edits with its own expected_revision. Creating, renaming, moving or deleting notes stays a separate proposal.", [
        "instruction": textField,
        "notes": ["type": "array", "minItems": 2, "maxItems": 20, "items": ["type": "object", "properties": [
            "document_id": textField, "expected_revision": textField,
            "edits": ["type": "array", "minItems": 1, "maxItems": 100, "items": ["type": "object", "properties": ["action": textField, "block_id": textField, "value": textField, "text": textField, "expected_text": textField, "target": textField, "position": ["type": "string", "enum": ["before", "after"]]], "required": ["action", "block_id"], "additionalProperties": false]]
        ], "required": ["document_id", "expected_revision", "edits"], "additionalProperties": false]]
    ], required: ["instruction", "notes"]),
    proposalTool("draft_propose_create_folder", "Propose a new folder (one level; nest by giving parent_folder_id). Draft shows its Space and full path for review and creates it only when the user applies it. Names must be unique among siblings (ignoring case) and can't contain “/”. One Undo removes it while it's still empty.", [
        "name": textField, "parent_folder_id": textField, "space_id": textField, "instruction": textField
    ], required: ["name", "instruction"]),
    proposalTool("draft_propose_delete_document", "Propose moving a note and its nested pages to Recently Deleted (never a permanent delete; restorable for 30 days). Needs the Destructive permission. The review lists every page and the notes that link to it. One Undo restores it.", [
        "document_id": textField, "expected_revision": textField, "instruction": textField
    ], required: ["document_id", "expected_revision", "instruction"]),
    tool("draft_list_folders", "List folders in a Space (default: the current one), with their full paths.", ["space_id": textField]),
    tool("draft_request_status", "Check whether a proposed edit was accepted or rejected in Draft.", ["request_id": textField], required: ["request_id"]),
]

func resultText(_ value: Any) throws -> String {
    let bytes = try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys, .fragmentsAllowed])
    return String(decoding: bytes, as: UTF8.self)
}

/// The connected client's name from `initialize`; permissions in Draft's settings are per name.
var clientName = "unknown"

func denied(_ what: String) -> DraftToolError {
    .unavailable("Draft doesn't allow \(clientName) to \(what). The user can change this in Draft › Settings › Agents.")
}

/// Writes the proposal file only; the note is changed by Draft after the user applies it.
func queue(_ proposal: AgentProposal, _ draft: DraftTools) throws -> String {
    var proposal = proposal
    proposal.client = clientName
    if proposal.requiredAccess == .destructive, !draft.library.settings.agentPermission(clientName).allows(.destructive) {
        throw denied("propose destructive changes (deleting content, replacing a whole note or moving notes)")
    }
    try AgentProposalStore.save(proposal, vaultURL: selectedVault)
    return try resultText(["request_id": proposal.id, "status": proposal.status, "message": "Review this proposal in Draft. Nothing was changed yet."])
}

/// Note edits from MCP arguments, checked against the note as it was read.
func parseEdits(_ raw: [[String: Any]], _ document: DocFile) throws -> [AgentEdit] {
    let id = document.id
    return try raw.map { item in
        guard let action = item["action"] as? String, let block = item["block_id"] as? String else { throw AgentEditError.invalid("Each edit needs action and block_id.") }
        guard !AgentEdit.documentActions.contains(action) else { throw AgentEditError.invalid("Use the create, rename or move tools for \(action).") }
        guard (["replace_document", "document_style", "append"].contains(action) && block == id) || document.content.block(block) != nil else { throw DraftToolError.missingBlock }
        if let target = item["target"] as? String, document.content.block(target) == nil { throw DraftToolError.missingBlock }
        return AgentEdit(action: action, blockId: block, value: item["value"] as? String, text: item["text"] as? String, expectedText: item["expected_text"] as? String,
                         target: item["target"] as? String, position: item["position"] as? String)
    }
}

func call(_ name: String, _ args: [String: Any]) throws -> String {
    let draft = try DraftTools(vaultURL: selectedVault)
    let permission = draft.library.settings.agentPermission(clientName)
    let proposes = name.hasPrefix("draft_propose_")
    guard permission.allows(proposes ? .propose : .read) else { throw denied(proposes ? "propose changes" : "read notes") }
    AgentActivity.record(.init(time: nowMs(), client: clientName, tool: name, document: args["document_id"] as? String), vault: selectedVault)
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
    case "draft_formatting_guide":
        return try resultText([
            "built_in_styles": Styles.builtIn.map { ["id": $0.id, "name": $0.name, "separator": $0.tokens.separator] },
            "saved_styles": draft.library.userStyles.map { ["id": $0.id, "name": $0.name, "separator": $0.tokens.separator] },
            "separator_styles": ["default", "line", "strong", "dotted", "dots", "wave", "tape", "page_break"],
            "text_emphasis": ["bold", "italic", "underline", "strike", "code", "highlight", "text_color"],
            "block_treatments": ["quote", "callout", "focus", "block", "block_color", "font", "align"],
            "principles": [
                "Start with structure: one clear title, short sections, and lists only where they help scanning.",
                "Use one decorative separator at a meaningful transition. Wave is gentle; tape is playful; dots are quiet. Avoid repeating them between every section.",
                "Highlight only the few words a reader should notice first. Keep long paragraphs unhighlighted.",
                "Choose one accent color and keep text contrast readable. Use callouts for genuinely important notes, not every paragraph.",
                "Preserve the author's meaning, links, block IDs, tasks, and attachments. Review the complete proposal before requesting approval.",
                "For “make this look better”: a title heading, subtitle-level headings for real sections, at most one callout or focus block, a highlight on one or two key phrases, one separator before a change of topic, and a document style that suits the content. Leave most paragraphs as plain text."
            ],
            "recipe_make_it_look_better": ["heading title on the first line", "heading subtitle for each real section", "list or task for steps", "callout for one warning or decision", "highlight #fff3a3 on one key phrase", "insert_separator wave or dots before the closing section", "document_style that matches the tone"]
        ])
    case "draft_propose_note_edits":
        guard let id = args["document_id"] as? String, let revision = args["expected_revision"] as? String,
              let instruction = args["instruction"] as? String, let raw = args["edits"] as? [[String: Any]] else {
            throw DraftToolError.unavailable("document_id, expected_revision, instruction and edits are required")
        }
        let document = try draft.document(id)
        guard try AgentProposalStore.revision(document) == revision else { throw AgentEditError.invalid("The document changed. Read it again before proposing edits.") }
        let edits = try parseEdits(raw, document)
        return try queue(AgentProposal(documentId: id, documentTitle: document.title, instruction: instruction, expectedRevision: revision, edits: edits), draft)
    case "draft_list_folders":
        let space = args["space_id"] as? String ?? draft.library.space.id
        return try resultText(draft.library.folders.filter { ($0.spaceId ?? draft.library.spaces.first?.id) == space }.map {
            ["id": $0.id, "name": $0.name, "parent_id": $0.parentId ?? "", "path": draft.library.folderPath($0.id)] as [String: Any]
        })
    case "draft_propose_create_document":
        guard let title = args["title"] as? String, let instruction = args["instruction"] as? String else { throw DraftToolError.unavailable("title and instruction are required") }
        let edit = AgentEdit(action: "create_document", blockId: "new", value: args["folder_id"] as? String, text: args["markdown"] as? String, expectedText: title, target: args["space_id"] as? String)
        return try queue(AgentProposal(documentId: "new", documentTitle: title, instruction: instruction, expectedRevision: AgentProposalStore.libraryRevision(draft.library), edits: [edit]), draft)
    case "draft_propose_multi_note_edits":
        guard let instruction = args["instruction"] as? String, let notes = args["notes"] as? [[String: Any]] else { throw DraftToolError.unavailable("instruction and notes are required") }
        let parts: [AgentNoteChange] = try notes.map { n in
            guard let id = n["document_id"] as? String, let revision = n["expected_revision"] as? String, let raw = n["edits"] as? [[String: Any]] else {
                throw DraftToolError.unavailable("Each note needs document_id, expected_revision and edits.")
            }
            let document = try draft.document(id)
            guard try AgentProposalStore.revision(document) == revision else { throw AgentEditError.invalid("“\(document.title)” changed. Read it again before proposing.") }
            return AgentNoteChange(documentId: id, documentTitle: document.title, expectedRevision: revision, edits: try parseEdits(raw, document))
        }
        return try queue(AgentProposal(instruction: instruction, parts: parts), draft)
    case "draft_propose_create_folder":
        guard let name = args["name"] as? String, let instruction = args["instruction"] as? String else { throw DraftToolError.unavailable("name and instruction are required") }
        let space = args["space_id"] as? String ?? draft.library.space.id
        try draft.library.checkNewFolder(name: name, parent: args["parent_folder_id"] as? String, space: space)
        let edit = AgentEdit(action: "create_folder", blockId: "new", value: args["parent_folder_id"] as? String, expectedText: name.trimmingCharacters(in: .whitespacesAndNewlines), target: space)
        return try queue(AgentProposal(documentId: "new", documentTitle: name, instruction: instruction, expectedRevision: AgentProposalStore.libraryRevision(draft.library), edits: [edit]), draft)
    case "draft_propose_delete_document":
        guard let id = args["document_id"] as? String, let revision = args["expected_revision"] as? String, let instruction = args["instruction"] as? String else {
            throw DraftToolError.unavailable("document_id, expected_revision and instruction are required")
        }
        let document = try draft.document(id)
        guard try AgentProposalStore.revision(document) == revision else { throw AgentEditError.invalid("The document changed. Read it again before proposing.") }
        return try queue(AgentProposal(documentId: id, documentTitle: document.title, instruction: instruction, expectedRevision: revision, edits: [AgentEdit(action: "delete_document", blockId: id)]), draft)
    case "draft_propose_rename_document", "draft_propose_move_document":
        guard let id = args["document_id"] as? String, let revision = args["expected_revision"] as? String, let instruction = args["instruction"] as? String else {
            throw DraftToolError.unavailable("document_id, expected_revision and instruction are required")
        }
        let document = try draft.document(id)
        guard try AgentProposalStore.revision(document) == revision else { throw AgentEditError.invalid("The document changed. Read it again before proposing.") }
        let edit = name == "draft_propose_rename_document"
            ? AgentEdit(action: "rename_document", blockId: id, expectedText: args["title"] as? String)
            : AgentEdit(action: "move_document", blockId: id, value: args["folder_id"] as? String, target: args["space_id"] as? String)
        return try queue(AgentProposal(documentId: id, documentTitle: document.title, instruction: instruction, expectedRevision: revision, edits: [edit]), draft)
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
        if let info = (message["params"] as? [String: Any])?["clientInfo"] as? [String: Any], let n = info["name"] as? String, !n.isEmpty { clientName = String(n.prefix(64)) }
        let requested = (message["params"] as? [String: Any])?["protocolVersion"] as? String ?? "2025-03-26"
        send(base.merging(["result": ["protocolVersion": requested, "capabilities": ["tools": [String: Any]()], "serverInfo": ["name": "draft-mcp", "version": "0.2.0"]] as [String: Any]]) { _, new in new })
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
