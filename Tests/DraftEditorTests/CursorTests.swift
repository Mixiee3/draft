import XCTest
import AppKit
import DraftCore
@testable import DraftEditor

final class CursorTests: XCTestCase {
    var window: NSWindow!
    var view: DocumentEditorView!
    let host = LinkFakeHost()
    var c: EditorController { view.controller }
    var tv: DraftTextView { c.textView }

    override func setUp() {
        view = DocumentEditorView(frame: NSRect(x: 0, y: 0, width: 900, height: 700))
        window = NSWindow(contentRect: view.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = view
        c.host = host
        c.load(Node("doc", content: [
            Node("paragraph", attrs: ["id": "b_p"], content: [.text("Plain text and "), .text("Plan", marks: [Mark("docLink", attrs: ["docId": "d_plan"])]), .text(" link")]),
            Node("taskList", attrs: ["id": "b_l"], content: [Node("taskItem", attrs: ["id": "b_t", "checked": false], content: [Node("paragraph", attrs: ["id": "b_tp"], content: [.text("a task")])])]),
            Node("pageCard", attrs: ["id": "b_c", "docId": "d_plan", "title": "Plan", "presentation": "card"]),
            Node("paragraph", attrs: ["id": "b_end"], content: [.text("end")]),
        ]))
        view.layoutSubtreeIfNeeded()
        c.layout.ensureLayout(for: c.container)
    }

    /// Point in text-view coordinates at the middle of a character.
    func point(_ loc: Int) -> NSPoint {
        let gr = c.layout.glyphRange(forCharacterRange: NSRange(location: loc, length: 1), actualCharacterRange: nil)
        let r = c.layout.boundingRect(forGlyphRange: gr, in: c.container)
        return NSPoint(x: r.midX + tv.textContainerOrigin.x, y: r.midY + tv.textContainerOrigin.y)
    }

    func testCursorFollowsContent() {
        XCTAssertEqual(tv.cursor(at: point(2)), .iBeam, "editable text")
        XCTAssertEqual(tv.cursor(at: point(16)), .pointingHand, "link chip")
        let card = c.paragraph(withId: "b_c")!.location
        XCTAssertEqual(tv.cursor(at: point(card)), .arrow, "cards act on click, not text")
        let task = c.paragraph(withId: "b_t")!
        let box = c.layout.checkboxRect(forParagraphAt: task)!
        XCTAssertEqual(tv.cursor(at: NSPoint(x: box.midX + tv.textContainerOrigin.x, y: box.midY + tv.textContainerOrigin.y)), .pointingHand, "checkbox")
        XCTAssertEqual(tv.cursor(at: NSPoint(x: tv.textContainerOrigin.x - 30, y: point(2).y)), .arrow, "page margin")
        XCTAssertEqual(tv.cursor(at: NSPoint(x: point(2).x, y: tv.textContainerOrigin.y + c.layout.usedRect(for: c.container).maxY + 200)), .arrow, "empty space below the text")
        tv.isEditable = false
        XCTAssertEqual(tv.cursor(at: point(2)), .arrow, "read-only documents are viewed with the arrow")
    }

    func testOverlaysUseTheArrowAndLeavingResetsIt() {
        tv.setSelectedRange(NSRange(location: 0, length: 5))
        c.toolbar.update()
        c.toolbar.cursorUpdate(with: NSEvent())
        XCTAssertEqual(NSCursor.current, .arrow)
        NSCursor.iBeam.set()
        view.removeFromSuperview()
        XCTAssertEqual(NSCursor.current, .arrow, "changing tabs never leaves the I-beam behind")
    }
}
