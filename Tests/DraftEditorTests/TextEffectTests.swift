import XCTest
import AppKit
import DraftCore
@testable import DraftEditor

final class TextEffectTests: XCTestCase {
    var window: NSWindow!
    var view: DocumentEditorView!
    var c: EditorController { view.controller }

    override func setUp() {
        view = DocumentEditorView(frame: NSRect(x: 0, y: 0, width: 900, height: 700))
        window = NSWindow(contentRect: view.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = view
        c.load(Node("doc", content: [Node("paragraph", attrs: ["id": "b_a"], content: [.text("Light reactions matter")])]))
        window.makeFirstResponder(c.textView)
    }

    func attrs(at i: Int) -> [NSAttributedString.Key: Any] { c.storage.attributes(at: i, effectiveRange: nil) }

    func testEffectsPersistRenderUndoAndKeepSelection() {
        let text = c.storage.string as NSString
        let r = text.range(of: "reactions")
        c.textView.setSelectedRange(r)
        c.setEffect("glow")
        XCTAssertEqual(c.textView.selectedRange(), r, "the selection stays")
        XCTAssertNotNil(attrs(at: r.location)[.shadow], "glow draws a shadow")
        XCTAssertEqual(c.document().content?[0].content?[1].marks, [Mark("effect", attrs: ["kind": "glow"])])
        XCTAssertEqual(c.document().content?[0].content?.map { $0.text ?? "" }.joined(), "Light reactions matter", "text unchanged")
        c.textView.undoManager?.undo()
        XCTAssertNil(c.document().content?[0].content?.first?.marks, "one Undo removes the effect")
        c.textView.undoManager?.redo()

        // Reload keeps it; every effect stays readable and Increase Contrast drops the decoration.
        let doc = c.document(); c.load(doc)
        XCTAssertEqual(attrs(at: r.location)[.draftEffect] as? String, "glow")
        for k in TextEffects.kinds {
            c.textView.setSelectedRange(r); c.setEffect(k)
            let fg = (attrs(at: r.location)[.foregroundColor] as! NSColor).usingColorSpace(.sRGB)!
            XCTAssertGreaterThanOrEqual(ColorMath.contrast(ColorMath.hex(Double(fg.redComponent), Double(fg.greenComponent), Double(fg.blueComponent)), c.theme.pageColor), 4.4, k)
        }
        c.textView.setSelectedRange(r); c.setEffect("outline")
        XCTAssertNotNil(attrs(at: r.location)[.strokeWidth])
        var th = c.theme; th.plainEffects = true; c.theme = th
        XCTAssertNil(attrs(at: r.location)[.strokeWidth]); XCTAssertNil(attrs(at: r.location)[.shadow])
        c.textView.setSelectedRange(r); c.setEffect(nil)
        XCTAssertNil(attrs(at: r.location)[.draftEffect])
    }

    func testAgentTextEffect() throws {
        try c.applyAgentEdits([AgentEdit(action: "text_effect", blockId: "b_a", value: "gradient", text: "Light")])
        XCTAssertEqual(c.document().content?[0].content?.first?.marks, [Mark("effect", attrs: ["kind": "gradient"])])
        XCTAssertThrowsError(try AgentEdit(action: "text_effect", blockId: "b_a", value: "sparkle", text: "Light").validate())
    }
}
