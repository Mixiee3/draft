import XCTest
import AppKit
import DraftCore
@testable import DraftEditor

final class PasteTests: XCTestCase {
    var window: NSWindow!
    var view: DocumentEditorView!
    var c: EditorController { view.controller }
    var tv: DraftTextView { c.textView }

    override func setUp() {
        view = DocumentEditorView(frame: NSRect(x: 0, y: 0, width: 900, height: 700))
        window = NSWindow(contentRect: view.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = view
        c.load(Node("doc", content: [
            Node("heading", attrs: ["id": "b_h", "level": 2], content: [.text("abcd")]),
            Node("paragraph", attrs: ["id": "b_p"], content: [.text("tail")]),
        ]))
        window.makeFirstResponder(tv)
    }
    func blocks() -> [Node] { c.document().content ?? [] }
    func pump() { let e = expectation(description: "q"); DispatchQueue.main.async { e.fulfill() }; wait(for: [e], timeout: 2) }

    func testMultiLinePlainPasteSplitsIntoBlocksAndKeepsSurroundingId() {
        tv.setSelectedRange(NSRange(location: 2, length: 0)) // ab|cd in the heading
        c.pastePlain("one\ntwo\nthree")
        let b = blocks()
        XCTAssertEqual(b.map(nodeText), ["abone", "two", "threecd", "tail"])
        XCTAssertEqual(b[0].id, "b_h"); XCTAssertEqual(b[0].type, "heading", "text before the caret keeps its block")
        XCTAssertEqual(b[1].type, "paragraph")
        XCTAssertEqual(Set(b.compactMap(\.id)).count, 4, "all ids unique")
        XCTAssertEqual(b[3].id, "b_p")
        pump(); tv.undoManager?.undo()
        XCTAssertEqual(blocks().map(nodeText), ["abcd", "tail"], "one undo step")
    }

    func testPasteAtStartKeepsBlockWithOriginalText() {
        tv.setSelectedRange(NSRange(location: 5, length: 0)) // |tail
        c.pastePlain("x\ny")
        let b = blocks()
        XCTAssertEqual(b.map(nodeText), ["abcd", "x", "ytail"])
        XCTAssertEqual(b[2].id, "b_p", "the paragraph holding the original text keeps its id")
    }

    func testMarkdownPasteCreatesStructure() {
        tv.setSelectedRange(NSRange(location: (tv.string as NSString).length, length: 0))
        tv.insertNewline(nil)
        c.pastePlain("## Plan\n- [ ] write\n- [x] test\n**done** today")
        let b = blocks()
        XCTAssertEqual(b.map(\.type), ["heading", "paragraph", "heading", "taskList", "paragraph"])
        XCTAssertEqual(b[3].content?.count, 2)
        XCTAssertTrue(b[4].content!.contains(.text("done", marks: [Mark("bold")])))
    }

    func testSingleLinePasteIsInline() {
        tv.setSelectedRange(NSRange(location: 2, length: 0))
        c.pastePlain("XY")
        XCTAssertEqual(blocks().map(nodeText), ["abXYcd", "tail"])
        XCTAssertEqual(blocks()[0].id, "b_h")
    }

    func testCopyPasteWithinDraftKeepsBlocksAndMarksWithNewIds() {
        let pb = NSPasteboard(name: NSPasteboard.Name("draft-test-\(UUID())"))
        tv.setSelectedRange(NSRange(location: 0, length: (tv.string as NSString).length))
        tv.writeSelection(to: pb, types: tv.writablePasteboardTypes)
        tv.setSelectedRange(NSRange(location: (tv.string as NSString).length, length: 0))
        tv.insertNewline(nil)
        XCTAssertTrue(tv.readSelection(from: pb, type: EditorController.pasteboardType))
        let b = blocks()
        XCTAssertEqual(b.map(\.type), ["heading", "paragraph", "heading", "paragraph"])
        XCTAssertEqual(b.map(nodeText), ["abcd", "tail", "abcd", "tail"])
        XCTAssertEqual(Set(b.compactMap(\.id)).count, 4)
        XCTAssertEqual(b[0].id, "b_h")
    }

    func testRichHTMLPasteMapsHeadingsListsAndMarks() throws {
        let html = "<h1>Big</h1><p>x <b>bold</b> <i>it</i> <a href=\"https://a.b\">link</a></p><ul><li>one</li><li>two</li></ul><ol><li>first</li></ol>"
        let s = try NSAttributedString(data: Data(html.utf8), options: [.documentType: NSAttributedString.DocumentType.html, .characterEncoding: String.Encoding.utf8.rawValue], documentAttributes: nil)
        tv.setSelectedRange(NSRange(location: (tv.string as NSString).length, length: 0))
        tv.insertNewline(nil)
        c.pasteRich(s)
        let b = Array(blocks().dropFirst(2))
        XCTAssertEqual(b.map(\.type), ["heading", "paragraph", "bulletList", "orderedList"])
        XCTAssertEqual(b[0].attrs?["level"], 1)
        XCTAssertTrue(b[1].content!.contains(.text("bold", marks: [Mark("bold")])))
        XCTAssertTrue(b[1].content!.contains(.text("it", marks: [Mark("italic")])))
        XCTAssertTrue(b[1].content!.contains { $0.text == "link" && $0.marks?.first?.type == "link" })
        XCTAssertEqual(b[2].content?.map(nodeText), ["one", "two"])
    }
}
