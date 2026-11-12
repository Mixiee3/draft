import XCTest
import CryptoKit
@testable import DraftCore

final class VaultRepairTests: XCTestCase {
    var dir: URL!
    var v: Vault!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("vr-" + UUID().uuidString)
        v = Vault(dir: dir); try v.prepare()
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: dir) }

    /// sha256 of every file in the vault, by relative path.
    func fingerprint() -> [String: String] {
        var out: [String: String] = [:]
        let root = dir.resolvingSymlinksInPath().path
        let e = FileManager.default.enumerator(at: dir.resolvingSymlinksInPath(), includingPropertiesForKeys: [.isRegularFileKey])!
        for case let u as URL in e where (try? u.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true {
            out[String(u.resolvingSymlinksInPath().path.dropFirst(root.count + 1))] = SHA256.hash(data: try! Data(contentsOf: u)).map { String(format: "%02x", $0) }.joined()
        }
        return out
    }

    func doc(_ id: String, _ title: String, _ blocks: [Node]) -> DocFile {
        var d = DocFile.empty(id: id, title: title, styleId: "paper"); d.content = Node("doc", content: blocks); return d
    }
    func para(_ id: String, _ text: String, marks: [Mark]? = nil) -> Node { Node("paragraph", attrs: ["id": .string(id)], content: [.text(text, marks: marks)]) }

    /// One problem of every kind Draft can repair or must report.
    func makeBrokenVault() throws -> Library {
        var lib = Library.empty()
        lib.extra["futureField"] = "kept"
        let img = try v.putAsset(Data("pic".utf8), ext: "png")
        _ = try v.putAsset(Data("unused".utf8), ext: "png")
        let link = Mark("docLink", attrs: ["docId": "d_nowhere"])
        let a = doc("d_a", "Alpha", [para("b_1", "one"), para("b_1", "dup"), Node("image", attrs: ["id": "b_img", "assetId": .string(img)]),
                                     Node("image", attrs: ["id": "b_gone", "assetId": "ffffffffffffffffffffffffffffffff.png"]), para("b_l", "link", marks: [link]),
                                     Node("pageCard", attrs: ["id": "b_pc", "docId": "d_lostpage"])])
        try Vault.writeAtomic(try DraftJSON.encode(a), to: v.docURL("d_a"))
        var b = doc("d_b", "Beta", [para("b_2", "beta")]); b.id = "d_other"
        try Vault.writeAtomic(try DraftJSON.encode(b), to: v.docURL("d_b"))
        let c = doc("d_c", "Unlisted child", [para("b_3", "child")])
        try Vault.writeAtomic(try DraftJSON.encode(c), to: v.docURL("d_c"))
        // d_c is shown by a page card in d_a? No: in d_e, so rebuild nests it there.
        let e = doc("d_e", "Parent", [Node("pageCard", attrs: ["id": "b_card", "docId": "d_c"])])
        try Vault.writeAtomic(try DraftJSON.encode(e), to: v.docURL("d_e"))
        try Vault.writeAtomic(Data("{not json".utf8), to: v.docURL("d_bad"))
        try Vault.writeAtomic(Data("left".utf8), to: dir.appendingPathComponent("docs/d_a.json.sb-123-tmp"))
        try Vault.writeAtomic(Data("garbage".utf8), to: dir.appendingPathComponent("index/index.json"))
        for (id, t) in [("d_a", "Alpha"), ("d_b", "Beta"), ("d_e", "Parent"), ("d_bad", "Bad"), ("d_missing", "Missing")] { lib.docs[id] = DocMeta(id: id, title: t) }
        lib.docs["d_a"]?.folderId = "f_gone"
        lib.docs["d_b"]?.parentDocId = "d_deleted"
        try v.saveLibrary(lib)
        return lib
    }

    func testScanReportsEveryKindAndWritesNothing() throws {
        _ = try makeBrokenVault()
        let before = fingerprint()
        let r = VaultCheck.run(v)
        XCTAssertEqual(fingerprint(), before, "a scan writes nothing")
        let kinds = Set(r.issues.map(\.kind))
        for k: VaultIssue.Kind in [.docMissing, .docMalformed, .docIdMismatch, .blockIdDuplicate, .docUnlisted, .assetMissing, .parentMissing, .folderMissing, .pageCardBroken, .linkBroken, .indexInvalid, .tempFile] {
            XCTAssertTrue(kinds.contains(k), "missing \(k)")
        }
        XCTAssertEqual(r.issues.first?.severity, .critical, "most severe first")
        XCTAssertNil(r.issues.first { $0.kind == .assetMissing }?.repair, "a missing image can't be invented")
        XCTAssertTrue(r.unusedAssets.isEmpty, "no unused list while d_bad can't be read")
    }

    func testRepairIsBackedUpValidatedAndUndoneToTheSameBytes() throws {
        _ = try makeBrokenVault()
        let before = fingerprint()
        let r = VaultCheck.run(v)
        let plan = VaultRepair.plan(r.issues, vault: v)
        XCTAssertFalse(plan.steps.isEmpty)
        XCTAssertTrue(plan.steps.allSatisfy { !$0.text.isEmpty })
        XCTAssertEqual(fingerprint(), before, "planning writes nothing")
        let fixable = plan.steps.map(\.issueId)
        let folder = try XCTUnwrap(VaultRepair.apply(plan, vault: v, summary: "Repair", fixes: fixable))
        let after = VaultCheck.run(v)
        XCTAssertTrue(Set(after.issues.map(\.id)).isDisjoint(with: fixable))
        let lib = try XCTUnwrap(try Migrations.migrateLibrary(Data(contentsOf: dir.appendingPathComponent("library.json"))).library)
        XCTAssertEqual(lib.extra["futureField"], "kept", "unknown fields survive")
        XCTAssertEqual(lib.docs["d_c"]?.parentDocId, "d_e", "an unlisted page is nested under the note with its card")
        XCTAssertNil(lib.docs["d_a"]?.folderId)
        XCTAssertNil(lib.docs["d_missing"], "no file and no version: entry removed (kept in backup)")
        let a = try XCTUnwrap(try v.loadDoc("d_a"))
        var ids: [String] = []; walk(a.content) { if let i = $0.id { ids.append(i) } }
        XCTAssertEqual(Set(ids).count, ids.count)
        XCTAssertEqual(ids.first, "b_1", "the first copy keeps its id")
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.appendingPathComponent("journal.json").path))
        try VaultRepair.undo(folder, vault: v)
        var now = fingerprint()
        now = now.filter { !$0.key.hasPrefix("backups/") }
        XCTAssertEqual(now, before.filter { !$0.key.hasPrefix("backups/") }, "Undo puts back exactly the same bytes")
    }

    func testUnreadableLibraryIsRebuiltFromNotesAndNewestBackup() throws {
        var lib = try makeBrokenVault()
        lib.folders = [Folder(id: "f_1", name: "Work")]
        lib.docs["d_a"]?.folderId = "f_1"
        try Vault.writeAtomic(try DraftJSON.encode(lib, pretty: true), to: dir.appendingPathComponent("backups/2026-11-01T10-00-00Z-library.v1.json"))
        try Vault.writeAtomic(Data("{\"docs\": [".utf8), to: dir.appendingPathComponent("library.json"))
        let r = VaultCheck.run(v)
        XCTAssertEqual(r.issues.first?.kind, .libraryUnreadable)
        let issue = r.issues.first!
        let plan = VaultRepair.plan([issue], vault: v)
        XCTAssertTrue(plan.steps[0].text.contains("rebuilt"), plan.steps[0].text)
        _ = try VaultRepair.apply(plan, vault: v, summary: "Rebuild library", fixes: [issue.id])
        let rebuilt = try XCTUnwrap(try Vault(dir: dir).loadLibrary())
        XCTAssertEqual(rebuilt.folders.map(\.name), ["Work"])
        XCTAssertEqual(rebuilt.docs["d_a"]?.folderId, "f_1", "folder kept from the backup")
        XCTAssertNotNil(rebuilt.docs["d_c"], "unlisted note added")
        XCTAssertNil(rebuilt.docs["d_missing"])
    }

    func testInterruptedRepairIsDetectedAndRolledBack() throws {
        let d = doc("d_x", "X", [para("b_x", "original")])
        try v.saveDoc(d); var lib = Library.empty(); lib.docs["d_x"] = DocMeta(id: "d_x", title: "X"); try v.saveLibrary(lib)
        let original = try Data(contentsOf: v.docURL("d_x"))
        var plan = VaultRepair.Plan()
        plan.writes["docs/d_x.json"] = try DraftJSON.encode(doc("d_x", "X", [para("b_x", "changed")]))
        let folder = try XCTUnwrap(VaultRepair.apply(plan, vault: v, summary: "Restore X", fixes: []))
        // Simulate a crash after writing, before the journal said done.
        var j = try JSONDecoder().decode(VaultRepair.Journal.self, from: Data(contentsOf: folder.appendingPathComponent("journal.json")))
        j.state = "writing"; try VaultRepair.writeJournal(j, folder)
        let issue = try XCTUnwrap(VaultCheck.run(v).issues.first { $0.kind == .journalOpen })
        XCTAssertEqual(issue.severity, .critical)
        _ = try VaultRepair.apply(VaultRepair.plan([issue], vault: v), vault: v, summary: "Roll back", fixes: [])
        XCTAssertEqual(try Data(contentsOf: v.docURL("d_x")), original)
        XCTAssertTrue(VaultRepair.openJournals(v).isEmpty)
    }

    func testFailedValidationPutsEveryFileBack() throws {
        let d = doc("d_y", "Y", [para("b_y", "y")])
        try v.saveDoc(d); var lib = Library.empty(); lib.docs["d_y"] = DocMeta(id: "d_y", title: "Y"); try v.saveLibrary(lib)
        let before = fingerprint()
        var plan = VaultRepair.Plan()
        plan.writes["library.json"] = Data("{}".utf8) // decodes as JSON but not as a library... or does
        plan.writes["docs/d_y.json"] = Data("[1,2]".utf8) // not a note
        XCTAssertThrowsError(try VaultRepair.apply(plan, vault: v, summary: "Bad", fixes: []))
        XCTAssertEqual(fingerprint().filter { !$0.key.hasPrefix("backups/") }, before)
    }

    func testNewerLibraryBlocksEveryRepair() throws {
        try Vault.writeAtomic(Data("{\"schemaVersion\": 99, \"docs\": {}}".utf8), to: dir.appendingPathComponent("library.json"))
        let r = VaultCheck.run(v)
        XCTAssertEqual(r.issues.first?.kind, .libraryNewer)
        XCTAssertTrue(VaultRepair.plan(r.issues, vault: v).isEmpty)
    }
}

extension VaultRepairTests {
    func testRollbackOwnsTheFilesOfTheInterruptedChange() throws {
        var lib = Library.empty(); lib.docs["d_k"] = DocMeta(id: "d_k", title: "Kept"); try v.saveLibrary(lib)
        try v.saveDoc(doc("d_k", "Kept", [para("b_k", "k")]))
        try Vault.writeAtomic(try DraftJSON.encode(doc("d_half", "Half", [para("b_h", "h")])), to: v.docURL("d_half"))
        let folder = dir.appendingPathComponent("backups/restore-2026-01-01T00-00-00Z")
        try VaultRepair.writeJournal(VaultRepair.Journal(kind: "restore", summary: "Restore", startedAt: 0, state: "writing", touched: [], created: ["docs/d_half.json"], fixes: []), folder)
        let issues = VaultCheck.run(v).issues
        XCTAssertTrue(issues.contains { $0.kind == .docUnlisted && $0.subject == "d_half" })
        let plan = VaultRepair.plan(issues, vault: v)
        XCTAssertNil(plan.writes["library.json"], "the half-written note is removed by the rollback, not added to the library")
        _ = try VaultRepair.apply(plan, vault: v, summary: "Recover", fixes: [])
        XCTAssertTrue(VaultCheck.run(v).issues.filter { $0.severity > .info }.isEmpty, "\(VaultCheck.run(v).issues.map(\.title))")
    }
}
