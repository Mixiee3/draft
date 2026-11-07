import XCTest
import DraftCore
@testable import DraftEditor

final class ConverterTests: XCTestCase {
    func roundTrip(_ n: Node) -> Node {
        let (s, trailing) = Converter.attributed(from: n)
        return Converter.document(from: s, trailing: trailing)
    }

    func testSeedDocumentsRoundTripExactly() throws {
        for d in Seed.firstRun().docs {
            XCTAssertEqual(roundTrip(d.content), d.content, d.title)
        }
    }

    func testNestedListsQuotesCodeAndUnknownNodes() {
        let doc = ensureBlockIds(Node("doc", content: [
            Node("bulletList", content: [
                Node("listItem", content: [Node("paragraph", content: [.text("a")]), Node("paragraph", content: [.text("a2")]),
                    Node("orderedList", attrs: ["start": 3], content: [Node("listItem", content: [Node("paragraph", content: [.text("b")])])])]),
                Node("listItem", content: [Node("paragraph", content: [.text("c")])]),
            ]),
            Node("blockquote", content: [Node("paragraph", content: [.text("q1")]), Node("paragraph", content: [.text("q2")])]),
            Node("codeBlock", attrs: ["language": "swift"], content: [.text("let a = 1\nlet b = 2")]),
            Node("paragraph", content: [.text("x"), Node("hardBreak"), .text("y", marks: [Mark("bold"), Mark("link", attrs: ["href": "https://a.b"])])]),
            Node("mermaid", attrs: ["source": "graph"]),
            Node("paragraph"),
        ]))
        XCTAssertEqual(roundTrip(doc), doc)
    }
}
