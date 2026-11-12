import XCTest
@testable import DraftCore

final class SearchIndexTests: XCTestCase {
    func p(_ id: String, _ t: String, _ marks: [Mark]? = nil) -> Node { Node("paragraph", attrs: ["id": .string(id)], content: [.text(t, marks: marks)]) }
    func doc(_ id: String, _ title: String, _ blocks: [Node], updated: Double = 1) -> DocFile {
        var d = DocFile.empty(id: id, title: title, styleId: "paper"); d.content = Node("doc", content: blocks); d.updatedAt = updated; return d
    }
    var notes: [DocFile] {[
        doc("d_trip", "Trip plan", [p("b_t1", "We fly to Lisbon on Monday #travel"), p("b_t2", "Budget: 900 euros"),
                                    p("b_t3", "Meet ", nil), Node("taskList", content: [Node("taskItem", attrs: ["id": "b_task", "due": "2026-11-20"], content: [p("b_tp", "Book the hotel")])]),
                                    p("b_t4", "See notes", [Mark("docLink", attrs: ["docId": "d_work"])])]),
        doc("d_work", "Work log", [p("b_w1", "Shipped the release candidate #work"), p("b_w2", "Next review on ", nil),
                                   Node("paragraph", attrs: ["id": "b_w3"], content: [.text("deadline "), .text("12 Dec", marks: [Mark("date", attrs: ["date": "2026-12-12"])])])]),
        doc("d_draft", "Draft ideas", [p("b_d1", "Lisbon tram photos, maybe a zine #travel #ideas"), p("b_d2", "error code 4711 in the build")]),
    ]}
    var metas: [DocMeta] { notes.map { d in var m = DocMeta(id: d.id, title: d.title); m.updatedAt = d.updatedAt; return m } }
    func index() -> SearchIndex {
        var i = SearchIndex(); let byId = Dictionary(uniqueKeysWithValues: notes.map { ($0.id, $0) })
        i.refresh(docs: Dictionary(uniqueKeysWithValues: metas.map { ($0.id, $0) }), rules: TagRules()) { byId[$0] }
        return i
    }
    func ids(_ q: String) throws -> [String] { try index().search(Search.parse(q), in: metas).map(\.meta.id) }

    func testQueryForms() throws {
        XCTAssertEqual(Set(try ids("lisbon")), ["d_trip", "d_draft"])
        XCTAssertEqual(try ids("\"release candidate\""), ["d_work"], "phrase")
        XCTAssertEqual(try ids("lisbon -tram"), ["d_trip"], "exclusion")
        XCTAssertEqual(try ids("/error code \\d{4}/"), ["d_draft"], "regex")
        XCTAssertEqual(Set(try ids("#travel")), ["d_trip", "d_draft"], "tag")
        XCTAssertEqual(try ids("#travel -#ideas"), ["d_trip"], "tag exclusion")
        XCTAssertEqual(try ids("tag:work"), ["d_work"])
        XCTAssertEqual(try ids("date:2026-12"), ["d_work"], "date chip by month")
        XCTAssertEqual(try ids("date:2026-11-20"), ["d_trip"], "task due date")
        XCTAssertEqual(try ids("after:2026-12-01"), ["d_work"])
        XCTAssertEqual(try ids("before:2026-12-01"), ["d_trip"])
        var q = try Search.parse("link:work"); q.links = ["d_work"]
        XCTAssertEqual(index().search(q, in: metas).map(\.meta.id), ["d_trip"], "notes that link to Work log")
        XCTAssertEqual(try ids("ideas in:title"), ["d_draft"], "title only")
        XCTAssertEqual(try ids("zine in:title"), [], "in:title ignores body text")
        let hit = try XCTUnwrap(index().search(Search.parse("lisbon"), in: metas).first { $0.meta.id == "d_trip" })
        XCTAssertEqual(hit.blocks.map(\.id), ["b_t1"], "block-level results")
        XCTAssertNotNil(hit.blocks.first?.match)
        XCTAssertThrowsError(try Search.parse("/([/"))
    }

    func testStaleEntriesUpdateAndIncrementalEqualsRebuild() {
        var i = index()
        var changed = notes; changed[1] = doc("d_work", "Work log", [p("b_w1", "Postponed the release")], updated: 2)
        var m = metas; m[1].updatedAt = 2
        let byId = Dictionary(uniqueKeysWithValues: changed.map { ($0.id, $0) })
        let n = i.refresh(docs: Dictionary(uniqueKeysWithValues: m.map { ($0.id, $0) }), rules: TagRules()) { byId[$0] }
        XCTAssertEqual(n, 1, "only the stale note is re-indexed")
        var fresh = SearchIndex()
        fresh.refresh(docs: Dictionary(uniqueKeysWithValues: m.map { ($0.id, $0) }), rules: TagRules()) { byId[$0] }
        XCTAssertEqual(i, fresh, "incremental updates equal a rebuild from scratch")
        i.refresh(docs: [:], rules: TagRules()) { _ in nil }
        XCTAssertTrue(i.entries.isEmpty, "deleted notes leave the index")
    }

    func testDamagedOrOlderIndexIsRebuiltAndNotesAreNeverWritten() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let v = Vault(dir: dir); try v.prepare()
        for d in notes { try v.saveDoc(d) }
        let before = try notes.map { try Data(contentsOf: v.docURL($0.id)) }
        try v.saveSearchIndex(index())
        XCTAssertEqual(v.loadSearchIndex(), index(), "round trip")
        try Vault.writeAtomic(Data("{broken".utf8), to: v.searchIndexURL)
        XCTAssertNil(v.loadSearchIndex())
        XCTAssertTrue(((try? FileManager.default.contentsOfDirectory(atPath: dir.appendingPathComponent("backups").path)) ?? []).contains { $0.hasSuffix("search.unreadable.json") }, "the damaged file is kept")
        var old = index(); old.version = 0
        try Vault.writeAtomic(try JSONEncoder().encode(old), to: v.searchIndexURL)
        XCTAssertNil(v.loadSearchIndex(), "an older format is rebuilt")
        XCTAssertEqual(try notes.map { try Data(contentsOf: v.docURL($0.id)) }, before, "the index never writes a note")
    }

    func testTenThousandBlockRebuildAndQueryAreWithinBudget() throws {
        let blocks = (0..<10_000).map { p("b_\($0)", "Paragraph \($0): ordinary words about lisbon trams and budgets #tag\($0 % 50)") }
        let big = doc("d_big", "Big", blocks)
        var m = DocMeta(id: "d_big", title: "Big"); m.updatedAt = 1
        var t0 = Date()
        var i = SearchIndex(); i.refresh(docs: ["d_big": m], rules: TagRules()) { _ in big }
        let rebuild = Date().timeIntervalSince(t0) * 1000
        t0 = Date()
        let hits = try i.search(Search.parse("\"Paragraph 7771:\""), in: [m])
        let tagHits = try i.search(Search.parse("#tag7 lisbon"), in: [m])
        let query = Date().timeIntervalSince(t0) * 1000
        print("search-index 10,000 blocks: rebuild \(Int(rebuild)) ms, two queries \(Int(query)) ms")
        XCTAssertEqual(hits.first?.blocks.first?.id, "b_7771")
        XCTAssertEqual(tagHits.count, 1)
        XCTAssertLessThan(rebuild, 3000); XCTAssertLessThan(query, 500)
    }
}
