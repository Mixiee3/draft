import XCTest
import CryptoKit
@testable import DraftCore

final class UpdatesTests: XCTestCase {
    let key = Curve25519.Signing.PrivateKey()
    func item(_ build: Int, _ channel: String = "stable", archive: Data = Data("app".utf8), library: Int = librarySchemaVersion, system: String = "14.0") throws -> UpdateItem {
        let d = try Updates.describe(archive: archive, key: key)
        return UpdateItem(version: "1.0.\(build)", build: build, channel: channel, date: "2026-11-13", notes: ["Fixes"], url: "https://example.com/Draft-\(build).zip",
                          size: d.size, sha256: d.sha256, signature: d.signature, minimumSystem: system, librarySchema: library, docSchema: docSchemaVersion)
    }

    func testChannelsAndNewest() throws {
        let items = [try item(5), try item(7, "beta"), try item(9, "development"), try item(3)]
        XCTAssertEqual(Updates.newest(in: items, channel: "stable", currentBuild: 4)?.build, 5, "stable only sees stable")
        XCTAssertEqual(Updates.newest(in: items, channel: "beta", currentBuild: 4)?.build, 7)
        XCTAssertEqual(Updates.newest(in: items, channel: "development", currentBuild: 4)?.build, 9)
        XCTAssertNil(Updates.newest(in: items, channel: "stable", currentBuild: 5), "nothing newer")
        XCTAssertNil(Updates.newest(in: items, channel: "stable", currentBuild: 4, skipped: "1.0.5-5"), "a skipped version isn't offered again")
    }

    func testSignedFeedAndArchiveVerification() throws {
        let archive = Data("the new app".utf8)
        let it = try item(10, archive: archive)
        let feed = try Updates.signFeed([it], key: key)
        XCTAssertEqual(try Updates.items(fromFeed: feed, key: key.publicKey).first?.build, 10)
        XCTAssertNoThrow(try Updates.verifyArchive(archive, item: it, key: key.publicKey))
        // Tampering anywhere is caught.
        XCTAssertThrowsError(try Updates.items(fromFeed: feed, key: Curve25519.Signing.PrivateKey().publicKey)) { XCTAssertEqual($0 as? UpdateError, .badFeedSignature) }
        var forged = try JSONDecoder().decode(SignedFeed.self, from: feed)
        var items = [it]; items[0].url = "https://evil.example/Draft.zip"
        forged.payload = try DraftJSON.encode(items).base64EncodedString()
        XCTAssertThrowsError(try Updates.items(fromFeed: try JSONEncoder().encode(forged), key: key.publicKey)) { XCTAssertEqual($0 as? UpdateError, .badFeedSignature) }
        XCTAssertThrowsError(try Updates.verifyArchive(Data("the new apq".utf8), item: it, key: key.publicKey)) { XCTAssertEqual($0 as? UpdateError, .checksumMismatch) }
        XCTAssertThrowsError(try Updates.verifyArchive(Data("short".utf8), item: it, key: key.publicKey)) { XCTAssertEqual($0 as? UpdateError, .sizeMismatch) }
        var resigned = it; resigned.signature = try Curve25519.Signing.PrivateKey().signature(for: archive).base64EncodedString()
        XCTAssertThrowsError(try Updates.verifyArchive(archive, item: resigned, key: key.publicKey)) { XCTAssertEqual($0 as? UpdateError, .badArchiveSignature) }
        XCTAssertThrowsError(try Updates.publicKey(base64: nil)) { XCTAssertEqual($0 as? UpdateError, .noPublicKey) }
    }

    func testCompatibilityAndTransport() throws {
        XCTAssertEqual(Updates.compatibility(try item(1)), .ok)
        XCTAssertEqual(Updates.compatibility(try item(1, library: librarySchemaVersion + 1)), .migration(fromLibrary: librarySchemaVersion, toLibrary: librarySchemaVersion + 1))
        XCTAssertEqual(Updates.compatibility(try item(1, system: "99.0")), .needsNewerSystem("99.0"))
        XCTAssertTrue(Updates.allowed(URL(string: "https://draft.example/feed.json")!, testMode: false))
        XCTAssertFalse(Updates.allowed(URL(string: "http://draft.example/feed.json")!, testMode: false), "never plain HTTP")
        XCTAssertFalse(Updates.allowed(URL(fileURLWithPath: "/tmp/feed.json"), testMode: false))
        XCTAssertTrue(Updates.allowed(URL(fileURLWithPath: "/tmp/feed.json"), testMode: true))
    }
}
