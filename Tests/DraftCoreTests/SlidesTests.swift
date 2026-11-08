import XCTest
@testable import DraftCore

final class SlidesTests: XCTestCase {
    func testHeadingsSplitSlides() {
        let doc = Node("doc", content: MarkdownImport.blocks("Intro line\n\n# One\n\nFirst point\n\n- a\n  - b\n\n### Detail\n\n## Two\n\n- [x] done\n- [ ] open\n\n#### small"))
        let s = slides(doc, title: "Talk")
        XCTAssertEqual(s.map(\.title), ["Talk", "One", "Two"])
        XCTAssertEqual(s[0].lines.map(\.text), ["Intro line"])
        XCTAssertEqual(s[1].lines.map(\.kind), [.text, .bullet, .bullet, .subheading])
        XCTAssertEqual(s[1].lines[2].depth, 1)
        XCTAssertEqual(s[2].lines.map(\.kind), [.done, .task, .subheading])
    }
}
