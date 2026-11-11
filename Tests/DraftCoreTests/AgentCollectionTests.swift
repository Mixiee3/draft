import XCTest
@testable import DraftCore

final class AgentCollectionTests: XCTestCase {
    var pages = 0
    func page() -> String { pages += 1; return "page\(pages)" }
    func e(_ action: String, target: String? = nil, value: String? = nil, text: String? = nil, expected: String? = nil, position: String? = nil) -> AgentEdit {
        AgentEdit(action: action, blockId: "col", value: value, text: text, expectedText: expected, target: target, position: position)
    }

    func testItemsFieldsAndViews() throws {
        var d = CollectionData.starter(name: "Reading")
        let status = d.fields[0], date = d.fields[1]
        d = try d.applying(e("collection_add_item", value: #"{"Status": "Doing", "Date": "2026-11-09"}"#, text: "Dune"), newPage: page)
        d = try d.applying(e("collection_add_item", value: #"{"Status": "To do"}"#, text: "Atlas"), newPage: page)
        XCTAssertEqual(d.items.map(\.docId), ["page1", "page2"])
        XCTAssertEqual(d.items[0].values[status.id], .string("Doing"))
        XCTAssertEqual(d.items[0].values[date.id], .string("2026-11-09"))
        let dune = d.items[0].id, atlas = d.items[1].id
        d = try d.applying(e("collection_add_field", value: "number", text: "Pages"), newPage: page)
        let pagesField = d.fields.last!
        d = try d.applying(e("collection_update_item", target: atlas, value: #"{"Pages": "120", "Status": "Done"}"#), newPage: page)
        XCTAssertEqual(d.items[1].values[pagesField.id], .number(120))
        d = try d.applying(e("collection_move_item", target: atlas, value: dune, position: "before"), newPage: page)
        XCTAssertEqual(d.items.map(\.id), [atlas, dune], "ids stay stable through moves")
        d = try d.applying(e("collection_rename_field", target: pagesField.id, text: "Page count"), newPage: page)
        let table = d.views.first { $0.type == "table" }!
        d = try d.applying(e("collection_set_view", target: table.id, value: #"{"sort": [{"field": "Page count", "ascending": false}], "filters": [{"field": "Status", "op": "isNot", "value": "Done"}], "visible": ["title", "Status"]}"#), newPage: page)
        let v = d.views.first { $0.id == table.id }!
        XCTAssertEqual(v.sort.first?.field, pagesField.id)
        XCTAssertEqual(v.visible, ["title", status.id])
        XCTAssertEqual(d.rows(v, title: { $0 }).map(\.id), [dune], "filter applied")
        d = try d.applying(e("collection_add_view", value: "kanban", text: "Board 2"), newPage: page)
        XCTAssertEqual(d.views.last?.groupBy, status.id)
        XCTAssertEqual(d.groups(d.views.last!, title: { $0 }).first { $0.key == "Done" }?.items.map(\.id), [atlas], "grouping")
        d = try d.applying(e("collection_delete_field", target: status.id), newPage: page)
        XCTAssertNil(d.items[0].values[status.id])
        XCTAssertFalse(d.views.contains { $0.filters.contains { $0.field == status.id } || $0.groupBy == status.id })
        d = try d.applying(e("collection_delete_item", target: dune), newPage: page)
        XCTAssertEqual(d.items.map(\.id), [atlas])
        let back = try JSONDecoder().decode(CollectionData.self, from: JSONEncoder().encode(d))
        XCTAssertEqual(back, d, "everything round-trips")
    }

    func testBadValuesAndTargetsAreRefused() throws {
        let d = CollectionData.starter()
        let board = d.views.first { $0.type == "kanban" }!
        for bad in [e("collection_add_item", value: #"{"Status": "Someday"}"#), e("collection_add_item", value: #"{"Date": "next week"}"#),
                    e("collection_add_item", value: #"{"Nope": "x"}"#), e("collection_add_item", value: "not json"),
                    e("collection_update_item", target: "i_missing", value: "{}"), e("collection_add_field", value: "color", text: "Hue"),
                    e("collection_add_field", value: "text", text: "status"), e("collection_set_view", target: board.id, value: #"{"groupBy": "Date"}"#),
                    e("collection_set_view", target: board.id, value: #"{"filters": [{"field": "Status", "op": "near"}]}"#)] {
            XCTAssertThrowsError(try d.applying(bad, newPage: page), bad.action)
        }
        let rev = String(repeating: "f", count: 64)
        XCTAssertThrowsError(try AgentProposal(instruction: "Mixed", parts: [
            AgentNoteChange(documentId: "d1", documentTitle: "a", expectedRevision: rev, edits: [e("collection_add_item", text: "x")]),
            AgentNoteChange(documentId: "d2", documentTitle: "b", expectedRevision: rev, edits: [AgentEdit(action: "bold", blockId: "b1", text: "x")])]))
        XCTAssertEqual(try AgentProposal(documentId: "d1", documentTitle: "t", instruction: "i", expectedRevision: rev, edits: [e("collection_delete_item", target: "i_1")]).requiredAccess, .destructive)
    }
}
