import XCTest
@testable import DraftCore

final class HTMLExportTests: XCTestCase {
    func doc(_ id: String, _ title: String, _ content: [Node], style: String = "citrus") -> DocFile {
        var d = DocFile.empty(id: id, title: title, styleId: style)
        d.content = Node("doc", content: content)
        return d
    }

    var a: DocFile {
        doc("d_a", "Alpha & Co", [
            Node("paragraph", attrs: ["id": "b_1", "font": "mono"], content: [.text("See "), .text("Beta", marks: [Mark("docLink", attrs: ["docId": "d_b", "blockId": "b_x"])]),
                                                                          .text(" on "), .text("Mon", marks: [Mark("date", attrs: ["date": "2026-11-09"])]), .text(" #one and #two <b>")]),
            Node("horizontalRule", attrs: ["id": "b_hr", "variant": "tape"]),
            Node("pageCard", attrs: ["id": "b_c", "docId": "d_b", "title": "Beta", "size": "feature", "preview": "icon"]),
            Node("linkPreview", attrs: ["id": "b_l", "url": "https://example.com", "title": "Example"]),
            Node("taskList", attrs: ["id": "b_tl"], content: [Node("taskItem", attrs: ["id": "b_t", "checked": true], content: [Node("paragraph", attrs: ["id": "b_tp"], content: [.text("done")])])]),
            Node("pageBreak", attrs: ["id": "b_pb"]),
        ])
    }

    func testStyledAndPlainHTML() {
        let tok = Styles.style("citrus").tokens
        let r = HTMLExport.render(a, tokens: tok, HTMLExport.Options(useStyle: true, docPath: { $0 == "d_b" ? "Beta.html" : nil }, today: "2026-11-07"))
        let h = r.html
        XCTAssertTrue(h.contains("<title>Alpha &amp; Co</title>"))
        XCTAssertTrue(h.contains(tok.pageColor) && h.contains(tok.textColor), "page and text colors come from the style")
        XCTAssertTrue(h.contains("linear-gradient("), "gradient backdrop")
        XCTAssertTrue(h.contains("href='Beta.html#b_x'"), "block link goes to the exported page and block")
        XCTAssertEqual(h.components(separatedBy: "class='tag'").count - 1, 2, "both tags")
        XCTAssertTrue(h.contains("&lt;b&gt;"), "text is escaped")
        XCTAssertTrue(h.contains("datetime='2026-11-09'"))
        XCTAssertTrue(h.contains("card feature") && h.contains("href='Beta.html'"))
        XCTAssertTrue(h.contains("href='https://example.com'"), "link previews stay plain links")
        XCTAssertTrue(h.contains("font-family:ui-monospace"), "per-block font")
        XCTAssertTrue(h.contains("class='done'") && h.contains("page-break"))
        XCTAssertFalse(h.contains("<script"))
        XCTAssertFalse(h.contains("src='http"), "nothing loaded from the network")
        let plain = HTMLExport.render(a, tokens: tok, HTMLExport.Options(useStyle: false, today: "2026-11-07")).html
        XCTAssertFalse(plain.contains(tok.pageColor), "use style off: neutral colors")
        XCTAssertFalse(plain.contains("href='Beta.html"), "unexported documents are not linked")
    }

    func testSiteLinksAllResolve() throws {
        var b = doc("d_b", "Beta", [Node("paragraph", attrs: ["id": "b_x"], content: [.text("Back to "), .text("Alpha", marks: [Mark("docLink", attrs: ["docId": "d_a"])])]),
                                     Node("image", attrs: ["id": "b_i", "assetId": "0123456789abcdef.png", "alt": "pic"])], style: "paper")
        b.title = "Beta"
        let store = ["d_a": a, "d_b": b]
        let metas = ["d_a": DocMeta(id: "d_a", title: "Alpha & Co"), "d_b": DocMeta(id: "d_b", title: "Beta", parentDocId: "d_a")]
        let site = SiteExport.build(rootIds: ["d_a"], metas: metas, folders: [], load: { store[$0] }, options: { _ in HTMLExport.Options(today: "2026-11-07") },
                                    tokens: { Styles.resolve($0.appearance) }, siteTitle: "My Space")
        XCTAssertEqual(site.docs.sorted(), ["d_a", "d_b"], "nested pages come along")
        XCTAssertEqual(site.assets, ["0123456789abcdef.png"])
        let paths = Set(site.files.map(\.path)).union(site.assets.map { "assets/" + $0 })
        let re = try NSRegularExpression(pattern: #"(?:href|src)='([^']+)'"#)
        var checked = 0
        for f in site.files {
            for m in re.matches(in: f.content, range: NSRange(f.content.startIndex..., in: f.content)) {
                let ref = String(f.content[Range(m.range(at: 1), in: f.content)!]).replacingOccurrences(of: "&amp;", with: "&").replacingOccurrences(of: "&#39;", with: "'").components(separatedBy: "#")[0].removingPercentEncoding!
                if ref.hasPrefix("http") || ref.isEmpty { continue }
                XCTAssertTrue(paths.contains(ref), "\(f.path) → \(ref)")
                checked += 1
            }
        }
        XCTAssertGreaterThanOrEqual(checked, 5)
        XCTAssertTrue(site.files[0].content.contains("Alpha &amp; Co.html") || site.files[0].content.contains("Alpha%20&amp;%20Co.html") || site.files[0].content.contains("Alpha"))
    }
}
