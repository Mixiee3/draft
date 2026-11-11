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

final class BlockEffectTests: XCTestCase {
    func testBlockEffectsKeepContentIdsAndUndo() throws {
        let view = DocumentEditorView(frame: NSRect(x: 0, y: 0, width: 900, height: 700))
        let window = NSWindow(contentRect: view.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = view
        let c = view.controller
        c.load(Node("doc", content: [Node("heading", attrs: ["id": "b_h", "level": 2], content: [.text("Summary")]), Node("paragraph", attrs: ["id": "b_p"], content: [.text("Keep this")])]))
        window.makeFirstResponder(c.textView)
        let before = c.document()
        c.textView.setSelectedRange(NSRange(location: 9, length: 0))
        for k in BlockEffects.kinds {
            c.setDecoration(k)
            let d = c.document()
            XCTAssertEqual(d.content?[1].attrs?["decoration"], .string(k))
            XCTAssertEqual(d.content?.map { $0.attrs?["id"] }, before.content?.map { $0.attrs?["id"] }, "block IDs unchanged")
            XCTAssertEqual(d.content?[1].content, before.content?[1].content, "content unchanged")
            view.display() // draws every effect without crashing
            c.setDecoration(k) // same again removes it
            XCTAssertNil(c.document().content?[1].attrs?["decoration"])
        }
        c.setDecoration("glow")
        c.textView.undoManager?.undo()
        XCTAssertNil(c.document().content?[1].attrs?["decoration"], "one Undo")
        try c.applyAgentEdits([AgentEdit(action: "decoration", blockId: "b_h", value: "accent")])
        XCTAssertEqual(c.document().content?[0].attrs?["decoration"], "accent")
        XCTAssertThrowsError(try AgentEdit(action: "decoration", blockId: "b_h", value: "sparkle").validate())
    }
}

final class SpectrumTests: XCTestCase {
    func testSpectrumPersistsAnimatesOnlyWhenAllowedAndStaysShort() throws {
        let view = DocumentEditorView(frame: NSRect(x: 0, y: 0, width: 900, height: 700))
        let window = NSWindow(contentRect: view.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = view
        let c = view.controller
        c.load(Node("doc", content: [Node("heading", attrs: ["id": "b_h", "level": 1], content: [.text("Aurora notes")]), Node("paragraph", attrs: ["id": "b_p"], content: [.text(String(repeating: "long body text ", count: 20))])]))
        window.makeFirstResponder(c.textView)
        let r = NSRange(location: 0, length: 6)
        c.textView.setSelectedRange(r)
        c.setEffect("spectrum:neon:fast:backward")
        XCTAssertEqual(c.document().content?[0].content?.first?.marks, [Mark("effect", attrs: ["kind": "spectrum", "palette": "neon", "speed": "fast", "direction": "backward"])])
        c.textView.undoManager?.undo()
        XCTAssertNil(c.storage.attribute(.draftEffect, at: 0, effectiveRange: nil), "one Undo")
        c.textView.undoManager?.redo()
        c.load(c.document())
        XCTAssertEqual(c.storage.attribute(.draftEffect, at: 0, effectiveRange: nil) as? String, "spectrum:neon:fast:backward", "survives reload")
        view.display() // the clipped gradient draws
        XCTAssertFalse(c.layout.spectrumRects(in: c.textView.bounds, origin: .zero).isEmpty, "moving runs are redrawn")
        var th = c.theme; th.animateEffects = false; c.theme = th
        XCTAssertTrue(c.layout.spectrumRects(in: c.textView.bounds, origin: .zero).isEmpty, "Reduce Motion: still")
        th.animateEffects = true; th.plainEffects = true; c.theme = th
        let fg = (c.storage.attribute(.foregroundColor, at: 0, effectiveRange: nil) as! NSColor).usingColorSpace(.sRGB)!
        XCTAssertGreaterThanOrEqual(ColorMath.contrast(ColorMath.hex(Double(fg.redComponent), Double(fg.greenComponent), Double(fg.blueComponent)), th.pageColor), 4.4, "Increase Contrast: a readable solid colour")
        // Too long or across paragraphs: refused.
        let ns = c.storage.string as NSString
        c.textView.setSelectedRange(NSRange(location: ns.range(of: "long").location, length: 250))
        c.setEffect("spectrum")
        XCTAssertNil(c.storage.attribute(.draftEffect, at: ns.range(of: "long").location, effectiveRange: nil))
        c.textView.setSelectedRange(NSRange(location: 2, length: 20))
        c.setEffect("spectrum")
        XCTAssertNil(c.storage.attribute(.draftEffect, at: 8, effectiveRange: nil), "never across paragraphs")
    }
}
