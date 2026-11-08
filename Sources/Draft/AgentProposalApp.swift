import SwiftUI
import DraftCore

extension AppModel {
    func startAgentProposalWatch() {
        agentProposalTimer?.invalidate()
        agentProposalTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.showNextAgentProposal() }
        }
        showNextAgentProposal()
    }

    func showNextAgentProposal() {
        guard agentProposal == nil, confirm == nil else { return }
        let pending = AgentProposalStore.pending(vaultURL: vault.dir)
        pendingAgentCount = pending.count
        agentProposal = pending.first { !deferredProposals.contains($0.id) }
    }

    /// Later: close the sheet and keep the proposal pending until the user asks to review it.
    func deferAgentProposal() {
        guard let p = agentProposal else { return }
        deferredProposals.insert(p.id)
        agentProposal = nil
    }

    func reviewPendingAgentProposals() {
        deferredProposals.removeAll()
        showNextAgentProposal()
    }

    func rejectAgentProposal() {
        guard var proposal = agentProposal else { return }
        proposal.status = "rejected"
        proposal.result = "The user declined this edit in Draft."
        do {
            try AgentProposalStore.save(proposal, vaultURL: vault.dir)
            agentProposal = nil
        } catch { toast("Could not record the rejection: \(error.localizedDescription)") }
    }

    func acceptAgentProposal() {
        guard var proposal = agentProposal else { return }
        do {
            guard readOnly == nil else { throw AgentEditError.invalid("Draft is read-only right now.") }
            guard library.settings.agentPermission(proposal.client).allows(proposal.requiredAccess) else {
                throw AgentEditError.invalid("\(proposal.client ?? "This agent") isn't allowed to make \(proposal.requiredAccess == .destructive ? "destructive" : "") changes. Change it in Settings › Agents.")
            }
            for edit in proposal.edits { try edit.validate() }
            flushAll()
            guard saveState != "error" else { throw AgentEditError.invalid("Draft could not save the current note. Fix the save error before applying this proposal.") }
            let message: String
            if proposal.changesLibrary {
                message = try applyLibraryProposal(&proposal)
            } else {
                guard let meta = library.docs[proposal.documentId], meta.deletedAt == nil, meta.template == nil,
                      let doc = ensureDoc(proposal.documentId) else { throw AgentEditError.invalid("This note is not available for editing.") }
                try checkRevision(&proposal, doc)
                if let spaceId = meta.spaceId, spaceId != library.space.id { switchSpace(spaceId) }
                let editor = editor(for: doc.id)
                if proposal.edits[0].action == "document_style" {
                    guard proposal.edits.count == 1, let styleId = proposal.edits[0].value,
                          Styles.all.contains(where: { $0.id == styleId }) else {
                        throw AgentEditError.invalid("This style is no longer available.")
                    }
                    updateAppearance(doc.id) { $0.styleId = styleId; $0.overrides = StyleOverrides() }
                } else {
                    try editor.controller.applyAgentEdits(proposal.edits)
                }
                openView(.doc(doc.id))
                markDocDirty(doc.id)
                message = "Applied in Draft. Use Command-Z in the note to undo it in one step."
            }
            flushAll()
            refreshIndex()
            guard saveState != "error" else { throw AgentEditError.invalid("Draft could not save the change. Use Undo or try saving again.") }
            proposal.status = "accepted"
            proposal.result = message
            try AgentProposalStore.save(proposal, vaultURL: vault.dir)
            if proposal.changesLibrary { toast("Applied: \(proposal.instruction)", action: "Undo") { [weak self] in self?.undoAgentChange() } }
            else { toast("Changes applied to “\(proposal.documentTitle.isEmpty ? "Untitled" : proposal.documentTitle)”") }
        } catch {
            if proposal.status == "pending" { proposal.status = "failed" }
            proposal.result = error.localizedDescription
            try? AgentProposalStore.save(proposal, vaultURL: vault.dir)
            toast("Not applied: \(error.localizedDescription)")
        }
        agentProposal = nil
    }

    private func checkRevision(_ proposal: inout AgentProposal, _ doc: DocFile) throws {
        guard let current = docs[doc.id], try AgentProposalStore.revision(current) == proposal.expectedRevision else {
            proposal.status = "stale"
            throw AgentEditError.invalid("The note changed after it was read. Read it again and propose a fresh change.")
        }
    }

    /// Create, rename and move change the library, not a note's text, so they get their own undo
    /// (the toast's Undo and Edit › Undo Agent Change), one step per accepted proposal.
    private func applyLibraryProposal(_ proposal: inout AgentProposal) throws -> String {
        let edit = proposal.edits[0]
        func folder(_ value: String?, in space: String) throws -> String? {
            guard let value, value != "unsorted" else { return nil }
            guard library.folders.contains(where: { $0.id == value && ($0.spaceId ?? library.spaces.first?.id) == space }) else {
                throw AgentEditError.invalid("The folder no longer exists in that Space.")
            }
            return value
        }
        switch edit.action {
        case "create_document":
            guard AgentProposalStore.libraryRevision(library) == proposal.expectedRevision else {
                proposal.status = "stale"
                throw AgentEditError.invalid("Spaces or folders changed after the proposal was made. Propose the note again.")
            }
            let space = edit.target ?? library.space.id
            guard library.spaces.contains(where: { $0.id == space }) else { throw AgentEditError.invalid("That Space no longer exists.") }
            let fid = try folder(edit.value, in: space)
            if space != library.space.id { switchSpace(space) }
            guard let id = createDoc(folderId: .some(fid), open: true, title: edit.title ?? "") else { throw AgentEditError.invalid("Draft couldn't create the note.") }
            if let text = edit.text, !text.isEmpty {
                let content = ensureBlockIds(Node("doc", content: MarkdownImport.blocks(text) + [Node("paragraph")]))
                docs[id]?.content = content
                editors[id]?.controller.load(content)
                if let d = docs[id] { library.docs[id]?.applyDerived(from: d) }
                markDocDirty(id)
            }
            freshDocs = []
            registerAgentUndo("Create “\(edit.title ?? "Untitled")”") { m in
                m.saveDirtyDocs()
                _ = m.library.trash(id)
                m.dropEditor(id)
                m.tabs.removeAll { $0.view.docId == id }
                if !m.tabs.contains(where: { $0.id == m.activeTabId }) { m.activeTabId = m.tabs[0].id }
                m.scheduleLibrarySave()
            }
            proposal.result = "Created document \(id)."
            return "Created \(id) in Draft. Undo moves it to Recently Deleted."
        case "rename_document":
            guard let doc = ensureDoc(proposal.documentId), library.docs[doc.id]?.deletedAt == nil else { throw AgentEditError.invalid("This note is not available.") }
            try checkRevision(&proposal, doc)
            let old = doc.title, new = edit.title ?? ""
            func set(_ m: AppModel, _ t: String) { m.setTitle(doc.id, t); m.editors[doc.id]?.title = t }
            set(self, new)
            registerAgentUndo("Rename “\(old)”") { m in set(m, old); m.flushAll() }
            return "Renamed to “\(new)”."
        case "move_document":
            guard let doc = ensureDoc(proposal.documentId), let meta = library.docs[doc.id], meta.deletedAt == nil else { throw AgentEditError.invalid("This note is not available.") }
            try checkRevision(&proposal, doc)
            let space = edit.target ?? meta.spaceId ?? library.space.id
            guard library.spaces.contains(where: { $0.id == space }) else { throw AgentEditError.invalid("That Space no longer exists.") }
            let fid = edit.value == nil && edit.target != nil ? nil : try folder(edit.value, in: space)
            let ids = [doc.id] + descendants(doc.id)
            let before = ids.map { ($0, library.docs[$0]?.folderId, library.docs[$0]?.spaceId) }
            for d in ids { library.docs[d]?.spaceId = space; if d == doc.id { library.docs[d]?.folderId = fid } }
            scheduleLibrarySave()
            registerAgentUndo("Move “\(meta.title)”") { m in
                for (d, f, sp) in before { m.library.docs[d]?.folderId = f; m.library.docs[d]?.spaceId = sp }
                m.scheduleLibrarySave(); m.flushAll(); m.indexTick &+= 1
            }
            indexTick &+= 1
            return "Moved\(ids.count > 1 ? " with \(ids.count - 1) nested page(s)" : "")."
        default:
            throw AgentEditError.invalid("Unknown library action.")
        }
    }

    private func registerAgentUndo(_ name: String, _ undo: @escaping (AppModel) -> Void) {
        agentUndo.beginUndoGrouping()
        agentUndo.registerUndo(withTarget: self) { m in onMain { undo(m); m.refreshIndex() } }
        agentUndo.setActionName(name)
        agentUndo.endUndoGrouping()
        agentUndoName = name
    }

    func undoAgentChange() {
        guard agentUndo.canUndo else { return }
        agentUndo.undo()
        agentUndoName = agentUndo.canUndo ? agentUndo.undoActionName : nil
    }
}

struct AgentProposalReview: View {
    @Environment(AppModel.self) var model
    @Environment(\.tokens) var t
    let proposal: AgentProposal

    var structure: DraftTools.DocumentStructure? { proposal.documentId == "new" ? nil : try? DraftTools(vaultURL: model.vault.dir).structure(proposal.documentId) }

    var body: some View {
        let blocks = Dictionary((structure?.blocks ?? []).map { ($0.id, $0.text) }, uniquingKeysWith: { a, _ in a })
        VStack(alignment: .leading, spacing: DS.s3) {
            VStack(alignment: .leading, spacing: DS.s1) {
                Text("Review proposed changes").font(.system(size: DS.title2, weight: .bold)).foregroundStyle(t.text).accessibilityAddTraits(.isHeader)
                Text(proposal.documentId == "new" ? "New note" : (proposal.documentTitle.isEmpty ? "Untitled" : proposal.documentTitle))
                    .font(.system(size: DS.headline, weight: .semibold)).foregroundStyle(t.text)
                Text(proposal.instruction).font(.system(size: DS.body)).foregroundStyle(t.secondary).fixedSize(horizontal: false, vertical: true)
            }
            permissionBox
            ScrollView {
                VStack(alignment: .leading, spacing: DS.s2) {
                    ForEach(Array(proposal.edits.enumerated()), id: \.offset) { i, edit in card(i, edit, blocks) }
                }
            }
            .frame(maxHeight: 420)
            Text("Nothing changes until you apply. Draft checks the note hasn't changed, keeps a backup, and one Undo reverses the whole proposal.")
                .font(.system(size: DS.footnote)).foregroundStyle(t.tertiary).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: DS.s2) {
                Button("Reject") { model.rejectAgentProposal() }.buttonStyle(.draft).keyboardShortcut(.cancelAction)
                    .accessibilityHint("Leaves the note unchanged and tells the agent")
                Button("Later") { model.deferAgentProposal() }.buttonStyle(DraftButtonStyle(role: .quiet))
                    .accessibilityHint("Closes this without deciding; review it from Edit › Review Agent Proposals")
                Spacer()
                Button(applyTitle) { model.acceptAgentProposal() }
                    .buttonStyle(DraftButtonStyle(role: allowed ? (destructive ? .destructive : .primary) : .secondary)).keyboardShortcut(.defaultAction)
                    .disabled(!allowed)
            }
        }
        .padding(DS.s5)
        .frame(minWidth: 420, idealWidth: 600, maxWidth: 600)
        .background(t.canvas)
        .interactiveDismissDisabled()
    }

    var destructive: Bool { proposal.requiredAccess == .destructive }
    var allowed: Bool { model.library.settings.agentPermission(proposal.client).allows(proposal.requiredAccess) }
    var applyTitle: String {
        let deletes = proposal.edits.filter { $0.action == "delete_block" }.count
        if deletes > 0 { return "Apply and Delete \(deletes) Block\(deletes == 1 ? "" : "s")" }
        return proposal.edits.count == 1 ? "Apply Change" : "Apply \(proposal.edits.count) Changes"
    }

    /// Who asked, which notes it touches, and what permission it needs.
    var permissionBox: some View {
        let id = proposal.documentId
        let pages = id == "new" ? [] : [id] + model.descendants(id)
        let movesPages = proposal.edits.first?.action == "move_document" && pages.count > 1
        let affected = id == "new" ? ["New note “\(proposal.documentTitle)”"]
            : (movesPages ? pages : [id]).map { model.library.docs[$0]?.title ?? "" }.map { $0.isEmpty ? "Untitled" : $0 }
        let need = destructive ? "Destructive changes" : "Propose changes"
        return VStack(alignment: .leading, spacing: DS.s1 + 2) {
            HStack(spacing: DS.s2) {
                Image(systemName: destructive ? "exclamationmark.triangle.fill" : "person.badge.key").foregroundStyle(destructive ? Color(hex: "#d24b4b") : t.accent).accessibilityHidden(true)
                Text("From \(proposal.client ?? "an agent") · needs “\(need)”").font(.system(size: DS.footnote, weight: .semibold)).foregroundStyle(t.text)
            }
            Text("Affects \(affected.count == 1 ? "1 note" : "\(affected.count) notes"): \(affected.prefix(8).joined(separator: ", "))\(affected.count > 8 ? " and \(affected.count - 8) more" : "")")
                .font(.system(size: DS.footnote)).foregroundStyle(t.secondary).fixedSize(horizontal: false, vertical: true)
            if !allowed {
                Text("\(proposal.client ?? "This agent") doesn't have this permission, so it can't be applied. Allow it in Settings › Agents, or reject it.")
                    .font(.system(size: DS.footnote)).foregroundStyle(Color(hex: "#d24b4b")).fixedSize(horizontal: false, vertical: true)
            } else if destructive {
                Text("This removes or moves content. Draft keeps a backup and one Undo reverses it.").font(.system(size: DS.footnote)).foregroundStyle(t.secondary)
            }
        }
        .padding(DS.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: DS.rControl, style: .continuous).strokeBorder(destructive ? Color(hex: "#d24b4b").opacity(0.5) : t.line, lineWidth: 1))
        .accessibilityElement(children: .combine)
    }

    func quoted(_ s: String?) -> String { "“\(String((s ?? "").prefix(80)))\((s ?? "").count > 80 ? "…" : "")”" }

    /// The block's text with the proposed inline format on the phrase, as it will look.
    func formatted(_ block: String, _ e: AgentEdit) -> AttributedString {
        var a = AttributedString(block)
        guard let phrase = e.text, let r = a.range(of: phrase) else { return a }
        switch e.action {
        case "bold": a[r].inlinePresentationIntent = .stronglyEmphasized
        case "italic": a[r].inlinePresentationIntent = .emphasized
        case "underline": a[r].underlineStyle = .single
        case "strike": a[r].strikethroughStyle = .single
        case "code": a[r].inlinePresentationIntent = .code
        case "highlight": a[r].backgroundColor = Color(hex: e.value ?? "#fff3a3"); a[r].foregroundColor = Color(hex: "#1d1d1b")
        case "text_color": a[r].foregroundColor = Color(hex: e.value ?? "#000000")
        case "link": a[r].link = URL(string: e.value ?? ""); a[r].underlineStyle = .single
        case "unlink": a[r].underlineStyle = nil
        default: break
        }
        return a
    }

    func card(_ i: Int, _ e: AgentEdit, _ blocks: [String: String]) -> some View {
        let block = blocks[e.blockId]
        let folder = { (id: String?) -> String in id == nil || id == "unsorted" ? "Unsorted" : model.library.folders.first { $0.id == id }?.name ?? "a folder" }
        let names = ["title": "a title", "subtitle": "a subtitle", "heading": "a heading", "strong": "a strong heading", "caption": "a caption", "body": "body text",
                     "quote": "a quote", "callout": "a callout", "code": "a code block", "bullet": "a bulleted list", "numbered": "a numbered list", "task": "a task", "none": "plain text"]
        // (title, removed/old text, new text, the unchanged block a format applies to, colour swatch)
        let (title, before, after, context, swatch): (String, String?, AttributedString?, String?, String?) = {
            let md = { (t: String?) in t.map { (try? AttributedString(markdown: $0, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString($0) } }
            switch e.action {
            case "create_document": return ("Create note “\(e.title ?? "Untitled")” in \(folder(e.value))", nil, md(e.text), nil, nil)
            case "rename_document": return ("Rename note", proposal.documentTitle, md(e.title), nil, nil)
            case "move_document":
                let space = e.target.flatMap { s in model.library.spaces.first { $0.id == s }?.name }
                return ("Move note to \(e.value != nil || e.target == nil ? folder(e.value) : "")\(space.map { " in \($0)" } ?? "")", nil, nil, nil, nil)
            case "replace_document": return ("Replace the whole note", nil, md(e.text), nil, nil)
            case "document_style": return ("Use the \(Styles.all.first { $0.id == e.value }?.name ?? e.value ?? "") style", nil, nil, nil, nil)
            case "replace_text": return ("Rewrite a paragraph", e.expectedText, md(e.text), nil, nil)
            case "append": return ("Add at the end", nil, md(e.text), nil, nil)
            case "insert_blocks": return ("Insert \(e.position ?? "after") \(quoted(block))", nil, md(e.text), nil, nil)
            case "delete_block": return ("Delete a paragraph", block, nil, nil, nil)
            case "move_block": return ("Move \(quoted(block)) \(e.position ?? "after") \(quoted(e.target.flatMap { blocks[$0] }))", nil, nil, nil, nil)
            case "task_checked": return (e.value == "true" ? "Check off a task" : "Uncheck a task", nil, nil, block, nil)
            case "insert_separator": return ("Insert a \(e.value == "dots" ? "three-dot" : e.value == "page_break" ? "page break" : (e.value ?? "")) separator after \(quoted(block))", nil, nil, nil, nil)
            case "separator_style": return ("Change the separator to \(e.value ?? "")", nil, nil, nil, nil)
            case "heading", "block_kind", "list": return ("Make it \(names[e.value ?? ""] ?? e.value ?? "")", nil, nil, block, nil)
            case "decoration": return (e.value == "none" ? "Remove the decoration" : "Add a \(e.value ?? "") decoration", nil, nil, block, nil)
            case "block_color": return ("Tint the block", nil, nil, block, e.value)
            case "font": return ("Use the \(e.value ?? "") font", nil, nil, block, nil)
            case "align": return ("Align \(e.value ?? "")", nil, nil, block, nil)
            case "bold", "italic", "underline", "strike", "code", "highlight", "text_color", "link", "unlink":
                let verb = ["bold": "Make bold", "italic": "Make italic", "underline": "Underline", "strike": "Strike through", "code": "Format as code",
                            "highlight": "Highlight", "text_color": "Colour", "link": "Link", "unlink": "Remove the link from"][e.action]!
                return ("\(verb) \(quoted(e.text))\(e.action == "link" ? " to \(e.value ?? "")" : "")", nil, block.map { formatted($0, e) },
                        nil, ["highlight", "text_color"].contains(e.action) ? e.value : nil)
            default: return (e.action.replacingOccurrences(of: "_", with: " ").capitalized, nil, nil, block, nil)
            }
        }()
        return VStack(alignment: .leading, spacing: DS.s1 + 2) {
            HStack(spacing: DS.s2) {
                Text("\(i + 1). \(title)").font(.system(size: DS.body, weight: .semibold)).foregroundStyle(t.text).fixedSize(horizontal: false, vertical: true)
                if let swatch {
                    RoundedRectangle(cornerRadius: 4, style: .continuous).fill(Color(hex: swatch)).frame(width: 16, height: 12)
                        .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(t.line, lineWidth: 0.5)).accessibilityHidden(true)
                }
            }
            if let context, !context.isEmpty { diffLine("Block", AttributedString(context), t.secondary, strike: false) }
            if let before, !before.isEmpty { diffLine("Before", AttributedString(before), Color(hex: "#d4544c"), strike: after != nil || e.action == "delete_block") }
            if let after, !after.characters.isEmpty { diffLine(["create_document", "append", "insert_blocks", "replace_document"].contains(e.action) ? "Adds" : "After", after, Color(hex: "#2f9a5a"), strike: false) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DS.s3)
        .background(RoundedRectangle(cornerRadius: DS.rControl, style: .continuous).fill(t.hover))
        .accessibilityElement(children: .combine)
    }

    func diffLine(_ label: String, _ text: AttributedString, _ color: Color, strike: Bool) -> some View {
        HStack(alignment: .top, spacing: DS.s2) {
            Text(label.uppercased()).font(.system(size: DS.micro + 1, weight: .semibold)).tracking(0.5).foregroundStyle(color).frame(width: 46, alignment: .leading)
            Text(text).font(.system(size: DS.footnote + 1)).foregroundStyle(t.text.opacity(strike ? 0.65 : 1)).strikethrough(strike, color: color.opacity(0.6))
                .lineLimit(12).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
        }
    }
}
