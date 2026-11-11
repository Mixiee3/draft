import Foundation

/// Draft's original layered backgrounds: procedural (gradient, light, pattern, grain), so they need
/// no image files or network, and each pairs with a page and text color that reads at 4.5:1 or more.
public enum Backgrounds {
    static func field(_ angle: Double, _ stops: [String], radial: (Double, Double)? = nil, glow: (String, Double, Double)? = nil,
                      pattern: (String, String, Double)? = nil, grain: Double? = nil, dots: DotTexture? = nil) -> Backdrop {
        let n = Double(max(1, stops.count - 1))
        return Backdrop(kind: "field", angle: angle, stops: stops.enumerated().map { ColorStop($1, at: Double($0) / n) },
                        radial: radial == nil ? nil : true, focusX: radial?.0, focusY: radial?.1,
                        glow: glow?.0, glowX: glow?.1, glowY: glow?.2,
                        pattern: pattern?.0, patternColor: pattern?.1, patternOpacity: pattern?.2, grain: grain, dots: dots)
    }

    static func style(_ id: String, _ name: String, _ b: Backdrop, page: String, text: String, accent: String, font: String, separator: String, shell: String) -> StyleDef {
        StyleDef(id: id, name: name, tokens: StyleTokens(backdrop: b, pageColor: page, textColor: text, accent: accent, font: font, separator: separator, shellTint: shell))
    }

    public static let presets: [StyleDef] = [
        style("soft-sunrise", "Soft Sunrise", field(160, ["#ffd9b8", "#ffb9a6", "#f6e1ee"], glow: ("#fff2c4", 0.8, 0.15), pattern: ("hills", "#f08f6c", 0.22), dots: DotTexture("fade", spacing: 12, radius: 2.4, opacity: 0.4, color: "#d9735a", fade: 0.9, focusX: 0.85, focusY: 0.1)),
              page: "#fffaf5", text: "#2e1f1a", accent: "#c9533a", font: "serif", separator: "wave", shell: "#fbe9df"),
        style("quiet-lavender", "Quiet Lavender", field(0, ["#efe6ff", "#d9c9f5", "#c3b2ea"], radial: (0.3, 0.3), pattern: ("rings", "#ffffff", 0.28), dots: DotTexture("radial", spacing: 13, radius: 2.4, opacity: 0.4, color: "#8e74c9", fade: 0.6, focusX: 0.14, focusY: 0.3)),
              page: "#fbf9ff", text: "#2a2240", accent: "#6e4fc0", font: "rounded", separator: "dots", shell: "#efe8fa"),
        style("blue-hour", "Blue Hour", field(200, ["#1e2a5a", "#3b4f8f", "#8090c8"], glow: ("#9fb4ff", 0.2, 0.18), pattern: ("stars", "#ffffff", 0.55), dots: DotTexture("scatter", spacing: 14, radius: 2.2, opacity: 0.6, color: "#dfe6ff", fade: 0.7, focusX: 0.2, focusY: 0.1)),
              page: "#f6f7fc", text: "#1b2140", accent: "#3f57c0", font: "serif", separator: "line", shell: "#2a3567"),
        style("moss-study", "Moss Study", field(135, ["#e3ebd6", "#c5d6b1"], pattern: ("grid", "#6f8a5a", 0.16), grain: 0.06, dots: DotTexture("grid", spacing: 14, radius: 2.1, opacity: 0.4, color: "#4f6b3c")),
              page: "#fcfdf8", text: "#1f2a1a", accent: "#4f7536", font: "system", separator: "dotted", shell: "#e4ecd9"),
        style("terracotta-paper", "Terracotta Paper", field(100, ["#e9b69c", "#d98f72"], pattern: ("diagonal", "#ffffff", 0.12), grain: 0.12, dots: DotTexture("cluster", spacing: 12, radius: 2.4, opacity: 0.55, color: "#fff4ec", fade: 0.5, focusX: 0.8, focusY: 0.2)),
              page: "#fff7f2", text: "#3a1d12", accent: "#a84b28", font: "serif", separator: "tape", shell: "#f1d2c3"),
        style("winter-glass", "Winter Glass", field(0, ["#f4f8fc", "#dce8f3", "#c5d6e8"], radial: (0.7, 0.2), pattern: ("blobs", "#ffffff", 0.45), dots: DotTexture("fade", spacing: 11, radius: 2.3, opacity: 0.42, color: "#7f9bbb", fade: 1, focusX: 0.86, focusY: 0.15)),
              page: "#ffffff", text: "#18232f", accent: "#2f6fae", font: "system", separator: "line", shell: "#e3ecf5"),
        style("coastal-haze", "Coastal Haze", field(180, ["#e7f1f2", "#cfe3e6", "#f3ece2"], pattern: ("waves", "#7fb3bb", 0.26), dots: DotTexture("halftone", spacing: 12, radius: 2.8, opacity: 0.4, color: "#6ea8b1", fade: 0.8, focusX: 0.0, focusY: 1.0)),
              page: "#fbfdfd", text: "#17292d", accent: "#24808d", font: "serif", separator: "wave", shell: "#e1eef0"),
        style("deep-ink", "Deep Ink", field(0, ["#2b2f5a", "#151833", "#0b0d1f"], radial: (0.5, 0.0), glow: ("#4a4fa0", 0.5, 0.05), grain: 0.05, dots: DotTexture("scatter", spacing: 15, radius: 2.1, opacity: 0.55, color: "#b9bdf5", fade: 0.6, focusX: 0.86, focusY: 0.0)),
              page: "#1c1f36", text: "#e8e7f3", accent: "#a3abff", font: "serif", separator: "dotted", shell: "#161a30"),
        style("apricot-grid", "Apricot Grid", field(120, ["#ffe3c2", "#ffc9a3"], pattern: ("grid", "#e08a5a", 0.22), dots: DotTexture("grid", spacing: 14, radius: 2.4, opacity: 0.45, color: "#e07a43")),
              page: "#fffaf3", text: "#33200f", accent: "#b9631b", font: "mono", separator: "dotted", shell: "#fde6cf"),
        style("sage-mist", "Sage Mist", field(0, ["#e6efe6", "#cfdccf"], radial: (0.2, 0.8), pattern: ("blobs", "#a9c2a8", 0.32), grain: 0.05, dots: DotTexture("cluster", spacing: 13, radius: 2.4, opacity: 0.4, color: "#6f8f6e", fade: 0.6, focusX: 0.2, focusY: 0.8)),
              page: "#fbfdfa", text: "#1e2a20", accent: "#46704c", font: "rounded", separator: "line", shell: "#e3ece3"),
        style("midnight-constellation", "Midnight Constellation", field(170, ["#0f1430", "#1d2550", "#2a1f4f"], pattern: ("stars", "#fff6d6", 0.85), dots: DotTexture("radial", spacing: 16, radius: 2.1, opacity: 0.4, color: "#fff6d6", fade: 0.8, focusX: 0.85, focusY: 0.15)),
              page: "#181c35", text: "#ece9f6", accent: "#f2c46b", font: "serif", separator: "dots", shell: "#141933"),
        style("rose-paper", "Rose Paper", field(150, ["#f9e1e4", "#f2ccd3"], pattern: ("halftone", "#e79aa8", 0.26), grain: 0.1, dots: DotTexture("halftone", spacing: 11, radius: 2.6, opacity: 0.4, color: "#e58fa0", fade: 0.9, focusX: 1.0, focusY: 0.0)),
              page: "#fffafa", text: "#3a1d24", accent: "#b04460", font: "serif", separator: "tape", shell: "#f6dfe3"),
        style("mineral-blue", "Mineral Blue", field(110, ["#cfe1ee", "#9fbfd6", "#7aa2bf"], pattern: ("diagonal", "#ffffff", 0.16), dots: DotTexture("fade", spacing: 13, radius: 2.3, opacity: 0.6, color: "#ffffff", fade: 0.8, focusX: 0.1, focusY: 0.9)),
              page: "#f9fbfd", text: "#142433", accent: "#2a6492", font: "system", separator: "line", shell: "#d5e3ee"),
        style("amber-desk", "Amber Desk", field(0, ["#fff0cc", "#f7d699", "#e8b964"], radial: (0.8, 0.1), glow: ("#fff7dc", 0.85, 0.08), grain: 0.08, dots: DotTexture("scatter", spacing: 13, radius: 2.4, opacity: 0.4, color: "#b07a1e", fade: 0.8, focusX: 0.85, focusY: 0.1)),
              page: "#fffcf4", text: "#2f2410", accent: "#94660f", font: "serif", separator: "line", shell: "#f8e7c2"),
        style("cloud-study", "Cloud Study", field(180, ["#f2f5fa", "#e3e9f2"], pattern: ("blobs", "#ffffff", 0.65), dots: DotTexture("grid", spacing: 12, radius: 2.2, opacity: 0.4, color: "#9aa8c4")),
              page: "#ffffff", text: "#1d2430", accent: "#4d5fe0", font: "system", separator: "dotted", shell: "#e9eef6"),
        style("forest-dusk", "Forest Dusk", field(160, ["#2f4a3a", "#1d3027", "#3a2f3f"], glow: ("#f0b46a", 0.8, 0.28), pattern: ("hills", "#12201a", 0.5), dots: DotTexture("scatter", spacing: 14, radius: 2.2, opacity: 0.6, color: "#f6dca8", fade: 0.7, focusX: 0.8, focusY: 0.25)),
              page: "#f6f8f4", text: "#18241c", accent: "#356b47", font: "serif", separator: "wave", shell: "#22362c"),
        style("lilac-fog", "Lilac Fog", field(0, ["#f3ecf8", "#e2d6ef", "#d2c5e6"], radial: (0.5, 0.5), pattern: ("waves", "#ffffff", 0.28), grain: 0.07, dots: DotTexture("radial", spacing: 12, radius: 2.3, opacity: 0.5, color: "#9a7cc0", fade: 0.5, focusX: 0.86, focusY: 0.5)),
              page: "#fdfbff", text: "#2b2236", accent: "#7d50a8", font: "rounded", separator: "wave", shell: "#ece4f4"),
        style("copper-evening", "Copper Evening", field(140, ["#3a2420", "#6b3a2c", "#b8673f"], glow: ("#ffb87a", 0.75, 0.25), pattern: ("hills", "#2a1915", 0.45), dots: DotTexture("fade", spacing: 13, radius: 2.3, opacity: 0.55, color: "#ffd2a6", fade: 0.9, focusX: 0.86, focusY: 0.25)),
              page: "#fff6ef", text: "#2e1a12", accent: "#a64c22", font: "serif", separator: "tape", shell: "#4a2c24"),
        style("sea-glass", "Sea Glass", field(0, ["#d8f0ea", "#b8e2d8", "#9ccfc6"], radial: (0.3, 0.7), pattern: ("rings", "#ffffff", 0.32), dots: DotTexture("cluster", spacing: 12, radius: 2.4, opacity: 0.4, color: "#3f9a88", fade: 0.5, focusX: 0.14, focusY: 0.7)),
              page: "#f9fdfc", text: "#10302b", accent: "#1f7a69", font: "rounded", separator: "dots", shell: "#d3ece6"),
        style("charcoal-bloom", "Charcoal Bloom", field(0, ["#3b3540", "#26232b", "#18171c"], radial: (0.7, 0.3), pattern: ("blobs", "#a0607a", 0.26), grain: 0.06, dots: DotTexture("halftone", spacing: 11, radius: 2.5, opacity: 0.4, color: "#e08aa8", fade: 0.8, focusX: 0.86, focusY: 0.3)),
              page: "#222026", text: "#ece7ee", accent: "#e892b0", font: "system", separator: "dotted", shell: "#1e1c22"),
        style("lemon-wash", "Lemon Wash", field(135, ["#fff9d6", "#fdf0a8", "#f6fbe0"], pattern: ("halftone", "#e3c94a", 0.22), dots: DotTexture("grid", spacing: 12, radius: 2.2, opacity: 0.4, color: "#c9a91c")),
              page: "#fffef6", text: "#2a2610", accent: "#856b07", font: "system", separator: "line", shell: "#fbf3c8"),
        style("indigo-paper", "Indigo Paper", field(150, ["#dfe2f5", "#c6cbee"], pattern: ("grid", "#4b55a8", 0.11), grain: 0.1, dots: DotTexture("fade", spacing: 12, radius: 2.1, opacity: 0.45, color: "#3a43a3", fade: 0.9, focusX: 0.0, focusY: 0.0)),
              page: "#fbfbff", text: "#1a1d3a", accent: "#3a43a3", font: "serif", separator: "dotted", shell: "#dde0f4"),
        style("warm-concrete", "Warm Concrete", field(180, ["#e6e1da", "#d6cfc6"], pattern: ("diagonal", "#ffffff", 0.1), grain: 0.16, dots: DotTexture("scatter", spacing: 11, radius: 2.0, opacity: 0.4, color: "#6f655b")),
              page: "#fbf9f6", text: "#262320", accent: "#7a5f45", font: "mono", separator: "line", shell: "#e4dfd8"),
        style("morning-window", "Morning Window", field(200, ["#fdf3e1", "#f8dfc1", "#e9eef6"], glow: ("#fff6d8", 0.25, 0.1), pattern: ("window", "#ffffff", 0.35), dots: DotTexture("cluster", spacing: 12, radius: 2.4, opacity: 0.4, color: "#c99456", fade: 0.8, focusX: 0.14, focusY: 0.1)),
              page: "#fffdf8", text: "#2b241c", accent: "#9e6720", font: "serif", separator: "wave", shell: "#f7ead8"),
    ]
}

/// Gradient stop editing used by the Style panel and by reviewed agent proposals.
public extension Backdrop {
    static func mix(_ a: String, _ b: String, _ t: Double) -> String {
        let x = ColorMath.rgb(a), y = ColorMath.rgb(b)
        return ColorMath.hex(x.0 + (y.0 - x.0) * t, x.1 + (y.1 - x.1) * t, x.2 + (y.2 - x.2) * t)
    }

    /// Editable stops: always explicit, sorted, at least two.
    var editableStops: [ColorStop] { colorStops }

    /// Adds a stop in the middle of the widest gap, colored between its neighbours.
    mutating func addStop() {
        var s = editableStops
        guard s.count < 8 else { return }
        let i = (0..<(s.count - 1)).max { (s[$0 + 1].at - s[$0].at) < (s[$1 + 1].at - s[$1].at) } ?? 0
        s.insert(ColorStop(Self.mix(s[i].color, s[i + 1].color, 0.5), at: (s[i].at + s[i + 1].at) / 2), at: i + 1)
        stops = s
    }

    mutating func removeStop(_ i: Int) {
        var s = editableStops
        guard s.count > 2, s.indices.contains(i) else { return }
        s.remove(at: i); stops = s
    }

    /// Reorders colors while every position stays where it was.
    mutating func moveStop(_ i: Int, by d: Int) {
        var s = editableStops
        let j = i + d
        guard s.indices.contains(i), s.indices.contains(j) else { return }
        (s[i].color, s[j].color) = (s[j].color, s[i].color)
        (s[i].opacity, s[j].opacity) = (s[j].opacity, s[i].opacity)
        stops = s
    }

    mutating func updateStop(_ i: Int, _ f: (inout ColorStop) -> Void) {
        var s = editableStops
        guard s.indices.contains(i) else { return }
        f(&s[i])
        s[i].at = min(1, max(0, s[i].at))
        if let o = s[i].opacity { s[i].opacity = o >= 0.995 ? nil : max(0, o) }
        stops = s
    }

    /// The strongest luminance jump between two stops. Above 4.5:1 the toolbar chips that float on
    /// the backdrop can sit on a part they do not match.
    var stopContrast: Double {
        let c = editableStops.map(\.color)
        return c.flatMap { a in c.map { ColorMath.contrast(a, $0) } }.max() ?? 1
    }

    /// A calmer version: stops move toward their average until the jump is at most `limit`.
    func softened(limit: Double = 4.5) -> Backdrop {
        var b = self
        var s = editableStops
        let rgb = s.map { ColorMath.rgb($0.color) }
        let avg = ColorMath.hex(rgb.map(\.0).reduce(0, +) / Double(rgb.count), rgb.map(\.1).reduce(0, +) / Double(rgb.count), rgb.map(\.2).reduce(0, +) / Double(rgb.count))
        let base = s.map(\.color)
        for step in 1...20 where b.stopContrast > limit {
            for k in s.indices { s[k].color = Self.mix(base[k], avg, Double(step) / 20) }
            b.stops = s
        }
        return b
    }
}
