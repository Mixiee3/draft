import SwiftUI
import DraftCore
import DraftEditor

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
            for edit in proposal.allEdits { try edit.validate() }
            flushAll()
            guard saveState != "error" else { throw AgentEditError.invalid("Draft could not save the current note. Fix the save error before applying this proposal.") }
            let message: String
            if proposal.parts != nil {
                message = try applyMultiNoteProposal(&proposal)
            } else if proposal.changesLibrary {
                message = try applyLibraryProposal(&proposal)
            } else {
                guard let meta = library.docs[proposal.documentId], meta.deletedAt == nil, meta.template == nil,
                      let doc = ensureDoc(proposal.documentId) else { throw AgentEditError.invalid("This note is not available for editing.") }
                try checkRevision(&proposal, doc)
                if let spaceId = meta.spaceId, spaceId != library.space.id { switchSpace(spaceId) }
                let editor = editor(for: doc.id)
                if proposal.edits.allSatisfy({ CollectionData.agentActions.contains($0.action) }) {
                    try applyCollectionEdits(doc.id, proposal.edits)
                } else if proposal.edits.contains(where: { CollectionData.agentActions.contains($0.action) }) {
                    throw AgentEditError.invalid("Collection changes must be their own proposal.")
                } else if proposal.edits[0].action == "document_style" {
                    guard proposal.edits.count == 1, let styleId = proposal.edits[0].value,
                          Styles.all.contains(where: { $0.id == styleId }) else {
                        throw AgentEditError.invalid("This style is no longer available.")
                    }
                    updateAppearance(doc.id) { $0.styleId = styleId; $0.overrides = StyleOverrides() }
                } else if proposal.edits[0].action == "document_backdrop" {
                    guard proposal.edits.count == 1 else { throw AgentEditError.invalid("A backdrop change is its own proposal.") }
                    let b = try AgentEdit.backdrop(proposal.edits[0].value)
                    updateAppearance(doc.id) { $0.overrides.backdrop = b }
                } else if let bad = proposal.edits.first(where: { $0.action == "link_note" && library.docs[$0.value ?? ""].map { $0.deletedAt != nil } ?? true }) {
                    throw AgentEditError.invalid("The note \(bad.value ?? "") to link to no longer exists.")
                } else if proposal.edits.contains(where: { ["insert_image", "insert_file"].contains($0.action) }) {
                    try applyWithAssets(doc.id, editor.controller, proposal.edits)
                } else {
                    try editor.controller.applyAgentEdits(proposal.edits)
                }
                openView(.doc(doc.id))
                markDocDirty(doc.id)
                message = proposal.usesAgentUndo
                    ? "Applied in Draft. Edit › Undo Agent Change reverses it in one step."
                    : "Applied in Draft. Use Command-Z in the note to undo it in one step."
            }
            flushAll()
            refreshIndex()
            guard saveState != "error" else { throw AgentEditError.invalid("Draft could not save the change. Use Undo or try saving again.") }
            proposal.status = "accepted"
            proposal.result = message
            try AgentProposalStore.save(proposal, vaultURL: vault.dir)
            if proposal.usesAgentUndo { toast("Applied: \(proposal.instruction)", action: "Undo") { [weak self] in self?.undoAgentChange() } }
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
        case "create_folder":
            guard AgentProposalStore.libraryRevision(library) == proposal.expectedRevision else {
                proposal.status = "stale"
                throw AgentEditError.invalid("Spaces or folders changed after the proposal was made. Propose the folder again.")
            }
            let space = edit.target ?? library.space.id
            let name = (edit.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            try library.checkNewFolder(name: name, parent: edit.value, space: space)
            let siblings = library.folders.filter { $0.parentId == edit.value && ($0.spaceId ?? library.spaces.first?.id) == space }.count
            let folder = Folder(name: name, parentId: edit.value, order: Double(siblings), spaceId: space)
            library.folders.append(folder)
            if let p = edit.value, !library.expandedFolders.contains(p) { library.expandedFolders.append(p) }
            scheduleLibrarySave()
            let path = library.folderPath(folder.id)
            registerAgentUndo("Create Folder “\(name)”") { m in
                // Only an empty folder goes away; anything filed in it since stays put.
                guard !m.library.docs.values.contains(where: { $0.folderId == folder.id }), !m.library.folders.contains(where: { $0.parentId == folder.id }) else {
                    m.toast("“\(name)” isn't empty any more, so it was kept.")
                    return
                }
                m.library.folders.removeAll { $0.id == folder.id }
                m.scheduleLibrarySave(); m.flushAll()
            }
            proposal.result = "Created folder \(folder.id)."
            return "Created folder \(folder.id) at \(path). Undo removes it while it's empty."
        case "delete_document":
            guard let doc = ensureDoc(proposal.documentId), library.docs[doc.id]?.deletedAt == nil else { throw AgentEditError.invalid("This note is not available (it may already be in Recently Deleted).") }
            try checkRevision(&proposal, doc)
            saveDirtyDocs()
            let ids = library.trash(doc.id)
            guard !ids.isEmpty else { throw AgentEditError.invalid("Draft couldn't move the note to Recently Deleted.") }
            for i in ids { dropEditor(i) }
            tabs.removeAll { $0.view.kind == "doc" && ids.contains($0.view.docId ?? "") }
            if !tabs.contains(where: { $0.id == activeTabId }) { activeTabId = tabs[0].id }
            panel = nil
            scheduleLibrarySave()
            registerAgentUndo("Delete “\(doc.title.isEmpty ? "Untitled" : doc.title)”") { m in _ = m.library.restore(doc.id); m.scheduleLibrarySave(); m.flushAll() }
            return "Moved \(ids.count) note\(ids.count == 1 ? "" : "s") to Recently Deleted (kept 30 days). Undo restores them."
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
        case "rename_folder":
            guard AgentProposalStore.libraryRevision(library) == proposal.expectedRevision else {
                proposal.status = "stale"
                throw AgentEditError.invalid("Folders changed after the proposal was made. Propose the rename again.")
            }
            guard let i = library.folders.firstIndex(where: { $0.id == edit.blockId }) else { throw AgentEditError.invalid("The folder no longer exists.") }
            let f = library.folders[i], name = (edit.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            try Library.checkFolderName(name)
            guard !library.folders.contains(where: { $0.id != f.id && $0.parentId == f.parentId && $0.spaceId == f.spaceId && $0.name.caseInsensitiveCompare(name) == .orderedSame }) else {
                throw AgentEditError.invalid("A folder named “\(name)” already exists there.")
            }
            let old = f.name
            library.folders[i].name = name
            scheduleLibrarySave()
            registerAgentUndo("Rename Folder “\(old)”") { m in
                if let j = m.library.folders.firstIndex(where: { $0.id == f.id }) { m.library.folders[j].name = old }
                m.scheduleLibrarySave(); m.flushAll()
            }
            return "Renamed the folder to “\(name)”."
        case "create_style":
            let tokens = try AgentEdit.styleTokens(edit.value)
            let name = (edit.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let u = UserStyle(name: name, base: "paper", tokens: tokens)
            library.userStyles.append(u)
            scheduleLibrarySave()
            // Optionally apply it to the proposal's note in the same step.
            var applied: (id: String, old: DocumentAppearance)?
            if proposal.documentId != "none", let doc = ensureDoc(proposal.documentId), library.docs[doc.id]?.deletedAt == nil {
                try checkRevision(&proposal, doc)
                applied = (doc.id, doc.appearance)
                var a = doc.appearance; a.styleId = u.id; a.overrides = StyleOverrides()
                setAppearance(doc.id, a, previous: doc.appearance, registering: false)
            }
            registerAgentUndo("Create Style “\(name)”") { m in
                if let applied { m.setAppearance(applied.id, applied.old, previous: nil, registering: false) }
                // Notes that picked the style up since fall back to its base, as when a style is deleted.
                if m.library.userStyles.contains(where: { $0.id == u.id }) { m.deleteStyle(u.id) }
                m.scheduleLibrarySave(); m.flushAll()
            }
            return "Created the style “\(name)”\(applied != nil ? " and applied it" : ""). Undo removes it."
        default:
            throw AgentEditError.invalid("Unknown library action.")
        }
    }

    /// All notes or none: every revision is checked first, then parts are applied in order; if one
    /// fails, the ones already applied are undone before the error is reported. One Undo reverts all.
    private func applyMultiNoteProposal(_ proposal: inout AgentProposal) throws -> String {
        let parts = proposal.parts ?? []
        for part in parts {
            guard let meta = library.docs[part.documentId], meta.deletedAt == nil, meta.template == nil, let doc = ensureDoc(part.documentId) else {
                throw AgentEditError.invalid("“\(part.documentTitle)” is not available for editing.")
            }
            guard (meta.spaceId ?? library.space.id) == library.space.id || parts.count == 1 else {
                throw AgentEditError.invalid("All notes in one proposal must be in the open Space.")
            }
            guard try AgentProposalStore.revision(doc) == part.expectedRevision else {
                proposal.status = "stale"
                throw AgentEditError.invalid("“\(part.documentTitle)” changed after it was read, so none of the notes were changed. Read them again and propose afresh.")
            }
        }
        var applied: [(String, EditorController)] = []
        func revert() {
            for (id, c) in applied.reversed() { if c.undo.groupingLevel > 0 { c.undo.endUndoGrouping() }; c.undo.undo(); markDocDirty(id) }
        }
        do {
            for part in parts {
                let c = editor(for: part.documentId).controller
                try c.applyAgentEdits(part.edits)
                applied.append((part.documentId, c))
                markDocDirty(part.documentId)
            }
        } catch {
            revert()
            flushAll()
            throw AgentEditError.invalid("\(error.localizedDescription) None of the notes were changed.")
        }
        let done = applied
        registerAgentUndo("Edit \(parts.count) Notes") { m in
            for (id, c) in done.reversed() { if c.undo.groupingLevel > 0 { c.undo.endUndoGrouping() }; c.undo.undo(); m.markDocDirty(id) }
            m.flushAll()
        }
        return "Applied to \(parts.count) notes. Edit › Undo Agent Change reverts all of them."
    }

    /// Collection changes: every edit is checked on a copy first; only then are item pages created,
    /// titles set and the collection written once. One Undo restores the data, trashes the new
    /// pages, brings back deleted ones and resets titles.
    private func applyCollectionEdits(_ docId: String, _ edits: [AgentEdit]) throws {
        var before: [String: CollectionData] = [:], after: [String: CollectionData] = [:]
        var placeholders: [String: String] = [:] // placeholder page id -> title
        for e in edits {
            guard let base = after[e.blockId] ?? collectionData(docId, e.blockId) else { throw AgentEditError.invalid("Block \(e.blockId) isn't a collection.") }
            if before[e.blockId] == nil { before[e.blockId] = base }
            after[e.blockId] = try base.applying(e) {
                let p = "pending-\(placeholders.count)"; placeholders[p] = e.text ?? ""; return p
            }
            if e.action == "collection_update_item", let t = e.text, !t.isEmpty, base.items.first(where: { $0.id == e.target }) == nil {
                throw AgentEditError.invalid("Item \(e.target ?? "") isn't in the collection any more.")
            }
        }
        // Everything passed: create pages, then substitute their ids.
        var real: [String: String] = [:]
        for (p, title) in placeholders.sorted(by: { $0.key < $1.key }) {
            guard let page = createNestedPage(parent: docId, title: title, content: Node("doc", content: [Node("paragraph", attrs: ["id": .string(newId("b_"))])])) else {
                for id in real.values { _ = library.trash(id) }
                throw AgentEditError.invalid("Draft couldn't create an item page.")
            }
            real[p] = page
        }
        var oldTitles: [String: String] = [:]
        for (block, var data) in after {
            for i in data.items.indices { if let r = real[data.items[i].docId] { data.items[i].docId = r } }
            after[block] = data
            for e in edits where e.blockId == block && e.action == "collection_update_item" {
                if let t = e.text, !t.isEmpty, let page = data.items.first(where: { $0.id == e.target })?.docId {
                    oldTitles[page] = oldTitles[page] ?? docTitle(page); setTitle(page, t)
                }
            }
            let old = before[block]!
            for gone in Set(old.items.map(\.docId)).subtracting(data.items.map(\.docId)) { _ = library.trash(gone) }
            writeCollection(docId, block, data)
        }
        scheduleLibrarySave()
        let done = after, was = before, titles = oldTitles
        registerAgentUndo("Collection Change") { m in
            for (block, old) in was {
                if let now = done[block] { m.restoreItemPages(old, comparedTo: now) }
                m.writeCollection(docId, block, old)
            }
            for (page, t) in titles { m.setTitle(page, t) }
            m.flushAll()
        }
    }

    /// Files from an agent: each is checked again (same type and size rules, and the exact bytes that
    /// were proposed), copied into the vault, then inserted with the other edits as one editor change.
    /// If anything fails, copies that weren't in the vault before are removed. One Undo removes the
    /// blocks and those copies.
    private func applyWithAssets(_ docId: String, _ c: EditorController, _ edits: [AgentEdit]) throws {
        var newAssets: [String] = []
        func cleanup() { for a in newAssets { if let u = try? vault.assetURL(a) { try? FileManager.default.removeItem(at: u) } } }
        var ready: [AgentEdit] = []
        do {
            for var e in edits {
                if ["insert_image", "insert_file"].contains(e.action) {
                    let info = try AgentAsset.check(path: e.value ?? "", as: e.action)
                    if let expected = e.expectedText, expected != info.sha256 {
                        throw AgentEditError.invalid("“\(info.name)” changed after it was proposed. Ask the agent to propose it again.")
                    }
                    let data = try Data(contentsOf: info.url, options: .mappedIfSafe)
                    let name = "\(info.sha256.prefix(32)).\(info.ext)"
                    let existed = (try? vault.assetURL(name)).map { FileManager.default.fileExists(atPath: $0.path) } ?? false
                    let asset = try vault.putAsset(data, ext: info.ext)
                    if !existed { newAssets.append(asset) }
                    e.value = asset
                    if e.action == "insert_file" { e.text = info.name; e.expectedText = String(info.size) } else { e.expectedText = nil }
                }
                ready.append(e)
            }
            try c.applyAgentEdits(ready)
        } catch { cleanup(); throw error }
        let added = newAssets
        registerAgentUndo("Insert \(edits.filter { ["insert_image", "insert_file"].contains($0.action) }.count == 1 ? "File" : "Files")") { m in
            if c.undo.groupingLevel > 0 { c.undo.endUndoGrouping() }
            c.undo.undo()
            m.markDocDirty(docId); m.flushAll()
            // Only copies this proposal created, and only if no open note uses them any more.
            for a in added where !m.docs.values.contains(where: { d in var used = false; walk(d.content) { if $0.attrs?["assetId"]?.string == a { used = true } }; return used }) {
                if let u = try? m.vault.assetURL(a) { try? FileManager.default.removeItem(at: u) }
            }
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

    var structure: DraftTools.DocumentStructure? { ["new", "multi"].contains(proposal.documentId) ? nil : try? DraftTools(vaultURL: model.vault.dir).structure(proposal.documentId) }

    var body: some View {
        let blocks = Dictionary((structure?.blocks ?? []).map { ($0.id, $0.text) }, uniquingKeysWith: { a, _ in a }).merging(tableLabels(structure), uniquingKeysWith: { a, _ in a }).merging(collectionLabels(proposal.documentId), uniquingKeysWith: { a, _ in a })
        VStack(alignment: .leading, spacing: DS.s3) {
            VStack(alignment: .leading, spacing: DS.s1) {
                Text("Review proposed changes").font(.system(size: DS.title2, weight: .bold)).foregroundStyle(t.text).accessibilityAddTraits(.isHeader)
                Text(proposal.documentId == "new" ? (proposal.edits.first?.action == "create_folder" ? "New folder" : "New note") : (proposal.documentTitle.isEmpty ? "Untitled" : proposal.documentTitle))
                    .font(.system(size: DS.headline, weight: .semibold)).foregroundStyle(t.text)
                Text(proposal.instruction).font(.system(size: DS.body)).foregroundStyle(t.secondary).fixedSize(horizontal: false, vertical: true)
            }
            permissionBox
            ScrollView {
                VStack(alignment: .leading, spacing: DS.s2) {
                    if let parts = proposal.parts {
                        ForEach(Array(parts.enumerated()), id: \.offset) { _, part in
                            let ps = try? DraftTools(vaultURL: model.vault.dir).structure(part.documentId)
                            let pb = Dictionary((ps?.blocks ?? []).map { ($0.id, $0.text) }, uniquingKeysWith: { a, _ in a }).merging(tableLabels(ps), uniquingKeysWith: { a, _ in a })
                            Text(part.documentTitle.isEmpty ? "Untitled" : part.documentTitle).font(.system(size: DS.footnote, weight: .semibold)).foregroundStyle(t.secondary)
                                .textCase(.uppercase).tracking(0.5).padding(.top, DS.s1).accessibilityAddTraits(.isHeader)
                            ForEach(tablePreviews(part.documentId, part.edits), id: \.0) { _, before, after in TablePreview(before: before, after: after) }
                            ForEach(Array(part.edits.enumerated()), id: \.offset) { i, edit in card(i, edit, pb) }
                        }
                    } else {
                        ForEach(tablePreviews(proposal.documentId, proposal.edits), id: \.0) { _, before, after in TablePreview(before: before, after: after) }
                        ForEach(Array(proposal.edits.enumerated()), id: \.offset) { i, edit in card(i, edit, blocks) }
                    }
                }
            }
            .frame(maxHeight: 420)
            Text("Nothing changes until you apply. Draft checks that nothing changed since the agent read it, keeps a backup of any note it changes, and one Undo reverses the whole proposal.")
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

    /// View settings in words: “Sort: Pages ↓ · Filter: Status is not To do”.
    func viewSummary(_ json: String?) -> AttributedString? {
        guard let o = json.flatMap({ try? JSONDecoder().decode(JSONValue.self, from: Data($0.utf8)) })?.object else { return json.map { AttributedString($0) } }
        var parts: [String] = []
        if let t = o["type"]?.string { parts.append("Layout: \(t)") }
        if let sort = o["sort"]?.items { parts.append("Sort: " + sort.map { "\($0.object?["field"]?.string ?? "") \($0.object?["ascending"]?.bool == false ? "↓" : "↑")" }.joined(separator: ", ")) }
        if let f = o["filters"]?.items { parts.append("Filter: " + (f.isEmpty ? "none" : f.map { "\($0.object?["field"]?.string ?? "") \($0.object?["op"]?.string ?? "") \($0.object?["value"]?.string ?? "")".trimmingCharacters(in: .whitespaces) }.joined(separator: (o["match"]?.string == "any") ? " or " : " and "))) }
        if let g = o["groupBy"] { parts.append("Group by: \(g.string ?? "none")") }
        if let v = o["visible"]?.items { parts.append("Shows: " + v.compactMap(\.string).joined(separator: ", ")) }
        if let n = o["name"]?.string { parts.append("Name: \(n)") }
        return AttributedString(parts.joined(separator: " · "))
    }

    /// Collection item, field and view ids named for the cards.
    func collectionLabels(_ docId: String) -> [String: String] {
        guard let doc = try? DraftTools(vaultURL: model.vault.dir).document(docId) else { return [:] }
        var out: [String: String] = [:]
        walk(doc.content) { n in
            guard let d = CollectionData(node: n) else { return }
            for it in d.items { out[it.id] = "“\(model.docTitle(it.docId))”" }
            for f in d.fields { out[f.id] = "“\(f.name)”" }
            for v in d.views { out[v.id] = "the “\(v.name)” view" }
        }
        return out
    }

    /// `{"Status": "Doing", "Pages": 412}` as “Status: Doing · Pages: 412”.
    func readable(_ json: String?) -> AttributedString? {
        guard let json else { return nil }
        guard let o = (try? JSONDecoder().decode(JSONValue.self, from: Data(json.utf8)))?.object else { return AttributedString(json) }
        func text(_ v: JSONValue) -> String {
            switch v {
            case .string(let s): return s
            case .number(let n): return n.rounded() == n ? String(Int(n)) : String(n)
            case .bool(let b): return b ? "Yes" : "No"
            case .array(let a): return a.map(text).joined(separator: ", ")
            case .null: return "(cleared)"
            case .object: return "…"
            }
        }
        return AttributedString(o.sorted { $0.key < $1.key }.map { "\($0.key): \(text($0.value))" }.joined(separator: " · "))
    }

    /// Row ids named by their first cell, cell ids by their column's header, for readable titles.
    func tableLabels(_ st: DraftTools.DocumentStructure?) -> [String: String] {
        var out: [String: String] = [:]
        for b in st?.blocks ?? [] {
            guard let rows = b.rows, let header = rows.first else { continue }
            for r in rows {
                out[r.id] = "row “\(r.cells.first?.text ?? "")”"
                for (i, c) in r.cells.enumerated() { out[c.id] = "the “\(i < header.cells.count ? header.cells[i].text : "")” column" }
            }
        }
        return out
    }

    /// Each table the proposal touches, as it is and as it will be after every edit; a collection
    /// is shown as a table of its items (title and fields), with new items titled from the proposal.
    func tablePreviews(_ docId: String, _ edits: [AgentEdit]) -> [(String, Node, Node)] {
        guard let doc = try? DraftTools(vaultURL: model.vault.dir).document(docId) else { return [] }
        if edits.allSatisfy({ CollectionData.agentActions.contains($0.action) }) {
            var out: [(String, Node, Node)] = []
            for block in Array(NSOrderedSet(array: edits.map(\.blockId))) as? [String] ?? [] {
                guard let n = doc.content.block(block), let base = CollectionData(node: n) else { continue }
                var titles: [String: String] = [:], d = base, k = 0
                for e in edits where e.blockId == block {
                    if let next = try? d.applying(e, newPage: { k += 1; let p = "pending-\(k)"; titles[p] = e.text ?? ""; return p }) { d = next }
                    if e.action == "collection_update_item", let t = e.text, let page = d.items.first(where: { $0.id == e.target })?.docId { titles[page] = t }
                }
                let title = { (id: String) in titles[id] ?? model.docTitle(id) }
                out.append((block, collectionTable(base, title: { model.docTitle($0) }), collectionTable(d, title: title)))
            }
            return out
        }
        var order: [String] = [], after: [String: Node] = [:], before: [String: Node] = [:]
        for e in edits where Tables.agentActions.contains(e.action) {
            guard let t = before[e.blockId] ?? doc.content.block(e.blockId) else { continue }
            if before[e.blockId] == nil { before[e.blockId] = t; order.append(e.blockId) }
            after[e.blockId] = (try? Tables.applying(e, to: after[e.blockId] ?? t)) ?? after[e.blockId] ?? t
        }
        return order.map { ($0, before[$0]!, after[$0]!) }
    }

    func collectionTable(_ d: CollectionData, title: (String) -> String) -> Node {
        let fields = d.fields.prefix(5)
        let header = Node("tableRow", attrs: ["id": "hdr"], content: [Node("tableCell", attrs: ["id": "hdr-title"], content: [.text("Title")])]
            + fields.map { Node("tableCell", attrs: ["id": .string("hdr-\($0.id)")], content: [.text($0.name)]) })
        let rows = d.items.map { it in
            Node("tableRow", attrs: ["id": .string(it.id)], content: [Node("tableCell", attrs: ["id": .string("\(it.id)-title")], content: [.text(title(it.docId))])]
                + fields.map { f in Node("tableCell", attrs: ["id": .string("\(it.id)-\(f.id)")], content: d.display(it, f.id, title: title).isEmpty ? nil : [.text(d.display(it, f.id, title: title))]) })
        }
        return Node("table", content: [header] + rows)
    }

    var destructive: Bool { proposal.requiredAccess == .destructive }
    var allowed: Bool { model.library.settings.agentPermission(proposal.client).allows(proposal.requiredAccess) }
    var applyTitle: String {
        let deletes = proposal.allEdits.filter { $0.action == "delete_block" }.count
        if deletes > 0 { return "Apply and Delete \(deletes) Block\(deletes == 1 ? "" : "s")" }
        if proposal.edits.first?.action == "delete_document" { return "Move to Recently Deleted" }
        if let parts = proposal.parts { return "Apply to \(parts.count) Notes" }
        return proposal.edits.count == 1 ? "Apply Change" : "Apply \(proposal.edits.count) Changes"
    }

    /// Who asked, which notes it touches, and what permission it needs.
    var permissionBox: some View {
        let id = proposal.documentId
        let pages = id == "new" || id == "multi" ? [] : [id] + model.descendants(id)
        let action = proposal.edits.first?.action ?? ""
        let movesPages = ["move_document", "delete_document"].contains(action) && pages.count > 1
        let affected = proposal.parts.map { $0.map { $0.documentTitle.isEmpty ? "Untitled" : $0.documentTitle } } ?? (id == "new" ? [action == "create_folder" ? "New folder “\(proposal.documentTitle)”" : "New note “\(proposal.documentTitle)”"]
            : (movesPages ? pages : [id]).map { model.library.docs[$0]?.title ?? "" }.map { $0.isEmpty ? "Untitled" : $0 })
        let need = destructive ? "Destructive changes" : "Propose changes"
        return VStack(alignment: .leading, spacing: DS.s1 + 2) {
            HStack(spacing: DS.s2) {
                Image(systemName: destructive ? "exclamationmark.triangle.fill" : "person.badge.key").foregroundStyle(destructive ? Color(hex: "#d24b4b") : t.accent).accessibilityHidden(true)
                Text("From \(proposal.client ?? "an agent") · needs “\(need)”").font(.system(size: DS.footnote, weight: .semibold)).foregroundStyle(t.text)
            }
            Text(action == "create_folder"
                 ? "Creates \(model.library.folderPath(proposal.edits[0].value, space: proposal.edits[0].target ?? model.library.space.id)) › \(proposal.documentTitle)"
                 : "Affects \(affected.count == 1 ? "1 note" : "\(affected.count) notes"): \(affected.prefix(8).joined(separator: ", "))\(affected.count > 8 ? " and \(affected.count - 8) more" : "")")
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
        case "text_effect": if e.value != "none" { a[r].foregroundColor = .accentColor; a[r].inlinePresentationIntent = .stronglyEmphasized }
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
            case "rename_folder":
                return ("Rename folder", model.library.folders.first { $0.id == e.blockId }.map { model.library.folderPath($0.id) }, md(e.title), nil, nil)
            case "create_style":
                return ("Create the style “\(e.title ?? "")”\(proposal.documentId == "none" ? "" : " and use it for this note")", nil, nil, nil, nil)
            case "link_note":
                let target = model.library.docs[e.value ?? ""].map { $0.title.isEmpty ? "Untitled" : $0.title } ?? "a missing note"
                return ("Link \(quoted(e.text)) to “\(target)”", nil, nil, block, nil)
            case "add_tag": return ("Add \(e.value ?? "")", nil, nil, block, nil)
            case "remove_tag": return ("Remove \(e.value ?? "")", nil, nil, block, nil)
            case "task_due":
                return (e.value == "none" ? "Clear the due date" : "Set the due date to \(Day.date(e.value ?? "").map { $0.formatted(date: .abbreviated, time: .omitted) } ?? e.value ?? "")", nil, nil, block, nil)
            case "image_caption", "image_alt":
                let key = e.action == "image_caption" ? "caption" : "alt"
                let old = model.docs[proposal.documentId]?.content.block(e.blockId)?.attrs?[key]?.string
                    ?? model.editors[proposal.documentId]?.controller.document().block(e.blockId)?.attrs?[key]?.string
                let title = key == "caption" ? (e.text?.isEmpty == false ? "Set the image caption" : "Remove the image caption") : "Set the image description (for VoiceOver)"
                return (title, old.flatMap { $0.isEmpty ? nil : $0 }, e.text.map { AttributedString($0) }, nil, nil)
            case "create_folder":
                let path = model.library.folderPath(e.value, space: e.target ?? model.library.space.id) + " › " + (e.title ?? "")
                return ("Create folder “\(e.title ?? "")”", nil, AttributedString(path), nil, nil)
            case "delete_document":
                let pages = [proposal.documentId] + model.descendants(proposal.documentId)
                let linking = Set(model.index.entries.filter { k, v in !pages.contains(k) && v.links.contains { pages.contains($0.doc) } }.map(\.key))
                    .compactMap { model.library.docs[$0]?.title }.map { $0.isEmpty ? "Untitled" : $0 }.sorted()
                return ("Move “\(proposal.documentTitle)”\(pages.count > 1 ? " and \(pages.count - 1) nested page\(pages.count == 2 ? "" : "s")" : "") to Recently Deleted",
                        nil, nil, linking.isEmpty ? nil : "Linked from \(linking.prefix(6).joined(separator: ", "))\(linking.count > 6 ? " and \(linking.count - 6) more" : ""). Those links show as missing until it's restored.", nil)
            case "move_document":
                let space = e.target.flatMap { s in model.library.spaces.first { $0.id == s }?.name }
                return ("Move note to \(e.value != nil || e.target == nil ? folder(e.value) : "")\(space.map { " in \($0)" } ?? "")", nil, nil, nil, nil)
            case "replace_document": return ("Replace the whole note", nil, md(e.text), nil, nil)
            case "document_style": return ("Use the \(Styles.all.first { $0.id == e.value }?.name ?? e.value ?? "") style", nil, nil, nil, nil)
            case "document_backdrop": return ("Use a custom gradient backdrop", nil, nil, nil, nil)
            case "replace_text": return ("Rewrite a paragraph", e.expectedText, md(e.text), nil, nil)
            case "append": return ("Add at the end", nil, md(e.text), nil, nil)
            case "insert_blocks": return ("Insert \(e.position ?? "after") \(quoted(block))", nil, md(e.text), nil, nil)
            case "delete_block": return ("Delete a paragraph", block, nil, nil, nil)
            case "move_block": return ("Move \(quoted(block)) \(e.position ?? "after") \(quoted(e.target.flatMap { blocks[$0] }))", nil, nil, nil, nil)
            case "task_checked": return (e.value == "true" ? "Check off a task" : "Uncheck a task", nil, nil, block, nil)
            case "table_set_cell": return ("Change a cell in \(blocks[e.target ?? ""] ?? "the table")", e.expectedText, md(e.text), nil, nil)
            case "table_insert_row": return ("Add a row \(e.position ?? "after") \(blocks[e.target ?? ""] ?? "another row")", nil, e.text.flatMap { $0.isEmpty ? nil : md($0) }, nil, nil)
            case "table_delete_row": return ("Delete \(blocks[e.target ?? ""] ?? "a table row")", nil, nil, nil, nil)
            case "table_move_row": return ("Move \(blocks[e.target ?? ""] ?? "a row") \(e.position ?? "after") \(blocks[e.value ?? ""] ?? "another row")", nil, nil, nil, nil)
            case "table_insert_column": return ("Add a column \(e.position ?? "after") \(blocks[e.target ?? ""] ?? "another column")", nil, e.text.flatMap { $0.isEmpty ? nil : md($0) }, nil, nil)
            case "table_delete_column": return ("Delete \(blocks[e.target ?? ""] ?? "a table column")", nil, nil, nil, nil)
            case "table_move_column": return ("Move \(blocks[e.target ?? ""] ?? "a column") \(e.position ?? "after") \(blocks[e.value ?? ""] ?? "another column")", nil, nil, nil, nil)
            case "insert_image", "insert_file":
                let name = URL(fileURLWithPath: e.value ?? "").lastPathComponent
                return ("Insert \(e.action == "insert_image" ? "image" : "file") “\(name)” \(e.position ?? "after") \(quoted(block))", nil, nil, nil, nil)
            case "collection_create": return ("Add a collection “\(e.text ?? "")” \(e.position ?? "after") \(quoted(block))", nil, nil, nil, nil)
            case "collection_add_item": return ("Add item “\(e.text ?? "Untitled")”", nil, readable(e.value), nil, nil)
            case "collection_update_item": return ("Update \(blocks[e.target ?? ""] ?? "an item")\(e.text.map { ", renamed “\($0)”" } ?? "")", nil, readable(e.value), nil, nil)
            case "collection_delete_item": return ("Delete \(blocks[e.target ?? ""] ?? "an item") (its page goes to Recently Deleted)", nil, nil, nil, nil)
            case "collection_move_item": return ("Move \(blocks[e.target ?? ""] ?? "an item") \(e.position ?? "after") \(blocks[e.value ?? ""] ?? "another")", nil, nil, nil, nil)
            case "collection_add_field": return ("Add field “\(e.text ?? "")” (\(e.value ?? "text"))", nil, e.expectedText.map { AttributedString("Options: " + $0.replacingOccurrences(of: "|", with: ", ")) }, nil, nil)
            case "collection_rename_field": return ("Rename \(blocks[e.target ?? ""] ?? "a field") to “\(e.text ?? "")”", nil, nil, nil, nil)
            case "collection_delete_field": return ("Delete \(blocks[e.target ?? ""] ?? "a field") and its values", nil, nil, nil, nil)
            case "collection_add_view": return ("Add a \(e.value ?? "table") view “\(e.text ?? "")”", nil, nil, nil, nil)
            case "collection_set_view": return ("Change \(blocks[e.target ?? ""] ?? "a view")", nil, viewSummary(e.value), nil, nil)
            case "insert_separator": return ("Insert a \(e.value == "dots" ? "three-dot" : e.value == "page_break" ? "page break" : (e.value ?? "")) separator after \(quoted(block))", nil, nil, nil, nil)
            case "separator_style": return ("Change the separator to \(e.value ?? "")", nil, nil, nil, nil)
            case "heading", "block_kind", "list": return ("Make it \(names[e.value ?? ""] ?? e.value ?? "")", nil, nil, block, nil)
            case "decoration": return (e.value == "none" ? "Remove the decoration" : "Add a \(e.value ?? "") decoration", nil, nil, block, nil)
            case "block_color": return ("Tint the block", nil, nil, block, e.value)
            case "font": return ("Use the \(e.value ?? "") font", nil, nil, block, nil)
            case "align": return ("Align \(e.value ?? "")", nil, nil, block, nil)
            case "text_effect":
                if let s = e.value.flatMap(Spectrum.init) {
                    let speed = Spectrum.speeds.first { $0.id == s.speed }?.name.lowercased() ?? s.speed
                    return ("Add a \(s.seconds > 0 ? "moving" : "still") \(s.name) gradient to \(quoted(e.text)) (\(speed)\(s.seconds > 0 ? ", \(s.direction)" : ""))", nil, block.map { formatted($0, e) }, nil, nil)
                }
                let name = TextEffects.all.first { $0.kind == e.value }?.name.lowercased()
                return (name.map { "Add a \($0) effect to \(quoted(e.text))" } ?? "Remove the effect from \(quoted(e.text))", nil, block.map { formatted($0, e) }, nil, nil)
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
            if ["document_style", "document_backdrop", "create_style"].contains(e.action) {
                let now = model.docs[proposal.documentId]?.appearance ?? model.vault.peekAppearance(proposal.documentId)
                let before = now.map { Styles.resolve($0) }
                let after: StyleTokens? = {
                    if e.action == "create_style" { return try? AgentEdit.styleTokens(e.value) }
                    guard var a = now else { return nil }
                    if e.action == "document_style" { a.styleId = e.value ?? a.styleId; a.overrides = StyleOverrides() }
                    else if let b = try? AgentEdit.backdrop(e.value) { a.overrides.backdrop = b }
                    return Styles.resolve(a)
                }()
                let name = proposal.documentTitle.isEmpty ? "Untitled" : proposal.documentTitle
                HStack(spacing: DS.s2) {
                    ForEach([("Before", before), ("After", after)].compactMap { l, tok in tok.map { (l, $0) } }, id: \.0) { label, tok in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(label.uppercased()).font(.system(size: DS.micro + 1, weight: .semibold)).tracking(0.5).foregroundStyle(label == "After" ? Color(hex: "#2f9a5a") : t.secondary)
                            StylePreviewCard(tokens: tok, name: e.action == "create_style" && label == "After" ? (e.title ?? name) : name, height: 110)
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(String(format: "%@: page %@, text contrast %.1f to 1", label, tok.pageColor, ColorMath.contrast(tok.textColor, tok.pageColor)))
                    }
                }
                .frame(maxWidth: 420)
            }
            if ["insert_image", "insert_file"].contains(e.action), let path = e.value {
                AssetPreview(path: path, caption: e.action == "insert_image" ? e.text : nil)
            }
            if let context, !context.isEmpty { diffLine(e.action == "delete_document" ? "Links" : "Block", AttributedString(context), t.secondary, strike: false) }
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

/// Before and after of a table: changed and new cells tinted green, cells that go away tinted red.
struct TablePreview: View {
    @Environment(\.tokens) var t
    let before: Node
    let after: Node

    var body: some View {
        let beforeText = Dictionary(Tables.cells(before).flatMap { $0 }.compactMap { c in c.id.map { ($0, nodeText(c)) } }, uniquingKeysWith: { a, _ in a })
        let afterIds = Set(Tables.cells(after).flatMap { $0 }.compactMap(\.id))
        VStack(alignment: .leading, spacing: DS.s2) {
            grid("Before", before) { c in afterIds.contains(c.id ?? "") ? nil : Color(hex: "#d4544c") }
            grid("After", after) { c in beforeText[c.id ?? ""] == nodeText(c) ? nil : Color(hex: "#2f9a5a") }
        }
        .padding(DS.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: DS.rControl, style: .continuous).fill(t.hover))
    }

    func grid(_ label: String, _ table: Node, tint: @escaping (Node) -> Color?) -> some View {
        let rows = Array(Tables.cells(table).prefix(8))
        let cols = min(6, Tables.columnCount(table))
        return VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased()).font(.system(size: DS.micro + 1, weight: .semibold)).tracking(0.5).foregroundStyle(label == "After" ? Color(hex: "#2f9a5a") : t.secondary)
            Grid(alignment: .leading, horizontalSpacing: 1, verticalSpacing: 1) {
                ForEach(Array(rows.enumerated()), id: \.offset) { r, row in
                    GridRow {
                        ForEach(0..<cols, id: \.self) { c in
                            let cell = c < row.count ? row[c] : Node("tableCell")
                            let color = tint(cell)
                            Text(nodeText(cell).isEmpty ? " " : nodeText(cell)).font(.system(size: DS.footnote, weight: r == 0 ? .semibold : .regular))
                                .foregroundStyle(t.text).lineLimit(1)
                                .padding(.horizontal, 6).padding(.vertical, 3)
                                .frame(minWidth: 60, maxWidth: 200, alignment: .leading)
                                .background(color.map { $0.opacity(0.18) } ?? t.card)
                        }
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(t.line, lineWidth: 0.5))
            if Tables.cells(table).count > 8 || Tables.columnCount(table) > 6 {
                Text("Showing the first 8 rows and 6 columns.").font(.system(size: DS.caption)).foregroundStyle(t.tertiary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label): " + Tables.text(table).prefix(8).map { $0.joined(separator: ", ") }.joined(separator: "; "))
    }
}

/// The file an agent wants to add, read from where it is now: nothing is copied before Apply.
struct AssetPreview: View {
    @Environment(\.tokens) var t
    let path: String
    let caption: String?
    @State private var thumb: NSImage?
    @State private var meta = ""

    var body: some View {
        HStack(alignment: .top, spacing: DS.s3) {
            Group {
                if let thumb { Image(nsImage: thumb).resizable().aspectRatio(contentMode: .fit) }
                else { RoundedRectangle(cornerRadius: 8, style: .continuous).fill(t.card) }
            }
            .frame(width: 96, height: 72)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(t.line, lineWidth: 0.5))
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(URL(fileURLWithPath: path).lastPathComponent).font(.system(size: DS.body, weight: .semibold)).foregroundStyle(t.text).lineLimit(1).truncationMode(.middle)
                Text(meta).font(.system(size: DS.footnote)).foregroundStyle(t.secondary)
                Text(path).font(.system(size: DS.caption)).foregroundStyle(t.tertiary).lineLimit(1).truncationMode(.middle).textSelection(.enabled)
                if let caption, !caption.isEmpty { Text("Caption: \(caption)").font(.system(size: DS.footnote)).foregroundStyle(t.secondary).lineLimit(2) }
            }
        }
        .accessibilityElement(children: .combine)
        .task(id: path) {
            let p = path
            let (image, info) = await Task.detached { () -> (NSImage?, String) in
                let url = URL(fileURLWithPath: p)
                let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                let kind = url.pathExtension.uppercased()
                let isImage = AgentAsset.imageTypes.contains(url.pathExtension.lowercased())
                var img: NSImage? = isImage ? NSImage(contentsOf: url) : nil
                if let i = img, i.size.width > 0 {
                    // A small copy, so a large photo isn't kept full size for a 96 pt thumbnail.
                    let scale = min(1, 240 / max(i.size.width, i.size.height))
                    let small = NSImage(size: NSSize(width: i.size.width * scale, height: i.size.height * scale))
                    small.lockFocus(); i.draw(in: NSRect(origin: .zero, size: small.size)); small.unlockFocus()
                    img = small
                }
                if img == nil { img = NSWorkspace.shared.icon(forFile: p) }
                let exists = FileManager.default.fileExists(atPath: p)
                return (img, exists ? "\(kind) · \(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))" : "File not found")
            }.value
            thumb = image; meta = info
        }
    }
}
