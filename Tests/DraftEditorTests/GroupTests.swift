import XCTest
import AppKit
import DraftCore
@testable import DraftEditor

/// Records what the editor asks of the app.
final class FakeHost: EditorHost {
    var pages: [String: (title: String, content: Node)] = [:]
    var active: [String: Bool] = [:]
    func image(forAsset id: String) -> NSImage? { nil }
    func pageInfo(docId: String) -> (title: String, excerpt: String, tint: NSColor)? { pages[docId].map { ($0.title, "", .gray) } }
    func openPage(docId: String) {}
    func createChildPage() -> (docId: String, title: String)? { nil }
    func pickImage(_ completion: @escaping (String?) -> Void) {}
    func storeImage(data: Data, ext: String) -> String? { nil }
    func open(url: URL) {}
    func editorDidChange() {}
    func editorStateDidChange() {}
    func createGroupedPage(title: String, content: Node) -> String? {
        let id = "d_page\(pages.count)"; pages[id] = (title, content); active[id] = true; return id
    }
    func setGroupedPage(_ docId: String, active a: Bool) { active[docId] = a }
    func pageDocument(docId: String) -> (title: String, content: Node)? { active[docId] == true ? pages[docId] : nil }
    func link(toBlock blockId: String) -> URL? { URL(string: "draft://open?doc=d_this&block=\(blockId)") }
}

final class GroupTests: XCTestCase {
    var window: NSWindow!
    var view: DocumentEditorView!
    let host = FakeHost()
    var c: EditorController { view.controller }
    var tv: DraftTextView { c.textView }

    let doc = Node("doc", content: [
        Node("paragraph", attrs: ["id": "b_intro"], content: [.text("intro")]),
        Node("heading", attrs: ["id": "b_h", "level": 2], content: [.text("Plan "), .text("A", marks: [Mark("bold")])]),
        Node("taskList", attrs: ["id": "b_l"], content: [Node("taskItem", attrs: ["id": "b_t", "checked": true], content: [Node("paragraph", attrs: ["id": "b_tp"], content: [.text("buy")])])]),
        Node("pageCard", attrs: ["id": "b_card", "docId": "d_nested", "title": "Nested", "presentation": "card"]),
        Node("paragraph", attrs: ["id": "b_end"], content: [.text("end")]),
    ])

    override func setUp() {
        view = DocumentEditorView(frame: NSRect(x: 0, y: 0, width: 900, height: 700))
        window = NSWindow(contentRect: view.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = view
        c.host = host
        c.load(doc)
        window.makeFirstResponder(tv)
    }
    func blocks() -> [Node] { c.document().content ?? [] }
    func pump() { let e = expectation(description: "q"); DispatchQueue.main.async { e.fulfill() }; wait(for: [e], timeout: 2) }
    func selectBlocks(_ ids: [String]) { c.selectBlocks(ids: ids) }

    func testGroupMakesPageKeepsIdsAndUndoRedo() {
        selectBlocks(["b_h", "b_t", "b_card"])
        EditorCommands.command("block.group")!.run(c)
        let b = blocks()
        XCTAssertEqual(b.map(\.type), ["paragraph", "pageCard", "paragraph"])
        XCTAssertEqual(b[1].id, "b_h", "the card keeps the first block's id")
        XCTAssertEqual(b[1].attrs?["title"], "Plan A")
        let (title, content) = host.pages["d_page0"]!
        XCTAssertEqual(title, "Plan A")
        XCTAssertEqual(content.content?.map(\.type), ["taskList", "pageCard"])
        XCTAssertEqual(content.content?[0].content?[0].id, "b_t", "moved blocks keep ids")
        XCTAssertEqual(content.content?[0].content?[0].attrs?["checked"], .bool(true))
        XCTAssertEqual(content.content?[1].attrs?["docId"], "d_nested", "nested pages move along")
        pump(); tv.undoManager?.undo()
        XCTAssertEqual(c.document(), doc, "undo restores the parent exactly")
        XCTAssertEqual(host.active["d_page0"], false, "undo sends the page to the trash")
        pump(); tv.undoManager?.redo()
        XCTAssertEqual(blocks()[1].type, "pageCard")
        XCTAssertEqual(host.active["d_page0"], true)
    }

    func testUngroupRoundTripsExactly() {
        selectBlocks(["b_h", "b_t"])
        c.groupSelectionIntoPage()
        pump() // separate user actions are separate undo steps
        XCTAssertTrue(c.canUngroup)
        EditorCommands.command("block.ungroup")!.run(c)
        XCTAssertEqual(c.document(), doc, "group then ungroup is the identity (ids, marks, checkbox)")
        XCTAssertEqual(host.active["d_page0"], false)
        pump(); tv.undoManager?.undo()
        XCTAssertEqual(blocks()[1].type, "pageCard")
        XCTAssertEqual(host.active["d_page0"], true)
    }

    func testGroupFromTextSelectionAcrossParagraphs() {
        let a = c.paragraph(withId: "b_intro")!.location
        let e = c.paragraph(withId: "b_h")!
        tv.setSelectedRange(NSRange(location: a + 2, length: NSMaxRange(e) - a - 4))
        c.groupSelectionIntoPage()
        XCTAssertEqual(blocks().map(\.type), ["pageCard", "taskList", "pageCard", "paragraph"])
        XCTAssertEqual(host.pages["d_page0"]?.title, "intro")
        XCTAssertEqual(host.pages["d_page0"]?.content.content?.first?.id, "b_h")
    }

    func testDuplicateAndCopyLinkAndMenu() {
        selectBlocks(["b_intro"])
        c.duplicateSelectedBlocks()
        let b = blocks()
        XCTAssertEqual(b.prefix(2).map(nodeText), ["intro", "intro"])
        XCTAssertEqual(b[0].id, "b_intro"); XCTAssertNotEqual(b[1].id, "b_intro")
        XCTAssertEqual(c.blockSelectionIds, [b[1].id!], "the copy is selected")
        c.copyLinkToBlock()
        XCTAssertEqual(NSPasteboard.general.string(forType: .string), "draft://open?doc=d_this&block=\(b[1].id!)")
        let menu = c.blockMenu()
        XCTAssertEqual(menu.items.filter { !$0.isSeparatorItem }.map(\.title),
                       ["Turn Into", "Duplicate Block", "Copy Link to Block", "Group into Page", "Ungroup Page", "Move Block Up", "Move Block Down", "Delete Block"])
        XCTAssertFalse(menu.item(withTitle: "Ungroup Page")!.isEnabled, "only a page can be ungrouped")
        // Turn Into → Checklist through the menu item itself
        let checklist = menu.item(withTitle: "Turn Into")!.submenu!.item(withTitle: "Checklist") as! ClosureMenuItem
        checklist.fire()
        XCTAssertEqual(blocks()[1].type, "taskList")
    }

    func testGroupIsDisabledForEmptyLines() {
        c.load(Node("doc", content: [Node("paragraph", attrs: ["id": "b_x"])]))
        XCTAssertFalse(c.canGroup)
        XCTAssertFalse(EditorCommands.command("block.group")!.isEnabled(c))
    }
}
