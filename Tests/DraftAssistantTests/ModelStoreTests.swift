import XCTest
@testable import DraftAssistant

final class ModelStoreTests: XCTestCase {
    func temp() -> URL { let u = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString); try! FileManager.default.createDirectory(at: u, withIntermediateDirectories: true); return u }

    func testVerifyAcceptsMatchingFileAndRejectsOthers() throws {
        let f = temp().appendingPathComponent("m.gguf")
        try Data("hello".utf8).write(to: f)
        let good = "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824"
        XCTAssertNoThrow(try ModelStore.verify(f, sha256: good, bytes: 5))
        XCTAssertThrowsError(try ModelStore.verify(f, sha256: String(repeating: "0", count: 64), bytes: 5)) { e in
            guard case ModelStoreError.checksumMismatch = e else { return XCTFail("\(e)") }
        }
        XCTAssertThrowsError(try ModelStore.verify(f, sha256: good, bytes: 6)) { XCTAssertEqual($0 as? ModelStoreError, .wrongSize(expected: 6, actual: 5)) }
    }

    func testDownloadVerifiesInstallsAndRemoves() throws {
        let src = temp().appendingPathComponent("src.gguf")
        try Data("hello".utf8).write(to: src)
        let m = LocalModel(id: "t", name: "T", file: "t.gguf", url: src, sha256: "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824", bytes: 5,
                           parameters: "", license: "", licenseURL: src, source: src, minimumMemory: 0)
        let store = ModelStore(directory: temp())
        let done = expectation(description: "download")
        var result: Result<URL, Error>?
        store.download(m, progress: { _ in }) { result = $0; done.fulfill() }
        wait(for: [done], timeout: 10)
        XCTAssertEqual(try result?.get(), store.path(for: m))
        XCTAssertTrue(store.isInstalled(m))
        try store.remove(m)
        XCTAssertFalse(store.isInstalled(m))
    }

    func testCorruptDownloadIsDeletedNotInstalled() throws {
        let src = temp().appendingPathComponent("src.gguf")
        try Data("hellO".utf8).write(to: src)
        let m = LocalModel(id: "t", name: "T", file: "t.gguf", url: src, sha256: "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824", bytes: 5,
                           parameters: "", license: "", licenseURL: src, source: src, minimumMemory: 0)
        let store = ModelStore(directory: temp())
        let done = expectation(description: "download")
        var result: Result<URL, Error>?
        store.download(m, progress: { _ in }) { result = $0; done.fulfill() }
        wait(for: [done], timeout: 10)
        XCTAssertThrowsError(try result?.get())
        XCTAssertFalse(store.isInstalled(m))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: store.directory.path), [])
    }

    func testCatalogPinsRevisionsAndHashes() {
        for m in LocalModel.all {
            XCTAssertEqual(m.sha256.count, 64)
            XCTAssertFalse(m.url.absoluteString.contains("/resolve/main/"), "download must be pinned to a commit")
            XCTAssertEqual(m.url.host, "huggingface.co")
        }
    }

    func testUTF8PrefixKeepsSplitCharacter() {
        var b = Array("né".utf8)
        let last = b.removeLast()
        XCTAssertEqual(String(validatingUTF8Prefix: &b), "n")
        b.append(last)
        XCTAssertEqual(String(validatingUTF8Prefix: &b), "é")
    }
}
