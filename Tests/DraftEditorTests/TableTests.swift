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
