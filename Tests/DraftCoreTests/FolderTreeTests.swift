import XCTest
@testable import DraftCore

final class FolderTreeTests: XCTestCase {
    func f(_ id: String, _ parent: String?, _ order: Double) -> Folder {
        Folder(id: id, name: id, parentId: parent, order: order)
    }

    func testChildrenShowOnlyWhenParentExpandedAndFollowParent() {
        let folders = [f("a", nil, 0), f("b", nil, 1), f("a1", "a", 2), f("a2", "a", 3)]
        let collapsed = FolderTree.rows(folders, expanded: [])
        XCTAssertEqual(collapsed.map(\.folder.id), ["a", "b"])
        let open = FolderTree.rows(folders, expanded: ["a"])
        XCTAssertEqual(open.map(\.folder.id), ["a", "a1", "a2", "b"])
        XCTAssertEqual(open.map(\.depth), [0, 1, 1, 0])
    }

    func testNestedDepthAndOrderFollowsSortOrder() {
        let folders = [f("c", "b", 5), f("b", "a", 1), f("a", nil, 0)]
        let rows = FolderTree.rows(folders, expanded: ["a", "b"])
        XCTAssertEqual(rows.map(\.folder.id), ["a", "b", "c"])
        XCTAssertEqual(rows.map(\.depth), [0, 1, 2])
    }

    func testFolderWithMissingParentIsShownAtTopLevel() {
        let folders = [f("orphan", "gone", 0), f("a", nil, 1)]
        let rows = FolderTree.rows(folders, expanded: [])
        XCTAssertEqual(rows.map(\.folder.id), ["orphan", "a"])
        XCTAssertEqual(rows.map(\.depth), [0, 0])
    }
}
