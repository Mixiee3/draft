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
            XCTAssertTrue((10...18).contains(d.spacing), "the scenes' ~13 pt lattice"); XCTAssertTrue((1.8...3).contains(d.radius), "the scenes' 2.6 pt dots")
            XCTAssertTrue((0.35...0.65).contains(d.opacity), "subtle but visible")
        }
        XCTAssertEqual(Set(dots.map(\.style)), Set(DotTexture.styles), "every dot style is used")
        XCTAssertEqual(Set(dots).count, dots.count, "no two presets share a dot layer")
        let b = p[0].tokens.backdrop
        XCTAssertEqual(try JSONDecoder().decode(Backdrop.self, from: JSONEncoder().encode(b)).dots, b.dots)
        let old = try JSONDecoder().decode(Backdrop.self, from: Data(##"{"kind":"color","color":"#ffffff"}"##.utf8))
        XCTAssertNil(old.dots, "older documents decode without dots")
    }
}

final class GradientEditTests: XCTestCase {
    func testStopEditing() {
        var b = Backdrop(kind: "gradient", from: "#000000", to: "#ffffff", angle: 90)
        b.addStop()
        XCTAssertEqual(b.stops?.map(\.at), [0, 0.5, 1]); XCTAssertEqual(b.stops?[1].color, "#808080")
        b.moveStop(0, by: 1)
        XCTAssertEqual(b.stops?.map(\.color), ["#808080", "#000000", "#ffffff"]); XCTAssertEqual(b.stops?.map(\.at), [0, 0.5, 1], "positions stay")
        b.updateStop(1) { $0.opacity = 0.4; $0.at = 0.7 }
        XCTAssertEqual(b.stops?[1].opacity, 0.4); XCTAssertEqual(b.stops?[1].at, 0.7)
        b.updateStop(2) { $0.at = 1.4 }
        XCTAssertEqual(b.stops?.last?.at, 1, "positions stay inside 0…1")
        b.updateStop(0) { $0.opacity = 1 }
        XCTAssertNil(b.stops?[0].opacity, "full opacity is stored as nothing")
        b.removeStop(0); b.removeStop(0)
        XCTAssertEqual(b.stops?.count, 2, "never fewer than two stops")
        b.moveStop(1, by: 1)
        XCTAssertEqual(b.stops?.count, 2)
        XCTAssertEqual(try JSONDecoder().decode(Backdrop.self, from: JSONEncoder().encode(b)), b)
    }

    func testSofteningCalmsHarshGradients() {
        let harsh = Backdrop(kind: "gradient", stops: [ColorStop("#000000", at: 0), ColorStop("#ffffff", at: 1)])
        XCTAssertGreaterThan(harsh.stopContrast, 20)
        let calm = harsh.softened()
        XCTAssertLessThanOrEqual(calm.stopContrast, 4.5)
        XCTAssertEqual(calm.stops?.map(\.at), [0, 1])
        for p in Backgrounds.presets { XCTAssertLessThanOrEqual(p.tokens.backdrop.stopContrast, 4.5, "\(p.name) needs no warning") }
    }
}

final class TextEffectExportTests: XCTestCase {
    func testEffectsExportAsClassesWithReadableColors() {
        var doc = DocFile.empty(id: "d_fx", title: "FX", styleId: "paper")
        doc.content = Node("doc", content: [Node("paragraph", attrs: ["id": "b_p"], content: [.text("Glow", marks: [Mark("effect", attrs: ["kind": "glow"])]), .text(" and "), .text("bad", marks: [Mark("effect", attrs: ["kind": "<script>"])])])])
        let html = HTMLExport.render(doc, tokens: Styles.builtIn[0].tokens, HTMLExport.Options(useStyle: true, today: "2026-11-09")).html
        XCTAssertTrue(html.contains("<span class='fx fx-glow'>Glow</span>"))
        XCTAssertFalse(html.contains("fx-<script>"), "unknown kinds are dropped")
        XCTAssertTrue(html.contains("prefers-contrast: more"))
        for s in Styles.all {
            let c = TextEffects.colors(accent: s.tokens.accent, text: s.tokens.textColor, page: s.tokens.pageColor)
            XCTAssertGreaterThanOrEqual(ColorMath.contrast(c.start, s.tokens.pageColor), 4.5, s.name)
            XCTAssertGreaterThanOrEqual(ColorMath.contrast(c.end, s.tokens.pageColor), 4.5, s.name)
        }
    }
}

final class BlockEffectExportTests: XCTestCase {
    func testDecorationsExport() {
        var doc = DocFile.empty(id: "d_be", title: "B", styleId: "paper")
        doc.content = Node("doc", content: [
            Node("heading", attrs: ["id": "b_h", "level": 2, "decoration": "accent"], content: [.text("Sum")]),
            Node("paragraph", attrs: ["id": "b_g", "decoration": "glass", "blockColor": "#a9e2c0"], content: [.text("Aside")]),
            Node("paragraph", attrs: ["id": "b_x", "decoration": "x' onload='1"], content: [.text("Bad")]),
        ])
        let html = HTMLExport.render(doc, tokens: Styles.builtIn[0].tokens, HTMLExport.Options(useStyle: true, today: "2026-11-09")).html
        XCTAssertTrue(html.contains("<h2 id='b_h' data-deco='accent'>"))
        XCTAssertTrue(html.contains("data-deco='glass' style='--tint:#a9e2c0'"))
        XCTAssertFalse(html.contains("onload"), "unknown decorations are dropped")
        XCTAssertTrue(html.contains("h2[data-deco=accent]"))
    }
}

final class AgentBackdropTests: XCTestCase {
    func testBackdropProposalValidation() throws {
        let ok = try AgentEdit.backdrop(##"{"stops":[{"color":"#dfe8f5","at":0},{"color":"#b9c8e6","at":1,"opacity":0.8}],"radial":true,"focusX":0.2,"focusY":0.1}"##)
        XCTAssertEqual(ok.kind, "gradient"); XCTAssertEqual(ok.radial, true); XCTAssertEqual(ok.colorStops.count, 2)
        XCTAssertNoThrow(try AgentEdit(action: "document_backdrop", blockId: "d_a", value: ##"{"stops":[{"color":"#ffffff","at":0},{"color":"#eeeeee","at":1}]}"##).validate())
        for bad in [##"{"stops":[{"color":"#000000","at":0},{"color":"#ffffff","at":1}]}"##,   // harsh
                    ##"{"stops":[{"color":"#fff","at":0},{"color":"#eeeeee","at":1}]}"##,       // short hex
                    ##"{"stops":[{"color":"#ffffff","at":0}]}"##,                               // one stop
                    ##"{"stops":[{"color":"#ffffff","at":0},{"color":"#eeeeee","at":2}]}"##,    // out of range
                    ##"{"image":"asset:x.png","stops":[]}"##, "not json", ""] {
            XCTAssertThrowsError(try AgentEdit.backdrop(bad), bad)
        }
    }
}

final class SpectrumCoreTests: XCTestCase {
    func testParsingColorsExportAndValidation() throws {
        XCTAssertEqual(Spectrum("spectrum")?.value, "spectrum:aurora:slow:forward")
        XCTAssertEqual(Spectrum("spectrum:prism:still")?.seconds, 0)
        for bad in ["spectrum:rainbow", "spectrum:prism:warp", "spectrum:prism:slow:up", "glow", "spectrum:a:b:c:d"] { XCTAssertNil(Spectrum(bad), bad) }
        XCTAssertEqual(Spectrum.palettes.map(\.name), ["Aurora", "Prism", "Sunset Spectrum", "Ocean Rainbow", "Neon Dusk"])
        for s in Styles.all { for p in Spectrum.palettes { for c in Spectrum(palette: p.id).colors(page: s.tokens.pageColor) {
            XCTAssertGreaterThanOrEqual(ColorMath.contrast(c, s.tokens.pageColor), 4.5, "\(p.name) on \(s.name)")
        } } }
        var doc = DocFile.empty(id: "d_sp", title: "S", styleId: "deep-ink")
        doc.content = Node("doc", content: [Node("heading", attrs: ["id": "b_h", "level": 1], content: [.text("Title", marks: [Mark("effect", attrs: ["kind": "spectrum", "palette": "ocean", "speed": "fast", "direction": "forward"])])])])
        let html = HTMLExport.render(doc, tokens: Styles.style("deep-ink").tokens, HTMLExport.Options(useStyle: true, today: "2026-11-11")).html
        XCTAssertTrue(html.contains("class='fx fx-spectrum' style='background-image:linear-gradient(90deg,"), "a still gradient")
        XCTAssertFalse(html.contains("animation"), "exports never animate")
        XCTAssertNoThrow(try AgentEdit(action: "text_effect", blockId: "b_h", value: "spectrum:sunset:normal:backward", text: "Title").validate())
        XCTAssertThrowsError(try AgentEdit(action: "text_effect", blockId: "b_h", value: "spectrum", text: String(repeating: "x", count: 201)).validate())
        XCTAssertThrowsError(try AgentEdit(action: "text_effect", blockId: "b_h", value: "spectrum:rainbow", text: "Title").validate())
    }
}

final class EffectExportTests: XCTestCase {
    func testColorsAndStrengthExport() {
        var doc = DocFile.empty(id: "d_ex", title: "E", styleId: "paper")
        doc.content = Node("doc", content: [Node("paragraph", attrs: ["id": "b_p"], content: [
            .text("Glow", marks: [EffectSpec("glow?color=#ff4fd8&intensity=0.80")!.mark]),
            .text("Grad", marks: [EffectSpec("gradient?stops=#3a5bd9,#d6336c&angle=30")!.mark])])])
        let html = HTMLExport.render(doc, tokens: Styles.builtIn[0].tokens, HTMLExport.Options(useStyle: true, today: "2026-11-11")).html
        XCTAssertTrue(html.contains("class='fx fx-glow' style='--fxc:#ff4fd8;--fxi:0.80'"), html)
        XCTAssertTrue(html.contains("linear-gradient(120deg,#3a5bd9,#d6336c)"), "stops and direction")
    }
}
