import XCTest
@testable import DraftCore

final class MarkdownImportTests: XCTestCase {
    func testBlocksListsAndInline() {
        let md = """
        # Title
        Plain line
        - one
          - nested
        - [x] done
        1. first
        > quoted
        ```swift
        let x = 1
        ```
        ---
        **bold** and *it* and [link](https://a.b) and `code`
        """
        let b = MarkdownImport.blocks(md)
        XCTAssertEqual(b.map(\.type), ["heading", "paragraph", "bulletList", "taskList", "orderedList", "blockquote", "codeBlock", "horizontalRule", "paragraph"])
        XCTAssertEqual(b[2].content?.first?.content?.last?.type, "bulletList", "indented item nests")
        XCTAssertEqual(b[3].content?.first?.attrs?["checked"], .bool(true))
        XCTAssertEqual(nodeText(b[6]), "let x = 1")
        let inl = b[8].content!
        XCTAssertEqual(inl.first, .text("bold", marks: [Mark("bold")]))
        XCTAssertTrue(inl.contains(.text("it", marks: [Mark("italic")])))
        XCTAssertTrue(inl.contains(.text("link", marks: [Mark("link", attrs: ["href": "https://a.b"])])))
        XCTAssertTrue(inl.contains(.text("code", marks: [Mark("code")])))
    }

    func testPlainProseIsNotMangled() {
        let b = MarkdownImport.blocks("5 * 3 * 2 = 30\nsnake_case_name stays\n\nThird")
        XCTAssertEqual(b.map(nodeText), ["5 * 3 * 2 = 30", "snake_case_name stays", "Third"])
        XCTAssertTrue(b.allSatisfy { ($0.content ?? []).allSatisfy { $0.marks == nil } })
    }

    func testExportThenImportKeepsStructureAndText() {
        let d = Seed.firstRun().docs[0]
        let md = Markdown.render(d, assetPath: { $0 }, pageLink: { _, t in t + ".md" }).markdown
        let back = MarkdownImport.blocks(md)
        XCTAssertEqual(back.first?.type, "heading") // the title
        XCTAssertEqual(Array(back.dropFirst()).filter { $0.type != "paragraph" }.map(\.type),
                       (d.content.content ?? []).filter { $0.type != "paragraph" && $0.type != "pageCard" }.map(\.type))
        XCTAssertTrue(docPlainText(Node("doc", content: back)).contains("Keep the interface fast, the data portable, and the writer in control."))
    }
}
