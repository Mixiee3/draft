import XCTest
import AppKit
import DraftCore
@testable import DraftEditor

final class EditorTests: XCTestCase {
    var window: NSWindow!
    var view: DocumentEditorView!
    var c: EditorController { view.controller }
    var tv: DraftTextView { c.textView }

    override func setUp() {
        view = DocumentEditorView(frame: NSRect(x: 0, y: 0, width: 900, height: 700))
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 700), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = view
        c.load(Node("doc", content: [Node("paragraph", attrs: ["id": "b_first"])]))
        window.makeFirstResponder(tv)
    }

    /// Simulates keystrokes: each character is its own event (closing undo groups) and
    /// pending main-queue work such as Markdown conversions runs in between.
    func type(_ s: String) {
        for ch in s {
            tv.insertText(String(ch), replacementRange: tv.selectedRange())
            pump()
        }
    }
    /// Drains work queued on the main queue so far (FIFO), e.g. Markdown conversions.
    func pump() {
        let e = expectation(description: "main queue drained")
        DispatchQueue.main.async { e.fulfill() }
        wait(for: [e], timeout: 2)
    }
    func blocks() -> [Node] { c.document().content ?? [] }
    func undo() { tv.undoManager?.undo() }

    func testTypingPersistsIntoDocument() {
        type("Hello world")
        XCTAssertEqual(nodeText(c.document()), "Hello world")
        XCTAssertEqual(blocks().first?.id, "b_first", "block id is stable while typing")
    }

    func testToggleBoldOnSelectionAndUndo() {
        type("Hello world")
        tv.setSelectedRange(NSRange(location: 6, length: 5))
        EditorCommands.command("mark.bold")!.run(c)
        let para = blocks()[0]
        XCTAssertEqual(para.content?.last?.marks, [Mark("bold")])
        XCTAssertEqual(para.content?.last?.text, "world")
        XCTAssertTrue(c.isMarkActive(.bold))
        undo()
        XCTAssertNil(blocks()[0].content?.last?.marks)
    }

    func testEnterAfterHeadingCreatesParagraphWithNewId() {
        type("Plan")
        EditorCommands.command("block.title")!.run(c)
        tv.insertNewline(nil)
        type("Body")
        let b = blocks()
        XCTAssertEqual(b.count, 2)
        XCTAssertEqual(b[0].type, "heading"); XCTAssertEqual(b[0].id, "b_first")
        XCTAssertEqual(b[1].type, "paragraph"); XCTAssertNotEqual(b[1].id, "b_first")
        XCTAssertEqual(nodeText(b[1]), "Body")
    }

    func testSplitInMiddleKeepsFirstIdAndText() {
        type("abcdef")
        tv.setSelectedRange(NSRange(location: 3, length: 0))
        tv.insertNewline(nil)
        let b = blocks()
        XCTAssertEqual(b.map(nodeText), ["abc", "def"])
        XCTAssertEqual(b[0].id, "b_first")
        XCTAssertEqual(Set(b.compactMap(\.id)).count, 2)
    }

    func testMarkdownHeadingTriggerAndUndoRestoresLiteral() {
        type("# ")
        XCTAssertEqual(blocks()[0].type, "heading")
        XCTAssertEqual(tv.string, "")
        pump()
        undo()
        XCTAssertEqual(tv.string, "# ")
        XCTAssertEqual(blocks()[0].type, "paragraph")
    }

    func testListTriggersEnterAndExit() {
        type("- one")
        tv.insertNewline(nil)
        type("two")
        tv.insertNewline(nil)
        tv.insertNewline(nil) // empty item exits the list
        type("after")
        let b = blocks()
        XCTAssertEqual(b[0].type, "bulletList")
        XCTAssertEqual(b[0].content?.count, 2)
        XCTAssertEqual(b[1].type, "paragraph")
        XCTAssertEqual(nodeText(b[1]), "after")
    }

    func testTaskTriggerTabNestingAndToggle() {
        type("[] buy milk")
        tv.insertNewline(nil)
        tv.insertTab(nil)
        type("oat")
        let list = blocks()[0]
        XCTAssertEqual(list.type, "taskList")
        let item = list.content![0]
        XCTAssertEqual(item.content?.last?.type, "taskList", "Tab nests under previous item")
        c.toggleTask(blockId: item.id!)
        XCTAssertEqual(blocks()[0].content![0].attrs?["checked"], .bool(true))
    }

    func testBackspaceAtStartOfBulletTurnsItIntoParagraph() {
        type("- item")
        tv.setSelectedRange(NSRange(location: 0, length: 0))
        tv.deleteBackward(nil)
        XCTAssertEqual(blocks()[0].type, "paragraph")
        XCTAssertEqual(nodeText(blocks()[0]), "item")
    }

    func testBackspaceMergeKeepsPreviousBlock() {
        type("Head")
        EditorCommands.command("block.heading")!.run(c)
        tv.insertNewline(nil)
        type("tail")
        tv.setSelectedRange(NSRange(location: 5, length: 0))
        tv.deleteBackward(nil)
        let b = blocks()
        XCTAssertEqual(b.count, 1)
        XCTAssertEqual(b[0].type, "heading"); XCTAssertEqual(b[0].id, "b_first")
        XCTAssertEqual(nodeText(b[0]), "Headtail")
    }

    func testInlineMarkdownBold() {
        type("make **this** bold")
        let p = blocks()[0]
        XCTAssertEqual(nodeText(p), "make this bold")
        XCTAssertTrue(p.content!.contains { $0.text == "this" && $0.marks == [Mark("bold")] })
        XCTAssertNil(p.content!.last?.marks, "typing after the closing ** is plain")
    }

    func testPaletteKeepsSelectionAndAppliesHighlight() {
        type("color me please")
        let sel = NSRange(location: 6, length: 2)
        tv.setSelectedRange(sel)
        c.toolbar.update()
        XCTAssertTrue(c.toolbar.isVisible)
        c.toolbar.setMode(.palette)
        let swatch = c.toolbar.items.first { $0.id == "h#c9ecf7" }!
        swatch.action!()
        XCTAssertEqual(tv.selectedRange(), sel, "selection preserved through the palette")
        let marked = blocks()[0].content!.first { $0.text == "me" }
        XCTAssertEqual(marked?.marks, [Mark("highlight", attrs: ["color": "#c9ecf7"])])
        // ⌘⇧B reapplies the same color elsewhere
        tv.setSelectedRange(NSRange(location: 0, length: 5))
        c.reapplyLastColor()
        XCTAssertEqual(blocks()[0].content!.first?.marks, [Mark("highlight", attrs: ["color": "#c9ecf7"])])
    }

    func testToolbarFlipsBelowNearTopAndClamps() {
        type("first line of the page")
        tv.setSelectedRange(NSRange(location: 0, length: 5))
        c.toolbar.update()
        let above = c.toolbar.frame
        XCTAssertLessThan(above.maxY, c.toolbar.selectionRects()!.first.minY, "normally sits above the selection")
        // Scroll so the selected line sits right under the top controls.
        view.scrollView.contentView.scroll(to: NSPoint(x: 0, y: c.toolbar.selectionRects()!.first.minY - 30))
        c.toolbar.update()
        let tb = c.toolbar.frame
        let selTop = c.toolbar.selectionRects()!.first
        XCTAssertGreaterThan(tb.minY, selTop.minY, "near the top of the visible area the bar flips below")
        XCTAssertGreaterThanOrEqual(tb.minX, view.paper.visibleRect.minX)
        XCTAssertLessThanOrEqual(tb.maxX, view.paper.visibleRect.maxX)
    }

    func testEscapeDismissesToolbar() {
        type("dismiss me")
        tv.setSelectedRange(NSRange(location: 0, length: 7))
        c.toolbar.update()
        XCTAssertTrue(c.toolbar.isVisible)
        tv.cancelOperation(nil)
        XCTAssertFalse(c.toolbar.isVisible)
    }

    func testFindReplaceAllIsOneUndo() {
        type("cat and cat and Cat")
        XCTAssertEqual(c.find("cat"), 3)
        c.replace(query: "cat", with: "dog", all: true)
        XCTAssertEqual(tv.string, "dog and dog and dog")
        pump()
        undo()
        XCTAssertEqual(tv.string, "cat and cat and Cat")
    }

    func testThemeChangeDoesNotChangeContent() {
        c.load(Seed.firstRun().docs[0].content)
        let before = c.document()
        var t = EditorTheme(); t.font = "mono"; t.separator = "tape"; t.textColor = "#ffffff"
        view.theme = t
        XCTAssertEqual(c.document(), before)
    }

    func testSlashMenuStaysInsideVisibleAreaInShortWindow() {
        view.topInset = 58
        window.setContentSize(NSSize(width: 520, height: 330))
        view.frame = NSRect(x: 0, y: 0, width: 520, height: 330)
        view.layoutSubtreeIfNeeded()
        for i in 0..<14 { type("line \(i)"); tv.insertNewline(nil) }
        type("/")
        tv.scrollRangeToVisible(tv.selectedRange())
        c.slash.position()
        XCTAssertTrue(c.slash.isOpen)
        let vis = view.paper.visibleRect
        XCTAssertTrue(vis.insetBy(dx: -1, dy: -1).contains(c.slash.frame), "\(c.slash.frame) inside \(vis)")
        XCTAssertLessThanOrEqual(view.scrollView.frame.maxY, view.bounds.height - 58, "text area starts below the top controls")
    }

    func testSlashMenuInsertsChecklist() {
        type("/check")
        XCTAssertTrue(c.slash.isOpen)
        XCTAssertEqual(c.slash.results.first?.id, "list.task")
        tv.insertNewline(nil)
        XCTAssertFalse(c.slash.isOpen)
        XCTAssertEqual(tv.string, "")
        XCTAssertEqual(blocks()[0].type, "taskList")
    }

    func testDividerTriggerAndFormatPanelCommandsShareUndo() {
        type("---")
        XCTAssertEqual(blocks()[0].type, "horizontalRule")
        XCTAssertEqual(blocks().count, 2)
        guard blocks().count == 2 else { return }
        type("x")
        EditorCommands.command("list.ordered")!.run(c)
        XCTAssertEqual(blocks()[1].type, "orderedList")
        pump()
        undo()
        XCTAssertEqual(blocks()[1].type, "paragraph")
    }
}
