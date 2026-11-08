import Foundation
import DraftCore

extension Automation {
    static func agentExternalAccept() async {
        var result: [String: String] = [:]
        m.showNextAgentProposal()
        if let proposal = m.agentProposal {
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
        } catch { result["error"] = error.localizedDescription }
    }
}
