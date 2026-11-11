import XCTest
import AppKit
import DraftCore
@testable import DraftEditor

final class RicherAgentActionTests: XCTestCase {
    func testLinksTagsDueDatesAndImagesInOneUndo() throws {
        let view = DocumentEditorView(frame: NSRect(x: 0, y: 0, width: 900, height: 700))
        let window = NSWindow(contentRect: view.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = view
        let c = view.controller
        let doc = Node("doc", content: [
            Node("paragraph", attrs: ["id": "b_p"], content: [.text("See the budget plan #old today")]),
            Node("taskList", attrs: ["id": "b_l"], content: [Node("taskItem", attrs: ["id": "b_t", "checked": false], content: [Node("paragraph", attrs: ["id": "b_tp"], content: [.text("Pay rent")])])]),
            Node("image", attrs: ["id": "b_i", "assetId": "0123456789abcdef0123456789abcdef.png", "alt": ""]),
        ])
        c.load(doc)
        window.makeFirstResponder(c.textView)
        let before = c.document()
        try c.applyAgentEdits([
            AgentEdit(action: "link_note", blockId: "b_p", value: "d_budget", text: "budget plan"),
            AgentEdit(action: "add_tag", blockId: "b_p", value: "#money"),
            AgentEdit(action: "add_tag", blockId: "b_p", value: "#money"), // already there: no duplicate
            AgentEdit(action: "remove_tag", blockId: "b_p", value: "#old"),
            AgentEdit(action: "task_due", blockId: "b_t", value: "2026-11-20"),
            AgentEdit(action: "image_caption", blockId: "b_i", text: "Receipt"),
            AgentEdit(action: "image_alt", blockId: "b_i", text: "A photo of a paper receipt"),
        ])
        let after = c.document()
        let p = after.content?[0].content ?? []
        XCTAssertTrue(p.contains { $0.text == "budget plan" && $0.marks?.contains { $0.type == "docLink" && $0.attrs?["docId"] == "d_budget" } == true }, "\(p)")
        let text = p.map { $0.text ?? "" }.joined()
        XCTAssertTrue(text.hasSuffix("#money"), text); XCTAssertFalse(text.contains("#old"), text)
        XCTAssertEqual(text.components(separatedBy: "#money").count, 2, "one tag, not two")
        XCTAssertEqual(after.content?.map { $0.attrs?["id"] }, before.content?.map { $0.attrs?["id"] }, "block ids kept")
        let task = after.content?[1].content?.first
        XCTAssertTrue(String(describing: task).contains("2026-11-20"), "due date set")
        XCTAssertEqual(after.content?[2].attrs?["caption"], "Receipt"); XCTAssertEqual(after.content?[2].attrs?["alt"], "A photo of a paper receipt")
        c.textView.undoManager?.undo()
        XCTAssertEqual(c.document(), before, "one Undo restores everything")
        XCTAssertThrowsError(try c.applyAgentEdits([AgentEdit(action: "task_due", blockId: "b_p", value: "2026-11-20")]), "not a task")
        XCTAssertThrowsError(try c.applyAgentEdits([AgentEdit(action: "image_caption", blockId: "b_p", text: "x")]), "not an image")
    }

    func testValidation() {
        XCTAssertThrowsError(try AgentEdit(action: "add_tag", blockId: "b_p", value: "money").validate())
        XCTAssertThrowsError(try AgentEdit(action: "task_due", blockId: "b_t", value: "20.11.2026").validate())
        XCTAssertThrowsError(try AgentEdit(action: "link_note", blockId: "b_p", value: "../x", text: "a").validate())
        XCTAssertThrowsError(try AgentEdit(action: "rename_folder", blockId: "f_1", expectedText: "a/b").validate())
        XCTAssertNoThrow(try AgentEdit(action: "create_style", blockId: "none", value: ##"{"base":"paper","accent":"#3a5bd9","font":"serif"}"##, expectedText: "Study").validate())
        XCTAssertThrowsError(try AgentEdit(action: "create_style", blockId: "none", value: ##"{"pageColor":"#ffffff","textColor":"#eeeeee"}"##, expectedText: "Pale").validate(), "unreadable text")
        XCTAssertThrowsError(try AgentEdit(action: "create_style", blockId: "none", value: ##"{"base":"nope"}"##, expectedText: "X").validate())
    }
}
