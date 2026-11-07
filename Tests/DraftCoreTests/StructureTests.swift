import XCTest
@testable import DraftCore

final class StructureTests: XCTestCase {
    func testTableEditsAndMarkdownRoundTrip() {
        var t = Tables.make(rows: 2, columns: 2)
        t = Tables.settingCell(t, row: 0, column: 0, inline: [.text("Name")])
        t = Tables.settingCell(t, row: 0, column: 1, inline: [.text("Note")])
        t = Tables.settingCell(t, row: 1, column: 0, inline: [.text("Ana", marks: [Mark("bold")])])
        t = Tables.settingCell(t, row: 1, column: 1, inline: [.text("a | b")])
        t = Tables.insertingRow(t, at: 2)
        t = Tables.settingCell(t, row: 2, column: 0, inline: [.text("Bo")])
        XCTAssertEqual(Tables.text(t), [["Name", "Note"], ["Ana", "a | b"], ["Bo", ""]])
        XCTAssertEqual(Tables.columnCount(Tables.insertingColumn(t, at: 1)), 3)
        XCTAssertEqual(Tables.text(Tables.removingColumn(t, at: 0)), [["Note"], ["a | b"], [""]])
        XCTAssertEqual(Tables.text(Tables.movingRow(t, from: 2, to: 1))[1], ["Bo", ""])
        XCTAssertEqual(Tables.text(Tables.removingRow(Tables.removingRow(Tables.removingRow(t, at: 0), at: 0), at: 0)).count, 1, "a table keeps one row")
        var lossy = Set<String>()
        let md = Tables.markdown(t, &lossy)
        XCTAssertEqual(md[0], "| Name | Note |"); XCTAssertEqual(md[1], "| --- | --- |"); XCTAssertEqual(md[2], "| **Ana** | a \\| b |")
        let back = MarkdownImport.blocks(md.joined(separator: "\n"))
        XCTAssertEqual(back.first?.type, "table")
        XCTAssertEqual(Tables.text(back[0]), Tables.text(t))
        XCTAssertEqual(back[0].content?[1].content?[0].content?.first?.marks, [Mark("bold")], "marks survive")
    }

    var data: CollectionData {
        var c = CollectionData.starter(name: "Reading")
        let pages = CollectionField(id: "f_pages", name: "Pages", type: "number")
        let done = CollectionField(id: "f_done", name: "Done", type: "checkbox")
        c.fields += [pages, done]
        let status = c.fields[0].id, tags = c.fields[2].id
        c.items = [
            CollectionItem(id: "i_1", docId: "d_1", values: [status: "Doing", "f_pages": 120, tags: .array(["fiction"]), "f_done": false]),
            CollectionItem(id: "i_2", docId: "d_2", values: [status: "Done", "f_pages": 300, tags: .array(["essay", "fiction"]), "f_done": true]),
            CollectionItem(id: "i_3", docId: "d_3", values: [status: "To do", "f_pages": 80]),
            CollectionItem(id: "i_4", docId: "d_4", values: [:]),
        ]
        return c
    }
    let titles = ["d_1": "Dune", "d_2": "Essays, \"Vol 1\"", "d_3": "Atlas", "d_4": "Zen"]
    func title(_ id: String) -> String { titles[id] ?? "" }

    func testFilterSortGroupAndMove() {
        var c = data
        let status = c.fields[0].id
        var v = c.view!
        v.sort = [SortRule(field: "f_pages", ascending: false)]
        XCTAssertEqual(c.rows(v, title: title).map(\.id), ["i_2", "i_1", "i_3", "i_4"], "numbers sort numerically, empty last")
        v.sort = [SortRule(field: CollectionData.titleField)]
        XCTAssertEqual(c.rows(v, title: title).map(\.id), ["i_3", "i_1", "i_2", "i_4"])
        v.filters = [FilterRule(field: "f_pages", op: "gt", value: "100"), FilterRule(field: c.fields[2].id, op: "is", value: "fiction")]
        XCTAssertEqual(Set(c.rows(v, title: title).map(\.id)), ["i_1", "i_2"], "AND")
        v.filters = [FilterRule(field: status, op: "is", value: "To do"), FilterRule(field: "f_done", op: "checked")]
        v.match = "any"
        XCTAssertEqual(Set(c.rows(v, title: title).map(\.id)), ["i_2", "i_3"], "OR")
        let board = c.views.first { $0.type == "kanban" }!
        let g = c.groups(board, title: title)
        XCTAssertEqual(g.map(\.key), ["To do", "Doing", "Done", nil])
        XCTAssertEqual(g.map { $0.items.map(\.id) }, [["i_3"], ["i_1"], ["i_2"], ["i_4"]])
        let before = c.items
        c.move("i_4", to: "Doing", groupBy: status)
        XCTAssertEqual(zip(before, c.items).filter { $0 != $1 }.count, 1, "a Kanban drag changes exactly one record")
        XCTAssertEqual(c.items[3].values.count, 1, "and only one field of it")
        XCTAssertEqual(c.groups(board, title: title)[1].items.map(\.id), ["i_1", "i_4"])
    }

    func testCalculationsMatchHandComputedValues() {
        let c = data
        let rows = c.items
        XCTAssertEqual(c.calculate("count", field: "f_pages", rows: rows, title: title), "4")
        XCTAssertEqual(c.calculate("sum", field: "f_pages", rows: rows, title: title), "500")
        XCTAssertEqual(c.calculate("average", field: "f_pages", rows: rows, title: title), "166.67")
        XCTAssertEqual(c.calculate("min", field: "f_pages", rows: rows, title: title), "80")
        XCTAssertEqual(c.calculate("max", field: "f_pages", rows: rows, title: title), "300")
        XCTAssertEqual(c.calculate("empty", field: "f_pages", rows: rows, title: title), "1")
        XCTAssertEqual(c.calculate("filled", field: c.fields[0].id, rows: rows, title: title), "3")
        XCTAssertEqual(c.calculate("checked", field: "f_done", rows: rows, title: title), "25%")
    }

    func testCSVRoundTripAndFrontmatter() {
        let c = data
        let csv = c.csv(title: title)
        let parsed = CollectionData.parseCSV(csv)
        XCTAssertEqual(parsed[0], ["Name", "Status", "Date", "Tags", "Pages", "Done"])
        XCTAssertEqual(parsed[2][0], "Essays, \"Vol 1\"", "quotes and commas survive")
        for (i, it) in c.items.enumerated() {
            let (t, values) = c.values(fromCSV: parsed[0], parsed[i + 1])
            XCTAssertEqual(t, title(it.docId))
            for f in c.fields { XCTAssertEqual(c.display(CollectionItem(docId: "", values: values), f.id, title: title), c.display(it, f.id, title: title), "\(it.id).\(f.name)") }
        }
        let fm = c.frontmatter(c.items[1], title: title)
        XCTAssertTrue(fm.hasPrefix("---\ncollection: Reading\nStatus: Done\n"))
        XCTAssertTrue(fm.contains("Tags: [essay, fiction]") && fm.contains("Pages: 300") && fm.contains("Done: true"))
        XCTAssertEqual(CollectionData(node: c.node(id: "b_c")), c, "the block round-trips")
    }

    func testExportWritesItemPagesWithFrontmatter() throws {
        var host = DocFile.empty(id: "d_h", title: "Library")
        host.content = Node("doc", content: [data.node(id: "b_c")])
        var store = ["d_h": host]
        var metas = ["d_h": DocMeta(id: "d_h", title: "Library")]
        for (id, t) in titles { store[id] = DocFile.empty(id: id, title: t); metas[id] = DocMeta(id: id, title: t, parentDocId: "d_h") }
        let b = try ExportBuilder.build(rootIds: ["d_h"], metas: metas, folders: [], groupByFolder: false, load: { store[$0] })
        let lib = try XCTUnwrap(b.files.first { $0.path == "Library.md" }?.content)
        XCTAssertTrue(lib.contains("| Name | Status | Date | Tags | Pages | Done |"))
        XCTAssertTrue(lib.contains("[Dune](Dune.md)"))
        let dune = try XCTUnwrap(b.files.first { $0.path == "Dune.md" }?.content)
        XCTAssertTrue(dune.hasPrefix("---\ncollection: Reading\nStatus: Doing"), dune)
    }
}
