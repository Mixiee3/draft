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

    func testDocumentStyleMustBeStandaloneAndSeparatorsHaveKnownValues() throws {
        let revision = String(repeating: "a", count: 64)
        let style = AgentEdit(action: "document_style", blockId: "d_test", value: "tidepool")
        XCTAssertNoThrow(try AgentProposal(documentId: "d_test", documentTitle: "Test", instruction: "Use a calmer style", expectedRevision: revision, edits: [style]))
        XCTAssertThrowsError(try AgentProposal(documentId: "d_test", documentTitle: "Test", instruction: "Style and edit", expectedRevision: revision,
            edits: [style, AgentEdit(action: "heading", blockId: "b_test", value: "title")]))
        XCTAssertNoThrow(try AgentEdit(action: "insert_separator", blockId: "b_test", value: "wave").validate())
        XCTAssertThrowsError(try AgentEdit(action: "insert_separator", blockId: "b_test", value: "sparkle").validate())
    }
}

final class AgentLibraryProposalTests: XCTestCase {
    let rev = String(repeating: "a", count: 64)

    func testCreateRenameMoveAreStandaloneAndValidated() throws {
        XCTAssertNoThrow(try AgentProposal(documentId: "new", documentTitle: "Trip", instruction: "New note", expectedRevision: rev,
                                           edits: [AgentEdit(action: "create_document", blockId: "new", value: "unsorted", text: "# Trip", expectedText: "Trip")]))
        // create must use the "new" id, and nothing else may.
        XCTAssertThrowsError(try AgentProposal(documentId: "d1", documentTitle: "x", instruction: "i", expectedRevision: rev,
                                               edits: [AgentEdit(action: "create_document", blockId: "d1", expectedText: "T")]))
        XCTAssertThrowsError(try AgentProposal(documentId: "new", documentTitle: "x", instruction: "i", expectedRevision: rev,
                                               edits: [AgentEdit(action: "append", blockId: "new", text: "x")]))
        // standalone: no mixing with block edits
        XCTAssertThrowsError(try AgentProposal(documentId: "d1", documentTitle: "x", instruction: "i", expectedRevision: rev,
                                               edits: [AgentEdit(action: "rename_document", blockId: "d1", expectedText: "New"), AgentEdit(action: "bold", blockId: "b1", text: "x")]))
        XCTAssertThrowsError(try AgentEdit(action: "rename_document", blockId: "d1", expectedText: "two\nlines").validate())
        XCTAssertThrowsError(try AgentEdit(action: "move_document", blockId: "d1").validate(), "needs a folder or a Space")
        XCTAssertThrowsError(try AgentEdit(action: "link", blockId: "b1", value: "javascript:alert(1)", text: "x").validate())
        XCTAssertThrowsError(try AgentEdit(action: "move_block", blockId: "b1", target: "b1").validate())
        XCTAssertNoThrow(try AgentEdit(action: "insert_blocks", blockId: "b1", text: "- a", position: "before").validate())
    }

    func testLibraryRevisionFollowsSpacesAndFolders() {
        var lib = Library.empty()
        let before = AgentProposalStore.libraryRevision(lib)
        lib.docs["x"] = DocMeta(id: "x") // documents don't matter for where a note can go
        XCTAssertEqual(AgentProposalStore.libraryRevision(lib), before)
        lib.folders.append(Folder(name: "Trips", order: 0, spaceId: lib.space.id))
        XCTAssertNotEqual(AgentProposalStore.libraryRevision(lib), before)
    }

    func testOlderProposalFilesStillDecode() throws {
        let json = #"{"id":"request_x","documentId":"d1","documentTitle":"t","instruction":"i","expectedRevision":"\#(rev)","edits":[{"action":"bold","blockId":"b1","text":"x"}],"createdAt":0,"status":"pending"}"#
        let p = try JSONDecoder().decode(AgentProposal.self, from: Data(json.utf8))
        XCTAssertNil(p.edits[0].target)
        XCTAssertFalse(p.changesLibrary)
    }
}

final class AgentPermissionTests: XCTestCase {
    func testDestructiveEditsNeedTheirOwnPermission() throws {
        let rev = String(repeating: "b", count: 64)
        let bold = try AgentProposal(documentId: "d1", documentTitle: "t", instruction: "i", expectedRevision: rev, edits: [AgentEdit(action: "bold", blockId: "b1", text: "x")])
        let delete = try AgentProposal(documentId: "d1", documentTitle: "t", instruction: "i", expectedRevision: rev, edits: [AgentEdit(action: "bold", blockId: "b1", text: "x"), AgentEdit(action: "delete_block", blockId: "b2")])
        let move = try AgentProposal(documentId: "d1", documentTitle: "t", instruction: "i", expectedRevision: rev, edits: [AgentEdit(action: "move_document", blockId: "d1", value: "unsorted")])
        XCTAssertEqual(bold.requiredAccess, .propose)
        XCTAssertEqual(delete.requiredAccess, .destructive)
        XCTAssertEqual(move.requiredAccess, .destructive)
        let normal = AgentPermission()
        XCTAssertTrue(normal.allows(.read) && normal.allows(.propose) && !normal.allows(.destructive))
        XCTAssertFalse(AgentPermission(read: true, propose: false, destructive: true).allows(.destructive), "destructive needs propose too")
    }

    func testSettingsKeepPermissionsAndDefaultUnknownClients() throws {
        var s = Settings(); s.agentPermissions["codex"] = AgentPermission(read: true, propose: true, destructive: true)
        let back = try JSONDecoder().decode(Settings.self, from: JSONEncoder().encode(s))
        XCTAssertTrue(back.agentPermission("codex").destructive)
        XCTAssertEqual(back.agentPermission("someone-new"), AgentPermission())
        XCTAssertEqual(try JSONDecoder().decode(Settings.self, from: Data("{}".utf8)).agentPermissions, [:])
    }

    func testActivityLogKeepsNoText() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        AgentActivity.record(.init(time: 1, client: "codex", tool: "draft_read_document", document: "d1"), vault: dir)
        AgentActivity.record(.init(time: 2, client: "claude-code", tool: "draft_search", document: nil), vault: dir)
        XCTAssertEqual(AgentActivity.entries(dir).map(\.tool), ["draft_read_document", "draft_search"])
        AgentActivity.clear(dir)
        XCTAssertTrue(AgentActivity.entries(dir).isEmpty)
    }
}
