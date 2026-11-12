import XCTest
@testable import DraftCore

final class VaultCheckTests: XCTestCase {
    func testReportsEachProblemAndMovesUnusedFilesReversibly() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let v = Vault(dir: dir); try v.prepare()
        let used = try v.putAsset(Data("image".utf8), ext: "png")
        let unused = try v.putAsset(Data("old picture".utf8), ext: "png")
        let trashedUse = try v.putAsset(Data("in the bin".utf8), ext: "jpg")
        var lib = Library.empty()
        var a = DocFile.empty(id: "d_a", title: "A", styleId: "paper")
        a.content = Node("doc", content: [Node("image", attrs: ["id": "b_i", "assetId": .string(used)]), Node("image", attrs: ["id": "b_m", "assetId": "0000000000000000aaaaaaaaaaaaaaaa.png"])])
        var t = DocFile.empty(id: "d_t", title: "Binned", styleId: "paper")
        t.appearance.cover = Cover(assetId: trashedUse)
        try v.saveDoc(a); try v.saveDoc(t)
        lib.docs["d_a"] = DocMeta(id: "d_a", title: "A"); lib.docs["d_t"] = DocMeta(id: "d_t", title: "Binned"); lib.docs["d_t"]?.deletedAt = 1
        lib.docs["d_gone"] = DocMeta(id: "d_gone", title: "Gone")
        try v.saveLibrary(lib)
        try Vault.writeAtomic(Data("{}".utf8), to: dir.appendingPathComponent("docs/d_stray.json"))
        var r = VaultCheck.run(v)
        XCTAssertEqual(r.missingDocFiles, ["d_gone"])
        XCTAssertEqual(r.strayDocFiles, ["d_stray"])
        XCTAssertEqual(r.unreadableDocs, ["d_stray"], "an empty object is not a note")
        XCTAssertEqual(r.missingAssets, ["0000000000000000aaaaaaaaaaaaaaaa.png"])
        XCTAssertTrue(r.unusedAssets.isEmpty, "no unused list while a note can't be read")
        try FileManager.default.removeItem(at: dir.appendingPathComponent("docs/d_stray.json"))
        r = VaultCheck.run(v)
        XCTAssertEqual(r.unusedAssets, [unused], "a note in Recently Deleted still uses its cover")
        XCTAssertEqual(r.unusedBytes, Int64("old picture".utf8.count))
        let before = try Data(contentsOf: try v.assetURL(unused))
        let folder = try VaultCheck.moveUnused(r.unusedAssets, in: v)
        XCTAssertFalse(FileManager.default.fileExists(atPath: try v.assetURL(unused).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: try v.assetURL(used).path))
        XCTAssertTrue(VaultCheck.run(v).unusedAssets.isEmpty)
        try VaultCheck.restore(from: folder, into: v)
        XCTAssertEqual(try Data(contentsOf: try v.assetURL(unused)), before, "Undo restores the same bytes")
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.path))
    }

    func testReadOnlyVaultRefusesToMoveFiles() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let v = Vault(dir: dir); try v.prepare()
        let a = try v.putAsset(Data("x".utf8), ext: "png")
        try Vault.writeAtomic(Data("not json".utf8), to: dir.appendingPathComponent("library.json"))
        _ = try? v.loadLibrary() // what Draft does at launch: an unreadable library makes the vault read-only
        let r = VaultCheck.run(v)
        XCTAssertFalse(r.libraryReadable)
        XCTAssertTrue(r.unusedAssets.isEmpty, "nothing is called unused without a readable library")
        XCTAssertThrowsError(try VaultCheck.moveUnused([a], in: v))
        XCTAssertTrue(FileManager.default.fileExists(atPath: try v.assetURL(a).path))
    }

    func testTwoThousandNotesAndAThousandFilesUnderTwoSeconds() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let v = Vault(dir: dir); try v.prepare()
        var lib = Library.empty()
        var assets: [String] = []
        for i in 0..<1000 { assets.append(try v.putAsset(Data("asset \(i)".utf8), ext: "png")) }
        for i in 0..<2000 {
            var d = DocFile.empty(id: "d_\(i)", title: "Note \(i)", styleId: "paper")
            var blocks = (0..<20).map { Node("paragraph", attrs: ["id": .string("b_\(i)_\($0)")], content: [.text("Line \($0) of note \(i) with some words in it.")]) }
            if i < 900 { blocks.append(Node("image", attrs: ["id": .string("b_img_\(i)"), "assetId": .string(assets[i])])) }
            d.content = Node("doc", content: blocks)
            try Vault.writeAtomic(try DraftJSON.encode(d), to: v.docURL(d.id))
            lib.docs[d.id] = DocMeta(id: d.id, title: d.title)
        }
        try v.saveLibrary(lib)
        let start = Date()
        let r = VaultCheck.run(v)
        let took = Date().timeIntervalSince(start)
        XCTAssertEqual(r.docsChecked, 2000)
        XCTAssertEqual(r.unusedAssets.count, 100)
        XCTAssertTrue(r.missingDocFiles.isEmpty && r.unreadableDocs.isEmpty)
        print("vault-check 2000 notes / 1000 files: \(Int(took * 1000)) ms")
        XCTAssertLessThan(took, 2)
    }
}
