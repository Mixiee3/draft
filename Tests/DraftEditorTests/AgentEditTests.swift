import XCTest
import AppKit
import DraftCore
@testable import DraftEditor

final class AgentEditTests: XCTestCase {
    var window: NSWindow!
    var view: DocumentEditorView!
    var controller: EditorController { view.controller }

    override func setUp() {
        view = DocumentEditorView(frame: NSRect(x: 0, y: 0, width: 900, height: 700))
        window = NSWindow(contentRect: view.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = view
        controller.host = LinkFakeHost()
        controller.load(ensureBlockIds(Node("doc", content: MarkdownImport.blocks("Garden plan\nBuy compost"))))
        window.makeFirstResponder(controller.textView)
        controller.undo.groupsByEvent = false
    }

    func boundary() { if controller.undo.groupingLevel > 0 { controller.undo.endUndoGrouping() } }

    func testTargetedEditsKeepBlockIdsAndUndoTogether() throws {
        let before = controller.document()
        let blocks = try XCTUnwrap(before.content)
        let titleId = try XCTUnwrap(blocks.first?.id)
        let bodyId = try XCTUnwrap(blocks.last?.id)
        try controller.applyAgentEdits([
            AgentEdit(action: "heading", blockId: titleId, value: "title"),
            AgentEdit(action: "replace_text", blockId: bodyId, text: "Buy **forty** bags of compost", expectedText: "Buy compost"),
            AgentEdit(action: "highlight", blockId: bodyId, value: "#fff3a3", text: "forty"),
            AgentEdit(action: "font", blockId: bodyId, value: "serif")
        ])
        let after = controller.document()
        XCTAssertEqual(after.content?.first?.id, titleId)
        XCTAssertEqual(after.content?.last?.id, bodyId)
        XCTAssertEqual(after.content?.first?.type, "heading")
        XCTAssertTrue(docPlainText(after).contains("forty bags"))
        XCTAssertEqual(after.content?.last?.attrs?["font"]?.string, "serif")
        boundary()
        controller.undo.undo()
        XCTAssertEqual(controller.document(), before)
    }

    func testStaleTextPreventsEveryChange() throws {
        let before = controller.document()
        let id = try XCTUnwrap(before.content?.last?.id)
        XCTAssertThrowsError(try controller.applyAgentEdits([
            AgentEdit(action: "heading", blockId: id, value: "heading"),
            AgentEdit(action: "replace_text", blockId: id, text: "New", expectedText: "Old")
        ]))
        XCTAssertEqual(controller.document(), before)
    }

    func testFormattingOnlyUndoesInOneStep() throws {
        let before = controller.document()
        let id = try XCTUnwrap(before.content?.last?.id)
        try controller.applyAgentEdits([
            AgentEdit(action: "block_kind", blockId: id, value: "callout"),
            AgentEdit(action: "decoration", blockId: id, value: "focus"),
            AgentEdit(action: "text_color", blockId: id, value: "#225577", text: "compost")
        ])
        let after = controller.document()
        XCTAssertEqual(after.content?.last?.type, "callout")
        XCTAssertEqual(after.content?.last?.content?.first?.attrs?["decoration"]?.string, "focus")
        boundary()
        controller.undo.undo()
        XCTAssertEqual(controller.document(), before)
    }

    func testWholeNoteReplacementIsOneUndoStep() throws {
        let before = controller.document()
        try controller.applyAgentEdits([AgentEdit(action: "replace_document", blockId: "d_test", text: "# Garden plan\n\n- Buy compost\n- Plant seeds")])
        XCTAssertEqual(controller.document().content?.count, 2)
        XCTAssertEqual(controller.document().content?.first?.id, before.content?.first?.id)
        boundary()
        controller.undo.undo()
        XCTAssertEqual(controller.document(), before)
    }

    func testDecorativeSeparatorCanBeInsertedRestyledAndUndone() throws {
        let before = controller.document()
        let anchor = try XCTUnwrap(before.content?.first?.id)
        try controller.applyAgentEdits([AgentEdit(action: "insert_separator", blockId: anchor, value: "tape")])
        let inserted = controller.document()
        let divider = try XCTUnwrap(inserted.content?.first(where: { $0.type == "horizontalRule" }))
        XCTAssertEqual(divider.attrs?["variant"]?.string, "tape")
        let dividerId = try XCTUnwrap(divider.id)
        boundary()
        try controller.applyAgentEdits([AgentEdit(action: "separator_style", blockId: dividerId, value: "wave")])
        XCTAssertEqual(controller.document().content?.first(where: { $0.id == dividerId })?.attrs?["variant"]?.string, "wave")
        boundary()
        controller.undo.undo()
        XCTAssertEqual(controller.document(), inserted)
        controller.undo.undo()
        XCTAssertEqual(controller.document(), before)
    }
}
