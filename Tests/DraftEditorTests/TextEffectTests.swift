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
        XCTAssertGreaterThanOrEqual(ColorMath.contrast(ColorMath.hex(Double(fg.redComponent), Double(fg.greenComponent), Double(fg.blueComponent)), th.pageColor), 4.4, "Increase Contrast: a readable solid color")
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

/// Renders the editor to a bitmap and reads the pixels of the run.
final class GradientRenderingTests: XCTestCase {
    func render(_ c: EditorController, _ view: NSView) -> NSBitmapImageRep {
        let rep = c.textView.bitmapImageRepForCachingDisplay(in: c.textView.bounds)!
        c.textView.cacheDisplay(in: c.textView.bounds, to: rep)
        return rep
    }
    /// Median hue of saturated pixels per column inside `rect` (view points).
    func hues(_ rep: NSBitmapImageRep, _ rect: NSRect, scale: CGFloat) -> [CGFloat] {
        var out: [CGFloat] = []
        for x in Int(rect.minX * scale)..<Int(rect.maxX * scale) {
            var hs: [CGFloat] = []
            for y in Int(rect.minY * scale)..<Int(rect.maxY * scale) {
                guard let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB), c.saturationComponent > 0.3 else { continue }
                hs.append(c.hueComponent)
            }
            if hs.count >= 2 { out.append(hs.sorted()[hs.count / 2]) }
        }
        return out
    }

    func testOneContinuousGradientThatMovesOnlyWhenAllowed() throws {
        let view = DocumentEditorView(frame: NSRect(x: 0, y: 0, width: 900, height: 400))
        let window = NSWindow(contentRect: view.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = view
        let c = view.controller
        c.load(Node("doc", content: [Node("heading", attrs: ["id": "b_h", "level": 1], content: [.text("Spectrum heading text", marks: [Mark("effect", attrs: ["kind": "spectrum", "palette": "prism", "speed": "fast", "direction": "forward"])])])]))
        view.layoutSubtreeIfNeeded()
        let gr = c.layout.glyphRange(forCharacterRange: NSRange(location: 0, length: 21), actualCharacterRange: nil)
        let o = c.textView.textContainerOrigin
        let run = c.layout.boundingRect(forGlyphRange: gr, in: c.container).offsetBy(dx: o.x, dy: o.y)
        let a = render(c, view)
        let scale = CGFloat(a.pixelsWide) / c.textView.bounds.width
        let h1 = hues(a, run, scale: scale)
        XCTAssertGreaterThan(h1.count, 40, "the run is drawn in color")
        let jumps = zip(h1, h1.dropFirst()).filter { min(abs($0 - $1), 1 - abs($0 - $1)) > 0.12 }.count
        XCTAssertLessThanOrEqual(jumps, 2, "one gradient across the phrase, not one per letter (\(jumps) jumps)")
        XCTAssertGreaterThan((h1.max() ?? 0) - (h1.min() ?? 0), 0.3, "several colors across the run")
        Thread.sleep(forTimeInterval: 0.6)
        let b = render(c, view)
        XCTAssertNotEqual(hues(b, run, scale: scale), h1, "it moves")
        var th = c.theme; th.animateEffects = false; c.theme = th
        let s1 = hues(render(c, view), run, scale: scale)
        Thread.sleep(forTimeInterval: 0.6)
        XCTAssertEqual(hues(render(c, view), run, scale: scale), s1, "still under Reduce Motion")
        // The plain Gradient effect uses the same layer: one smooth gradient, still.
        c.load(Node("doc", content: [Node("heading", attrs: ["id": "b_h", "level": 1], content: [.text("Gradient heading text", marks: [Mark("effect", attrs: ["kind": "gradient"])])])]))
        view.layoutSubtreeIfNeeded()
        let g1 = render(c, view)
        Thread.sleep(forTimeInterval: 0.3)
        XCTAssertEqual(hues(render(c, view), run, scale: scale), hues(g1, run, scale: scale), "Gradient is still")
    }
}
