import XCTest
import AppKit
import DraftCore
@testable import DraftEditor

/// Input methods (Japanese, Chinese, dead keys) compose text as "marked" text before committing it.
/// Composition must never trigger editor shortcuts, split blocks or lose formatting.
final class IMETests: XCTestCase {
    var window: NSWindow!
    var view: DocumentEditorView!
    var c: EditorController { view.controller }
    var tv: DraftTextView { c.textView }

    override func setUp() {
        view = DocumentEditorView(frame: NSRect(x: 0, y: 0, width: 900, height: 700))
        window = NSWindow(contentRect: view.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = view
        c.load(Node("doc", content: [Node("paragraph", attrs: ["id": "b_p"])]))
        window.makeFirstResponder(tv)
    }
    func pump() { let e = expectation(description: "q"); DispatchQueue.main.async { e.fulfill() }; wait(for: [e], timeout: 2) }
    func compose(_ s: String) { tv.setMarkedText(s, selectedRange: NSRange(location: (s as NSString).length, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0)); pump() }
    func commit(_ s: String) { tv.insertText(s, replacementRange: NSRange(location: NSNotFound, length: 0)); pump() }
    var blocks: [Node] { c.document().content ?? [] }

    func testJapaneseCompositionCommitsIntoTheSameBlock() {
        compose("に"); compose("にほ"); compose("にほん")
        XCTAssertTrue(tv.hasMarkedText())
        XCTAssertEqual(blocks.count, 1, "composition never splits the block")
        commit("日本")
        XCTAssertFalse(tv.hasMarkedText())
        XCTAssertEqual(blocks.map(nodeText), ["日本"])
        XCTAssertEqual(blocks.first?.id, "b_p", "the block keeps its id")
    }

    func testChineseCompositionWithCandidateChangesCommitsOnce() {
        commit("我们")
        compose("z"); compose("zh"); compose("zhong"); compose("中")
        commit("中文")
        XCTAssertEqual(nodeText(blocks[0]), "我们中文")
        XCTAssertEqual(blocks.count, 1)
    }

    func testSlashAndMarkdownShortcutsWaitForCommittedText() {
        compose("/")
        XCTAssertFalse(c.slash.isOpen, "a composing slash doesn't open the command menu")
        commit("、")
        XCTAssertFalse(c.slash.isOpen)
        tv.setSelectedRange(NSRange(location: 0, length: (tv.string as NSString).length)); tv.delete(nil); pump()
        commit("#")
        compose(" ")
        pump()
        XCTAssertEqual(blocks.first?.type, "paragraph", "a composing space doesn't turn the line into a heading")
    }

    func testCompositionInsideAHeadingKeepsTheBlockAndFormatting() {
        c.load(Node("doc", content: [Node("heading", attrs: ["id": "b_h", "level": 2], content: [.text("Plán ", marks: [Mark("bold")])])]))
        tv.setSelectedRange(NSRange(location: 5, length: 0))
        compose("か"); commit("カ")
        XCTAssertEqual(blocks.first?.type, "heading")
        XCTAssertEqual(blocks.first?.id, "b_h")
        XCTAssertEqual(nodeText(blocks[0]), "Plán カ")
        XCTAssertTrue(blocks[0].content?.last?.marks?.contains { $0.type == "bold" } ?? false, "committed text takes the bold around it")
    }

    func testCompositionInSpectrumTextKeepsTheEffect() {
        let spec = EffectSpec("spectrum:aurora:slow:forward")!.mark
        c.load(Node("doc", content: [Node("heading", attrs: ["id": "b_s", "level": 1], content: [.text("Aurora", marks: [spec])])]))
        tv.setSelectedRange(NSRange(location: 3, length: 0))
        compose("ㅎ"); compose("하"); tv.display(); commit("한")
        XCTAssertEqual(nodeText(blocks[0]), "Aur한ora")
        XCTAssertTrue(blocks[0].content?.allSatisfy { $0.marks?.contains { $0.type == "effect" } ?? false } ?? false, "the effect still covers the whole phrase")
    }
}
