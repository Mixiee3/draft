import XCTest
import AppKit
import DraftCore
@testable import DraftEditor

final class SketchTests: XCTestCase {
    func sample() -> Sketch {
        Sketch(strokes: [Sketch.Stroke(tool: "pen", color: "ink", width: 3, points: [10, 10, 0.5, 120.04, 80, 0.7, 200, 160, 0.4]),
                         Sketch.Stroke(tool: "highlighter", color: "#f5a524", width: 4, points: [300, 300, 0.5, 500, 310, 0.5])])
    }

    func testRoundTripsThroughTheNoteFormat() throws {
        let s = sample()
        let node = Node("image", attrs: ["assetId": "a.png", "sketch": s.json])
        let decoded = try JSONDecoder().decode(Node.self, from: DraftJSON.encode(node))
        let back = try XCTUnwrap(Sketch(decoded.attrs?["sketch"]))
        XCTAssertEqual(back.strokes.count, 2)
        XCTAssertEqual(back.strokes[0].points[3], 120, accuracy: 0.05, "points are kept to one decimal")
        XCTAssertEqual(back.strokes[1].color, "#f5a524")
        XCTAssertNil(Sketch(nil), "plain images are not sketches")
    }

    func testRendersAPictureForExports() throws {
        let png = try XCTUnwrap(SketchRenderer.png(sample()))
        let rep = try XCTUnwrap(NSBitmapImageRep(data: png))
        XCTAssertEqual(rep.pixelsWide, 1600, "2× the canvas")
        XCTAssertTrue(rep.hasAlpha, "transparent background so it sits on any page")
        // A pixel on the pen stroke is inked; a far corner stays transparent.
        XCTAssertGreaterThan(rep.colorAt(x: 10 * 2, y: 10 * 2)?.alphaComponent ?? 0, 0.5, "the pen stroke starts at canvas (10, 10)")
        XCTAssertEqual(rep.colorAt(x: 1590, y: 10)?.alphaComponent ?? 1, 0, accuracy: 0.01)
    }

    func testEraserUndoAndRedo() {
        let canvas = SketchCanvas(frame: NSRect(x: 0, y: 0, width: 800, height: 500))
        canvas.sketch = sample()
        canvas.tool = "eraser"
        let down = NSEvent.mouseEvent(with: .leftMouseDown, location: NSPoint(x: 120, y: 500 - 80), modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        canvas.mouseDown(with: down)
        XCTAssertEqual(canvas.sketch.strokes.count, 1, "the touched stroke is erased whole")
        canvas.undo()
        XCTAssertEqual(canvas.sketch.strokes.count, 2)
        canvas.redo()
        XCTAssertEqual(canvas.sketch.strokes.count, 1)
    }

    /// A 400×300 "photo" of white paper with a black line at the top-left and a red blob at the right.
    func paperSketch() -> Data {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 400, pixelsHigh: 300, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor.white.setFill(); NSRect(x: 0, y: 0, width: 400, height: 300).fill()
        NSColor.black.setFill(); NSRect(x: 100, y: 200, width: 120, height: 10).fill()      // y from the bottom: near the top
        NSColor(red: 0.9, green: 0.1, blue: 0.1, alpha: 1).setFill(); NSRect(x: 260, y: 100, width: 20, height: 20).fill()
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])!
    }

    func testIPhoneSketchInkIsLiftedOffThePaperAndTrimmed() throws {
        let out = try XCTUnwrap(InkImage.lift(paperSketch()))
        let rep = try XCTUnwrap(NSBitmapImageRep(data: out))
        XCTAssertLessThan(rep.pixelsWide, 400, "trimmed to the strokes")
        XCTAssertLessThan(rep.pixelsHigh, 300)
        XCTAssertGreaterThan(rep.pixelsWide, 180, "both strokes kept")
        var transparent = 0, black = 0, red = 0
        for y in 0..<rep.pixelsHigh { for x in 0..<rep.pixelsWide {
            guard let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
            if c.alphaComponent < 0.02 { transparent += 1 }
            else if c.alphaComponent > 0.9 && c.redComponent < 0.1 { black += 1 }
            else if c.alphaComponent > 0.9 && c.redComponent > 0.8 && c.greenComponent < 0.25 { red += 1 }
        } }
        XCTAssertGreaterThan(transparent, rep.pixelsWide * rep.pixelsHigh / 2, "the paper is gone")
        XCTAssertGreaterThan(black, 900, "black ink stays solid")
        XCTAssertGreaterThan(red, 300, "coloured ink keeps its colour")
        XCTAssertNil(InkImage.lift(blankPaper()), "blank paper has no ink")
    }

    func blankPaper() -> Data {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 50, pixelsHigh: 50, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor.white.setFill(); NSRect(x: 0, y: 0, width: 50, height: 50).fill(); NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])!
    }
}
