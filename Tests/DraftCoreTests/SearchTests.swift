import XCTest
@testable import DraftCore

final class SearchTests: XCTestCase {
    func meta(_ id: String, _ title: String, _ body: String, updated: Double = 0) -> DocMeta {
        DocMeta(id: id, title: title, updatedAt: updated, searchText: title + "\n" + body)
    }

    func testAllTermsMustMatchCountsAndRanking() {
        let docs = [
            meta("a", "Garden plan", "Plant tomatoes. Water the tomatoes daily.", updated: 1),
            meta("b", "Notes", "Tomatoes and basil and more TOMATOES and tomatoes", updated: 2),
            meta("c", "Recipes", "Basil only"),
        ]
        let h = Search.hits("tomatoes", in: docs)
        XCTAssertEqual(h.map(\.meta.id), ["b", "a"], "more matches rank first when neither title matches")
        XCTAssertEqual(h.first?.count, 3, "case-insensitive count in the body")
        XCTAssertEqual(Search.hits("tomatoes basil", in: docs).map(\.meta.id), ["b"], "all terms must match")
        XCTAssertEqual(Search.hits("garden", in: docs).first?.titleMatch, true)
        XCTAssertEqual(Search.hits("dejiny", in: [meta("d", "Dějiny", "")]).count, 1, "diacritic-insensitive")
    }

    func testSnippetHighlightsMatch() {
        let body = String(repeating: "lorem ", count: 30) + "needle here " + String(repeating: "ipsum ", count: 30)
        let h = Search.hits("NEEDLE", in: [meta("x", "T", body)]).first!
        XCTAssertTrue(h.snippet.hasPrefix("…") && h.snippet.hasSuffix("…"))
        XCTAssertEqual(h.snippet[h.snippetMatch!], "needle")
    }
}
