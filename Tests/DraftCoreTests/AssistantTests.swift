import XCTest
@testable import DraftCore

final class AssistantTests: XCTestCase {
    func entry(_ blocks: [(String, String)]) -> DocIndexEntry {
        var e = DocIndexEntry(updatedAt: 0)
        e.blocks = blocks.map { IndexedBlock(id: $0.0, text: $0.1) }
        return e
    }

    func testRetrievalFindsTheRelevantBlockAcrossDocuments() {
        let entries = [
            "d_garden": entry([("b1", "Ines orders forty bags of compost from Hollow Farm"), ("b2", "The plant sale is on Saturday 18 April at the north gate")]),
            "d_bike": entry([("b3", "Pack the patch kit and two spare tubes"), ("b4", "The hostel has no lockers")]),
            "d_recipes": entry([("b5", "Compost the onion peels"), ("b6", "Bake at 180 degrees")]),
        ]
        let titles = ["d_garden": "Garden co-op", "d_bike": "Bike trip", "d_recipes": "Recipes"]
        let hits = Retrieval.rank("When is the plant sale?", entries: entries, titles: titles)
        XCTAssertEqual(hits.first?.blockId, "b2")
        XCTAssertEqual(Retrieval.rank("spare tubes for the bike", entries: entries, titles: titles).first?.blockId, "b3")
        XCTAssertTrue(Retrieval.rank("the and of", entries: entries, titles: titles).isEmpty, "stop words alone match nothing")
        XCTAssertTrue(Retrieval.rank("quantum chromodynamics", entries: entries, titles: titles).isEmpty)
    }

    func testRetrievalLimitsBlocksPerDocument() {
        let e = entry((0..<10).map { ("b\($0)", "compost note number \($0)") })
        let hits = Retrieval.rank("compost", entries: ["d1": e, "d2": entry([("x", "compost elsewhere")])], titles: [:], limit: 8, perDoc: 3)
        XCTAssertEqual(hits.filter { $0.docId == "d1" }.count, 3)
        XCTAssertTrue(hits.contains { $0.docId == "d2" })
    }

    func testCitationsParseValidNumbersInOrder() {
        XCTAssertEqual(Citations.cited(in: "The sale is on 18 April [3]. Compost comes from Hollow Farm [1, 3].", sourceCount: 3), [3, 1])
        XCTAssertEqual(Citations.cited(in: "See [2][1] and [9] and [0].", sourceCount: 3), [2, 1])
        XCTAssertEqual(Citations.cited(in: "No sources here.", sourceCount: 3), [])
        XCTAssertEqual(Citations.cited(in: "[1]", sourceCount: 0), [])
    }

    func testSpacePromptNumbersSourcesAndRespectsBudget() {
        let many = (1...50).map { AssistantSource(n: $0, docId: "d\($0)", blockId: "b\($0)", title: "Doc \($0)", text: String(repeating: "word ", count: 80)) }
        let p = AssistantPrompt.prepare(AssistantRequest(action: .ask, scope: .space, question: "What?", retrieved: many), budgetTokens: 1000)
        XCTAssertLessThan(p.sources.count, 50)
        XCTAssertEqual(p.sources.map(\.n), Array(1...p.sources.count))
        let user = p.turns.last!.text
        XCTAssertTrue(user.contains("[1] Doc 1:"))
        XCTAssertLessThanOrEqual(user.count, Int(1000 * AssistantPrompt.charsPerToken) + 200)
        XCTAssertEqual(p.turns.first?.role, "system")
    }

    func testLongDocumentIsTruncatedAndReported() {
        let text = (0..<2000).map { "Line \($0) of the document." }.joined(separator: "\n")
        let p = AssistantPrompt.prepare(AssistantRequest(action: .summarize, scope: .document, text: text, docId: "d1", docTitle: "Long"), budgetTokens: 1000)
        XCTAssertLessThan(p.includedFraction, 1)
        XCTAssertGreaterThan(p.includedFraction, 0)
        XCTAssertTrue(p.turns.last!.text.contains("only the first part fits"))
        XCTAssertFalse(p.turns.last!.text.contains("Line 1999"))
        XCTAssertEqual(p.sources.first?.docId, "d1")
    }

    func testEmptySpaceSaysSoInsteadOfInventingSources() {
        let p = AssistantPrompt.prepare(AssistantRequest(action: .ask, scope: .space, question: "Anything about taxes?"))
        XCTAssertTrue(p.sources.isEmpty)
        XCTAssertTrue(p.turns.last!.text.contains("No matching notes"))
    }

    /// The prompt carries only the chosen context: nothing from other documents leaks in.
    func testPromptContainsOnlyChosenContext() {
        let r = AssistantRequest(action: .rewrite, scope: .selection, text: "Only this sentence.", docId: "d1", docTitle: "Mine",
                                 retrieved: [AssistantSource(n: 1, docId: "d2", blockId: "b", title: "Secret", text: "private diary entry")])
        let all = AssistantPrompt.prepare(r).turns.map(\.text).joined()
        XCTAssertTrue(all.contains("Only this sentence."))
        XCTAssertFalse(all.contains("private diary entry"))
    }

    func testChatPersistsPerSpace() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let v = Vault(dir: dir)
        var a = AssistantChat(spaceId: "s_one")
        a.messages = [AssistantMessage(role: "user", text: "Hello", action: .ask, scope: .space),
                      AssistantMessage(role: "assistant", text: "Hi [1]", sources: [AssistantSource(n: 1, docId: "d", blockId: "b", title: "T", text: "x")])]
        try a.save(v)
        XCTAssertEqual(AssistantChat.load(v, spaceId: "s_one"), a)
        XCTAssertTrue(AssistantChat.load(v, spaceId: "s_two").messages.isEmpty)
        AssistantChat.delete(v, spaceId: "s_one")
        XCTAssertTrue(AssistantChat.load(v, spaceId: "s_one").messages.isEmpty)
    }

    func testHistoryKeepsRecentTurnsAndSkipsFailures() {
        var c = AssistantChat(spaceId: "s")
        for i in 0..<10 { c.messages.append(AssistantMessage(role: i % 2 == 0 ? "user" : "assistant", text: "m\(i)")) }
        c.messages.append(AssistantMessage(role: "assistant", text: "error", failed: true))
        XCTAssertEqual(c.turns.map(\.text), ["m4", "m5", "m6", "m7", "m8", "m9"])
    }

    func testWordDiff() {
        let d = WordDiff.diff("The quick brown fox", "The slow brown fox jumps")
        XCTAssertEqual(d.filter { $0.op == .removed }.map(\.text).joined(), "quick")
        XCTAssertEqual(d.filter { $0.op == .added }.map(\.text).joined(), "slow jumps")
        XCTAssertEqual(d.filter { $0.op != .added }.map(\.text).joined(), "The quick brown fox")
        XCTAssertEqual(d.filter { $0.op != .removed }.map(\.text).joined(), "The slow brown fox jumps")
    }
}
