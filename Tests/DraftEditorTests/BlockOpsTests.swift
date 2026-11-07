import XCTest
import AppKit
import DraftCore
@testable import DraftEditor

final class BlockOpsTests: XCTestCase {
    var window: NSWindow!
    var view: DocumentEditorView!
    var c: EditorController { view.controller }
    var tv: DraftTextView { c.textView }

    /// a, b (bold), c (task), image-ish divider, d
    let doc = Node("doc", content: [
        Node("paragraph", attrs: ["id": "b_a"], content: [.text("alpha")]),
        Node("paragraph", attrs: ["id": "b_b"], content: [.text("bravo", marks: [Mark("bold")])]),
        Node("taskList", attrs: ["id": "b_l"], content: [Node("taskItem", attrs: ["id": "b_c", "checked": true], content: [Node("paragraph", attrs: ["id": "b_cp"], content: [.text("charlie")])])]),
        Node("horizontalRule", attrs: ["id": "b_hr"]),
        Node("paragraph", attrs: ["id": "b_d"], content: [.text("delta")]),
    ])

    override func setUp() {
        view = DocumentEditorView(frame: NSRect(x: 0, y: 0, width: 900, height: 700))
        window = NSWindow(contentRect: view.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = view
        c.load(doc)
        window.makeFirstResponder(tv)
        view.layoutSubtreeIfNeeded()
    }

    func ids() -> [String] { (c.document().content ?? []).flatMap { n -> [String] in n.type == "taskList" ? (n.content ?? []).compactMap(\.id) : [n.id ?? "?"] } }
    func caret(in id: String) { tv.setSelectedRange(NSRange(location: c.paragraph(withId: id)!.location, length: 0)) }
    func pump() { let e = expectation(description: "q"); DispatchQueue.main.async { e.fulfill() }; wait(for: [e], timeout: 2) }

    func testMoveUpDownPreservesIdsMarksAndIsOneUndo() {
        let before = c.document()
        caret(in: "b_b")
        EditorCommands.command("block.moveUp")!.run(c)
        XCTAssertEqual(ids(), ["b_b", "b_a", "b_c", "b_hr", "b_d"])
        XCTAssertEqual(c.document().content?.first?.content?.first?.marks, [Mark("bold")], "marks travel with the block")
        caret(in: "b_c")
        EditorCommands.command("block.moveDown")!.run(c)
        XCTAssertEqual(ids(), ["b_b", "b_a", "b_hr", "b_c", "b_d"])
        XCTAssertTrue(c.document().content!.contains { $0.type == "taskList" && $0.content?.first?.attrs?["checked"] == .bool(true) })
        pump(); tv.undoManager?.undo()
        pump(); tv.undoManager?.undo()
        XCTAssertEqual(c.document(), before, "two undos restore the original exactly")
    }

    func testMoveLastBlockUpAndFirstToBottom() {
        caret(in: "b_d")
        c.moveSelectedBlocks(by: -1)
        XCTAssertEqual(ids(), ["b_a", "b_b", "b_c", "b_d", "b_hr"])
        caret(in: "b_a")
        c.moveSelectedBlocksToEdge(top: false)
        XCTAssertEqual(ids(), ["b_b", "b_c", "b_d", "b_hr", "b_a"])
        XCTAssertEqual(nodeText(c.document()), "bravocharliedeltaalpha")
    }

    func testEscSelectsBlockShiftExtendsDeleteRemovesUndoRestores() {
        let before = c.document()
        caret(in: "b_a")
        tv.cancelOperation(nil)
        XCTAssertEqual(c.blockSelectionIds, ["b_a"])
        tv.moveDownAndModifySelection(nil)
        XCTAssertEqual(c.blockSelectionIds, ["b_a", "b_b"])
        XCTAssertEqual(c.selectedBlockRange, 0...1)
        XCTAssertFalse(c.toolbar.isVisible, "text formatting bar stays hidden for block selections")
        tv.deleteBackward(nil)
        XCTAssertFalse(c.isBlockMode)
        XCTAssertEqual(ids(), ["b_c", "b_hr", "b_d"])
        pump(); tv.undoManager?.undo()
        XCTAssertEqual(c.document(), before)
    }

    func testBlockModeMovesAsAGroupAndTypingExitsWithoutReplacing() {
        caret(in: "b_a")
        c.enterBlockMode()
        tv.moveDownAndModifySelection(nil)
        c.moveSelectedBlocks(by: 1)
        XCTAssertEqual(ids(), ["b_c", "b_a", "b_b", "b_hr", "b_d"])
        XCTAssertEqual(c.blockSelectionIds, ["b_a", "b_b"], "moved blocks stay selected")
        tv.insertText("!", replacementRange: tv.selectedRange())
        XCTAssertFalse(c.isBlockMode)
        XCTAssertEqual(nodeText(c.document()), "charliealphabravo!delta")
    }

    func testDragDropBoundaryMapping() {
        // Drop on the lower half of "charlie" → boundary after it (index 3).
        let pr = c.paragraph(withId: "b_c")!
        let r = c.layout.paragraphRect(pr)!
        let y = r.maxY - 2 + tv.textContainerOrigin.y
        XCTAssertEqual(view.boundary(atTextViewY: y)?.0, 3)
        XCTAssertEqual(view.boundary(atTextViewY: -10)?.0, 0)
        caret(in: "b_a")
        c.moveBlocks(c.selectedBlockRange, to: 3)
        XCTAssertEqual(ids(), ["b_b", "b_c", "b_a", "b_hr", "b_d"])
    }
}
