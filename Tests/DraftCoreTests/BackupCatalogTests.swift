import XCTest
@testable import DraftCore

final class BackupCatalogTests: XCTestCase {
    func vault() throws -> Vault {
        let v = Vault(dir: FileManager.default.temporaryDirectory.appendingPathComponent("bc-" + UUID().uuidString)); try v.prepare(); return v
    }

    func testListsEveryKindWithHealthPreviewAndSafeCleanup() throws {
        let v = try vault()
        var d = DocFile.empty(id: "d_1", title: "Notes", styleId: "paper")
        d.content = Node("doc", content: [Node("paragraph", attrs: ["id": "b_1"], content: [.text("first line")])])
        try v.saveDoc(d); var lib = Library.empty(); lib.docs["d_1"] = DocMeta(id: "d_1", title: "Notes"); try v.saveLibrary(lib)
        let old = Date().addingTimeInterval(-40 * 86_400).timeIntervalSince1970 * 1000
        try v.snapshotIfDue(d, now: old)
        try v.snapshotIfDue(d, now: old + 1000, force: true, source: "manual")
        try Vault.writeAtomic(Data("{oops".utf8), to: v.dir.appendingPathComponent("history/d_1/\(Int64(old + 2000)).json"))
        try Vault.writeAtomic(try DraftJSON.encode(lib), to: v.dir.appendingPathComponent("backups/2026-01-01T00-00-00Z-library.v1.json"))
        try Vault.writeAtomic(Data("x".utf8), to: v.dir.appendingPathComponent("backups/2026-01-01T00-00-00Z-library.unreadable.json"))
        _ = try VaultCheck.moveUnused([try v.putAsset(Data("u".utf8), ext: "png")], in: v)
        var plan = VaultRepair.Plan(); plan.writes["docs/d_1.json"] = try DraftJSON.encode(d)
        _ = try VaultRepair.apply(plan, vault: v, summary: "Test repair", fixes: [])
        let items = BackupCatalog.list(v)
        let kinds = Set(items.map(\.kind))
        for k: BackupCatalog.Item.Kind in [.version, .migration, .change, .unusedFiles, .unreadableCopy] { XCTAssertTrue(kinds.contains(k), "\(k)") }
        XCTAssertEqual(items.first { $0.kind == .change }?.source, "Test repair")
        let h = BackupCatalog.health(v, items: items)
        XCTAssertEqual(h.unreadable.count, 1, "\(h.unreadable)")
        XCTAssertEqual(h.notesWithVersions, 1)
        let version = items.first { $0.kind == .version && $0.source == "Saved by you" }!
        XCTAssertTrue(BackupCatalog.preview(v, version).first!.contains("Notes"))
        let clean = BackupCatalog.cleanupCandidates(items)
        XCTAssertFalse(clean.contains { $0.kind == .version && $0.date == items.filter { $0.kind == .version }.map(\.date).max() }, "the newest version of a note is never cleaned up")
        XCTAssertThrowsError(try BackupCatalog.moveToTrash([BackupCatalog.Item(path: "docs/d_1.json", kind: .other, source: "", date: Date(), bytes: 0, docId: nil, isFolder: false)], vault: v), "only backups can be removed")
    }

    func testAssetCatalogStatuses() throws {
        let v = try vault()
        let used = try v.putAsset(Data("used".utf8), ext: "png")
        let unused = try v.putAsset(Data("unused".utf8), ext: "pdf")
        var d = DocFile.empty(id: "d_a", title: "A", styleId: "paper")
        d.content = Node("doc", content: [Node("image", attrs: ["id": "b_i", "assetId": .string(used)]), Node("file", attrs: ["id": "b_f", "assetId": "0123456789abcdef.zip"])])
        try v.saveDoc(d); var lib = Library.empty(); lib.docs["d_a"] = DocMeta(id: "d_a", title: "A"); try v.saveLibrary(lib)
        let items = AssetCatalog.list(v, report: VaultCheck.run(v), library: lib)
        XCTAssertEqual(items.first { $0.name == used }?.status, .used)
        XCTAssertEqual(items.first { $0.name == used }?.users, ["d_a"])
        XCTAssertNotNil(items.first { $0.name == used }?.lastReference)
        XCTAssertEqual(items.first { $0.name == unused }?.status, .unused)
        XCTAssertEqual(items.first { $0.name == unused }?.kind, "PDF")
        XCTAssertEqual(items.first { $0.name == "0123456789abcdef.zip" }?.status, .missing)
    }

    func testFiveThousandBackupsListUnderASecond() throws {
        let v = try vault()
        defer { try? FileManager.default.removeItem(at: v.dir) }
        var d = DocFile.empty(id: "d_x", title: "X", styleId: "paper")
        for doc in 0..<170 {
            d.id = "d_\(doc)"
            let dir = try v.historyDir(d.id)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let data = try DraftJSON.encode(d)
            for i in 0..<30 { try data.write(to: dir.appendingPathComponent("\(1_700_000_000_000 + i).json")) }
        }
        let t0 = Date()
        let items = BackupCatalog.list(v)
        let ms = Date().timeIntervalSince(t0) * 1000
        print("backup catalog \(items.count) items: \(Int(ms)) ms")
        XCTAssertEqual(items.count, 5100)
        XCTAssertLessThan(ms, 1000)
    }
}
