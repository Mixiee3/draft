import XCTest
import AppKit
import DraftCore
@testable import DraftEditor

final class ImageInsertTests: XCTestCase {
    var window: NSWindow!
    var view: DocumentEditorView!
    let host = FakeHost()
    var c: EditorController { view.controller }

    override func setUp() {
        view = DocumentEditorView(frame: NSRect(x: 0, y: 0, width: 900, height: 700))
        window = NSWindow(contentRect: view.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = view
        c.host = host
        c.load(Node("doc", content: [Node("paragraph", attrs: ["id": "b_p"], content: [.text("before")])]))
        window.makeFirstResponder(c.textView)
    }
    func pump() { let e = expectation(description: "q"); DispatchQueue.main.async { e.fulfill() }; wait(for: [e], timeout: 2) }

    func testDroppingSeveralFilesIsOneUndoStep() {
        c.textView.setSelectedRange(NSRange(location: 6, length: 0))
        XCTAssertTrue(c.insertFiles([URL(fileURLWithPath: "/tmp/a.txt"), URL(fileURLWithPath: "/tmp/b.txt")]))
        XCTAssertEqual(c.document().content?.filter { $0.type == "file" }.count, 2)
        pump(); c.textView.undoManager?.undo()
        XCTAssertEqual(c.document().content?.filter { $0.type == "file" }.count, 0, "one Undo removes every dropped file")
        XCTAssertEqual(c.document().content?.first?.id, "b_p")
    }
}
