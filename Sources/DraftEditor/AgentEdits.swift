import AppKit
import DraftCore

extension EditorController {
    /// Apply a reviewed proposal through the editor's semantic commands and undo manager.
    public func applyAgentEdits(_ edits: [AgentEdit]) throws {
        guard !edits.isEmpty else { throw AgentEditError.invalid("The proposal has no edits.") }
        if edits.contains(where: { $0.action == "replace_document" }) {
            guard edits.count == 1, let markdown = edits[0].text else { throw AgentEditError.invalid("A whole-note replacement must be its own proposal.") }
            try replaceDocumentFromAgent(markdown)
            return
        }
        var planned: [String: String] = [:]
        for edit in edits {
            try edit.validate()
            if edit.action == "append" { continue }
            guard let pr = paragraph(withId: edit.blockId) else { throw AgentEditError.invalid("Block \(edit.blockId) is missing.") }
            let kind = block(at: pr).kind
            switch edit.action {
            case "insert_blocks": continue
            case "delete_block":
                // Images, files, nested pages and tables are kept: their assets and child pages hang off them.
                guard !kind.isAttachment || kind == .divider else { throw AgentEditError.invalid("Block \(edit.blockId) holds an image, file, page or table; Draft won't delete it from a proposal.") }
                continue
            case "move_block":
                guard let t = edit.target, paragraph(withId: t) != nil else { throw AgentEditError.invalid("Target block \(edit.target ?? "") is missing.") }
                continue
            case "task_checked":
                guard kind == .task else { throw AgentEditError.invalid("Block \(edit.blockId) is not a task.") }
                continue
            default: break
            }
            if edit.action == "separator_style" {
                guard kind == .divider else { throw AgentEditError.invalid("Only a separator can change separator style.") }
            } else if edit.action != "insert_separator" && kind.isAttachment {
                throw AgentEditError.invalid("Block \(edit.blockId) cannot be formatted as text.")
            }
            let current = planned[edit.blockId] ?? ns.substring(with: contentRange(pr))
            if edit.action == "replace_text" {
                guard current == edit.expectedText else { throw AgentEditError.invalid("Text in block \(edit.blockId) changed. Read the note again.") }
                planned[edit.blockId] = (MarkdownImport.inline(edit.text ?? "")).map { $0.text ?? "" }.joined()
            } else if ["bold", "italic", "underline", "strike", "code", "highlight", "text_color", "link", "unlink"].contains(edit.action) {
                let phrase = edit.text ?? ""
                let count = current.components(separatedBy: phrase).count - 1
                guard count == 1 else { throw AgentEditError.invalid("The phrase “\(phrase)” must occur exactly once in block \(edit.blockId).") }
            }
        }
        undo.beginUndoGrouping()
        undoGroup {
            for edit in edits {
                if ["append", "insert_blocks", "delete_block", "move_block"].contains(edit.action) { applyStructural(edit); continue }
                guard let pr = paragraph(withId: edit.blockId) else { continue }
                textView.setSelectedRange(NSRange(location: pr.location, length: 0))
                switch edit.action {
                case "insert_separator":
                    let style = edit.value ?? "default"
                    let node = style == "page_break" ? Node("pageBreak") : Node("horizontalRule", attrs: style == "default" ? nil : ["variant": .string(style)])
                    insertAttachmentBlock(kind: .divider, node: node)
                case "separator_style":
                    let style = edit.value ?? "default"
                    updateAttachment(at: pr.location) { node in
                        node.type = style == "page_break" ? "pageBreak" : "horizontalRule"
                        node[attr: "variant"] = style == "default" || style == "page_break" ? nil : .string(style)
                    }
                case "replace_text":
                    let b = block(at: pr)
                    let out = NSMutableAttributedString()
                    for node in MarkdownImport.inline(edit.text ?? "") { out.append(Converter.inlineToAttributed(node, code: b.kind == .code)) }
                    if out.length > 0 { out.addAttribute(.draftBlock, value: b, range: NSRange(location: 0, length: out.length)) }
                    replace(contentRange(pr), with: out)
                    setBlock(paragraphRange(at: pr.location), b)
                case "heading":
                    switch edit.value {
                    case "title": setBlockKind(.heading, level: 1)
                    case "subtitle": setBlockKind(.heading, level: 2)
                    case "heading": setBlockKind(.heading, level: 3)
                    case "strong": setBlockKind(.heading, level: 4)
                    case "caption": setBlockKind(.paragraph, variant: "caption")
                    default: setBlockKind(.paragraph)
                    }
                case "block_kind":
                    switch edit.value {
                    case "quote": setBlockKind(.quote)
                    case "callout": setBlockKind(.callout)
                    case "code": setBlockKind(.code)
                    default: setBlockKind(.paragraph)
                    }
                case "decoration":
                    let desired = edit.value == "none" ? nil : edit.value
                    if block(at: pr).decoration != desired { setDecoration(desired) }
                case "list":
                    let kind: BlockKind = edit.value == "bullet" ? .bullet : edit.value == "numbered" ? .ordered : .task
                    if edit.value == "none" { setBlockKind(.paragraph) }
                    else if block(at: pr).kind != kind { toggleList(kind) }
                case "task_checked":
                    if block(at: pr).checked != (edit.value == "true") { toggleTask(at: pr) }
                case "link", "unlink":
                    let cr = contentRange(pr)
                    let local = (ns.substring(with: cr) as NSString).range(of: edit.text ?? "")
                    setLink(edit.action == "link" ? edit.value : nil, range: NSRange(location: cr.location + local.location, length: local.length))
                case "font": setBlockFont(edit.value == "document" ? nil : edit.value)
                case "align": setAlign(edit.value)
                case "block_color": setBlockColor(edit.value)
                case "bold", "italic", "underline", "strike", "code", "highlight", "text_color":
                    let cr = contentRange(paragraph(withId: edit.blockId)!)
                    let phrase = edit.text ?? ""
                    let local = (ns.substring(with: cr) as NSString).range(of: phrase)
                    let range = NSRange(location: cr.location + local.location, length: local.length)
                    let key: NSAttributedString.Key
                    switch edit.action {
                    case "bold": key = .draftBold
                    case "italic": key = .draftItalic
                    case "underline": key = .draftUnderline
                    case "strike": key = .draftStrike
                    case "code": key = .draftCode
                    case "text_color": key = .draftTextColor
                    default: key = .draftHighlight
                    }
                    setInline(key, ["highlight", "text_color"].contains(edit.action) ? edit.value : true, range: range)
                default: break
                }
            }
        }
        undo.setActionName("Apply Agent Edits")
        undo.endUndoGrouping()
        host?.editorDidChange()
    }

    /// Block-level changes through the flat block list, so ids, marks and attachments of every
    /// other block travel unchanged. New blocks get fresh ids.
    private func applyStructural(_ edit: AgentEdit) {
        var flat = flatBlocks()
        func index(_ id: String) -> Int? { flat.firstIndex { $0.info.id == id } }
        switch edit.action {
        case "append", "insert_blocks":
            let new = Converter.flatten(ensureBlockIds(Node("doc", content: MarkdownImport.blocks(edit.text ?? ""))))
            var at = flat.count
            if edit.action == "append" {
                // A note ends with an empty paragraph to type into; add above it.
                if let last = flat.last, !last.info.kind.isAttachment, last.inline.isEmpty, flat.count > 1 { at = flat.count - 1 }
            } else if let i = index(edit.blockId) { at = edit.position == "before" ? i : i + 1 }
            flat.insert(contentsOf: new, at: at)
            rebuild(flat, select: new.first.map { [$0.info.id] } ?? [], blockMode: false)
        case "delete_block":
            guard let i = index(edit.blockId) else { return }
            flat.remove(at: i)
            if flat.isEmpty { flat = Converter.flatten(ensureBlockIds(Node("doc", content: [Node("paragraph")]))) }
            rebuild(flat, select: [], blockMode: false)
        case "move_block":
            guard let i = index(edit.blockId) else { return }
            let moved = flat.remove(at: i)
            guard let j = edit.target.flatMap(index) else { return }
            flat.insert(moved, at: edit.position == "before" ? j : j + 1)
            rebuild(flat, select: [moved.info.id], blockMode: false)
        default: break
        }
    }

    private func replaceDocumentFromAgent(_ markdown: String) throws {
        let old = flatBlocks()
        guard !old.contains(where: { $0.info.kind.isAttachment }) else {
            throw AgentEditError.invalid("This note has images, files, tables or page cards. Use block edits so those objects stay intact.")
        }
        var proposed = Converter.flatten(ensureBlockIds(Node("doc", content: MarkdownImport.blocks(markdown))))
        guard !proposed.contains(where: { $0.info.kind.isAttachment }) else {
            throw AgentEditError.invalid("Whole-note replacement supports text, headings and lists. Use block edits for tables or files.")
        }
        // Keep references to existing blocks when the text survives the rewrite; use position for
        // other surviving paragraphs. New paragraphs receive fresh IDs from MarkdownImport.
        var used = Set<String>()
        for i in proposed.indices {
            let text = Converter.attributed(flat: [proposed[i]]).0.string
            let exact = old.first { !used.contains($0.info.id) && Converter.attributed(flat: [$0]).0.string == text }
            let match = exact ?? (i < old.count && !used.contains(old[i].info.id) ? old[i] : nil)
            if let match {
                proposed[i].info = proposed[i].info.with(id: match.info.id,
                    blockColor: .some(match.info.blockColor), decoration: .some(match.info.decoration),
                    align: .some(match.info.align), font: .some(match.info.font))
                if exact != nil { proposed[i].inline = match.inline }
                used.insert(match.info.id)
            }
        }
        undo.beginUndoGrouping()
        rebuild(proposed, select: proposed.first.map { [$0.info.id] } ?? [], blockMode: false)
        undo.setActionName("Replace Note with Codex Draft")
        undo.endUndoGrouping()
    }
}
