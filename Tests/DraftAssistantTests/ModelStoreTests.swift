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

/// Records every request instead of sending it.
final class RecordingProtocol: URLProtocol {
    nonisolated(unsafe) static var requests: [URLRequest] = []
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.requests.append(request)
        client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
    }
    override func stopLoading() {}
}

final class PrivacyTests: XCTestCase {
    /// The model download is the Assistant's only network request: a bodiless GET of the pinned
    /// file, with no note text, query or identifying headers.
    func testDownloadRequestCarriesNothingButThePinnedURL() {
        RecordingProtocol.requests = []
        let cfg = URLSessionConfiguration.ephemeral
        cfg.protocolClasses = [RecordingProtocol.self]
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = ModelStore(directory: dir, configuration: cfg)
        let done = expectation(description: "download")
        store.download(.lfm2_6, progress: { _ in }) { _ in done.fulfill() }
        wait(for: [done], timeout: 10)
        XCTAssertEqual(RecordingProtocol.requests.count, 1)
        let r = RecordingProtocol.requests[0]
        XCTAssertEqual(r.url, LocalModel.lfm2_6.url)
        XCTAssertEqual(r.httpMethod, "GET")
        XCTAssertNil(r.httpBody)
        XCTAssertNil(r.url?.query)
        XCTAssertEqual(Set((r.allHTTPHeaderFields ?? [:]).keys).subtracting(["User-Agent", "Accept", "Accept-Encoding", "Accept-Language"]), [])
        XCTAssertFalse(store.isInstalled(.lfm2_6), "a failed download installs nothing")
    }

    /// Generation goes through an in-process engine; a stand-in proves the Assistant's prompt path
    /// needs nothing but the generator it is given.
    func testGenerationIsInProcess() throws {
        final class Echo: TextGenerator {
            var contextTokens = 4096
            func countTokens(_ text: String) -> Int { text.count / 4 }
            func generate(_ turns: [ChatTurn], maxTokens: Int, cancel: CancelFlag, onPiece: (String) -> Void) throws -> GenerationStats {
                for w in ["<think>check</think>", "Answer ", "[1]"] { if cancel.isCancelled { var s = GenerationStats(); s.cancelled = true; return s }; onPiece(w) }
                return GenerationStats()
            }
        }
        RecordingProtocol.requests = []
        let p = AssistantPrompt.prepare(AssistantRequest(action: .ask, scope: .space, question: "q", retrieved: [AssistantSource(n: 1, docId: "d", blockId: "b", title: "T", text: "x")]))
        var split = ThinkSplitter()
        _ = try Echo().generate(p.turns, maxTokens: 10, cancel: CancelFlag()) { split.feed($0) }
        split.finish()
        XCTAssertEqual(split.answer, "Answer [1]")
        XCTAssertEqual(Citations.cited(in: split.answer, sourceCount: p.sources.count), [1])
        let flag = CancelFlag(); flag.cancel()
        XCTAssertTrue(try Echo().generate(p.turns, maxTokens: 10, cancel: flag) { _ in }.cancelled)
        XCTAssertTrue(RecordingProtocol.requests.isEmpty)
    }
}
