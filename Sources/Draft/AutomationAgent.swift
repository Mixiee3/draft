import Foundation
import AppKit
import DraftCore
import DraftEditor

extension Automation {
    static func agentExternalAccept() async {
        var result: [String: String] = [:]
        m.showNextAgentProposal()
        if let proposal = m.agentProposal {
            await wait(0.8)
            if let w = NSApp.windows.first(where: { $0.isVisible }), let sheet = w.attachedSheet { await captureWindow(sheet, "agent-proposal-review") }
            result["requestId"] = proposal.id
            m.acceptAgentProposal()
            result["status"] = (try? AgentProposalStore.load(proposal.id, vaultURL: m.vault.dir).status) ?? "missing"
            result["heading"] = m.ensureDoc(proposal.documentId)?.content.content?.first?.type ?? "missing"
        }
        if let data = try? JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: out.appendingPathComponent("agent-external-result.json"))
        }
        await wait(0.7) // let SwiftUI dismiss the review sheet before Automation terminates the app
    }

    static func agentEdit() async {
        var result: [String: String] = [:]
        defer {
            if let data = try? JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]) {
                try? data.write(to: out.appendingPathComponent("agent-edit-result.json"))
            }
        }
        guard let id = m.createDoc(title: "Garden"), let doc = m.ensureDoc(id) else { return }
        let editor = m.editor(for: id)
        editor.controller.load(ensureBlockIds(Node("doc", content: MarkdownImport.blocks("Garden plan\nBuy compost"))))
        m.markDocDirty(id); m.flushAll()
        guard let saved = m.docs[id], let blocks = saved.content.content, blocks.count == 2,
              let firstId = blocks[0].id, let secondId = blocks[1].id else { return }
        do {
            let revision = try AgentProposalStore.revision(saved)
            let proposal = try AgentProposal(documentId: id, documentTitle: doc.title, instruction: "Make this garden note clearer and easier to scan", expectedRevision: revision,
                edits: [AgentEdit(action: "heading", blockId: firstId, value: "title"),
                        AgentEdit(action: "replace_text", blockId: secondId, text: "Buy **forty** bags of compost", expectedText: "Buy compost"),
                        AgentEdit(action: "highlight", blockId: secondId, value: "#fff3a3", text: "forty")])
            try AgentProposalStore.save(proposal, vaultURL: m.vault.dir)
            result["before"] = docPlainText(saved.content)
            result["queued"] = AgentProposalStore.pending(vaultURL: m.vault.dir).count == 1 ? "yes" : "no"
            m.showNextAgentProposal()
            m.acceptAgentProposal()
            result["status"] = try AgentProposalStore.load(proposal.id, vaultURL: m.vault.dir).status
            let after = try m.vault.loadDoc(id)
            result["after"] = after.map { docPlainText($0.content) } ?? ""
            result["idsKept"] = after?.content.content?.first?.id == firstId && after?.content.content?.last?.id == secondId ? "yes" : "no"
            result["heading"] = after?.content.content?.first?.type ?? ""
            editor.controller.undo.undo()
            result["undo"] = docPlainText(editor.controller.document()) == result["before"] ? "yes" : "no"
            m.markDocDirty(id); m.flushAll()
            if let restored = m.docs[id] {
                let style = try AgentProposal(documentId: id, documentTitle: restored.title,
                    instruction: "Use a calm blue document style", expectedRevision: AgentProposalStore.revision(restored),
                    edits: [AgentEdit(action: "document_style", blockId: id, value: "tidepool")])
                try AgentProposalStore.save(style, vaultURL: m.vault.dir)
                m.showNextAgentProposal(); m.acceptAgentProposal()
                result["styleStatus"] = try AgentProposalStore.load(style.id, vaultURL: m.vault.dir).status
                result["styleApplied"] = m.docs[id]?.appearance.styleId == "tidepool" ? "yes" : "no"
                editor.controller.undo.undo()
                result["styleUndo"] = m.docs[id]?.appearance.styleId == "paper" ? "yes" : "no"
            }
        } catch { result["error"] = error.localizedDescription }
    }

    /// Reject, stale revision, and what a targeted edit must leave alone: links, tags, tasks, nested pages.
    static func agentIntegrity() async {
        var r: [String: String] = [:]
        defer { if let d = try? JSONSerialization.data(withJSONObject: r, options: [.prettyPrinted, .sortedKeys]) { try? d.write(to: out.appendingPathComponent("agent-integrity-result.json")) } }
        guard let id = m.createDoc(title: "Plot notes") else { return }
        let ed = m.editor(for: id)
        ed.controller.load(ensureBlockIds(Node("doc", content: MarkdownImport.blocks("Spring plan #garden\n- [ ] water the beds\nSee [the guide](https://example.com/guide)\nOld wording here"))))
        m.markDocDirty(id); m.flushAll()
        if let child = m.createDoc(parentDocId: id, open: false, title: "Seed list") {
            let tv = ed.controller.textView
            tv.setSelectedRange(NSRange(location: (tv.string as NSString).length, length: 0))
            ed.controller.insertAttachmentBlock(kind: .page, node: Node("pageCard", attrs: ["docId": .string(child), "title": "Seed list", "presentation": "card"]))
        }
        m.openView(.doc(id)); await wait(0.4)
        m.markDocDirty(id); m.flushAll(); m.rebuildIndex(); await wait(0.6)
        func blocks() -> [Node] { m.docs[id]?.content.content ?? [] }
        guard let last = blocks().first(where: { nodeText($0) == "Old wording here" })?.id, let doc = m.docs[id] else { r["setup"] = "failed"; return }
        r["cardBefore"] = blocks().contains { $0.type == "pageCard" } ? "yes" : "no"
        do {
            // Reject leaves the note untouched and records the answer for Codex.
            let rev = try AgentProposalStore.revision(doc)
            let rejectMe = try AgentProposal(documentId: id, documentTitle: doc.title, instruction: "Reword", expectedRevision: rev,
                                             edits: [AgentEdit(action: "replace_text", blockId: last, text: "Rejected wording", expectedText: "Old wording here")])
            try AgentProposalStore.save(rejectMe, vaultURL: m.vault.dir)
            m.showNextAgentProposal(); m.rejectAgentProposal()
            r["rejectStatus"] = try AgentProposalStore.load(rejectMe.id, vaultURL: m.vault.dir).status
            r["rejectUnchanged"] = (try m.vault.loadDoc(id)).map { docPlainText($0.content).contains("Old wording here") } == true ? "yes" : "no"

            // A proposal made against an older revision is refused after the note changed.
            let stale = try AgentProposal(documentId: id, documentTitle: doc.title, instruction: "Reword", expectedRevision: rev,
                                          edits: [AgentEdit(action: "replace_text", blockId: last, text: "Stale wording", expectedText: "Old wording here")])
            ed.controller.textView.setSelectedRange(NSRange(location: 0, length: 0)); ed.controller.textView.insertText("Note: ", replacementRange: NSRange(location: 0, length: 0))
            m.markDocDirty(id); m.flushAll()
            try AgentProposalStore.save(stale, vaultURL: m.vault.dir)
            m.showNextAgentProposal(); m.acceptAgentProposal()
            r["staleStatus"] = try AgentProposalStore.load(stale.id, vaultURL: m.vault.dir).status
            r["staleUnchanged"] = (try m.vault.loadDoc(id)).map { !docPlainText($0.content).contains("Stale wording") } == true ? "yes" : "no"

            // A fresh targeted edit changes one block and keeps everything else.
            guard let now = m.docs[id] else { return }
            let ok = try AgentProposal(documentId: id, documentTitle: now.title, instruction: "Reword", expectedRevision: AgentProposalStore.revision(now),
                                       edits: [AgentEdit(action: "replace_text", blockId: last, text: "New **wording** here", expectedText: "Old wording here")])
            try AgentProposalStore.save(ok, vaultURL: m.vault.dir)
            m.showNextAgentProposal(); m.acceptAgentProposal()
            r["acceptStatus"] = try AgentProposalStore.load(ok.id, vaultURL: m.vault.dir).status
            let saved = try m.vault.loadDoc(id)
            let text = saved.map { docPlainText($0.content) } ?? ""
            r["changed"] = text.contains("New wording here") ? "yes" : "no"
            r["tagKept"] = text.contains("#garden") ? "yes" : "no"
            r["taskKept"] = saved.map { tasksOf($0.content).count } == 1 ? "yes" : "no"
            var link = false
            if let c = saved?.content { walk(c) { n in if n.marks?.contains(where: { $0.type == "link" }) == true { link = true } } }
            r["linkKept"] = link ? "yes" : "no"
            r["cardKept"] = saved?.content.content?.contains { $0.type == "pageCard" } == true ? "yes" : "no"
            r["childKept"] = m.library.liveDocs.contains { $0.parentDocId == id && $0.title == "Seed list" } ? "yes" : "no"
            r["backups"] = "\(m.snapshots(id).count)"
            await wait(1.2)
            r["indexHasEdit"] = (m.index.entries[id]?.blocks ?? []).contains { $0.text.contains("New wording here") } ? "yes" : "no"
            ed.controller.undo.undo(); m.markDocDirty(id); m.flushAll()
            r["undoRestores"] = (try m.vault.loadDoc(id)).map { docPlainText($0.content).contains("Old wording here") } == true ? "yes" : "no"
        } catch { r["error"] = error.localizedDescription }
    }

    /// `agent-review`: the user's side of an MCP proposal. Shows the first pending proposal, captures
    /// the sheet, then applies or rejects it (DRAFT_AGENT_DECISION) and, with DRAFT_AGENT_UNDO, undoes it
    /// once. Writes what a person would see: status, note text, index text, titles, folders.
    static func agentReview() async {
        var r: [String: String] = [:]
        defer { if let d = try? JSONSerialization.data(withJSONObject: r, options: [.prettyPrinted, .sortedKeys]) { try? d.write(to: out.appendingPathComponent("agent-review.json")) } }
        await wait(0.6)
        m.agentProposalTimer?.invalidate() // one proposal per run; the next stays queued
        let env = ProcessInfo.processInfo.environment
        if let theme = env["DRAFT_AGENT_THEME"] { m.setSettings { $0.theme = theme } }
        if env["DRAFT_AGENT_NARROW"] != nil, let w = NSApp.windows.first(where: { $0.isVisible }) { w.setFrame(NSRect(x: 60, y: 60, width: 760, height: 720), display: true) }
        await wait(0.3)
        if let theme = env["DRAFT_AGENT_SETTINGS"], let w = NSApp.windows.first(where: { $0.isVisible }) {
            m.setSettings { $0.theme = theme }
            m.openView(ViewRef(kind: "settings", section: "agents")); await shot("agents-settings-\(theme)", w, settle: 0.8); return
        }
        m.showNextAgentProposal()
        guard let p = m.agentProposal else { r["error"] = "no pending proposal"; return }
        await wait(0.8)
        if let name = ProcessInfo.processInfo.environment["DRAFT_AGENT_SHOT"], let w = NSApp.windows.first(where: { $0.isVisible }), let sheet = w.attachedSheet {
            await captureWindow(sheet, name)
        }
        r["requestId"] = p.id
        if env["DRAFT_AGENT_REVOKE"] != nil { m.setSettings { $0.agentPermissions[p.client ?? ""] = AgentPermission(read: true, propose: true, destructive: false) } }
        r["client"] = p.client ?? ""
        let decision = env["DRAFT_AGENT_DECISION"] ?? "accept"
        if let w = NSApp.windows.first(where: { $0.isVisible }), let sheet = w.attachedSheet {
            r["sheetSize"] = "\(Int(sheet.frame.width))x\(Int(sheet.frame.height))"
            r["sheetInsideWindow"] = w.frame.insetBy(dx: -1, dy: -1).contains(sheet.frame) ? "yes" : "no"
        }
        if let key = env["DRAFT_AGENT_KEY"] {
            // A real key press through the app, as a keyboard-only user would: Return applies, Escape rejects.
            guard let w = NSApp.windows.first(where: { $0.isVisible }), let sheet = w.attachedSheet else { r["error"] = "no sheet"; return }
            sheet.makeKey()
            let code: UInt16 = key == "return" ? 36 : 53
            for type in [NSEvent.EventType.keyDown, .keyUp] {
                if let e = NSEvent.keyEvent(with: type, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: sheet.windowNumber,
                                            context: nil, characters: key == "return" ? "\r" : "\u{1b}", charactersIgnoringModifiers: key == "return" ? "\r" : "\u{1b}", isARepeat: false, keyCode: code) {
                    NSApp.sendEvent(e)
                }
            }
            await wait(0.6)
            r["sheetClosedByKey"] = w.attachedSheet == nil ? "yes" : "no"
        } else if decision == "later" {
            m.deferAgentProposal(); await wait(0.3)
            r["hiddenAfterLater"] = m.agentProposal == nil ? "yes" : "no"
            m.showNextAgentProposal()
            r["notReshownByWatcher"] = m.agentProposal == nil ? "yes" : "no"
            m.reviewPendingAgentProposals()
            r["reshownOnRequest"] = m.agentProposal?.id == p.id ? "yes" : "no"
            m.deferAgentProposal()
        } else if decision == "reject" { m.rejectAgentProposal() } else { m.acceptAgentProposal() }
        await wait(0.5)
        let saved = (try? AgentProposalStore.load(p.id, vaultURL: m.vault.dir))
        r["status"] = saved?.status ?? "missing"
        r["result"] = saved?.result ?? ""
        let docId = p.documentId == "new" ? (saved?.result?.components(separatedBy: " ").first { $0.hasPrefix("d_") }?.trimmingCharacters(in: .punctuationCharacters) ?? "") : p.documentId
        r["documentId"] = docId
        if let fid = saved?.result?.components(separatedBy: " ").first(where: { $0.hasPrefix("f_") })?.trimmingCharacters(in: .punctuationCharacters) {
            r["folderId"] = fid
            r["folderPath"] = m.library.folderPath(fid)
        }
        func record(_ prefix: String) {
            let doc = try? m.vault.loadDoc(docId)
            r[prefix + "Text"] = doc.map { docPlainText($0.content) } ?? ""
            r[prefix + "Title"] = m.library.docs[docId]?.title ?? ""
            r[prefix + "Folder"] = m.library.docs[docId]?.folderId ?? "unsorted"
            r[prefix + "Space"] = m.library.docs[docId]?.spaceId ?? ""
            r[prefix + "Deleted"] = m.library.docs[docId]?.deletedAt == nil ? "no" : "yes"
            r[prefix + "Index"] = (m.index.entries[docId]?.blocks ?? []).map(\.text).joined(separator: " | ")
            r[prefix + "Types"] = doc?.content.content?.map(\.type).joined(separator: ",") ?? ""
            var marks: [String] = []
            if let c = doc?.content { walk(c) { n in for mk in n.marks ?? [] { marks.append(mk.type + (mk.attrs?["href"]?.string.map { ":" + $0 } ?? "")) } } }
            r[prefix + "Marks"] = marks.sorted().joined(separator: ",")
            r[prefix + "Tasks"] = doc.map { tasksOf($0.content).map { "\($0.checked)" }.joined(separator: ",") } ?? ""
            r[prefix + "Style"] = doc?.appearance.styleId ?? ""
            r[prefix + "Trashed"] = "\(m.library.docs.values.filter { $0.deletedAt != nil }.count)"
        }
        m.refreshIndex(); await wait(1.2)
        record("after")
        r["backups"] = "\(m.snapshots(docId).count)"
        if ProcessInfo.processInfo.environment["DRAFT_AGENT_UNDO"] != nil, saved?.status == "accepted" {
            if p.changesLibrary { m.undoAgentChange() }
            else if let um = m.editors[docId]?.controller.undo {
                if um.groupingLevel > 0 { um.endUndoGrouping() }
                um.undo()
                m.markDocDirty(docId)
            }
            m.flushAll(); m.refreshIndex(); await wait(1.2)
            record("undone")
            if let fid = r["folderId"] { r["folderAfterUndo"] = m.library.folders.contains { $0.id == fid } ? "kept" : "removed" }
        }
    }

    /// `agent-seed`: a throwaway vault for the MCP end-to-end check — a note with a tag, a task, a
    /// web link, an image with a caption, a file, a nested page and a test phrase; a folder; a second Space.
    static func agentSeed() async {
        m.agentProposalTimer?.invalidate(); m.agentProposal = nil // queued proposals wait for agent-review
        await wait(0.3)
        m.setSettings {
            $0.agentPermissions["mcp-test"] = AgentPermission(read: true, propose: true, destructive: true)
            $0.agentPermissions["blocked"] = AgentPermission(read: false, propose: false, destructive: false)
        }
        let folder = m.createFolder(); m.renameFolder(folder, "Archive"); m.renamingFolder = nil
        guard let id = m.createDoc(title: "MCP test note") else { return }
        var content = Node("doc", content: MarkdownImport.blocks("Planning zebra-quartz #garden\n- [ ] water the beds\nSee [the guide](https://example.com/guide)\nPlain closing line"))
        content.content!.append(Node("image", attrs: ["assetId": "missing-asset", "alt": "Bed plan", "caption": "Bed plan"]))
        content.content!.append(Node("file", attrs: ["assetId": "missing-file", "name": "plan.pdf", "size": 1200]))
        if let table = Tables.parse(["| Crop | Bed |", "| --- | --- |", "| Beans | 3 |"]) { content.content!.append(table) }
        if let child = m.createDoc(parentDocId: id, open: false, title: "Seed list") {
            content.content!.append(Node("pageCard", attrs: ["docId": .string(child), "title": "Seed list", "presentation": "card"]))
        }
        content.content!.append(Node("paragraph"))
        m.docs[id]?.content = ensureBlockIds(content)
        m.editors[id]?.controller.load(m.docs[id]!.content)
        if let d = m.docs[id] { m.library.docs[id]?.applyDerived(from: d) }
        m.markDocDirty(id)
        let home = m.library.space.id
        m.createSpace("Work"); m.switchSpace(home)
        m.flushAll(); m.rebuildIndex(); await wait(1.0); m.flushAll()
        try? "\(id) \(folder)".write(to: out.appendingPathComponent("agent-seed.txt"), atomically: true, encoding: .utf8)
    }
}
