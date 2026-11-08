import XCTest
@testable import DraftCore

/// Retrieval over the quality benchmark's notes: every answerable question must reach its note.
final class RetrievalQualityTests: XCTestCase {
    func testEveryQuestionRetrievesItsNote() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures/assistant-quality.json")
        let fx = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
        let notes = fx["notes"] as! [[String: String]]
        var entries: [String: DocIndexEntry] = [:], titles: [String: String] = [:]
        for (i, n) in notes.enumerated() {
            var e = DocIndexEntry(updatedAt: 0)
            e.blocks = [IndexedBlock(id: "b\(i)", text: n["text"]!, heading: nil)]
            entries["d\(i + 1)"] = e; titles["d\(i + 1)"] = n["title"]!
        }
        var misses: [String] = []
        for q in fx["questions"] as! [[String: Any]] {
            guard let src = q["source"] as? Int else { continue }
            let hits = Retrieval.rank(q["q"] as! String, entries: entries, titles: titles, limit: 10)
            if hits.first?.docId != "d\(src)" { misses.append("\(q["q"]!) -> \(hits.map(\.docId))") }
        }
        XCTAssertEqual(misses, [])
    }
}
