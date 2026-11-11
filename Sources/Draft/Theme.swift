import SwiftUI
import DraftCore
import DraftEditor

extension Color {
    init(hex: String, opacity: Double = 1) {
        let (r, g, b) = ColorMath.rgb(hex)
        self.init(.sRGB, red: r, green: g, blue: b, opacity: opacity)
    }
}

/// App chrome tokens (the "quiet register"). Documents carry their own style tokens.
struct Tokens {
    var dark: Bool
    var accent: Color
    var shell: Color
    var rail: Color
    var canvas: Color
    var card: Color
    var text: Color
    var secondary: Color
    var tertiary: Color
    var line: Color
    var hover: Color
    var selected: Color
    var pill: Color
    var pillText: Color
    var pillBorder: Color

    static let radiusPanel: CGFloat = 18
    static let radiusCard: CGFloat = 14
    static let radiusControl: CGFloat = 10

    static func make(dark: Bool, accent: String, tint: String?) -> Tokens {
        var t = Tokens(
            dark: dark,
            accent: Color(hex: accent),
            shell: dark ? Color(hex: "#1f1f20") : Color(hex: "#e9e7e2"),
            rail: dark ? Color(hex: "#2a2a2b") : Color(hex: "#f5f4f1"),
            canvas: dark ? Color(hex: "#2d2d2e") : Color(hex: "#f8f7f4"),
            card: dark ? Color(hex: "#3a3a3b") : .white,
            text: dark ? Color(hex: "#f1f0ee") : Color(hex: "#1f1f1d"),
            secondary: dark ? Color(hex: "#a9a8a4") : Color(hex: "#6f6e69"),
            tertiary: dark ? Color(hex: "#7c7b78") : Color(hex: "#9b9a95"),
            line: dark ? Color.white.opacity(0.08) : Color.black.opacity(0.07),
            hover: dark ? Color.white.opacity(0.06) : Color.black.opacity(0.045),
            selected: dark ? Color.white.opacity(0.11) : Color.black.opacity(0.075),
            pill: dark ? Color(hex: "#111112") : Color.white,
            pillText: dark ? .white : Color(hex: "#1f1f1d"),
            pillBorder: dark ? Color.white.opacity(0.06) : Color.black.opacity(0.09))
        if let tint {
            // "Use document style for the app": tint rail and tab strip with the document's color.
            let tintDark = ColorMath.isDark(tint)
            t.shell = Color(hex: tint)
            t.rail = tintDark ? Color(hex: tint).opacity(0.85) : Color.white.opacity(0.55)
            t.text = tintDark ? Color(hex: "#f1f0ee") : Color(hex: "#1f1f1d")
            t.secondary = tintDark ? Color(hex: "#bdbbc8") : Color(hex: "#5f5e59")
            t.tertiary = tintDark ? Color(hex: "#8d8b99") : Color(hex: "#8a8984")
            t.hover = tintDark ? Color.white.opacity(0.07) : Color.black.opacity(0.05)
            t.selected = tintDark ? Color.white.opacity(0.13) : Color.white.opacity(0.75)
            t.line = tintDark ? Color.white.opacity(0.09) : Color.black.opacity(0.07)
            t.dark = tintDark
        }
        return t
    }
}

struct TokensKey: EnvironmentKey { static let defaultValue = Tokens.make(dark: false, accent: "#5b6cf0", tint: nil) }
extension EnvironmentValues {
    var tokens: Tokens { get { self[TokensKey.self] } set { self[TokensKey.self] = newValue } }
}

/// Native renderer for Draft's original scenic backdrops (vector; no image files).
struct SceneView: View {
    let sceneId: String
    var body: some View {
        Canvas { ctx, size in
            guard let s = Scenes.all[sceneId] else { return }
            let p = s.palette
            let rect = CGRect(origin: .zero, size: size)
            ctx.fill(Path(rect), with: .linearGradient(Gradient(colors: [Color(hex: p.sky.0), Color(hex: p.sky.1)]), startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
            let sun = CGPoint(x: size.width * (0.66 + s.seed * 0.015), y: size.height * 0.28)
            let glowR = min(size.width, size.height) * 0.32
            ctx.fill(Path(ellipseIn: CGRect(x: sun.x - glowR, y: sun.y - glowR, width: glowR * 2, height: glowR * 2)),
                     with: .radialGradient(Gradient(colors: [Color(hex: p.sun, opacity: 0.85), Color(hex: p.sun, opacity: 0)]), center: sun, startRadius: 0, endRadius: glowR))
            let r = glowR * 0.34
            ctx.fill(Path(ellipseIn: CGRect(x: sun.x - r, y: sun.y - r, width: r * 2, height: r * 2)), with: .color(Color(hex: p.sun, opacity: 0.88)))
            // Halftone dot clusters (drawn before the hills so the land stays clean)
            for (cx, cy, rad) in [(0.78, 0.22, 0.24), (0.14, 0.6, 0.2)] {
                let c = CGPoint(x: size.width * cx, y: size.height * cy)
                let R = min(size.width, size.height) * rad * 1.4
                var y = c.y - R
                while y < c.y + R {
                    var x = c.x - R
                    while x < c.x + R {
                        let d = hypot(x - c.x, y - c.y) / R
                        if d < 1 {
                            let dr = 2.6 * (1 - d * d)
                            ctx.fill(Path(ellipseIn: CGRect(x: x - dr, y: y - dr, width: dr * 2, height: dr * 2)), with: .color(Color(hex: p.dots, opacity: 0.55)))
                        }
                        x += 13
                    }
                    y += 13
                }
            }
            let n = p.layers.count
            for (i, col) in p.layers.enumerated() {
                let baseY = size.height * (0.52 + Double(i) * 0.42 / Double(n))
                let amp = size.height * (0.046 - Double(i) * 0.006)
                let freq = 1.2 + Double(i) * 0.35
                let phase = s.seed * 1.3 + Double(i) * 2.1
                var path = Path()
                path.move(to: CGPoint(x: 0, y: size.height))
                for k in 0...64 {
                    let t = Double(k) / 64
                    let y = baseY + sin(t * .pi * 2 * freq + phase) * amp + sin(t * .pi * 2 * freq * 2.3 + phase * 1.7) * amp * 0.35
                    path.addLine(to: CGPoint(x: t * size.width, y: y))
                }
                path.addLine(to: CGPoint(x: size.width, y: size.height))
                path.closeSubpath()
                ctx.fill(path, with: .color(Color(hex: col)))
            }
        }
    }
}

/// The document backdrop layer: none / solid / gradient / scenic / uploaded image.
struct BackdropView: View, Equatable {
    let backdrop: Backdrop
    var assetImage: NSImage? = nil
    static func == (a: BackdropView, b: BackdropView) -> Bool { a.backdrop == b.backdrop && a.assetImage === b.assetImage }
    var body: some View {
        ZStack {
            switch backdrop.kind {
            case "solid": Color(hex: backdrop.color ?? "#e9e6df")
            case "gradient", "field": FieldView(backdrop: backdrop)
            case "image":
                if let img = assetImage {
                    Image(nsImage: img).resizable().aspectRatio(contentMode: .fill)
                } else {
                    SceneView(sceneId: backdrop.image ?? "lagoon")
                }
            default: Color(hex: "#ecebe8")
            }
        }
        .blur(radius: backdrop.blur == true ? 18 : 0)
        .overlay(backdrop.effect == "faded" ? Color.white.opacity(0.42) : Color.clear)
        .clipped()
    }
}

/// A layered background drawn once per size: a linear or radial gradient, a soft light, a quiet
/// pattern and grain. Static, so typing and scrolling never redraw it; Increase Contrast keeps only
/// the gradient.
struct FieldView: View {
    let backdrop: Backdrop
    @Environment(\.colorSchemeContrast) var contrast

    var body: some View {
        let b = backdrop
        // Screens for the standard look can be captured on a Mac that has Increase Contrast on.
        let increased = contrast == .increased && ProcessInfo.processInfo.environment["DRAFT_CAPTURE_STANDARD_CONTRAST"] == nil
        let plain = increased || b.kind == "gradient" && b.pattern == nil && b.glow == nil && b.grain == nil
        Canvas { ctx, size in
            let rect = CGRect(origin: .zero, size: size)
            let stops = b.colorStops.map { Gradient.Stop(color: Color(hex: $0.color).opacity($0.opacity ?? 1), location: $0.at) }
            let g = Gradient(stops: stops)
            if b.radial == true {
                let c = CGPoint(x: size.width * (b.focusX ?? 0.5), y: size.height * (b.focusY ?? 0.5))
                ctx.fill(Path(rect), with: .radialGradient(g, center: c, startRadius: 0, endRadius: max(size.width, size.height) * 1.1))
            } else {
                let a = (b.angle ?? 135) * .pi / 180
                let d = CGPoint(x: cos(a) * size.width / 2, y: sin(a) * size.height / 2)
                let m = CGPoint(x: size.width / 2, y: size.height / 2)
                ctx.fill(Path(rect), with: .linearGradient(g, startPoint: CGPoint(x: m.x - d.x, y: m.y - d.y), endPoint: CGPoint(x: m.x + d.x, y: m.y + d.y)))
            }
            if plain { return }
            if let glow = b.glow {
                let c = CGPoint(x: size.width * (b.glowX ?? 0.5), y: size.height * (b.glowY ?? 0.2))
                let r = max(size.width, size.height) * 0.55
                ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)),
                         with: .radialGradient(Gradient(colors: [Color(hex: glow).opacity(0.7), Color(hex: glow).opacity(0)]), center: c, startRadius: 0, endRadius: r))
            }
            if let d = b.dots { Self.drawDots(d, in: &ctx, size: size) } // before the pattern, so hills keep the land clean
            if let p = b.pattern { Self.drawPattern(p, color: Color(hex: b.patternColor ?? "#ffffff").opacity(b.patternOpacity ?? 0.2), in: &ctx, size: size, focus: CGPoint(x: b.focusX ?? 0.5, y: b.focusY ?? 0.5)) }
            if let grain = b.grain, grain > 0 {
                var rng = Seeded(seed: 7)
                let n = Int(size.width * size.height / 40 * min(grain, 0.2))
                for i in 0..<n {
                    let x = rng.next() * size.width, y = rng.next() * size.height
                    ctx.fill(Path(CGRect(x: x, y: y, width: 1, height: 1)), with: .color((i % 2 == 0 ? Color.white : Color.black).opacity(0.18)))
                }
            }
        }
    }

    /// Deterministic, so every render (and every export) of a preset looks the same.
    struct Seeded {
        var state: UInt64
        init(seed: UInt64) { state = seed &* 6364136223846793005 &+ 1442695040888963407 }
        mutating func next() -> CGFloat { state = state &* 6364136223846793005 &+ 1442695040888963407; return CGFloat(state >> 33) / CGFloat(1 << 31) }
    }

    /// Dots in the language of Draft's scenes: a ~13 pt lattice whose dot size (not opacity) falls
    /// off as 1 − d² inside soft discs anchored to the light, one palette colour, one fill. Styles
    /// only change where the discs are and how the size is modulated.
    static func drawDots(_ d: DotTexture, in ctx: inout GraphicsContext, size: CGSize) {
        let w = size.width, h = size.height, sp = max(8, CGFloat(d.spacing)), r0 = CGFloat(d.radius)
        let R = min(w, h) * (0.28 + 0.22 * CGFloat(d.fade ?? 0.6))
        let focus = CGPoint(x: w * (d.focusX ?? 0.8), y: h * (d.focusY ?? 0.2))
        var rng = Seeded(seed: (d.style + d.color).unicodeScalars.reduce(11) { $0 &* 31 &+ UInt64($1.value) })
        var discs: [(c: CGPoint, r: CGFloat)] = [(focus, R)]
        switch d.style {
        case "halftone": // a second, smaller disc across the page, like the scenes' lower-left cluster
            discs.append((CGPoint(x: w - focus.x * 0.85, y: min(h * 0.82, focus.y + h * 0.42)), R * 0.75))
        case "cluster":
            discs[0].r = R * 0.62
            // groups stay in the side margins, where the page card doesn't cover them
            for i in 0..<3 { let side = (i + (focus.x > w / 2 ? 1 : 0)) % 2 == 0 ? 0.03 + rng.next() * 0.15 : 0.82 + rng.next() * 0.15
                discs.append((CGPoint(x: side * w, y: (0.12 + rng.next() * 0.76) * h), R * (0.3 + rng.next() * 0.25))) }
        default: break
        }
        var path = Path()
        for y in stride(from: sp / 2, through: h, by: sp) {
            for x in stride(from: sp / 2, through: w, by: sp) {
                var p = CGPoint(x: x, y: y)
                let jitter = d.style == "scatter" ? (rng.next() - 0.5, rng.next() - 0.5, rng.next()) : (0, 0, 1)
                if d.style == "scatter" { p.x += jitter.0 * sp * 0.9; p.y += jitter.1 * sp * 0.9 }
                var s: CGFloat = 0
                for disc in discs {
                    let q = hypot(p.x - disc.c.x, p.y - disc.c.y) / disc.r
                    if q < 1 { s = max(s, 1 - q * q) }
                }
                let dist = hypot(p.x - focus.x, p.y - focus.y)
                var r: CGFloat
                switch d.style {
                case "radial": r = r0 * s * (0.3 + 0.7 * (0.5 + 0.5 * cos(dist / (sp * 1.7) * .pi)))
                case "scatter": r = jitter.2 < 0.45 ? 0 : r0 * s.squareRoot() * (0.45 + jitter.2 * 0.7)
                case "fade": r = r0 * max(0, 1 - dist / (R * 1.9))
                case "grid": r = r0 * 0.8 * min(1, s * 2.2)
                default: r = r0 * s // halftone, cluster
                }
                if r > 0.35 { path.addEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)) }
            }
        }
        ctx.fill(path, with: .color(Color(hex: d.color).opacity(d.opacity)))
    }

    static func drawPattern(_ p: String, color: Color, in ctx: inout GraphicsContext, size: CGSize, focus: CGPoint) {
        let w = size.width, h = size.height
        var rng = Seeded(seed: p.unicodeScalars.reduce(3) { $0 &* 31 &+ UInt64($1.value) })
        switch p {
        case "dots":
            var path = Path()
            for x in stride(from: 9.0, through: w, by: 22) { for y in stride(from: 9.0, through: h, by: 22) { path.addEllipse(in: CGRect(x: x, y: y, width: 2.4, height: 2.4)) } }
            ctx.fill(path, with: .color(color))
        case "grid":
            var path = Path()
            for x in stride(from: 0.0, through: w, by: 28) { path.move(to: CGPoint(x: x, y: 0)); path.addLine(to: CGPoint(x: x, y: h)) }
            for y in stride(from: 0.0, through: h, by: 28) { path.move(to: CGPoint(x: 0, y: y)); path.addLine(to: CGPoint(x: w, y: y)) }
            ctx.stroke(path, with: .color(color), lineWidth: 0.7)
        case "halftone":
            var path = Path()
            for x in stride(from: 0.0, through: w, by: 16) {
                for y in stride(from: 0.0, through: h, by: 16) {
                    let r = 3.2 * max(0.15, 1 - (x / max(w, 1) + y / max(h, 1)) / 2)
                    path.addEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
                }
            }
            ctx.fill(path, with: .color(color))
        case "waves":
            var path = Path()
            for y in stride(from: 30.0, through: h, by: 46) {
                path.move(to: CGPoint(x: 0, y: y))
                for x in stride(from: 0.0, through: w, by: 8) { path.addLine(to: CGPoint(x: x, y: y + sin(x / 38 + y / 90) * 7)) }
            }
            ctx.stroke(path, with: .color(color), lineWidth: 1.2)
        case "hills":
            for i in 0..<3 {
                var path = Path()
                let base = h * (0.62 + Double(i) * 0.12)
                path.move(to: CGPoint(x: 0, y: h))
                for x in stride(from: 0.0, through: w + 8, by: 8) { path.addLine(to: CGPoint(x: x, y: base - sin(x / (w / (2.2 + Double(i))) + Double(i)) * h * 0.07)) }
                path.addLine(to: CGPoint(x: w, y: h)); path.closeSubpath()
                ctx.fill(path, with: .color(color.opacity(0.55 + Double(i) * 0.2)))
            }
        case "stars":
            let count = Int(w * h / 5200)
            for i in 0..<count {
                let x = rng.next() * w, y = rng.next() * h * 0.85
                let r = i % 9 == 0 ? 1.8 : 0.9
                ctx.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)), with: .color(color.opacity(i % 9 == 0 ? 1 : 0.6)))
            }
        case "blobs":
            ctx.drawLayer { l in
                l.addFilter(.blur(radius: min(w, h) * 0.06))
                for _ in 0..<5 {
                    let r = min(w, h) * (0.18 + rng.next() * 0.22)
                    l.fill(Path(ellipseIn: CGRect(x: rng.next() * w - r, y: rng.next() * h - r, width: r * 2.2, height: r * 1.6)), with: .color(color))
                }
            }
        case "rings":
            let c = CGPoint(x: w * focus.x, y: h * focus.y)
            var path = Path()
            for r in stride(from: 40.0, through: max(w, h) * 1.2, by: 44) { path.addEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)) }
            ctx.stroke(path, with: .color(color), lineWidth: 1)
        case "diagonal":
            var path = Path()
            for x in stride(from: -h, through: w, by: 22) { path.move(to: CGPoint(x: x, y: h)); path.addLine(to: CGPoint(x: x + h, y: 0)) }
            ctx.stroke(path, with: .color(color), lineWidth: 1)
        case "window":
            ctx.drawLayer { l in
                l.addFilter(.blur(radius: 24))
                for i in 0..<3 {
                    var path = Path()
                    let x = w * (0.15 + Double(i) * 0.16)
                    path.move(to: CGPoint(x: x, y: 0)); path.addLine(to: CGPoint(x: x + w * 0.08, y: 0))
                    path.addLine(to: CGPoint(x: x + w * 0.5, y: h)); path.addLine(to: CGPoint(x: x + w * 0.38, y: h)); path.closeSubpath()
                    l.fill(path, with: .color(color))
                }
            }
        default: break
        }
    }
}
