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
struct BackdropView: View {
    let backdrop: Backdrop
    var assetImage: NSImage? = nil
    var body: some View {
        ZStack {
            switch backdrop.kind {
            case "solid": Color(hex: backdrop.color ?? "#e9e6df")
            case "gradient":
                let a = Angle(degrees: backdrop.angle ?? 135)
                LinearGradient(colors: [Color(hex: backdrop.from ?? "#ffd36e"), Color(hex: backdrop.to ?? "#ff8a5c")],
                               startPoint: UnitPoint(x: 0.5 - cos(a.radians) / 2, y: 0.5 - sin(a.radians) / 2),
                               endPoint: UnitPoint(x: 0.5 + cos(a.radians) / 2, y: 0.5 + sin(a.radians) / 2))
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
