import XCTest
import AppKit
import DraftCore
@testable import DraftEditor

final class StyleEditorTests: XCTestCase {
    var window: NSWindow!
    var view: DocumentEditorView!
    var c: EditorController { view.controller }
    let host = LinkFakeHost()

    override func setUp() {
        view = DocumentEditorView(frame: NSRect(x: 0, y: 0, width: 900, height: 700))
        window = NSWindow(contentRect: view.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = view
        c.host = host
        c.load(Node("doc", content: [
            Node("paragraph", attrs: ["id": "b_a"], content: [.text("plain")]),
            Node("heading", attrs: ["id": "b_h", "level": 2, "font": "mono"], content: [.text("Mono heading")]),
            Node("taskList", attrs: ["id": "b_l"], content: [Node("taskItem", attrs: ["id": "b_t", "checked": false, "font": "rounded"], content: [Node("paragraph", attrs: ["id": "b_tp"], content: [.text("task")])])]),
            Node("codeBlock", attrs: ["id": "b_c"], content: [.text("x = 1")]),
            Node("pageCard", attrs: ["id": "b_card", "docId": "d_plan", "title": "Plan", "presentation": "card"]),
        ]))
        window.makeFirstResponder(c.textView)
    }
    func pump() { let e = expectation(description: "q"); DispatchQueue.main.async { e.fulfill() }; wait(for: [e], timeout: 2) }

    func testBlockFontRoundTripsAndSurvivesRestyle() {
        let doc = c.document()
        XCTAssertEqual(doc.content?[1].attrs?["font"], "mono")
        XCTAssertEqual(doc.content?[2].content?.first?.attrs?["font"], "rounded", "list items keep their font")
        let h = c.paragraph(withId: "b_h")!.location
        let monoName = (c.storage.attribute(.font, at: h, effectiveRange: nil) as! NSFont).fontName
        var th = c.theme; th.font = "serif"; c.theme = th // restyle the whole document
        XCTAssertEqual((c.storage.attribute(.font, at: h, effectiveRange: nil) as! NSFont).fontName, monoName, "a block font wins over the document font")
        let a = c.paragraph(withId: "b_a")!.location
        c.textView.setSelectedRange(NSRange(location: a, length: 0))
        EditorCommands.command("font.mono")!.run(c)
        XCTAssertEqual(c.document().content?.first?.attrs?["font"], "mono")
        XCTAssertTrue(EditorCommands.command("font.mono")!.isActive(c))
        pump(); c.textView.undoManager?.undo()
        XCTAssertNil(c.document().content?.first?.attrs?["font"], "one undo")
        let code = c.paragraph(withId: "b_c")!.location
        c.textView.setSelectedRange(NSRange(location: code, length: 0))
        c.setBlockFont("serif")
        XCTAssertNil(c.document().content?[3].attrs?["font"], "code blocks stay mono")
    }

    func testCardSizeAndPreviewAreStoredAndUndoable() {
        let card = c.paragraph(withId: "b_card")!.location
        c.textView.setSelectedRange(NSRange(location: card, length: 0))
        c.setCardOption("size", "feature")
        pump()
        c.setCardOption("preview", "gallery")
        let n = c.document().content?.last
        XCTAssertEqual(n?.attrs?["size"], "feature"); XCTAssertEqual(n?.attrs?["preview"], "gallery")
        XCTAssertEqual(n?.attrs?["docId"], "d_plan", "the card still points at its page")
        let h = c.layout.paragraphRect(c.paragraph(withId: "b_card")!)?.height ?? 0
        XCTAssertGreaterThan(h, 150, "feature cards are tall")
        pump(); c.textView.undoManager?.undo()
        XCTAssertNil(c.document().content?.last?.attrs?["preview"])
        XCTAssertEqual(c.document().content?.last?.attrs?["size"], "feature")
    }

    func testPastedURLBecomesPreviewOnlyWhenTurnedOn() {
        c.load(Node("doc", content: [Node("paragraph", attrs: ["id": "b_a"])]))
        c.pastePlainForAutomation("https://www.example.com/post")
        XCTAssertEqual(c.document().content?.first?.type, "paragraph", "off by default: plain text")
        XCTAssertTrue(host.fetched.isEmpty, "no network request when off")
        c.load(Node("doc", content: [Node("paragraph", attrs: ["id": "b_a"])]))
        host.previews = true
        c.pastePlainForAutomation("https://www.example.com/post")
        XCTAssertEqual(c.document().content?.first?.type, "linkPreview")
        XCTAssertEqual(c.document().content?.first?.attrs?["title"], "example.com")
        XCTAssertEqual(host.fetched.first?.absoluteString, "https://www.example.com/post")
        pump()
        let undoBefore = c.undo.canUndo
        host.pending?(LinkPreview(url: "https://www.example.com/post", title: "A Post", summary: "Short", site: "example.com"))
        XCTAssertEqual(c.document().content?.first?.attrs?["title"], "A Post")
        XCTAssertEqual(c.undo.canUndo, undoBefore, "filling in the card adds no undo step")
        let md = Markdown.render(DocFile(id: "x", title: "T", content: c.document(), appearance: DocumentAppearance(styleId: "paper"), createdAt: 0, updatedAt: 0), assetPath: { $0 }, pageLink: { _, _ in nil }).markdown
        XCTAssertTrue(md.contains("[A Post](https://www.example.com/post)"), md)
        pump(); c.textView.undoManager?.undo()
        XCTAssertNotEqual(c.document().content?.first?.type, "linkPreview", "one undo removes the card")
    }
}
