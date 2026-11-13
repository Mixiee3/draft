import XCTest
@testable import DraftCore

final class BackupArchiveTests: XCTestCase {
    func testArchiveRestoresIdenticalFilesAndRejectsDamage() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ba-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let v = Vault(dir: root.appendingPathComponent("vault")); try v.prepare()
        var d = DocFile.empty(id: "d_a", title: "Notes", styleId: "paper")
        d.content = Node("doc", content: [Node("paragraph", attrs: ["id": "b_1"], content: [.text("hello")])])
        try v.saveDoc(d); var lib = Library.empty(); lib.docs["d_a"] = DocMeta(id: "d_a", title: "Notes"); try v.saveLibrary(lib)
        _ = try v.putAsset(Data("pic".utf8), ext: "png")
        try v.snapshotIfDue(d, force: true, source: "manual")
        try Vault.writeAtomic(Data("x".utf8), to: v.dir.appendingPathComponent("index/index.json"))
        try Vault.writeAtomic(Data("junk".utf8), to: v.dir.appendingPathComponent("docs/.DS_Store"))
        let zip = try BackupArchive.create(vault: v, into: root.appendingPathComponent("out"), appVersion: "0.10.0")
        let restored = try BackupArchive.restore(zip, into: root.appendingPathComponent("restore"))
        let original = BackupArchive.files(in: v.dir)
        XCTAssertEqual(BackupArchive.files(in: restored.vault), original)
        XCTAssertFalse(original.contains { $0.hasPrefix("index/") || $0.hasSuffix(".DS_Store") }, "derived and system files are left out")
        for f in original { XCTAssertEqual(try Data(contentsOf: restored.vault.appendingPathComponent(f)), try Data(contentsOf: v.dir.appendingPathComponent(f)), f) }
        XCTAssertTrue(restored.check.issues.filter { $0.severity > .info }.isEmpty)
        XCTAssertEqual(restored.manifest.appVersion, "0.10.0")
        XCTAssertThrowsError(try BackupArchive.restore(zip, into: root.appendingPathComponent("restore")), "never restores over an existing copy")
        // A damaged archive restores nothing.
        let x = root.appendingPathComponent("x"); try FileManager.default.createDirectory(at: x, withIntermediateDirectories: true)
        try BackupArchive.ditto(["-x", "-k", zip.path, x.path])
        let inner = try FileManager.default.contentsOfDirectory(at: x, includingPropertiesForKeys: nil)[0]
        try Data("tampered".utf8).write(to: inner.appendingPathComponent("vault/docs/d_a.json"))
        let bad = root.appendingPathComponent("bad.zip")
        try BackupArchive.ditto(["-c", "-k", "--keepParent", inner.path, bad.path])
        XCTAssertThrowsError(try BackupArchive.restore(bad, into: root.appendingPathComponent("restore2")))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("restore2/bad (restored)").path))
    }
}
