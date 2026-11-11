import XCTest
import AppKit
import DraftCore
@testable import DraftEditor

final class SelectionToolbarTests: XCTestCase {
    var view: DocumentEditorView!
    var window: NSWindow!
    var c: EditorController { view.controller }

    func make(width: CGFloat) {
        view = DocumentEditorView(frame: NSRect(x: 0, y: 0, width: width, height: 600))
        window = NSWindow(contentRect: view.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = view
        c.load(Node("doc", content: [Node("paragraph", attrs: ["id": "b_p"], content: [.text("Select these words to format them nicely")])]))
        window.makeFirstResponder(c.textView)
        c.textView.setSelectedRange(NSRange(location: 7, length: 11))
        c.toolbar.update()
    }

    func testGroupsLabelsAndPages() {
        make(width: 900)
        XCTAssertTrue(c.toolbar.isVisible)
        XCTAssertEqual(c.toolbar.buttonLabels.prefix(4).map { $0.components(separatedBy: " (").first! }, ["Bold", "Italic", "Underline", "Strikethrough"])
        XCTAssertTrue(c.toolbar.buttonLabels.contains("Text effects")); XCTAssertTrue(c.toolbar.buttonLabels.contains { $0.hasPrefix("More") })
        c.toolbar.setMode(.palette)
        XCTAssertTrue(c.toolbar.buttonLabels.first!.hasPrefix("Back"))
        XCTAssertEqual(c.toolbar.buttonLabels.filter { $0.hasPrefix("Highlight ") }.count, DraftPalette.highlights.count)
        c.toolbar.setMode(.effects)
        XCTAssertTrue(c.toolbar.buttonLabels.contains { $0.hasPrefix("Glow effect") })
        XCTAssertTrue(c.toolbar.buttonLabels.contains { $0.hasPrefix("Spectrum") })
        for label in c.toolbar.buttonLabels { XCTAssertFalse(label.isEmpty) }
        let children = (c.toolbar.accessibilityChildren() ?? []).compactMap { ($0 as? NSAccessibilityElement)?.accessibilityLabel() }
        XCTAssertTrue(children.contains("Effects"), "the section label is announced")
        // Applying an effect keeps the selection.
        if let p = c.toolbar.center(ofItem: "fxglow") {
            let local = c.toolbar.convert(p, from: nil)
            c.toolbar.mouseDown(with: NSEvent.mouseEvent(with: .leftMouseDown, location: c.toolbar.convert(local, to: nil), modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!)
        }
        XCTAssertEqual(c.storage.attribute(.draftEffect, at: 8, effectiveRange: nil) as? String, "glow")
        XCTAssertEqual(c.textView.selectedRange(), NSRange(location: 7, length: 11))
    }

    func testNarrowWindowWrapsInsteadOfOverflowing() {
        make(width: 420)
        c.toolbar.setMode(.effects)
        let host = c.toolbar.superview!
        XCTAssertLessThanOrEqual(c.toolbar.frame.width, max(300, host.visibleRect.width), "no wider than the editor")
        XCTAssertGreaterThan(c.toolbar.frame.height, 46, "two rows")
    }

    func testContextMenuIsForClipboardAndStructure() {
        make(width: 900)
        let gr = c.layout.glyphRange(forCharacterRange: NSRange(location: 9, length: 1), actualCharacterRange: nil)
        let rr = c.layout.boundingRect(forGlyphRange: gr, in: c.container), o = c.textView.textContainerOrigin
        let inside = c.textView.convert(NSPoint(x: rr.midX + o.x, y: rr.midY + o.y), to: nil) // right-click on the selection itself
        let e = NSEvent.mouseEvent(with: .rightMouseDown, location: inside, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        let titles = c.textView.menu(for: e)!.items.map(\.title)
        XCTAssertEqual(titles.first, "Format Selection…"); XCTAssertTrue(titles.contains("Block"))
        for gone in ["Font", "Layout Orientation", "AutoFill"] { XCTAssertFalse(titles.contains(gone), gone) }
        XCTAssertNil(c.textView.validRequestor(forSendType: nil, returnType: .tiff), "no Continuity Camera insertion")
        // Escape with the bar showing dismisses it and keeps the selection.
        c.textView.cancelOperation(nil)
        XCTAssertFalse(c.toolbar.isVisible); XCTAssertEqual(c.textView.selectedRange().length, 11)
    }
}
