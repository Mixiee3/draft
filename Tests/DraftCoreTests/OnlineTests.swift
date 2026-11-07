import XCTest
@testable import DraftCore

final class OnlineTests: XCTestCase {
    func testImageSearchRequestAndParse() throws {
        let r = OnlineImageSearch.request("blue lake")!
        XCTAssertEqual(r.url?.host, "api.openverse.org")
        XCTAssertTrue(r.url!.absoluteString.contains("q=blue%20lake"))
        XCTAssertNil(OnlineImageSearch.request("  "))
        let json = #"{"results":[{"id":"1","title":"Lake","url":"https://x.org/a.jpg","thumbnail":"https://x.org/t.jpg","creator":"Ana","license":"by"},{"id":"2","url":"http://insecure/b.jpg"}]}"#
        XCTAssertEqual(try OnlineImageSearch.parse(Data(json.utf8)).map(\.id), ["1"], "https only")
    }

    func testLinkPreviewParsing() {
        XCTAssertNotNil(LinkPreviews.soleURL(" https://example.com/a?b=1 "))
        XCTAssertNil(LinkPreviews.soleURL("see https://example.com"))
        XCTAssertNil(LinkPreviews.soleURL("ftp://x.org/f"))
        XCTAssertNil(LinkPreviews.soleURL("draft://open?doc=d_1"))
        let u = URL(string: "https://www.example.com/post")!
        let og = LinkPreviews.parse(html: #"<html><head><meta property="og:title" content="Ships &amp; Sails"><meta name="description" content="A short read."><title>ignored</title></head>"#, url: u)
        XCTAssertEqual(og.title, "Ships & Sails"); XCTAssertEqual(og.summary, "A short read."); XCTAssertEqual(og.site, "example.com")
        XCTAssertEqual(LinkPreviews.parse(html: "<title>\n Plain page </title>", url: u).title, "Plain page")
        XCTAssertEqual(LinkPreviews.parse(html: "", url: u).title, "example.com", "falls back to the site name")
    }
}
