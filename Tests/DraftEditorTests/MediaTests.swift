import XCTest
import AppKit
import DraftCore
@testable import DraftEditor

final class MediaTests: XCTestCase {
    var window: NSWindow!
    var view: DocumentEditorView!
    let host = FakeHost()
    var c: EditorController { view.controller }
    var tv: DraftTextView { c.textView }

    override func setUp() {
        view = DocumentEditorView(frame: NSRect(x: 0, y: 0, width: 900, height: 700))
        window = NSWindow(contentRect: view.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = view
        c.host = host
        c.load(Node("doc", content: [Node("paragraph", attrs: ["id": "b_p"], content: [.text("before")])]))
        window.makeFirstResponder(tv)
        tv.setSelectedRange(NSRange(location: 6, length: 0))
        c.insertImage(assetId: "abcdef0123456789.png")
    }
    func pump() { let e = expectation(description: "q"); DispatchQueue.main.async { e.fulfill() }; wait(for: [e], timeout: 2) }
    func image() -> Node { c.document().content!.first { $0.type == "image" }! }
    func selectImage() { tv.setSelectedRange(NSRange(location: c.paragraph(withId: image().id!)!.location, length: 1)) }
    func cell() -> ImageCell { (c.storage.attribute(.attachment, at: c.paragraph(withId: image().id!)!.location, effectiveRange: nil) as! NSTextAttachment).attachmentCell as! ImageCell }

    func testImageBarSizeCaptionAltAndUndo() {
        selectImage()
        XCTAssertTrue(c.imageBar.isVisible)
        XCTAssertFalse(c.toolbar.isVisible)
        let fullHeight = cell().height(forWidth: 600)
        c.imageBar.size.selectedSegment = 1
        c.imageBar.sizeChanged()
        XCTAssertEqual(image().attrs?["width"], 0.5)
        XCTAssertLessThan(cell().height(forWidth: 600), fullHeight)
        c.imageBar.caption.stringValue = "Harbour at dawn"
        c.imageBar.commit(c.imageBar.caption)
        XCTAssertEqual(image().attrs?["caption"], "Harbour at dawn")
        XCTAssertEqual(cell().height(forWidth: 600), cell().imageSize(forWidth: 600).height + ImageCell.captionHeight)
        c.imageBar.alt.stringValue = "Boats in fog"
        c.imageBar.commit(c.imageBar.alt)
        XCTAssertEqual(image().attrs?["alt"], "Boats in fog")
        XCTAssertEqual(cell().accessibilityLabel(), "Image: Boats in fog")
        XCTAssertEqual(tv.selectedRange().length, 1, "editing the image keeps it selected")
        pump(); tv.undoManager?.undo()
        XCTAssertEqual(image().attrs?["alt"], "", "each change is its own undo step")
        let (s, t) = Converter.attributed(from: c.document())
        XCTAssertEqual(Converter.document(from: s, trailing: t), c.document())
    }

    func testDragResizeKeepsFractionAndShrinks() {
        let size = cell().imageSize(forWidth: 600)
        XCTAssertEqual(size.width, 600, accuracy: 0.5, "large images fill the width by default")
        c.updateAttachment(at: c.paragraph(withId: image().id!)!.location) { $0[attr: "width"] = 0.25 }
        XCTAssertEqual(cell().imageSize(forWidth: 600).width, 150, accuracy: 0.5)
        XCTAssertEqual(cell().imageRect(in: NSRect(x: 0, y: 0, width: 600, height: 100)).midX, 300, accuracy: 0.5, "smaller images are centered")
    }

    func testFilesInsertOpenPasteAndExport() throws {
        c.insertFileFromPicker()
        let file = c.document().content!.first { $0.type == "file" }!
        XCTAssertEqual(file.attrs?["name"], "Plan.pdf")
        XCTAssertEqual(file.attrs?["size"], 2048)
        let loc = c.paragraph(withId: file.id!)!.location
        let fc = (c.storage.attribute(.attachment, at: loc, effectiveRange: nil) as! NSTextAttachment).attachmentCell as! FileCell
        XCTAssertEqual(fc.accessibilityLabel(), "File: Plan.pdf")
        let down = NSEvent.mouseEvent(with: .leftMouseDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        _ = fc.trackMouse(with: down, in: .zero, of: tv, untilMouseUp: true)
        pump()
        XCTAssertEqual(host.opened, ["Plan.pdf"])
        // A file copied in Finder pastes as a file block.
        let pb = NSPasteboard(name: NSPasteboard.Name("draft-test-\(UUID())"))
        pb.clearContents()
        pb.writeObjects([URL(fileURLWithPath: "/tmp/notes.txt") as NSURL])
        XCTAssertTrue(tv.readSelection(from: pb, type: .fileURL))
        XCTAssertTrue(c.document().content!.contains { $0.type == "file" && $0.attrs?["name"] == "notes.txt" })
        XCTAssertTrue(attachmentsOf(c.document()).contains { $0.kind == "file" })
    }
}
