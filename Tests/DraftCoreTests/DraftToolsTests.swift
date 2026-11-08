import XCTest
@testable import DraftCore

final class DraftToolsTests: XCTestCase {
    func testSearchAndReadNeverChangeTheVault() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let vault = Vault(dir: dir)
        try vault.prepare()
        var library = Library.empty()
        let space = library.space.id
        var meta = DocMeta(id: "d_test", title: "Garden")
        meta.spaceId = space
        library.docs[meta.id] = meta
        var doc = DocFile.empty(id: meta.id, title: meta.title)
        doc.content = Node("doc", content: [Node("paragraph", attrs: ["id": .string("b_compost")], content: [.text("Ines ordered compost on Saturday")])])
        try vault.saveLibrary(library)
        try vault.saveDoc(doc)
        let beforeLibrary = try Data(contentsOf: dir.appendingPathComponent("library.json"))
        let beforeDoc = try Data(contentsOf: dir.appendingPathComponent("docs/d_test.json"))

        let tools = try DraftTools(vaultURL: dir)
        XCTAssertEqual(try tools.documents().map(\.id), ["d_test"])
        XCTAssertEqual(try tools.search("compost").first?.blockId, "b_compost")
        XCTAssertTrue(try tools.markdown("d_test").contains("Ines ordered compost"))
        XCTAssertTrue(try tools.block(docId: "d_test", blockId: "b_compost").contains("Ines ordered compost"))
        XCTAssertEqual(try Data(contentsOf: dir.appendingPathComponent("library.json")), beforeLibrary)
        XCTAssertEqual(try Data(contentsOf: dir.appendingPathComponent("docs/d_test.json")), beforeDoc)
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.appendingPathComponent("index").path))
    }

    func testReadRejectsTrashedDocuments() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let vault = Vault(dir: dir)
        try vault.prepare()
        var library = Library.empty()
        var meta = DocMeta(id: "d_deleted", title: "Deleted")
        meta.spaceId = library.space.id
        meta.deletedAt = nowMs()
        library.docs[meta.id] = meta
        try vault.saveLibrary(library)
        try vault.saveDoc(DocFile.empty(id: meta.id))
        let tools = try DraftTools(vaultURL: dir)
        XCTAssertThrowsError(try tools.markdown(meta.id))
    }
}
