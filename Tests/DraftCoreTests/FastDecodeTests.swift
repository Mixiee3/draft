import XCTest
@testable import DraftCore

final class FastDecodeTests: XCTestCase {
    func testFastPathMatchesCodable() throws {
        var doc = DocFile.empty(id: "d1", title: "Mixed")
        doc.content = Node("doc", content: [
            Node("heading", attrs: ["id": .string("h1"), "level": .number(2)], content: [.text("Title")]),
            Node("paragraph", attrs: ["id": .string("p1"), "align": .string("center"), "flag": .bool(true), "ratio": .number(0.5), "none": .null],
                 content: [.text("bold", marks: [Mark("bold")]), .text(" link", marks: [Mark("link", attrs: ["href": .string("draft://x")])])]),
            Node("taskList", attrs: ["id": .string("t")], content: [Node("taskItem", attrs: ["id": .string("ti"), "checked": .bool(false)], content: [Node("paragraph", attrs: ["id": .string("p2")])])]),
        ])
        doc.extra = ["futureField": .array([.number(1), .string("a")])]
        let data = try DraftJSON.encode(doc)
        let fast = try XCTUnwrap(Migrations.fastDecode(data))
        let slow = try JSONDecoder().decode(DocFile.self, from: data)
        XCTAssertEqual(fast, slow)
        XCTAssertEqual(fast.extra["futureField"], .array([.number(1), .string("a")]))
    }

    func testOtherSchemasTakeTheMigrationPath() throws {
        let old = #"{"schemaVersion":0,"id":"x","title":"t","content":{"type":"doc"},"appearance":{"styleId":"paper","overrides":{}},"createdAt":0,"updatedAt":0}"#
        XCTAssertNil(Migrations.fastDecode(Data(old.utf8)))
    }
}
