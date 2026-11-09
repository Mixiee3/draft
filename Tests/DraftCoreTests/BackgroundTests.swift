import XCTest
@testable import DraftCore

final class BackgroundTests: XCTestCase {
    func testPresetsAreDistinctReadableAndResolvable() {
        let p = Backgrounds.presets
        XCTAssertGreaterThanOrEqual(p.count, 20)
        XCTAssertEqual(Set(p.map(\.id)).count, p.count); XCTAssertEqual(Set(p.map(\.name)).count, p.count)
        XCTAssertTrue(Set(p.map(\.id)).isDisjoint(with: Styles.builtIn.map(\.id)))
        for s in p {
            let t = s.tokens
            XCTAssertEqual(t.backdrop.kind, "field", s.name)
            XCTAssertGreaterThanOrEqual(t.backdrop.colorStops.count, 2, s.name)
            XCTAssertGreaterThanOrEqual(ColorMath.contrast(t.textColor, t.pageColor), 4.5, "\(s.name) text on page")
            XCTAssertGreaterThanOrEqual(ColorMath.contrast(t.accent, t.pageColor), 3, "\(s.name) accent headings on page")
            if let pat = t.backdrop.pattern { XCTAssertTrue(Backdrop.patterns.contains(pat), s.name) }
            XCTAssertEqual(Styles.style(s.id).name, s.name)
        }
        // Not the same picture with another hue: no two share palette, pattern and light together.
        let shapes = p.map { "\($0.tokens.backdrop.pattern ?? "-")|\($0.tokens.backdrop.radial == true)|\($0.tokens.backdrop.glow != nil)|\($0.tokens.backdrop.colorStops.map(\.color))" }
        XCTAssertEqual(Set(shapes).count, p.count)
        XCTAssertGreaterThanOrEqual(Set(p.compactMap { $0.tokens.backdrop.pattern }).count, 9, "most patterns are used")
    }

    func testModelRoundTripAndFallbacks() throws {
        let b = Backgrounds.presets[0].tokens.backdrop
        XCTAssertEqual(try JSONDecoder().decode(Backdrop.self, from: JSONEncoder().encode(b)), b)
        let old = try JSONDecoder().decode(Backdrop.self, from: Data(##"{"kind":"gradient","from":"#112233","to":"#ddeeff","angle":40}"##.utf8))
        XCTAssertNil(old.stops); XCTAssertEqual(old.colorStops.map(\.color), ["#112233", "#ddeeff"])
        var a = DocumentAppearance(styleId: "midnight-constellation")
        XCTAssertEqual(Styles.resolve(a).pageColor, "#181c35")
        a.styleId = "removed-style"
        XCTAssertEqual(Styles.resolve(a).pageColor, Styles.builtIn[0].tokens.pageColor, "a missing style falls back to Paper")
    }

    func testExportCSS() {
        var t = Styles.builtIn[0].tokens
        t.backdrop = Backdrop(kind: "gradient", angle: 90, stops: [ColorStop("#ff0000", at: 0), ColorStop("#00ff00", at: 0.5, opacity: 0.5), ColorStop("#0000ff", at: 1)])
        XCTAssertTrue(HTMLExport.css(t, useStyle: true, backdropImage: nil).contains("linear-gradient(180deg, #ff0000 0%, rgba(0,255,0,0.50) 50%, #0000ff 100%)"))
        t.backdrop.radial = true; t.backdrop.focusX = 0.3; t.backdrop.focusY = 0.2
        XCTAssertTrue(HTMLExport.css(t, useStyle: true, backdropImage: nil).contains("radial-gradient(circle at 30% 20%"))
        let field = Backgrounds.presets[0].tokens
        XCTAssertTrue(HTMLExport.css(field, useStyle: true, backdropImage: "backdrop.png").contains("url('backdrop.png')"))
    }

    func testDotTexturesAreVisibleVariedAndPersist() throws {
        let p = Backgrounds.presets
        let dots = p.compactMap { $0.tokens.backdrop.dots }
        XCTAssertEqual(dots.count, p.count, "every preset carries a dot layer")
        for d in dots {
            XCTAssertTrue(DotTexture.styles.contains(d.style), d.style)
            XCTAssertTrue((12...48).contains(d.spacing)); XCTAssertTrue((0.5...3).contains(d.radius))
            XCTAssertTrue((0.2...0.8).contains(d.opacity), "subtle but visible")
        }
        XCTAssertEqual(Set(dots.map(\.style)), Set(DotTexture.styles), "every dot style is used")
        XCTAssertEqual(Set(dots).count, dots.count, "no two presets share a dot layer")
        let b = p[0].tokens.backdrop
        XCTAssertEqual(try JSONDecoder().decode(Backdrop.self, from: JSONEncoder().encode(b)).dots, b.dots)
        let old = try JSONDecoder().decode(Backdrop.self, from: Data(##"{"kind":"color","color":"#ffffff"}"##.utf8))
        XCTAssertNil(old.dots, "older documents decode without dots")
    }
}
