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
        agentProposal = AgentProposalStore.pending(vaultURL: vault.dir).first
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
            guard readOnly == nil, let meta = library.docs[proposal.documentId], meta.deletedAt == nil, meta.template == nil,
                  let doc = ensureDoc(proposal.documentId) else { throw AgentEditError.invalid("This note is not available for editing.") }
            for edit in proposal.edits { try edit.validate() }
            flushAll()
            guard saveState != "error" else { throw AgentEditError.invalid("Draft could not save the current note. Fix the save error before applying this proposal.") }
            guard let current = docs[proposal.documentId], try AgentProposalStore.revision(current) == proposal.expectedRevision else {
                proposal.status = "stale"
                throw AgentEditError.invalid("The note changed since Codex read it. Ask Codex to read it again and propose a fresh edit.")
            }
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
            flushAll()
            guard saveState != "error" else { throw AgentEditError.invalid("Draft could not save the Codex edit. The change may still be open in the editor; use Command-Z to undo or try saving again.") }
            proposal.status = "accepted"
            proposal.result = "Applied in Draft. Use Command-Z in the note to undo the edit."
            try AgentProposalStore.save(proposal, vaultURL: vault.dir)
            toast("Codex changes applied to “\(meta.title.isEmpty ? "Untitled" : meta.title)”")
        } catch {
            if proposal.status == "pending" { proposal.status = "failed" }
            proposal.result = error.localizedDescription
            try? AgentProposalStore.save(proposal, vaultURL: vault.dir)
            toast("Codex edit was not applied: \(error.localizedDescription)")
        }
        agentProposal = nil
    }
}

struct AgentProposalReview: View {
    @Environment(AppModel.self) var model
    @Environment(\.tokens) var tokens
    let proposal: AgentProposal

    var current: DraftTools.DocumentStructure? { try? DraftTools(vaultURL: model.vault.dir).structure(proposal.documentId) }
    var currentMarkdown: String? { try? DraftTools(vaultURL: model.vault.dir).markdown(proposal.documentId, maxCharacters: 100_000) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Review Codex changes").font(.title2.bold())
            Text(proposal.documentTitle.isEmpty ? "Untitled" : proposal.documentTitle).font(.headline)
            Text(proposal.instruction).foregroundStyle(tokens.secondary)
            Text("Nothing changes until you accept. You can undo the accepted edit in Draft.")
                .font(.footnote).foregroundStyle(tokens.secondary)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(proposal.edits.enumerated()), id: \.offset) { i, edit in
                        VStack(alignment: .leading, spacing: 5) {
                            Text("\(i + 1). \(edit.action.replacingOccurrences(of: "_", with: " ").capitalized)")
                                .font(.subheadline.bold())
                            Text(["replace_document", "document_style"].contains(edit.action) ? "Entire note" : "Block \(edit.blockId)")
                                .font(.caption).foregroundStyle(tokens.secondary)
                            if edit.action == "replace_document", let before = currentMarkdown {
                                Text("CURRENT NOTE").font(.caption.bold()).foregroundStyle(tokens.secondary)
                                Text(before).font(.body.monospaced()).textSelection(.enabled)
                                Text("PROPOSED NOTE").font(.caption.bold()).foregroundStyle(tokens.secondary)
                            } else if edit.expectedText == nil, let block = current?.blocks.first(where: { $0.id == edit.blockId }) {
                                Text("Current: \(block.text)").font(.caption).textSelection(.enabled)
                            }
                            if let before = edit.expectedText, !before.isEmpty { Text("Before: \(before)").font(.caption).textSelection(.enabled) }
                            if let text = edit.text { Text(text).font(.body.monospaced()).textSelection(.enabled) }
                            if let value = edit.value { Text("Format: \(value)").font(.caption) }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 10).fill(tokens.hover))
                    }
                }
            }
            .frame(maxHeight: 460)
            HStack {
                Button("Reject") { model.rejectAgentProposal() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Apply Changes") { model.acceptAgentProposal() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 640)
        .interactiveDismissDisabled()
    }
}
