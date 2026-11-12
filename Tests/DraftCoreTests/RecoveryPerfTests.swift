import XCTest
@testable import DraftCore

/// v0.8 budgets on a large throwaway vault (debug build): library rebuild < 3 s, asset scan < 2 s,
/// repair plan < 2 s, migration dry run on a copy < 5 s. Also: a rebuild keeps unknown fields and places.
final class RecoveryPerfTests: XCTestCase {
    static var dir: URL!
    static var vault: Vault!

    override class func setUp() {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("perf-" + UUID().uuidString)
        vault = Vault(dir: dir); try! vault.prepare()
        var lib = Library.empty()
        lib.extra["fromTheFuture"] = "keep"
        lib.folders = [Folder(id: "f_1", name: "Archive")]
        var assets: [String] = []
        for i in 0..<1000 { assets.append(try! vault.putAsset(Data("asset \(i)".utf8), ext: i % 3 == 0 ? "jpg" : "png")) }
        for i in 0..<2000 {
            var d = DocFile.empty(id: "d_\(i)", title: "Note \(i)", styleId: "paper")
            var blocks = (0..<20).map { Node("paragraph", attrs: ["id": .string("b_\(i)_\($0)")], content: [.text("Line \($0) of note \(i) with ordinary words.")]) }
            if i < 900 { blocks.append(Node("image", attrs: ["id": .string("b_img_\(i)"), "assetId": .string(assets[i])])) }
            d.content = Node("doc", content: blocks)
            try! Vault.writeAtomic(try! DraftJSON.encode(d), to: vault.docURL(d.id))
            var m = DocMeta(id: d.id, title: d.title); m.folderId = i % 10 == 0 ? "f_1" : nil; m.starred = i == 7
            if i < 1990 { lib.docs[d.id] = m } // ten notes the library is missing
        }
        try! vault.saveLibrary(lib)
    }
    override class func tearDown() { try? FileManager.default.removeItem(at: dir) }

    func time(_ label: String, _ budget: Double, _ f: () throws -> Void) rethrows {
        let t0 = Date(); try f(); let ms = Date().timeIntervalSince(t0) * 1000
        print("recovery-perf \(label): \(Int(ms)) ms (budget \(Int(budget * 1000)))")
        XCTAssertLessThan(ms, budget * 1000, label)
    }

    func testLibraryRebuildKeepsPlacesAndIsFast() throws {
        var plan = VaultRepair.Plan()
        try time("library rebuild dry run, 2,000 notes", 3) { plan = VaultRepair.rebuildPlan(Self.vault) }
        let lib = try Migrations.migrateLibrary(XCTUnwrap(plan.writes["library.json"] ?? nil)).library
        XCTAssertEqual(lib.docs.count, 2000)
        XCTAssertEqual(lib.extra["fromTheFuture"], "keep")
        XCTAssertEqual(lib.docs["d_10"]?.folderId, "f_1")
        XCTAssertEqual(lib.docs["d_7"]?.starred, true)
        XCTAssertEqual(plan.steps.filter { $0.text.contains("add “") }.count, 10)
    }

    func testAssetAndRepairScansAreFast() throws {
        var report = VaultCheck.Report()
        try time("vault check (repair scan), 2,000 notes / 1,000 assets", 2) { report = VaultCheck.run(Self.vault) }
        try time("asset browser list", 2) { XCTAssertEqual(AssetCatalog.list(Self.vault, report: report, library: nil).count, 1000) }
        try time("repair plan for every issue", 2) { XCTAssertFalse(VaultRepair.plan(report.issues, vault: Self.vault).isEmpty) }
    }

    func testMigrationDryRunOnACopyIsFast() throws {
        try time("migration validator, 2,000 notes", 5) {
            let r = try MigrationValidator.validate(vault: Self.dir)
            XCTAssertTrue(r.problems.allSatisfy { $0.contains("Document list") }, "\(r.problems.prefix(2))")
        }
    }

    func testMigrationOfAnOlderLibraryOnACopyIsFast() throws {
        let copy = FileManager.default.temporaryDirectory.appendingPathComponent("perf-old-" + UUID().uuidString)
        try FileManager.default.copyItem(at: Self.dir, to: copy)
        defer { try? FileManager.default.removeItem(at: copy) }
        var raw = try JSONSerialization.jsonObject(with: Data(contentsOf: copy.appendingPathComponent("library.json"))) as! [String: Any]
        raw["schemaVersion"] = 1; raw["spaces"] = nil
        var docs = raw["docs"] as! [String: Any]
        for (k, v) in docs { var o = v as! [String: Any]; o["spaceId"] = nil; docs[k] = o }
        raw["docs"] = docs
        try JSONSerialization.data(withJSONObject: raw).write(to: copy.appendingPathComponent("library.json"))
        let before = try Data(contentsOf: copy.appendingPathComponent("library.json"))
        try time("migration validator, schema 1 → 2, 2,000 notes", 5) {
            let r = try MigrationValidator.validate(vault: copy)
            XCTAssertTrue(r.needsMigration)
            XCTAssertTrue(r.problems.allSatisfy { $0.contains("Document list") }, "\(r.problems.prefix(2))")
        }
        XCTAssertEqual(try Data(contentsOf: copy.appendingPathComponent("library.json")), before, "the real vault is untouched")
    }
}
