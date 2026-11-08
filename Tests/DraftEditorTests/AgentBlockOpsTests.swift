import XCTest
import AppKit
import DraftCore
@testable import DraftEditor

/// Block-level proposal actions: each accepted proposal is one undo step and keeps every other
/// block's id, marks and attachments.
final class AgentBlockOpsTests: XCTestCase {
    var window: NSWindow!
    var view: DocumentEditorView!
    var c: EditorController { view.controller }

    override func setUp() {
        view = DocumentEditorView(frame: NSRect(x: 0, y: 0, width: 900, height: 700))
        window = NSWindow(contentRect: view.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = view
        c.host = LinkFakeHost()
        var doc = Node("doc", content: MarkdownImport.blocks("Intro #garden\n- [ ] water the beds\nSee [the guide](https://example.com)\nLast line"))
        doc.content!.append(Node("image", attrs: ["assetId": "asset1", "alt": "Bed plan", "caption": "Bed plan"]))
        doc.content!.append(Node("pageCard", attrs: ["docId": "child1", "title": "Seed list", "presentation": "card"]))
        c.load(ensureBlockIds(doc))
        window.makeFirstResponder(c.textView)
        c.undo.groupsByEvent = false
    }

    func ids() -> [String] { c.document().content?.compactMap(\.id) ?? [] }
    /// The editable block with this text (a list item rather than its list).
    func id(_ text: String) -> String {
        var found: String?
        walk(c.document()) { n in if found == nil, nodeText(n) == text, !["bulletList", "orderedList", "taskList", "doc", "paragraph"].contains(n.type) || (n.type == "paragraph" && n.id != nil), let i = n.id, c.paragraph(withId: i) != nil { found = i } }
        return found!
    }
    func undoOnce() { if c.undo.groupingLevel > 0 { c.undo.endUndoGrouping() }; c.undo.undo() }

    func testInsertAppendMoveDeleteAreOneUndoEachAndKeepOtherBlocks() throws {
        let original = c.document(), before = ids()
        try c.applyAgentEdits([
            AgentEdit(action: "insert_blocks", blockId: id("Intro #garden"), text: "## Plan\n- step one", position: "after"),
            AgentEdit(action: "append", blockId: "doc", text: "Closing thought"),
            AgentEdit(action: "move_block", blockId: id("Last line"), target: id("Intro #garden"), position: "before"),
            AgentEdit(action: "delete_block", blockId: id("See the guide")),
        ])
        let after = c.document()
        let texts = after.content!.map(nodeText)
        XCTAssertEqual(texts.first, "Last line")
        XCTAssertTrue(texts.contains("Plan") && texts.contains("Closing thought"))
        XCTAssertFalse(texts.contains("See the guide"))
        XCTAssertTrue(after.content!.contains { $0.type == "image" } && after.content!.contains { $0.type == "pageCard" }, "attachments kept")
        XCTAssertEqual(tasksOf(after).count, 1)
        let newIds = Set(ids()).subtracting(before)
        XCTAssertEqual(newIds.count, 3, "fresh ids for the inserted heading, list item and appended paragraph")
        XCTAssertTrue(Set(before).subtracting([id("Last line")]).isSubset(of: Set(ids()).union(before)))
        undoOnce()
        XCTAssertEqual(c.document(), original)
    }

    func testAttachmentsCannotBeDeletedAndBadTargetsAreRefused() {
        let image = c.document().content!.first { $0.type == "image" }!.id!
        let card = c.document().content!.first { $0.type == "pageCard" }!.id!
        XCTAssertThrowsError(try c.applyAgentEdits([AgentEdit(action: "delete_block", blockId: image)]))
        XCTAssertThrowsError(try c.applyAgentEdits([AgentEdit(action: "delete_block", blockId: card)]))
        XCTAssertThrowsError(try c.applyAgentEdits([AgentEdit(action: "move_block", blockId: id("Last line"), target: "missing")]))
        XCTAssertThrowsError(try c.applyAgentEdits([AgentEdit(action: "task_checked", blockId: id("Last line"), value: "true")]))
    }

    func testLinksTasksAndFormattingInOneStep() throws {
        let original = c.document()
        try c.applyAgentEdits([
            AgentEdit(action: "link", blockId: id("Last line"), value: "https://draft.example/notes", text: "line"),
            AgentEdit(action: "unlink", blockId: id("See the guide"), text: "the guide"),
            AgentEdit(action: "task_checked", blockId: id("water the beds"), value: "true"),
            AgentEdit(action: "list", blockId: id("Last line"), value: "bullet"),
            AgentEdit(action: "underline", blockId: id("Intro #garden"), text: "Intro"),
            AgentEdit(action: "text_color", blockId: id("Intro #garden"), value: "#2f6fb0", text: "Intro"),
            AgentEdit(action: "decoration", blockId: id("Intro #garden"), value: "focus"),
            AgentEdit(action: "block_color", blockId: id("Intro #garden"), value: "#fff4d6"),
        ])
        let d = c.document()
        var links: [String] = []
        walk(d) { n in for m in n.marks ?? [] where m.type == "link" { links.append(m.attrs?["href"]?.string ?? "") } }
        XCTAssertEqual(links, ["https://draft.example/notes"])
        XCTAssertEqual(tasksOf(d).first?.checked, true)
        XCTAssertTrue(docPlainText(d).contains("#garden"), "tag text kept")
        undoOnce()
        XCTAssertEqual(c.document(), original)
    }
}
