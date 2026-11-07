import XCTest
@testable import DraftCore

final class ImportTests: XCTestCase {
    func testMarkdownFolder() {
        let files: [(path: String, text: String)] = [
            ("Index.md", "# Home\n\nSee [the plan](Work/Plan.md) and [web](https://x.org).\n\n![logo](img/logo.png)"),
            ("Work/Plan.md", "---\ntags: [a]\n---\nSteps:\n- [ ] ship\n\n[back](../Index.md)"),
        ]
        var stored: [String] = []
        let r = Importer.markdown(files: files, spaceId: "s_1") { path, ext in stored.append(path); return "0123456789abcdef.\(ext)" }
        XCTAssertEqual(r.docs.map(\.title), ["Home", "Plan"], "title from # heading, else the file name")
        XCTAssertEqual(r.folders.map(\.name), ["Work"]); XCTAssertEqual(r.metas[1].folderId, r.folders[0].id)
        XCTAssertEqual(r.metas.map(\.spaceId), ["s_1", "s_1"])
        var links: [String] = []
        for d in r.docs { walk(d.content) { n in n.marks?.forEach { if $0.type == "docLink" { links.append($0.attrs!["docId"]!.string!) } } } }
        XCTAssertEqual(Set(links), Set(r.docs.map(\.id)), "links between files become document links (both ways)")
        XCTAssertTrue(r.docs[0].content.content!.contains { $0.type == "image" }); XCTAssertEqual(stored, ["img/logo.png"])
        XCTAssertFalse(docPlainText(r.docs[1].content).contains("tags:"), "frontmatter is not text")
        XCTAssertEqual(tasksOf(r.docs[1].content).first?.text, "ship")
    }

    func testOPML() throws {
        let x = #"<?xml version="1.0"?><opml version="2.0"><head><title>Ideas</title></head><body><outline text="One"><outline text="One a"/></outline><outline text="**Two**"/></body></opml>"#
        let r = try Importer.opml(Data(x.utf8), fallbackTitle: "f", spaceId: nil)
        XCTAssertEqual(r.docs[0].title, "Ideas")
        let list = r.docs[0].content.content![0]
        XCTAssertEqual(list.type, "bulletList"); XCTAssertEqual(list.content?.count, 2)
        XCTAssertEqual(list.content?[0].content?[1].type, "bulletList", "nesting kept")
        XCTAssertEqual(list.content?[1].content?[0].content?.first?.marks, [Mark("bold")])
        XCTAssertThrowsError(try Importer.opml(Data("<opml><body>".utf8), fallbackTitle: "f", spaceId: nil))
    }

    func testDraftExportRoundTrip() throws {
        let folder = Folder(id: "f_w", name: "Work")
        let style = UserStyle(id: "u_s", name: "Studio", base: "citrus", tokens: Styles.style("citrus").tokens)
        var a = DocFile.empty(id: "d_a", title: "Alpha", styleId: "u_s")
        var col = CollectionData.starter(name: "Items"); col.items = [CollectionItem(id: "i_1", docId: "d_b")]
        a.content = Node("doc", content: [Node("paragraph", attrs: ["id": "b_1"], content: [.text("Beta", marks: [Mark("docLink", attrs: ["docId": "d_b"])])]), col.node(id: "b_c")])
        let b = DocFile.empty(id: "d_b", title: "Beta")
        var ma = DocMeta(id: "d_a", title: "Alpha", folderId: "f_w"); ma.styleId = "u_s"
        let metas = ["d_a": ma, "d_b": DocMeta(id: "d_b", title: "Beta", parentDocId: "d_a")]
        let bundle = try ExportBuilder.build(rootIds: ["d_a"], metas: metas, folders: [folder], groupByFolder: true, styles: [style], load: { ["d_a": a, "d_b": b][$0] })
        let json = Data(try XCTUnwrap(bundle.files.first { $0.path == "draft-export.json" }).content.utf8)
        // Into an empty vault: everything comes back as it was.
        let r = try Importer.draftJSON(json, existingDocs: [], existingFolders: [], existingStyles: [], spaceId: "s_new")
        XCTAssertEqual(Set(r.docs.map(\.id)), ["d_a", "d_b"]); XCTAssertEqual(r.folders.map(\.name), ["Work"]); XCTAssertEqual(r.styles.map(\.name), ["Studio"])
        XCTAssertEqual(r.docs.first { $0.id == "d_a" }?.content, a.content)
        XCTAssertEqual(r.metas.first { $0.id == "d_a" }?.folderId, "f_w"); XCTAssertEqual(r.metas.first { $0.id == "d_b" }?.parentDocId, "d_a")
        // Into a vault that already has these ids: new ids, every reference follows.
        let r2 = try Importer.draftJSON(json, existingDocs: ["d_a", "d_b"], existingFolders: ["f_w"], existingStyles: ["u_s"], spaceId: nil)
        let newA = try XCTUnwrap(r2.docs.first { $0.title == "Alpha" }), newB = try XCTUnwrap(r2.docs.first { $0.title == "Beta" })
        XCTAssertNotEqual(newA.id, "d_a"); XCTAssertNotEqual(newB.id, "d_b")
        var link = ""; walk(newA.content) { if let m = $0.marks?.first(where: { $0.type == "docLink" }) { link = m.attrs!["docId"]!.string! } }
        XCTAssertEqual(link, newB.id)
        XCTAssertEqual(CollectionData(node: newA.content.content![1])?.items.first?.docId, newB.id)
        XCTAssertEqual(r2.metas.first { $0.id == newB.id }?.parentDocId, newA.id)
        XCTAssertNotEqual(r2.metas.first { $0.id == newA.id }?.folderId, "f_w"); XCTAssertEqual(r2.folders.count, 1)
        XCTAssertTrue(r2.styles.isEmpty, "a style that already exists is reused")
        XCTAssertThrowsError(try Importer.draftJSON(Data("{}".utf8), existingDocs: [], existingFolders: [], existingStyles: [], spaceId: nil))
    }
}
