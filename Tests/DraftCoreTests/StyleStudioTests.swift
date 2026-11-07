import XCTest
@testable import DraftCore

final class StyleStudioTests: XCTestCase {
    override func tearDown() { Styles.user = [] }

    func testPresetsAreReadableAndOriginalScenesExist() {
        XCTAssertGreaterThanOrEqual(Styles.builtIn.count, 12, "at least 5 new presets on top of the 7 from v0.1")
        XCTAssertEqual(Set(Styles.builtIn.map(\.id)).count, Styles.builtIn.count)
        for s in Styles.builtIn {
            XCTAssertGreaterThanOrEqual(ColorMath.contrast(s.tokens.textColor, s.tokens.pageColor), 4.5, s.name)
            if s.tokens.backdrop.kind == "image" { XCTAssertNotNil(Scenes.all[s.tokens.backdrop.image ?? ""], s.name) }
        }
        XCTAssertEqual(Set(Scenes.order), Set(Scenes.all.keys))
        XCTAssertGreaterThanOrEqual(Scenes.order.count, 12)
    }

    func testReadableColorKeepsHueAndExplainsRatio() {
        let (hex, ratio) = ColorMath.readable("#9db7ff", on: "#ffffff")
        XCTAssertGreaterThanOrEqual(ratio, 4.5)
        XCTAssertLessThan(ratio, 5.5, "the nearest readable shade, not black")
        let (r, g, b) = ColorMath.rgb(hex)
        XCTAssertGreaterThan(b, r); XCTAssertGreaterThan(b, g, "still blue")
        XCTAssertEqual(ColorMath.readable("#202020", on: "#ffffff").hex, "#202020", "already readable: unchanged")
        XCTAssertGreaterThanOrEqual(ColorMath.readable("#555555", on: "#1c1d20").ratio, 4.5, "lightens on dark pages")
    }

    func testUserStylesResolveAndRoundTripInLibrary() throws {
        var lib = Library.empty()
        var tok = Styles.style("citrus").tokens
        tok.pageColor = "#fefefe"
        let u = UserStyle(name: "Studio", base: "citrus", tokens: tok, pinned: true)
        lib.userStyles = [u]
        let back = try JSONDecoder().decode(Library.self, from: DraftJSON.encode(lib))
        XCTAssertEqual(back.userStyles, [u])
        Styles.user = back.userStyles
        XCTAssertEqual(Styles.resolve(DocumentAppearance(styleId: u.id)).pageColor, "#fefefe")
        XCTAssertEqual(Styles.all.first { $0.id == u.id }?.name, "Studio")
        // A library written before v0.4 has no userStyles key.
        var old = try JSONSerialization.jsonObject(with: DraftJSON.encode(Library.empty())) as! [String: Any]
        old["userStyles"] = nil
        XCTAssertEqual(try JSONDecoder().decode(Library.self, from: JSONSerialization.data(withJSONObject: old)).userStyles, [])
        XCTAssertFalse(String(decoding: try DraftJSON.encode(Library.empty()), as: UTF8.self).contains("userStyles"), "no new key unless used")
    }

    func testSeparatorVariationIsStablePerBlock() {
        XCTAssertEqual(Variation.unit("b_one", 1), Variation.unit("b_one", 1))
        XCTAssertNotEqual(Variation.unit("b_one", 1), Variation.unit("b_two", 1))
        XCTAssertNotEqual(Variation.unit("b_one", 1), Variation.unit("b_one", 2))
        let vals = (0..<50).map { Variation.unit("b_\($0)") }
        XCTAssertTrue(vals.allSatisfy { $0 >= 0 && $0 < 1 })
        XCTAssertGreaterThan(Set(vals.map { Int($0 * 10) }).count, 5, "spread out")
    }
}
