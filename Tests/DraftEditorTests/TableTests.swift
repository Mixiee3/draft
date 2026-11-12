import XCTest
import AppKit
import DraftCore
@testable import DraftEditor

final class TableTests: XCTestCase {
    var window: NSWindow!
    var view: DocumentEditorView!
    var c: EditorController { view.controller }

    override func setUp() {
        view = DocumentEditorView(frame: NSRect(x: 0, y: 0, width: 900, height: 700))
        window = NSWindow(contentRect: view.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = view
        c.host = LinkFakeHost()
        c.load(Node("doc", content: [Node("paragraph", attrs: ["id": "b_p"])]))
        window.makeFirstResponder(c.textView)
    }
    func pump() { let e = expectation(description: "q"); DispatchQueue.main.async { e.fulfill() }; wait(for: [e], timeout: 2) }
    var table: Node? { c.document().content?.first { $0.type == "table" } }

    func testColumnAndRowReorderKeepsCellsAndIsOneUndo() throws {
        func cell(_ id: String, _ inline: [Node]) -> Node { Node("tableCell", attrs: ["id": .string(id)], content: inline) }
        let link = Mark("link", attrs: ["href": "https://example.com"])
        let t = Node("table", attrs: ["id": "b_t"], content: [
            Node("tableRow", attrs: ["id": "r_0"], content: [cell("c_00", [.text("Name")]), cell("c_01", [.text("Site")]), cell("c_02", [.text("Score")])]),
            Node("tableRow", attrs: ["id": "r_1"], content: [cell("c_10", [.text("Ada", marks: [Mark("bold")])]), cell("c_11", [.text("home", marks: [link])]), cell("c_12", [.text("9")])]),
        ])
        c.load(Node("doc", content: [t, Node("paragraph", attrs: ["id": "b_after"])]))
        c.tableEditor.begin(tableId: "b_t", row: 1, column: 0)
        pump()
        let before = try XCTUnwrap(table)
        c.tableEditor.moveColumn(by: 1)
        pump()
        var after = try XCTUnwrap(table)
        XCTAssertEqual(Tables.text(after)[0], ["Site", "Name", "Score"])
        XCTAssertEqual(after.content?[1].content?.map { $0.id ?? "" }, ["c_11", "c_10", "c_12"], "cell ids move with their column")
        XCTAssertEqual(after.content?[1].content?[1].content?.first?.marks?.first?.type, "bold", "rich text survives")
        XCTAssertEqual(after.content?[1].content?[0].content?.first?.marks?.first?.attrs?["href"], "https://example.com", "links survive")
        XCTAssertEqual(c.tableEditor.current.column, 1, "focus follows the column")
        c.tableEditor.moveColumn(by: 5) // past the edge: nothing happens
        XCTAssertEqual(Tables.text(try XCTUnwrap(table))[0], ["Site", "Name", "Score"])
        pump()
        c.tableEditor.moveRow(by: -1)
        pump()
        after = try XCTUnwrap(table)
        XCTAssertEqual(after.content?.map { $0.id ?? "" }, ["r_1", "r_0"])
        c.tableEditor.end(); pump()
        c.undo.undo(); pump()
        XCTAssertEqual(Tables.text(try XCTUnwrap(table)), [["Site", "Name", "Score"], ["home", "Ada", "9"]], "one Undo per move")
        c.undo.undo(); pump()
        XCTAssertEqual(table, before, "and the next Undo restores the original exactly")
        var md = DocFile.empty(id: "d", title: "t")
        c.tableEditor.begin(tableId: "b_t", row: 0, column: 2); pump(); c.tableEditor.moveColumn(by: -2); c.tableEditor.end(); pump()
        md.content = c.document()
        let out = Markdown.render(md, assetPath: { _ in "" }, pageLink: { _, _ in nil }).markdown
        XCTAssertNotNil(out.range(of: #"\|\s*Score\s*\|\s*Name\s*\|\s*Site\s*\|"#, options: .regularExpression), "export keeps the new order: \(out)")
    }

    func testDeletingARowOrColumnNeverOverwritesItsNeighbour() throws {
        func cell(_ id: String, _ t: String) -> Node { Node("tableCell", attrs: ["id": .string(id)], content: [.text(t)]) }
        c.load(Node("doc", content: [Node("table", attrs: ["id": "b_t"], content: [
            Node("tableRow", attrs: ["id": "r_0"], content: [cell("a", "A"), cell("b", "B")]),
            Node("tableRow", attrs: ["id": "r_1"], content: [cell("c", "C"), cell("d", "D")]),
            Node("tableRow", attrs: ["id": "r_2"], content: [cell("e", "E"), cell("f", "F")])]), Node("paragraph", attrs: ["id": "b_after"])]))
        c.tableEditor.begin(tableId: "b_t", row: 1, column: 0); pump()
        c.tableEditor.removeRow(); pump()
        XCTAssertEqual(Tables.text(try XCTUnwrap(table)), [["A", "B"], ["E", "F"]])
        c.tableEditor.removeColumn(); pump()
        XCTAssertEqual(Tables.text(try XCTUnwrap(table)), [["B"], ["F"]])
        c.tableEditor.end()
    }

    func testInsertEditTabAddRowAndUndo() throws {
        EditorCommands.command("insert.table")!.run(c)
        let id = try XCTUnwrap(table?.id)
        XCTAssertEqual(Tables.text(table!).count, 3)
        pump()
        let ed = c.tableEditor
        ed.begin(tableId: id, row: 0, column: 0)
        XCTAssertEqual(ed.fields.count, 3); XCTAssertEqual(ed.fields[0].count, 3)
        let pr = c.paragraph(withId: id)!
        let cell = (c.storage.attribute(.attachment, at: pr.location, effectiveRange: nil) as! BlockAttachment).attachmentCell as! TableCell
        c.textView.display()
        let drawn = c.textView.convert(try XCTUnwrap(cell.drawnFrame), to: c.overlayHost)
        ed.reposition()
        XCTAssertEqual(ed.frame.minY, drawn.minY, accuracy: 0.5, "fields sit exactly over the drawn cells")
        ed.fields[0][0].stringValue = "**Name**"
        ed.move(by: 1) // Tab commits and moves
        XCTAssertEqual(ed.current.column, 1)
        XCTAssertEqual(Tables.text(table!)[0][0], "Name")
        XCTAssertEqual(table!.content?[0].content?[0].content?.first?.marks, [Mark("bold")])
        pump()
        ed.fields[0][1].stringValue = "Note"
        ed.move(by: -1)
        XCTAssertEqual(ed.current.column, 0)
        pump()
        ed.addRow()
        XCTAssertEqual(Tables.text(table!).count, 4)
        XCTAssertEqual(ed.current.row, 1, "focus moves to the new row")
        pump(); c.textView.undoManager?.undo()
        XCTAssertEqual(Tables.text(table!).count, 3, "one undo per edit: the row")
        pump(); c.textView.undoManager?.undo()
        XCTAssertEqual(Tables.text(table!)[0][1], "", "then the cell")
        ed.end()
        let md = Markdown.render(DocFile(id: "x", title: "T", content: c.document(), appearance: DocumentAppearance(styleId: "paper"), createdAt: 0, updatedAt: 0), assetPath: { $0 }, pageLink: { _, _ in nil }).markdown
        XCTAssertTrue(md.contains("| **Name** |  |  |"), md)
    }

    func testCollectionBlockRoundTrips() {
        EditorCommands.command("insert.collection")!.run(c)
        let n = c.document().content?.first { $0.type == "collection" }
        XCTAssertEqual(CollectionData(node: n!)?.views.map(\.type), ["table", "gallery", "kanban"])
        let (s, t) = Converter.attributed(from: c.document())
        XCTAssertEqual(Converter.document(from: s, trailing: t).content?.first { $0.type == "collection" }, n)
    }
}
