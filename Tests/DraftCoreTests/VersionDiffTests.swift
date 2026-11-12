import XCTest
@testable import DraftCore

final class VersionDiffTests: XCTestCase {
    func p(_ id: String, _ t: String, _ marks: [Mark]? = nil) -> Node { Node("paragraph", attrs: ["id": .string(id)], content: [.text(t, marks: marks)]) }
    func doc(_ title: String, _ blocks: [Node], style: String = "paper") -> DocFile {
        var d = DocFile.empty(id: "d_v", title: title, styleId: style); d.content = Node("doc", content: blocks); return d
    }

    func testEveryKindOfChange() {
        let old = doc("Trip", [p("b_1", "We fly on Monday morning"), p("b_2", "Pack light"), p("b_3", "Old idea"), p("b_4", "Stay"),
                               Node("bulletList", attrs: ["id": "b_l"], content: [Node("listItem", attrs: ["id": "b_li"], content: [p("b_lp", "socks")])]),
                               Node("image", attrs: ["id": "b_img", "assetId": "aaaaaaaaaaaaaaaa.png"])])
        let new = doc("Trip plan", [p("b_4", "Stay"), p("b_1", "We fly on Tuesday morning"), p("b_2", "Pack light", [Mark("bold")]),
                                    Node("heading", attrs: ["id": "b_new", "level": 2], content: [.text("Budget")]),
                                    Node("bulletList", attrs: ["id": "b_l"], content: [Node("listItem", attrs: ["id": "b_li"], content: [p("b_lp", "warm socks")])]),
                                    Node("image", attrs: ["id": "b_img2", "assetId": "bbbbbbbbbbbbbbbb.png"])], style: "ember")
        let d = VersionDiff.compute(from: old, to: new)
        XCTAssertEqual(d.titleAfter, "Trip plan")
        let edit = d.blocks.first { $0.blockId == "b_1" }!
        XCTAssertEqual(edit.kind, .edited)
        XCTAssertEqual(edit.words.filter { $0.op == .removed }.map(\.text), ["Monday"])
        XCTAssertEqual(edit.words.filter { $0.op == .added }.map(\.text), ["Tuesday"])
        XCTAssertEqual(d.blocks.first { $0.blockId == "b_2" }?.notes, ["bold added"])
        XCTAssertEqual(d.blocks.first { $0.blockId == "b_3" }?.kind, .removed)
        XCTAssertEqual(d.blocks.first { $0.blockId == "b_new" }?.type, "Heading 2")
        XCTAssertEqual(d.blocks.first { $0.blockId == "b_li" }?.kind, .edited, "list items are compared one by one")
        XCTAssertTrue(d.blocks.contains { $0.blockId == "b_4" && ($0.kind == .moved) } || d.blocks.contains { $0.blockId == "b_1" && $0.notes.contains("moved") })
        XCTAssertTrue(d.lookNotes.first!.hasPrefix("Style:"))
        XCTAssertEqual(d.assetsAdded, ["bbbbbbbbbbbbbbbb.png"])
        XCTAssertEqual(d.assetsRemoved, ["aaaaaaaaaaaaaaaa.png"])
        XCTAssertTrue(d.summary.contains("edited"), d.summary)
        XCTAssertTrue(VersionDiff.compute(from: old, to: old).isEmpty)
        XCTAssertEqual(VersionDiff.lostBlockIds(current: new, restored: old), ["b_new", "b_img2"])
    }

    func testSnapshotSourcesAndRetention() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let v = Vault(dir: dir); try v.prepare()
        var d = doc("A", [p("b_1", "x")]); d.id = "d_s"
        try v.saveDoc(d)
        XCTAssertTrue(try v.snapshotIfDue(d, now: 1000))
        XCTAssertTrue(try v.snapshotIfDue(d, now: 2000, force: true, source: "manual"), "a manual version is kept even when nothing changed")
        let s = v.snapshots("d_s")
        XCTAssertEqual(s.map(\.source), ["manual", "auto"])
        XCTAssertEqual(s.first?.sourceLabel, "Saved by you")
        for i in 0..<35 { d.title = "A\(i)"; try v.snapshotIfDue(d, now: Double(10_000_000 + i * 1_000_000)) }
        XCTAssertEqual(v.snapshots("d_s").filter { $0.source == "auto" }.count, Vault.snapshotsKept)
        XCTAssertEqual(v.snapshots("d_s").filter { $0.source == "manual" }.count, 1, "automatic pruning never removes your own versions")
    }

    func testHistoryOfALargeNoteLoadsAndDiffsQuickly() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let v = Vault(dir: dir); try v.prepare()
        var d = doc("Big", (0..<2000).map { p("b_\($0)", "Paragraph \($0) with a handful of ordinary words in it.") }); d.id = "d_big"
        for i in 0..<30 {
            d.content.content![i * 50] = p("b_\(i * 50)", "Edited in version \(i)")
            try v.snapshotIfDue(d, now: Double(1_000_000 * (i + 1)))
        }
        let t0 = Date()
        let snaps = v.snapshots("d_big")
        let newest = try v.loadSnapshot(snaps[0]), older = try v.loadSnapshot(snaps[1])
        let diff = VersionDiff.compute(from: older, to: newest)
        let ms = Date().timeIntervalSince(t0) * 1000
        print("history 30 versions of 2,000 blocks: list + 2 loads + diff \(Int(ms)) ms")
        XCTAssertEqual(snaps.count, 30)
        XCTAssertEqual(diff.count(.edited), 1)
        XCTAssertLessThan(ms, 500)
    }
}
