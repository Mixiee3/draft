import XCTest
@testable import DraftCore

final class AgentProposalTests: XCTestCase {
    func testProposalStoreDoesNotChangeDocumentAndTracksStatus() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let vault = Vault(dir: dir)
        try vault.prepare()
        let doc = DocFile.empty(id: "d_test", title: "Test")
        try vault.saveDoc(doc)
        let before = try Data(contentsOf: dir.appendingPathComponent("docs/d_test.json"))
        let revision = try AgentProposalStore.revision(doc)
        var proposal = try AgentProposal(documentId: doc.id, documentTitle: doc.title, instruction: "Improve the title", expectedRevision: revision,
                                         edits: [AgentEdit(action: "heading", blockId: doc.content.content![0].id!, value: "title")])
        try AgentProposalStore.save(proposal, vaultURL: dir)
        XCTAssertEqual(AgentProposalStore.pending(vaultURL: dir).map(\.id), [proposal.id])
        XCTAssertEqual(try Data(contentsOf: dir.appendingPathComponent("docs/d_test.json")), before)
        proposal.status = "accepted"
        try AgentProposalStore.save(proposal, vaultURL: dir)
        XCTAssertTrue(AgentProposalStore.pending(vaultURL: dir).isEmpty)
        XCTAssertEqual(try AgentProposalStore.load(proposal.id, vaultURL: dir).status, "accepted")
    }

    func testInvalidEditCannotBeQueued() {
        XCTAssertThrowsError(try AgentProposal(documentId: "d", documentTitle: "", instruction: "Polish", expectedRevision: "x",
            edits: [AgentEdit(action: "replace_document", blockId: "d", text: "")]))
        XCTAssertThrowsError(try AgentProposal(documentId: "d", documentTitle: "", instruction: "Polish", expectedRevision: "x",
            edits: [AgentEdit(action: "block_color", blockId: "b", value: "red")]))
    }
}
