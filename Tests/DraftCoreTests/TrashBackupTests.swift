import XCTest
@testable import DraftCore

final class TrashTests: XCTestCase {
    func seed() -> Library { Seed.firstRun().library }

    func testTrashTakesNestedPagesAndClosesTabsRestoreBringsThemBack() {
        var lib = seed()
        let welcome = lib.docs.values.first { $0.title == "Welcome to Draft" }!.id
        let child = lib.docs.values.first { $0.parentDocId == welcome }!.id
        lib.tabs.append(Tab(view: .doc(child))); lib.activeTabId = lib.tabs.last!.id
        let ids = lib.trash(welcome, at: 1000)
        XCTAssertEqual(Set(ids), [welcome, child])
        XCTAssertEqual(lib.liveDocs.count, 1)
        XCTAssertFalse(lib.tabs.contains { $0.view.docId == child })
        XCTAssertTrue(lib.tabs.contains { $0.id == lib.activeTabId })
        XCTAssertEqual(Set(lib.restore(welcome)), [welcome, child])
        XCTAssertEqual(lib.liveDocs.count, 3)
        XCTAssertEqual(lib.docs[child]?.parentDocId, welcome, "structure intact")
    }

    func testRestoringAPageWhoseParentIsTrashedMakesItTopLevel() {
        var lib = seed()
        let welcome = lib.docs.values.first { $0.title == "Welcome to Draft" }!.id
        let child = lib.docs.values.first { $0.parentDocId == welcome }!.id
        lib.trash(child, at: 1)
        lib.trash(welcome, at: 2)
        lib.restore(child)
        XCTAssertNil(lib.docs[child]?.deletedAt)
        XCTAssertNil(lib.docs[child]?.parentDocId)
        XCTAssertNotNil(lib.docs[welcome]?.deletedAt)
    }

    func testExpiry() {
        var lib = seed()
        let id = lib.docs.values.first { $0.parentDocId == nil && $0.title == "Morning pages" }!.id
        lib.trash(id, at: 0)
        XCTAssertEqual(lib.expiredTrash(now: 29 * 86_400_000), [])
        XCTAssertEqual(lib.expiredTrash(now: 31 * 86_400_000), [id])
    }

    func testDeletedAtSurvivesEncoding() throws {
        var lib = seed()
        let id = lib.docs.keys.first!
        lib.trash(id, at: 42)
        let back = try JSONDecoder().decode(Library.self, from: DraftJSON.encode(lib))
        XCTAssertEqual(back.docs[id]?.deletedAt, 42)
    }
}

final class BackupTests: XCTestCase {
    var dir: URL!
    override func setUp() { dir = FileManager.default.temporaryDirectory.appendingPathComponent("draft-bk-\(UUID().uuidString)") }
    override func tearDown() { try? FileManager.default.removeItem(at: dir) }

    func testThrottledSkipsUnchangedPrunesAndLoads() throws {
        let v = Vault(dir: dir); try v.prepare()
        var d = Seed.firstRun().docs[0]
        XCTAssertTrue(try v.snapshotIfDue(d, now: 1_000_000))
        d.title = "Edited"
        XCTAssertFalse(try v.snapshotIfDue(d, now: 1_000_000 + 60_000), "within the interval")
        XCTAssertTrue(try v.snapshotIfDue(d, now: 1_000_000 + Vault.snapshotInterval))
        XCTAssertFalse(try v.snapshotIfDue(d, now: 1_000_000 + 3 * Vault.snapshotInterval), "unchanged content is not duplicated")
        XCTAssertEqual(v.snapshots(d.id).map(\.savedAt), [1_000_000 + Vault.snapshotInterval, 1_000_000])
        XCTAssertEqual(try v.loadSnapshot(v.snapshots(d.id)[1]).title, "Welcome to Draft")
        for i in 0..<40 { d.title = "v\(i)"; try v.snapshotIfDue(d, now: 2_000_000 + Double(i), force: true) }
        XCTAssertEqual(v.snapshots(d.id).count, Vault.snapshotsKept)
        XCTAssertEqual(try v.loadSnapshot(v.snapshots(d.id)[0]).title, "v39")
        try v.saveDoc(d)
        try v.purgeDoc(d.id)
        XCTAssertTrue(v.snapshots(d.id).isEmpty)
        XCTAssertNil(try v.loadDoc(d.id))
    }
}
