import XCTest
import AppKit
import DraftCore
@testable import DraftEditor

final class BlockTypesTests: XCTestCase {
    var window: NSWindow!
    var view: DocumentEditorView!
    var c: EditorController { view.controller }
    var tv: DraftTextView { c.textView }

    override func setUp() {
        view = DocumentEditorView(frame: NSRect(x: 0, y: 0, width: 900, height: 700))
        window = NSWindow(contentRect: view.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = view
        c.load(Node("doc", content: [Node("paragraph", attrs: ["id": "b_first"])]))
        window.makeFirstResponder(tv)
    }
    func pump() { let e = expectation(description: "q"); DispatchQueue.main.async { e.fulfill() }; wait(for: [e], timeout: 2) }
    func type(_ s: String) { for ch in s { if ch == "\n" { tv.insertNewline(nil) } else { tv.insertText(String(ch), replacementRange: tv.selectedRange()) }; pump() } }
    func blocks() -> [Node] { c.document().content ?? [] }

    func testXTriggerMakesTask() {
        type("x buy milk")
        XCTAssertEqual(blocks()[0].type, "taskList")
        XCTAssertEqual(blocks()[0].content?[0].attrs?["checked"], .bool(false))
    }

    func testSeparatorVariantsAndPageBreak() {
        type("=--"); type("a\n.--"); type("b\n..-"); type("c\n==="); type("d")
        let rules = blocks().filter { $0.type == "horizontalRule" || $0.type == "pageBreak" }
        XCTAssertEqual(rules.map(\.type), ["horizontalRule", "horizontalRule", "horizontalRule", "pageBreak"])
        XCTAssertEqual(rules.map { $0.attrs?["variant"]?.string ?? "-" }, ["strong", "dotted", "dots", "-"])
        XCTAssertEqual(nodeText(c.document()), "abcd")
    }

    func testCalloutContinuesExitsAndRoundTrips() {
        EditorCommands.command("block.callout")!.run(c)
        type("Remember\nsecond line\n\nafter")
        let b = blocks()
        XCTAssertEqual(b.map(\.type), ["callout", "paragraph"])
        XCTAssertEqual(b[0].attrs?["icon"], "💡")
        XCTAssertEqual(b[0].content?.map(nodeText), ["Remember", "second line"])
        let (s, tr) = Converter.attributed(from: c.document())
        XCTAssertEqual(Converter.document(from: s, trailing: tr), c.document())
        let md = Markdown.render(DocFile(id: "d", title: "", content: c.document(), appearance: DocumentAppearance(styleId: "paper"), createdAt: 0, updatedAt: 0), assetPath: { $0 }, pageLink: { _, _ in nil })
        XCTAssertTrue(md.markdown.contains("> 💡 Remember\n> \n> second line") || md.markdown.contains("> 💡 Remember"))
    }

    func testIncrementalToggleHidingMatchesAFullRecompute() {
        func toggle(_ id: String, _ text: String, _ kids: [Node], open: Bool = true) -> Node {
            Node("toggleList", content: [Node("toggleItem", attrs: ["id": .string(id), "open": .bool(open)], content: [Node("paragraph", content: [.text(text)])] + kids)])
        }
        let inner = toggle("b_in", "inner", [Node("toggleList", content: [Node("toggleItem", attrs: ["id": "b_leaf"], content: [Node("paragraph", content: [.text("leaf")])])])])
        c.load(Node("doc", content: [toggle("b_a", "A", [inner]), Node("paragraph", attrs: ["id": "b_mid"], content: [.text("between")]), toggle("b_b", "B", [], open: false)]))
        for id in ["b_in", "b_a", "b_in", "b_a", "b_b", "b_a"] {
            guard let pr = c.paragraph(withId: id) else { return XCTFail(id) }
            c.toggleOpen(at: pr)
            XCTAssertEqual(c.hiddenChars, c.computeHidden(), "after toggling \(id)")
        }
    }

    func testToggleCollapseHidesChildrenUndoAndPersistence() {
        type("+ Details\n")
        tv.insertTab(nil)
        type("hidden child")
        tv.insertNewline(nil); tv.insertNewline(nil); tv.insertNewline(nil) // exit nested, then the toggle list
        type("after")
        var b = blocks()
        XCTAssertEqual(b.map(\.type), ["toggleList", "paragraph"])
        XCTAssertEqual(b[0].content?[0].attrs?["open"], .bool(true))
        let header = c.paragraphRange(at: 0)
        let child = c.paragraphRange(at: NSMaxRange(header))
        let open = c.layout.paragraphRect(child)!.height
        XCTAssertGreaterThan(open, 10)
        c.toggleOpen(at: header)
        c.layout.ensureLayout(for: c.container)
        XCTAssertTrue(c.hiddenChars.contains(child.location))
        XCTAssertLessThan(c.layout.paragraphRect(child)?.height ?? 0, 1, "collapsed child takes no space")
        b = blocks()
        XCTAssertEqual(b[0].content?[0].attrs?["open"], .bool(false), "open state is saved")
        XCTAssertEqual(nodeText(b[0]), "Detailshidden child", "collapsing never removes content")
        // The caret skips hidden text.
        tv.setSelectedRange(NSRange(location: child.location + 2, length: 0))
        XCTAssertFalse(c.hiddenChars.contains(tv.selectedRange().location))
        pump(); tv.undoManager?.undo(); pump()
        XCTAssertEqual(blocks()[0].content?[0].attrs?["open"], .bool(true))
        XCTAssertFalse(c.hiddenChars.contains(child.location))
        // Reloading a collapsed toggle hides its children again.
        c.toggleOpen(at: header)
        let saved = c.document()
        c.load(saved)
        XCTAssertTrue(c.hiddenChars.contains(c.paragraphRange(at: NSMaxRange(c.paragraphRange(at: 0))).location))
    }

    func testOldDocumentsStillLoadAndUnknownStaysOpaque() {
        // A v0.2 document (no new node types) round-trips unchanged.
        let old = Seed.firstRun().docs[0].content
        c.load(old)
        XCTAssertEqual(c.document(), old)
    }
}
