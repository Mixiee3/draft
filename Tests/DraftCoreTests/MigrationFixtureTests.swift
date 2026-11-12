import XCTest
@testable import DraftCore

/// Every schema Draft has written, validated on a copy and migrated for real in a throwaway vault.
final class MigrationFixtureTests: XCTestCase {
    func fixture(_ name: String) throws -> URL {
        let src = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures/vaults/\(name)")
        let dst = FileManager.default.temporaryDirectory.appendingPathComponent("mig-\(name)-" + UUID().uuidString)
        try FileManager.default.copyItem(at: src, to: dst)
        return dst
    }
    func bytes(_ dir: URL) -> [String: Data] {
        var out: [String: Data] = [:]
        for case let u as URL in FileManager.default.enumerator(at: dir.resolvingSymlinksInPath(), includingPropertiesForKeys: nil)! where !u.hasDirectoryPath {
            out[u.lastPathComponent] = try? Data(contentsOf: u)
        }
        return out
    }

    func testValidatorReadsEveryFixtureWithoutWriting() throws {
        let expect: [(String, Int, Int, Bool)] = [("v0", 0, 3, true), ("v1", 1, 1, true), ("v2", 2, 0, false)]
        for (name, schema, changes, needs) in expect {
            let dir = try fixture(name)
            let before = bytes(dir)
            let r = try MigrationValidator.validate(vault: dir)
            XCTAssertEqual(bytes(dir), before, "\(name): the real vault is untouched")
            XCTAssertTrue(r.ok, "\(name): \(r.problems)")
            XCTAssertEqual(r.librarySchema, schema, name)
            XCTAssertEqual(r.expectedChanges.count, changes, "\(name): \(r.expectedChanges)")
            XCTAssertEqual(r.needsMigration, needs, name)
        }
        let v0 = try MigrationValidator.validate(vault: fixture("v0"))
        XCTAssertTrue(v0.unknownFields.contains("library.json: legacyFlag"), "\(v0.unknownFields)")
        XCTAssertTrue(v0.unknownFields.contains("docs/d_old.json: mysteryField"), "\(v0.unknownFields)")
    }

    func testRealMigrationKeepsEverythingAndRollsBack() throws {
        for name in ["v0", "v1"] {
            let dir = try fixture(name)
            let originalLibrary = try Data(contentsOf: dir.appendingPathComponent("library.json"))
            let v = Vault(dir: dir)
            let lib = try XCTUnwrap(try v.loadLibrary())
            XCTAssertNotNil(lib.docs.values.first?.spaceId, name)
            for id in lib.docs.keys { XCTAssertEqual(try v.loadDoc(id)?.schemaVersion, docSchemaVersion) }
            if name == "v0" {
                XCTAssertEqual(lib.extra["legacyFlag"], .bool(true), "unknown library field kept")
                XCTAssertEqual(try v.loadDoc("d_old")?.extra["mysteryField"], "keep me", "unknown note field kept")
            } else {
                XCTAssertEqual(lib.docs["d_child"]?.parentDocId, "d_parent")
                XCTAssertEqual(lib.folders.first?.name, "Work")
                XCTAssertEqual(lib.docs["d_parent"]?.starred, true)
            }
            XCTAssertTrue(VaultCheck.run(Vault(dir: dir)).issues.filter { $0.severity > .info }.isEmpty)
            let plan = MigrationValidator.rollbackPlan(v)
            XCTAssertTrue(plan.writes.keys.contains("library.json"), name)
            _ = try VaultRepair.apply(plan, vault: v, kind: "rollback", summary: "Roll back migration", fixes: [])
            XCTAssertEqual(try Data(contentsOf: dir.appendingPathComponent("library.json")), originalLibrary, "\(name): rollback restores the old library")
        }
    }
}
