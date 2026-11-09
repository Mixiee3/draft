import XCTest
import AppKit
import DraftCore
@testable import DraftEditor

final class AgentTableEditTests: XCTestCase {
    var window: NSWindow!
    var view: DocumentEditorView!
    var c: EditorController { view.controller }

    override func setUp() {
        view = DocumentEditorView(frame: NSRect(x: 0, y: 0, width: 900, height: 700))
        window = NSWindow(contentRect: view.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = view
        c.host = LinkFakeHost()
        let table = Tables.parse(["| Crop | Bed |", "| --- | --- |", "| Beans | 3 |"])!
        c.load(ensureBlockIds(Node("doc", content: [Node("paragraph", content: [.text("Plan")]), table, Node("image", attrs: ["assetId": "a1", "alt": "x"])])))
        window.makeFirstResponder(c.textView)
        c.undo.groupsByEvent = false
    }

    var table: Node { c.document().content!.first { $0.type == "table" }! }

    func testTableProposalIsOneUndoAndAllOrNothing() throws {
        let original = c.document()
        let t = table, beans = t.content![1].content![0].id!
        try c.applyAgentEdits([
            AgentEdit(action: "table_set_cell", blockId: t.id!, text: "*Beans*", expectedText: "Beans", target: beans),
            AgentEdit(action: "table_insert_row", blockId: t.id!, text: "Kale | 5", target: t.content![1].id!, position: "after"),
            AgentEdit(action: "bold", blockId: c.document().content![0].id!, text: "Plan"),
        ])
        XCTAssertEqual(Tables.text(table).map { $0[0] }, ["Crop", "Beans", "Kale"])
        XCTAssertEqual(table.id, t.id, "the table keeps its id")
        XCTAssertTrue(c.document().content!.contains { $0.type == "image" })
        if c.undo.groupingLevel > 0 { c.undo.endUndoGrouping() }
        c.undo.undo()
        XCTAssertEqual(c.document(), original, "one Undo")

        // The second edit names a row that doesn't exist: nothing, including the first edit, is applied.
        XCTAssertThrowsError(try c.applyAgentEdits([
            AgentEdit(action: "table_set_cell", blockId: t.id!, text: "Changed", target: beans),
            AgentEdit(action: "table_delete_row", blockId: t.id!, target: "b_gone"),
        ]))
        XCTAssertEqual(c.document(), original)
        XCTAssertThrowsError(try c.applyAgentEdits([AgentEdit(action: "table_set_cell", blockId: c.document().content![0].id!, text: "x", target: beans)]), "not a table")
    }
}
