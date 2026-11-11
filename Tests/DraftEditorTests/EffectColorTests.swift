import XCTest
import AppKit
import DraftCore
@testable import DraftEditor

final class EffectColorTests: XCTestCase {
    var view: DocumentEditorView!
    var window: NSWindow!
    var c: EditorController { view.controller }
    override func setUp() {
        view = DocumentEditorView(frame: NSRect(x: 0, y: 0, width: 900, height: 500))
        window = NSWindow(contentRect: view.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = view
        c.load(Node("doc", content: [Node("heading", attrs: ["id": "b_h", "level": 1], content: [.text("Colourful heading")]), Node("paragraph", attrs: ["id": "b_p"], content: [.text("Plain neighbour text")])]))
        window.makeFirstResponder(c.textView)
    }
    func hex(_ any: Any?) -> String? { (any as? NSColor)?.usingColorSpace(.sRGB).map { ColorMath.hex(Double($0.redComponent), Double($0.greenComponent), Double($0.blueComponent)) } }

    func testSpecRoundTripsAndRefusesJunk() {
        let v = "glow?color=#ff4fd8&intensity=0.80"
        XCTAssertEqual(EffectSpec(v)?.value, v)
        let g = EffectSpec("gradient?stops=#3a5bd9,#8b5cf6,#d6336c&angle=30")!
        XCTAssertEqual(g.stops?.count, 3); XCTAssertEqual(g.angle, 30)
        XCTAssertEqual(EffectSpec(mark: g.mark), g)
        XCTAssertEqual(EffectSpec("spectrum:neon:fast:backward")?.spectrum?.palette, "neon")
        for bad in ["glow?color=red", "gradient?stops=#123456", "glow?intensity=3", "glow?evil=1", "sparkle", "outline?angle=999"] { XCTAssertNil(EffectSpec(bad), bad) }
        XCTAssertNoThrow(try AgentEdit(action: "text_effect", blockId: "b_h", value: v, text: "Colourful").validate())
        XCTAssertThrowsError(try AgentEdit(action: "text_effect", blockId: "b_h", value: "glow?color=#zzzzzz", text: "Colourful").validate())
    }

    func testTextColourAndEffectColourAreIndependent() {
        let r = (c.textView.string as NSString).range(of: "Colourful")
        c.textView.setSelectedRange(r)
        c.setTextColor("#2f5bd3")
        for (kind, check) in [("glow", { (a: [NSAttributedString.Key: Any]) in self.hex((a[.shadow] as? NSShadow)?.shadowColor?.withAlphaComponent(1)) }),
                              ("shadow", { a in self.hex((a[.shadow] as? NSShadow)?.shadowColor?.withAlphaComponent(1)) }),
                              ("lift", { a in self.hex((a[.shadow] as? NSShadow)?.shadowColor?.withAlphaComponent(1)) }),
                              ("outline", { a in self.hex((a[.strokeColor] as? NSColor)?.withAlphaComponent(1)) })] {
            c.textView.setSelectedRange(r)
            c.setEffect("\(kind)?color=#c2366b&intensity=0.9")
            let a = c.storage.attributes(at: r.location, effectiveRange: nil)
            XCTAssertEqual(hex(a[.foregroundColor]), "#2f5bd3", "\(kind): the letters keep the text colour")
            XCTAssertEqual(check(a), "#c2366b", "\(kind): the effect has its own colour")
        }
        // Neighbouring text is untouched.
        let n = c.storage.attributes(at: (c.textView.string as NSString).range(of: "Plain").location, effectiveRange: nil)
        XCTAssertNil(n[.draftEffect]); XCTAssertNil(n[.shadow]); XCTAssertNil(n[.draftTextColor])
        // Persisted with both colours, and back after a reload.
        let d = c.document()
        XCTAssertEqual(d.content?[0].content?.first?.marks?.first { $0.type == "effect" }?.attrs?["color"], "#c2366b")
        XCTAssertTrue(d.content?[0].content?.first?.marks?.contains(Mark("textStyle", attrs: ["color": "#2f5bd3"])) == true)
        c.load(d); XCTAssertEqual(c.document(), d)
    }

    func testAccentAndGradientFillsStayReadable() {
        let r = (c.textView.string as NSString).range(of: "Colourful")
        c.textView.setSelectedRange(r); c.setEffect("accent?color=#fff3a3")
        let fg = hex(c.storage.attribute(.foregroundColor, at: r.location, effectiveRange: nil))!
        XCTAssertGreaterThanOrEqual(ColorMath.contrast(fg, c.theme.pageColor), 4.4, "a pale accent is darkened")
        XCTAssertTrue(EffectSpec("accent?color=#fff3a3")!.adjustedForContrast(page: c.theme.pageColor))
        XCTAssertFalse(EffectSpec("accent?color=#2f5bd3")!.adjustedForContrast(page: c.theme.pageColor))
    }

    func testLiveDragIsOneUndo() {
        let r = (c.textView.string as NSString).range(of: "Colourful")
        c.textView.setSelectedRange(r)
        let before = c.document()
        for i in stride(from: 0.1, through: 1.0, by: 0.1) { c.setEffect("glow?intensity=\(String(format: "%.2f", i))", coalescing: true) }
        XCTAssertEqual(c.storage.attribute(.draftEffect, at: r.location, effectiveRange: nil) as? String, "glow?intensity=1.00")
        c.textView.undoManager?.undo()
        XCTAssertEqual(c.document(), before, "one Undo for the whole drag")
        for i in 1...4 { c.setTextColor(["#2f5bd3", "#7b4fd6", "#c2366b", "#c75a1d"][i - 1], coalescing: true) }
        c.textView.undoManager?.undo()
        XCTAssertEqual(c.document(), before, "colour drags too")
    }

    func testGradientStopsAndAngleReachThePixels() {
        c.load(Node("doc", content: [Node("heading", attrs: ["id": "b_h", "level": 1], content: [.text("Gradient stops heading", marks: [Mark("effect", attrs: ["kind": "gradient", "stops": "#1f5fd6,#c2366b"])])])]))
        view.layoutSubtreeIfNeeded()
        let gr = c.layout.glyphRange(forCharacterRange: NSRange(location: 0, length: 22), actualCharacterRange: nil)
        let o = c.textView.textContainerOrigin
        let run = c.layout.boundingRect(forGlyphRange: gr, in: c.container).offsetBy(dx: o.x, dy: o.y)
        let rep = c.textView.bitmapImageRepForCachingDisplay(in: c.textView.bounds)!
        c.textView.cacheDisplay(in: c.textView.bounds, to: rep)
        let scale = CGFloat(rep.pixelsWide) / c.textView.bounds.width
        func hueNear(_ x: CGFloat) -> CGFloat? {
            var hs: [CGFloat] = []
            for px in Int((x - 12) * scale)..<Int((x + 12) * scale) { for py in Int(run.minY * scale)..<Int(run.maxY * scale) {
                if let col = rep.colorAt(x: px, y: py)?.usingColorSpace(.sRGB), col.saturationComponent > 0.35 { hs.append(col.hueComponent) } } }
            return hs.isEmpty ? nil : hs.sorted()[hs.count / 2]
        }
        let left = hueNear(run.minX + 14), right = hueNear(run.maxX - 14)
        XCTAssertNotNil(left); XCTAssertNotNil(right)
        XCTAssertEqual(Double(left ?? 0), Double(NSColor(hex: "#1f5fd6").hueComponent), accuracy: 0.06, "starts at the first stop")
        XCTAssertGreaterThan(Double(right ?? 0), 0.85, "ends at the berry stop")
    }
}
