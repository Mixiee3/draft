import XCTest
@testable import DraftCore

final class SchemaTwoTests: XCTestCase {
    var dir: URL!
    override func setUp() { dir = FileManager.default.temporaryDirectory.appendingPathComponent("draft-s2-\(UUID().uuidString)") }
    override func tearDown() { try? FileManager.default.removeItem(at: dir) }

    /// A schema 1 vault as v0.4 wrote it.
    func writeV1Vault() throws {
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("docs"), withIntermediateDirectories: true)
        var doc = DocFile.empty(id: "d_a", title: "Alpha", styleId: "citrus")
        doc.content = Node("doc", content: [Node("paragraph", attrs: ["id": "b_1"], content: [.text("See "), .text("Beta", marks: [Mark("docLink", attrs: ["docId": "d_b"])])])])
        try DraftJSON.encode(doc).write(to: dir.appendingPathComponent("docs/d_a.json"))
        try DraftJSON.encode(DocFile.empty(id: "d_b", title: "Beta")).write(to: dir.appendingPathComponent("docs/d_b.json"))
        let lib: [String: Any] = [
            "schemaVersion": 1, "space": ["id": "s_home", "name": "Home"],
            "folders": [["id": "f_1", "name": "Work", "order": 0, "createdAt": 0]],
            "docs": ["d_a": ["id": "d_a", "title": "Alpha", "folderId": "f_1", "styleId": "citrus"], "d_b": ["id": "d_b", "title": "Beta", "parentDocId": "d_a", "styleId": "paper", "deletedAt": 5]],
            "settings": [:], "tabs": [["id": "t_1", "view": ["kind": "all"]]], "activeTabId": "t_1", "expandedFolders": [], "futureKey": "kept",
        ]
        try JSONSerialization.data(withJSONObject: lib).write(to: dir.appendingPathComponent("library.json"))
    }

    func checksum() throws -> [String: Data] {
        var out: [String: Data] = [:]
        for f in try FileManager.default.subpathsOfDirectory(atPath: dir.path) where f.hasSuffix(".json") { out[f] = try Data(contentsOf: dir.appendingPathComponent(f)) }
        return out
    }

    func testDryRunReportsNoDifferencesAndWritesNothing() throws {
        try writeV1Vault()
        let before = try checksum()
        let r = try Migrations.dryRun(vault: dir)
        XCTAssertEqual(r.from, 1); XCTAssertEqual(r.to, 2); XCTAssertEqual(r.documents, 2)
        XCTAssertTrue(r.ok, r.differences.joined(separator: "; "))
        XCTAssertEqual(try checksum(), before, "a dry run never writes")
    }

    func testRealMigrationBacksUpAndKeepsEverything() throws {
        try writeV1Vault()
        let v = Vault(dir: dir)
        let lib = try XCTUnwrap(v.loadLibrary())
        XCTAssertEqual(lib.schemaVersion, 2)
        XCTAssertEqual(lib.spaces.map(\.id), ["s_home"])
        XCTAssertEqual(lib.docs["d_a"]?.spaceId, "s_home"); XCTAssertEqual(lib.folders.first?.spaceId, "s_home")
        XCTAssertEqual(lib.docs["d_b"]?.deletedAt, 5); XCTAssertEqual(lib.docs["d_b"]?.parentDocId, "d_a")
        XCTAssertEqual(lib.extra["futureKey"], "kept", "unknown fields survive")
        let backups = try FileManager.default.contentsOfDirectory(atPath: dir.appendingPathComponent("backups").path)
        XCTAssertTrue(backups.contains { $0.hasSuffix("library.v1.json") }, "the original is backed up first")
        XCTAssertEqual(try Migrations.migrateLibrary(Data(contentsOf: dir.appendingPathComponent("library.json"))).from, 2)
    }

    func testSpacesScopeTheLibrary() {
        var lib = Library.empty()
        let home = lib.space
        let work = Space(id: "s_work", name: "Work")
        lib.spaces.append(work)
        lib.docs["d_1"] = DocMeta(id: "d_1", title: "Home doc"); lib.docs["d_1"]!.spaceId = home.id
        lib.docs["d_2"] = DocMeta(id: "d_2", title: "Work doc"); lib.docs["d_2"]!.spaceId = work.id
        lib.docs["d_3"] = DocMeta(id: "d_3", title: "Old doc") // no spaceId: first Space
        lib.docs["d_t"] = DocMeta(id: "d_t", title: "A template"); lib.docs["d_t"]!.template = "Meetings"
        XCTAssertEqual(Set(lib.liveDocs.map(\.id)), ["d_1", "d_3"])
        lib.space = work
        XCTAssertEqual(lib.liveDocs.map(\.id), ["d_2"])
        XCTAssertEqual(lib.templates.map(\.id), ["d_t"], "templates are shared and never listed as documents")
    }
}
