import XCTest
@testable import DraftCore

final class BlockIdTests: XCTestCase {
    func testMissingAndDuplicateIdsAreRepairedFirstWins() {
        let root = Node("doc", content: [
            Node("paragraph", attrs: ["id": "b_same"]),
            Node("paragraph", attrs: ["id": "b_same"]),
            Node("heading", attrs: ["level": 2]),
        ])
        let fixed = ensureBlockIds(root)
        let ids = fixed.content!.map { $0.id }
        XCTAssertEqual(ids[0], "b_same", "first occurrence keeps its id")
        XCTAssertNotEqual(ids[1], "b_same")
        XCTAssertNotNil(ids[2])
        XCTAssertEqual(Set(ids.compactMap { $0 }).count, 3)
        XCTAssertEqual(fixed.content![2].attrs?["level"]?.int, 2, "other attrs preserved")
    }

    func testReIdChangesEveryBlockButNotText() {
        let seed = Seed.firstRun().docs[0].content
        let copy = reId(seed)
        var a: [String] = [], b: [String] = []
        walk(seed) { if let i = $0.id { a.append(i) } }
        walk(copy) { if let i = $0.id { b.append(i) } }
        XCTAssertEqual(a.count, b.count)
        XCTAssertTrue(Set(a).isDisjoint(with: Set(b)))
        XCTAssertEqual(docPlainText(seed), docPlainText(copy))
    }
}

final class MigrationTests: XCTestCase {
    func testLibraryV0MigratesAndKeepsUnknownFields() throws {
        let v0 = """
        {"docs":[{"id":"d_1","title":"Old","updatedAt":5}],"futureThing":{"x":1}}
        """
        let (lib, migrated, from) = try Migrations.migrateLibrary(Data(v0.utf8))
        XCTAssertTrue(migrated); XCTAssertEqual(from, 0)
        XCTAssertEqual(lib.schemaVersion, 1)
        XCTAssertEqual(lib.docs["d_1"]?.title, "Old")
        XCTAssertEqual(lib.docs["d_1"]?.createdAt != nil, true)
        XCTAssertEqual(lib.extra["futureThing"], .object(["x": 1]))
        // Unknown fields survive a full encode/decode round trip.
        let again = try JSONDecoder().decode(Library.self, from: DraftJSON.encode(lib))
        XCTAssertEqual(again.extra["futureThing"], .object(["x": 1]))
    }

    func testDocV0GetsAppearanceAndBlockIds() throws {
        let v0 = """
        {"id":"d_1","title":"Hi","content":{"type":"doc","content":[{"type":"paragraph","content":[{"type":"text","text":"x"}]}]},"custom":true}
        """
        let (doc, migrated, _) = try Migrations.migrateDoc(Data(v0.utf8))
        XCTAssertTrue(migrated)
        XCTAssertEqual(doc.appearance.styleId, "paper")
        XCTAssertNotNil(doc.content.content?.first?.id)
        XCTAssertEqual(doc.extra["custom"], .bool(true))
    }

    func testNewerSchemaIsRejectedNotRewritten() {
        let v99 = #"{"schemaVersion":99,"space":{"id":"s","name":"x"}}"#
        XCTAssertThrowsError(try Migrations.migrateLibrary(Data(v99.utf8))) { XCTAssertTrue($0 is NewerSchemaError) }
    }

    func testUnknownNodeTypesAndAttrsRoundTrip() throws {
        var d = DocFile.empty(id: "d_x")
        d.content.content = [Node("mermaid", attrs: ["id": "b_1", "source": "graph TD"], content: nil), Node("paragraph", attrs: ["id": "b_2", "futureAttr": .array([1, 2])])]
        let back = try JSONDecoder().decode(DocFile.self, from: DraftJSON.encode(d))
        XCTAssertEqual(back.content, d.content)
    }
}

final class VaultTests: XCTestCase {
    var dir: URL!
    override func setUp() { dir = FileManager.default.temporaryDirectory.appendingPathComponent("draft-test-\(UUID().uuidString)") }
    override func tearDown() { try? FileManager.default.removeItem(at: dir) }

    func testFirstRunSaveReloadRoundTrip() throws {
        let v = Vault(dir: dir); try v.prepare()
        XCTAssertNil(try v.loadLibrary())
        let seed = Seed.firstRun()
        for d in seed.docs { try v.saveDoc(d) }
        try v.saveLibrary(seed.library)
        let v2 = Vault(dir: dir)
        let lib = try XCTUnwrap(v2.loadLibrary())
        XCTAssertEqual(lib.docs.count, 3)
        let d = try XCTUnwrap(v2.loadDoc(seed.docs[0].id))
        XCTAssertEqual(d, seed.docs[0])
        // No temp files left behind by atomic writes.
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: dir.appendingPathComponent("docs").path).filter { !$0.hasSuffix(".json") }
        XCTAssertEqual(leftovers, [])
    }

    func testMigrationWritesBackupFirst() throws {
        let v = Vault(dir: dir); try v.prepare()
        try Data(#"{"docs":[]}"#.utf8).write(to: dir.appendingPathComponent("library.json"))
        _ = try v.loadLibrary()
        let backups = try FileManager.default.contentsOfDirectory(atPath: dir.appendingPathComponent("backups").path)
        XCTAssertEqual(backups.count, 1)
        XCTAssertTrue(backups[0].hasSuffix("library.v0.json"))
        let rewritten = try Data(contentsOf: dir.appendingPathComponent("library.json"))
        XCTAssertTrue(String(decoding: rewritten, as: UTF8.self).contains("\"schemaVersion\" : 1"))
    }

    func testNewerLibraryMakesVaultReadOnly() throws {
        let v = Vault(dir: dir); try v.prepare()
        let original = #"{"schemaVersion":7,"space":{"id":"s","name":"x"}}"#
        try Data(original.utf8).write(to: dir.appendingPathComponent("library.json"))
        XCTAssertThrowsError(try v.loadLibrary())
        XCTAssertTrue(v.isReadOnly)
        XCTAssertThrowsError(try v.saveLibrary(Library.empty()))
        XCTAssertEqual(try String(contentsOf: dir.appendingPathComponent("library.json"), encoding: .utf8), original)
    }

    func testAssetsAreContentAddressed() throws {
        let v = Vault(dir: dir); try v.prepare()
        let a = try v.putAsset(Data([1, 2, 3]), ext: "png")
        let b = try v.putAsset(Data([1, 2, 3]), ext: "png")
        XCTAssertEqual(a, b)
        XCTAssertThrowsError(try v.assetURL("../../etc/passwd"))
    }
}

final class MarkdownTests: XCTestCase {
    func testCommonSubsetExports() {
        var d = DocFile.empty(id: "d_1", title: "Plán")
        d.content = Node("doc", content: [
            Node("heading", attrs: ["level": 2], content: [.text("Goals")]),
            Node("paragraph", content: [.text("a "), .text("bold", marks: [Mark("bold")]), .text(" and "), .text("link", marks: [Mark("link", attrs: ["href": "https://example.org"])]), .text(" "), .text("mark", marks: [Mark("highlight", attrs: ["color": "#fff3a3"])])]),
            Node("bulletList", content: [Node("listItem", content: [Node("paragraph", content: [.text("one")]), Node("bulletList", content: [Node("listItem", content: [Node("paragraph", content: [.text("nested")])])])])]),
            Node("taskList", content: [Node("taskItem", attrs: ["checked": true], content: [Node("paragraph", content: [.text("done")])])]),
            Node("blockquote", content: [Node("paragraph", content: [.text("quote")])]),
            Node("codeBlock", attrs: ["language": "swift"], content: [.text("let x = 1")]),
            Node("horizontalRule"),
            Node("image", attrs: ["assetId": "abcdef0123456789.png", "alt": "pic"]),
            Node("pageCard", attrs: ["docId": "d_2", "title": "Child"]),
        ])
        let r = Markdown.render(d, assetPath: { "assets/" + $0 }, pageLink: { _, t in t + ".md" })
        let md = r.markdown
        XCTAssertTrue(md.hasPrefix("# Plán\n"))
        XCTAssertTrue(md.contains("## Goals"))
        XCTAssertTrue(md.contains("a **bold** and [link](https://example.org) ==mark=="))
        XCTAssertTrue(md.contains("- one\n  - nested"))
        XCTAssertTrue(md.contains("- [x] done"))
        XCTAssertTrue(md.contains("> quote"))
        XCTAssertTrue(md.contains("```swift\nlet x = 1\n```"))
        XCTAssertTrue(md.contains("\n---\n"))
        XCTAssertTrue(md.contains("![pic](assets/abcdef0123456789.png)"))
        XCTAssertTrue(md.contains("[Child](Child.md)"))
        XCTAssertEqual(r.assets, ["abcdef0123456789.png"])
        XCTAssertEqual(r.pages, ["d_2"])
        XCTAssertFalse(r.lossy.isEmpty, "highlight color is reported as lossy")
    }

    func testSafeFileNameKeepsDiacritics() {
        XCTAssertEqual(Markdown.safeFileName("Dějiny: 1820/1848?"), "Dějiny- 1820-1848-")
        XCTAssertEqual(Markdown.safeFileName("   "), "Untitled")
    }

    func testExportBundleIncludesNestedPagesAndNativeJSON() throws {
        let seed = Seed.firstRun()
        let docs = Dictionary(uniqueKeysWithValues: seed.docs.map { ($0.id, $0) })
        let welcome = seed.docs[0]
        let b = try ExportBuilder.build(rootIds: [welcome.id], metas: seed.library.docs, folders: seed.library.folders, groupByFolder: false, load: { docs[$0] })
        let paths = b.files.map(\.path)
        XCTAssertEqual(paths, ["Welcome to Draft.md", "Keyboard shortcuts.md", "draft-export.json"])
        XCTAssertTrue(b.files[0].content.contains("[Keyboard shortcuts](Keyboard%20shortcuts.md)"))
        XCTAssertTrue(b.files[2].content.contains("\"format\" : \"draft-export\""))
    }
}

final class StyleTests: XCTestCase {
    func testOverridesLayerOnStyleWithoutTouchingContent() {
        var a = DocumentAppearance(styleId: "tidepool")
        a.overrides.pageColor = "#000000"
        let t = Styles.resolve(a)
        XCTAssertEqual(t.pageColor, "#000000")
        XCTAssertEqual(t.font, "serif")
        XCTAssertEqual(Styles.resolve(DocumentAppearance(styleId: "nope")).pageColor, Styles.builtIn[0].tokens.pageColor)
    }

    func testBuiltInStylesHaveReadableText() {
        for s in Styles.builtIn {
            XCTAssertGreaterThanOrEqual(ColorMath.contrast(s.tokens.textColor, s.tokens.pageColor), 7, s.name)
        }
    }
}
