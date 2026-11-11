import XCTest
import AppKit
import DraftCore
@testable import DraftEditor

/// Mouse selections stop at the text: no paragraph breaks or empty blocks around them.
final class SelectionRangeTests: XCTestCase {
    var view: DocumentEditorView!
    var window: NSWindow!
    var c: EditorController { view.controller }

    override func setUp() {
        view = DocumentEditorView(frame: NSRect(x: 0, y: 0, width: 900, height: 700))
        window = NSWindow(contentRect: view.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = view
        c.load(Node("doc", content: [
            Node("heading", attrs: ["id": "b_h", "level": 2], content: [.text("Three word heading")]),
            Node("paragraph", attrs: ["id": "b_e1"]), Node("paragraph", attrs: ["id": "b_e2"]), Node("paragraph", attrs: ["id": "b_e3"]),
            Node("paragraph", attrs: ["id": "b_a"], content: [.text("First real paragraph.")]),
            Node("paragraph", attrs: ["id": "b_blank"]),
            Node("paragraph", attrs: ["id": "b_b"], content: [.text("Second real paragraph.")]),
        ]))
        window.makeFirstResponder(c.textView)
    }
    var ns: NSString { c.textView.string as NSString }

    func testTrailingAndLeadingBreaksAreDropped() {
        let h = ns.range(of: "Three word heading")
        // Heading followed by one or several empty blocks (a drag that ends below the heading).
        XCTAssertEqual(c.trimmedMouseSelection(NSRange(location: h.location, length: h.length + 1)), h)
        XCTAssertEqual(c.trimmedMouseSelection(NSRange(location: h.location, length: h.length + 3)), h)
        // Text followed by a blank paragraph, and a selection starting at the end of a line.
        let a = ns.range(of: "First real paragraph.")
        XCTAssertEqual(c.trimmedMouseSelection(NSRange(location: a.location, length: a.length + 2)), a)
        XCTAssertEqual(c.trimmedMouseSelection(NSRange(location: NSMaxRange(h), length: 4 + a.length)), a, "leading breaks and empty blocks go too")
        // Two real paragraphs: the break between them stays.
        let b = ns.range(of: "Second real paragraph.")
        let both = NSRange(location: a.location, length: NSMaxRange(b) - a.location)
        XCTAssertEqual(c.trimmedMouseSelection(both), both)
        // Only breaks selected: left alone (a single empty line can still be picked).
        XCTAssertEqual(c.trimmedMouseSelection(NSRange(location: NSMaxRange(h), length: 1)).length, 1)
    }

    func testFormatAppliesOnlyToTheTextAndUndoes() {
        let h = ns.range(of: "Three word heading")
        c.textView.setSelectedRange(c.trimmedMouseSelection(NSRange(location: h.location, length: h.length + 3)))
        c.toggleMark(.bold)
        let d = c.document()
        XCTAssertEqual(d.content?.first?.content?.first?.marks, [Mark("bold")])
        XCTAssertEqual(d.content?.count, 7, "no block merged or lost")
        XCTAssertTrue(d.content?[1...3].allSatisfy { ($0.content ?? []).isEmpty } == true, "empty blocks untouched")
        XCTAssertEqual(d.content?[1].attrs?["id"], "b_e1")
        c.load(d) // as after a relaunch
        XCTAssertEqual(c.document(), d)
        c.textView.setSelectedRange(ns.range(of: "Three word heading")); c.toggleMark(.bold)
        c.textView.undoManager?.undo()
        XCTAssertEqual(c.document(), d, "undo restores")
    }
}

final class PanelLayoutTests: XCTestCase {
    func testSidePanelNeverReflowsThePage() {
        for width: CGFloat in [1200, 960, 720] {
            let view = DocumentEditorView(frame: NSRect(x: 0, y: 0, width: width, height: 700))
            let window = NSWindow(contentRect: view.frame, styleMask: [.titled], backing: .buffered, defer: false)
            window.contentView = view
            view.controller.load(Node("doc", content: (1...40).map { Node("paragraph", attrs: ["id": .string("b_\($0)")], content: [.text("Paragraph \($0) with enough words to wrap across the page at most widths.")]) }))
            view.layoutSubtreeIfNeeded()
            let tv = view.controller.textView
            let w0 = tv.frame.width, h0 = tv.frame.height
            view.setTrailingInset(328, animated: false); view.layoutSubtreeIfNeeded()
            XCTAssertEqual(tv.frame.width, w0, "width \(width): the text column keeps its width")
            XCTAssertEqual(tv.frame.height, h0, "width \(width): nothing re-wraps")
            view.setTrailingInset(0, animated: false); view.layoutSubtreeIfNeeded()
            XCTAssertEqual(tv.frame.width, w0)
        }
    }
}
