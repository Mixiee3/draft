import XCTest
@testable import DraftCore

final class VaultQueueTests: XCTestCase {
    func vault() -> Vault { Vault(dir: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)) }

    /// Saves run off the main thread; a read right after them must see the last one.
    func testQueuedWritesKeepOrderAndReadsWaitForThem() throws {
        let v = vault()
        for i in 0..<50 {
            var d = DocFile.empty(id: "d_q", title: "Version \(i)")
            d.updatedAt = Double(i)
            v.enqueue({ try v.saveDoc(d) }, failed: { e in XCTFail("\(e)") })
        }
        XCTAssertEqual(try v.loadDoc("d_q")?.title, "Version 49")
    }

    func testCurrentDocumentsKeepUnknownFieldsOnTheFastPath() throws {
        let json = #"{"schemaVersion":\#(docSchemaVersion),"id":"d_x","title":"T","createdAt":1,"updatedAt":2,"appearance":{"styleId":"paper","overrides":{}},"content":{"type":"doc","content":[{"type":"paragraph"}]},"futureField":{"a":1}}"#
        let (doc, migrated, _) = try Migrations.migrateDoc(Data(json.utf8))
        XCTAssertFalse(migrated)
        XCTAssertEqual(doc.extra["futureField"], .object(["a": .number(1)]))
        XCTAssertNotNil(doc.content.content?.first?.id, "blocks still get ids")
        XCTAssertTrue(String(decoding: try DraftJSON.encode(doc), as: UTF8.self).contains("futureField"))
    }
}
