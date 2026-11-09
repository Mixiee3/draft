import XCTest
@testable import DraftCore

final class AgentTableTests: XCTestCase {
    let table = Tables.parse(["| Crop | Bed |", "| --- | --- |", "| Beans | 3 |", "| [Peas](https://example.com/peas) | 4 |"])!
    var rowIds: [String] { (table.content ?? []).compactMap(\.id) }
    func cell(_ t: Node, _ r: Int, _ c: Int) -> Node { (t.content![r].content ?? [])[c] }
    func edit(_ action: String, target: String, value: String? = nil, text: String? = nil, expected: String? = nil, position: String? = nil) -> AgentEdit {
        AgentEdit(action: action, blockId: table.id ?? "t", value: value, text: text, expectedText: expected, target: target, position: position)
    }

    func testCellsRowsAndColumns() throws {
        let beans = cell(table, 1, 0).id!
        var t = try Tables.applying(edit("table_set_cell", target: beans, text: "**Broad beans**", expected: "Beans"), to: table)
        XCTAssertEqual(Tables.text(t)[1][0], "Broad beans")
        XCTAssertEqual(cell(t, 1, 0).content?.first?.marks?.first?.type, "bold")
        XCTAssertEqual(cell(t, 1, 0).id, beans, "cell keeps its id")
        t = try Tables.applying(edit("table_insert_row", target: rowIds[1], text: "Kale | 5", position: "after"), to: t)
        XCTAssertEqual(Tables.text(t).map { $0[0] }, ["Crop", "Broad beans", "Kale", "Peas"])
        t = try Tables.applying(edit("table_move_row", target: rowIds[2], value: rowIds[0], position: "after"), to: t)
        XCTAssertEqual(Tables.text(t).map { $0[0] }, ["Crop", "Peas", "Broad beans", "Kale"])
        var lossy = Set<String>()
        XCTAssertTrue(Tables.markdown(t, &lossy).joined().contains("(https://example.com/peas)"), "links in other cells survive")
        t = try Tables.applying(edit("table_insert_column", target: cell(t, 0, 1).id!, text: "Notes | early | | late", position: "after"), to: t)
        XCTAssertEqual(Tables.text(t)[0], ["Crop", "Bed", "Notes"])
        XCTAssertEqual(Tables.text(t)[3][2], "late")
        t = try Tables.applying(edit("table_move_column", target: cell(t, 0, 2).id!, value: cell(t, 0, 0).id!, position: "before"), to: t)
        XCTAssertEqual(Tables.text(t)[0], ["Notes", "Crop", "Bed"])
        t = try Tables.applying(edit("table_delete_column", target: cell(t, 0, 0).id!), to: t)
        t = try Tables.applying(edit("table_delete_row", target: rowIds[2]), to: t)
        XCTAssertEqual(Tables.text(t).map { $0[0] }, ["Crop", "Broad beans", "Kale"], "the Peas row (by id) is gone")
    }

    func testStaleCellsMissingIdsAndMinimumSize() throws {
        let beans = cell(table, 1, 0).id!
        XCTAssertThrowsError(try Tables.applying(edit("table_set_cell", target: beans, text: "x", expected: "Carrots"), to: table))
        XCTAssertThrowsError(try Tables.applying(edit("table_delete_row", target: "b_missing"), to: table))
        XCTAssertThrowsError(try Tables.applying(edit("table_move_row", target: rowIds[1], value: rowIds[1]), to: table))
        let tiny = Tables.make(rows: 1, columns: 1)
        XCTAssertThrowsError(try Tables.applying(AgentEdit(action: "table_delete_row", blockId: tiny.id!, target: tiny.content![0].id), to: tiny))
        XCTAssertThrowsError(try Tables.applying(AgentEdit(action: "table_delete_column", blockId: tiny.id!, target: tiny.content![0].content![0].id), to: tiny))
        XCTAssertThrowsError(try AgentEdit(action: "table_set_cell", blockId: "t1").validate(), "needs a target")
        let rev = String(repeating: "e", count: 64)
        XCTAssertEqual(try AgentProposal(documentId: "d1", documentTitle: "t", instruction: "i", expectedRevision: rev, edits: [edit("table_delete_row", target: rowIds[1])]).requiredAccess, .destructive)
        XCTAssertEqual(try AgentProposal(documentId: "d1", documentTitle: "t", instruction: "i", expectedRevision: rev, edits: [edit("table_set_cell", target: beans, text: "x")]).requiredAccess, .propose)
    }
}
