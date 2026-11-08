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
            guard let pr = paragraph(withId: edit.blockId), !block(at: pr).kind.isAttachment else { throw AgentEditError.invalid("Block \(edit.blockId) is missing or cannot be formatted as text.") }
            let current = planned[edit.blockId] ?? ns.substring(with: contentRange(pr))
            if edit.action == "replace_text" {
                guard current == edit.expectedText else { throw AgentEditError.invalid("Text in block \(edit.blockId) changed. Read the note again.") }
                planned[edit.blockId] = (MarkdownImport.inline(edit.text ?? "")).map { $0.text ?? "" }.joined()
            } else if ["bold", "italic", "underline", "strike", "code", "highlight", "text_color"].contains(edit.action) {
                let phrase = edit.text ?? ""
                let count = current.components(separatedBy: phrase).count - 1
                guard count == 1 else { throw AgentEditError.invalid("The phrase “\(phrase)” must occur exactly once in block \(edit.blockId).") }
            }
        }
        undo.beginUndoGrouping()
        undoGroup {
            for edit in edits {
                guard let pr = paragraph(withId: edit.blockId) else { continue }
                textView.setSelectedRange(NSRange(location: pr.location, length: 0))
                switch edit.action {
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
        undo.setActionName("Apply Codex Note Edits")
        undo.endUndoGrouping()
        host?.editorDidChange()
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
