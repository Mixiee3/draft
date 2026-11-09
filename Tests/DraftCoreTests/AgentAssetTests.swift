import XCTest
@testable import DraftCore

final class AgentAssetTests: XCTestCase {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    override func setUp() { try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true) }
    override func tearDown() { try? FileManager.default.removeItem(at: dir) }
    func file(_ name: String, bytes: Int = 64) -> String {
        let u = dir.appendingPathComponent(name); try? Data(repeating: 7, count: bytes).write(to: u); return u.path
    }

    func testAllowedTypesSizesAndPaths() throws {
        let png = try AgentAsset.check(path: file("plan.png"), as: "insert_image")
        XCTAssertTrue(png.isImage); XCTAssertEqual(png.size, 64); XCTAssertEqual(png.sha256.count, 64)
        XCTAssertNoThrow(try AgentAsset.check(path: file("notes.pdf"), as: "insert_file"))
        XCTAssertNoThrow(try AgentAsset.check(path: file("photo.jpg"), as: "insert_file"), "an image can be attached as a file")
        XCTAssertThrowsError(try AgentAsset.check(path: file("tool.sh"), as: "insert_file"), "scripts aren't accepted")
        XCTAssertThrowsError(try AgentAsset.check(path: file("notes.pdf"), as: "insert_image"), "not an image")
        XCTAssertThrowsError(try AgentAsset.check(path: dir.appendingPathComponent("missing.png").path, as: "insert_image"))
        XCTAssertThrowsError(try AgentAsset.check(path: "relative/plan.png", as: "insert_image"))
        XCTAssertThrowsError(try AgentAsset.check(path: file("empty.png", bytes: 0), as: "insert_image"))
        XCTAssertThrowsError(try AgentAsset.check(path: file("huge.png", bytes: AgentAsset.imageLimit + 1), as: "insert_image"), "over 25 MB")
        let link = dir.appendingPathComponent("link.png")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: URL(fileURLWithPath: file("real.png")))
        XCTAssertThrowsError(try AgentAsset.check(path: link.path, as: "insert_image"), "symlinks aren't followed")
    }
}
