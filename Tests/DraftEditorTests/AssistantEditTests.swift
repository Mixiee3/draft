import XCTest
import AppKit
import DraftCore
@testable import DraftEditor

final class AssistantEditTests: XCTestCase {
    var window: NSWindow!
    var view: DocumentEditorView!
    var c: EditorController { view.controller }

    override func setUp() {
        view = DocumentEditorView(frame: NSRect(x: 0, y: 0, width: 900, height: 700))
        window = NSWindow(contentRect: view.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = view
        c.host = LinkFakeHost()
        c.load(ensureBlockIds(Node("doc", content: MarkdownImport.blocks("Intro line\n\nfirst draft sentence\n\nOutro line"))))
        window.makeFirstResponder(c.textView)
    }
    var types: [String] { c.document().content?.map(\.type) ?? [] }
    var text: String { docPlainText(c.document()) }
    /// Ends the event's undo group the way AppKit does between events.
    func boundary() { c.undo.groupsByEvent = false; if c.undo.groupingLevel > 0 { c.undo.endUndoGrouping() } }

    func select(_ s: String) {
        let r = (c.textView.string as NSString).range(of: s)
        c.textView.setSelectedRange(r)
    }

    func testReplaceSelectionKeepsStructureAndUndoesInOneStep() throws {
        let before = c.document()
        select("first draft")
        let range = try XCTUnwrap(c.selectedBlocksRange)
        XCTAssertEqual(c.fragment(range).content?.count, 1)
        c.applyAssistant("## Plan\n- [ ] order compost\n- fix the pump", range: range, replace: true, actionName: "Replace with Assistant Text")
        XCTAssertEqual(types, ["paragraph", "heading", "taskList", "bulletList", "paragraph"])
        XCTAssertTrue(text.contains("order compost"))
        XCTAssertFalse(text.contains("first draft"))
        XCTAssertTrue(text.hasPrefix("Intro line"))
        XCTAssertEqual(c.undo.undoMenuItemTitle, "Undo Replace with Assistant Text")
        boundary()
        c.undo.undo()
        XCTAssertEqual(docPlainText(c.document()), docPlainText(before))
        XCTAssertEqual(c.document().content?.map(\.type), before.content?.map(\.type))
    }

    func testInsertAfterSelectionLeavesOriginalAndUndoesInOneStep() throws {
        let before = c.document()
        select("first draft")
        let range = try XCTUnwrap(c.selectedBlocksRange)
        c.applyAssistant("- one\n- two", range: range, replace: false, actionName: "Insert Assistant Text")
        XCTAssertEqual(types, ["paragraph", "paragraph", "bulletList", "paragraph"])
        XCTAssertTrue(text.contains("first draft sentence"))
        XCTAssertTrue(text.contains("one"))
        boundary()
        c.undo.undo()
        XCTAssertEqual(docPlainText(c.document()), docPlainText(before))
        XCTAssertEqual(c.document().content?.count, before.content?.count)
    }

    func testNoSelectionHasNoSelectedRange() {
        c.textView.setSelectedRange(NSRange(location: 2, length: 0))
        XCTAssertNil(c.selectedBlocksRange)
    }
}
