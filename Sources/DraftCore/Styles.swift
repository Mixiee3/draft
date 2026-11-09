import Foundation

public struct StyleDef: Hashable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var tokens: StyleTokens
}

/// A style the user saved. `base` is the built-in style it started from; documents using a
/// deleted user style fall back to it.
public struct UserStyle: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var base: String
    public var tokens: StyleTokens
    public var pinned: Bool?
    public var createdAt: Double
    public init(id: String = newId("u_"), name: String, base: String, tokens: StyleTokens, pinned: Bool? = nil, createdAt: Double = nowMs()) {
        self.id = id; self.name = name; self.base = base; self.tokens = tokens; self.pinned = pinned; self.createdAt = createdAt
    }
}

/// Original Draft styles: a calm default first, then expressive and scenic ones.
public enum Styles {
    public static let builtIn: [StyleDef] = [
        StyleDef(id: "paper", name: "Paper", tokens: StyleTokens(backdrop: Backdrop(kind: "solid", color: "#e9e6df"), pageColor: "#fffdf8", textColor: "#252521", accent: "#5b6cf0", font: "serif", separator: "line", shellTint: "#f1efea")),
        StyleDef(id: "tidepool", name: "Tidepool", tokens: StyleTokens(backdrop: Backdrop(kind: "image", image: "lagoon", blur: false, effect: "immersive"), pageColor: "#f9fcfc", textColor: "#13272e", accent: "#1f7f93", font: "serif", separator: "wave", shellTint: "#dcecef")),
        StyleDef(id: "ember", name: "Ember", tokens: StyleTokens(backdrop: Backdrop(kind: "image", image: "dusk", blur: false, effect: "immersive"), pageColor: "#fff8f2", textColor: "#2a1712", accent: "#d2553c", font: "serif", separator: "tape", shellTint: "#f6e0d8")),
        StyleDef(id: "meadow", name: "Meadow", tokens: StyleTokens(backdrop: Backdrop(kind: "image", image: "meadow", blur: true, effect: "faded"), pageColor: "#fcfdf7", textColor: "#1f2a1b", accent: "#4f8a44", font: "rounded", separator: "dotted", shellTint: "#e6efdc")),
        StyleDef(id: "citrus", name: "Citrus", tokens: StyleTokens(backdrop: Backdrop(kind: "gradient", from: "#ffd36e", to: "#ff8a5c", angle: 135), pageColor: "#fffdf6", textColor: "#2b2214", accent: "#e0752e", font: "system", separator: "tape", shellTint: "#fbead0")),
        StyleDef(id: "nightink", name: "Night Ink", tokens: StyleTokens(backdrop: Backdrop(kind: "image", image: "night", blur: false, effect: "immersive"), pageColor: "#20223a", textColor: "#ebe8f6", accent: "#a99cff", font: "serif", separator: "dotted", shellTint: "#2a2b44")),
        StyleDef(id: "typewriter", name: "Typewriter", tokens: StyleTokens(backdrop: Backdrop(kind: "solid", color: "#d9dde3"), pageColor: "#ffffff", textColor: "#1d1f22", accent: "#3a6ea5", font: "mono", separator: "dotted", shellTint: "#eceef1")),
        StyleDef(id: "linen", name: "Linen", tokens: StyleTokens(backdrop: Backdrop(kind: "solid", color: "#e7dccb"), pageColor: "#fbf6ec", textColor: "#3a2f24", accent: "#a0643a", font: "serif", separator: "dots", shellTint: "#efe6d8")),
        StyleDef(id: "aurora", name: "Aurora", tokens: StyleTokens(backdrop: Backdrop(kind: "image", image: "aurora", blur: false, effect: "immersive"), pageColor: "#f6fbf9", textColor: "#13241f", accent: "#2b9a7a", font: "system", separator: "wave", shellTint: "#d9eee7")),
        StyleDef(id: "graphite", name: "Graphite", tokens: StyleTokens(backdrop: Backdrop(kind: "solid", color: "#2b2d31"), pageColor: "#1c1d20", textColor: "#e6e4df", accent: "#e0a64f", font: "system", separator: "line", shellTint: "#26272b")),
        StyleDef(id: "sorbet", name: "Sorbet", tokens: StyleTokens(backdrop: Backdrop(kind: "gradient", from: "#f6b3c8", to: "#b9c6ff", angle: 160), pageColor: "#fffafc", textColor: "#2e2133", accent: "#c0508a", font: "rounded", separator: "tape", shellTint: "#f6e3ef")),
        StyleDef(id: "harbor", name: "Harbor", tokens: StyleTokens(backdrop: Backdrop(kind: "image", image: "harbor", blur: true, effect: "immersive"), pageColor: "#f7f9fc", textColor: "#18222e", accent: "#2f6fb0", font: "serif", separator: "line", shellTint: "#dfe7f1")),
        StyleDef(id: "orchard", name: "Orchard", tokens: StyleTokens(backdrop: Backdrop(kind: "image", image: "orchard", blur: false, effect: "faded"), pageColor: "#fffdf5", textColor: "#2a2416", accent: "#c26a2a", font: "rounded", separator: "dotted", shellTint: "#f3ead5")),
    ]

    /// The user's saved styles; kept in step with library.json by the app.
    nonisolated(unsafe) public static var user: [UserStyle] = []

    /// Built-in styles followed by saved ones (pinned first).
    public static var all: [StyleDef] {
        builtIn + Backgrounds.presets + user.sorted { ($0.pinned == true ? 0 : 1, $0.createdAt) < ($1.pinned == true ? 0 : 1, $1.createdAt) }.map { StyleDef(id: $0.id, name: $0.name, tokens: $0.tokens) }
    }

    public static func style(_ id: String) -> StyleDef {
        if let u = user.first(where: { $0.id == id }) { return StyleDef(id: u.id, name: u.name, tokens: u.tokens) }
        return builtIn.first { $0.id == id } ?? Backgrounds.presets.first { $0.id == id } ?? builtIn[0]
    }

    /// Style tokens with the document's sparse overrides applied.
    /// What the editor shows: an untouched Paper page turns dark with a dark app. The file keeps
    /// the light style, so exports and other machines are unaffected.
    public static func forDisplay(_ a: DocumentAppearance, dark: Bool) -> StyleTokens {
        var t = resolve(a)
        guard dark, a.styleId == "paper", a.overrides.pageColor == nil, a.overrides.textColor == nil, a.overrides.backdrop == nil else { return t }
        t.backdrop = Backdrop(kind: "solid", color: "#19191b")
        t.pageColor = "#232325"
        t.textColor = "#e7e4de"
        t.shellTint = "#1f1f21"
        return t
    }

    public static func resolve(_ a: DocumentAppearance) -> StyleTokens {
        var t = style(a.styleId).tokens
        let o = a.overrides
        if let b = o.backdrop { t.backdrop = b }
        if let v = o.pageColor { t.pageColor = v }
        if let v = o.textColor { t.textColor = v }
        if let v = o.accent { t.accent = v }
        if let v = o.font { t.font = v }
        if let v = o.separator { t.separator = v }
        if let v = o.shellTint { t.shellTint = v }
        return t
    }

    /// Color shown around a document preview in the library.
    public static func tint(_ t: StyleTokens) -> String {
        switch t.backdrop.kind {
        case "solid": return t.backdrop.color ?? "#d9d4ca"
        case "gradient": return t.backdrop.from ?? t.accent
        case "image": return t.accent
        default: return "#d9d4ca"
        }
    }
}

/// Original scenic backdrop palettes. Rendered natively (vector), no third-party imagery.
public struct ScenePalette: Hashable, Sendable {
    public var sky: (String, String)
    public var sun: String
    public var layers: [String]
    public var dots: String
    public static func == (a: ScenePalette, b: ScenePalette) -> Bool { a.sky == b.sky && a.sun == b.sun && a.layers == b.layers && a.dots == b.dots }
    public func hash(into h: inout Hasher) { h.combine(sun); h.combine(layers) }
}

public enum Scenes {
    public static let order = ["lagoon", "dusk", "meadow", "ridge", "fog", "night", "aurora", "dunes", "harbor", "orchard", "snowfield", "canyon"]
    public static let all: [String: (name: String, seed: Double, palette: ScenePalette)] = [
        "lagoon": ("Lagoon", 1, ScenePalette(sky: ("#8fd3e6", "#e8f6f4"), sun: "#fff6d8", layers: ["#7cc4cf", "#4fa6b6", "#2f8597", "#1f6475"], dots: "#ffffff")),
        "dusk": ("Dusk", 2, ScenePalette(sky: ("#f06a4a", "#f9c79a"), sun: "#fff1c9", layers: ["#f19a7b", "#e0715d", "#c5524b", "#8e3a42"], dots: "#fff4ea")),
        "meadow": ("Meadow", 3, ScenePalette(sky: ("#cfe7c4", "#f6f3dc"), sun: "#fffbe0", layers: ["#b4d69a", "#8dbd77", "#679f5d", "#4a7f4b"], dots: "#ffffff")),
        "ridge": ("Ridge", 4, ScenePalette(sky: ("#a9b5e8", "#efe6f4"), sun: "#fff3f7", layers: ["#b3a6dd", "#8f86c9", "#6b66ad", "#4b4a86"], dots: "#ffffff")),
        "fog": ("Fog", 5, ScenePalette(sky: ("#dfe3e8", "#f6f5f2"), sun: "#ffffff", layers: ["#d3d8de", "#c2c8d0", "#aeb6c0", "#9aa3ae"], dots: "#ffffff")),
        "night": ("Night", 6, ScenePalette(sky: ("#151a33", "#3b3568"), sun: "#f5e9c9", layers: ["#2c2a55", "#232247", "#1b1a39", "#13132b"], dots: "#c9c4ff")),
        "aurora": ("Aurora", 7, ScenePalette(sky: ("#0f2a3a", "#3fbf9a"), sun: "#d7fff0", layers: ["#1d4e57", "#173f48", "#11313a", "#0b232b"], dots: "#bff7e2")),
        "dunes": ("Dunes", 8, ScenePalette(sky: ("#f7c98b", "#fbe9c8"), sun: "#fff7e0", layers: ["#e8b77c", "#d79b60", "#bf7f4a", "#9c6238"], dots: "#fff3dc")),
        "harbor": ("Harbor", 9, ScenePalette(sky: ("#9ec3e6", "#eaf1f8"), sun: "#fffaf0", layers: ["#7fa8cf", "#5b88b6", "#3f6b9a", "#2a4f78"], dots: "#ffffff")),
        "orchard": ("Orchard", 10, ScenePalette(sky: ("#f9d8b0", "#fdf3e1"), sun: "#fff8e6", layers: ["#c9d98a", "#a9c06a", "#86a24f", "#64803c"], dots: "#ffe3c4")),
        "snowfield": ("Snowfield", 11, ScenePalette(sky: ("#cfe0f2", "#f8fbff"), sun: "#ffffff", layers: ["#e6eef7", "#d7e3f0", "#c4d4e6", "#aec3da"], dots: "#ffffff")),
        "canyon": ("Canyon", 12, ScenePalette(sky: ("#f0a36b", "#f8d9b8"), sun: "#fff0d6", layers: ["#d9784d", "#bf5d3c", "#9c4632", "#743226"], dots: "#ffe6cf")),
    ]
}

/* ---------- Contrast (WCAG 2.x) ---------- */

public enum ColorMath {
    public static func rgb(_ hex: String) -> (Double, Double, Double) {
        var h = hex.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "#", with: "")
        if h.count == 3 { h = h.map { "\($0)\($0)" }.joined() }
        let n = UInt32(h.prefix(6), radix: 16) ?? 0
        return (Double((n >> 16) & 255) / 255, Double((n >> 8) & 255) / 255, Double(n & 255) / 255)
    }
    public static func luminance(_ hex: String) -> Double {
        let (r, g, b) = rgb(hex)
        func f(_ s: Double) -> Double { s <= 0.03928 ? s / 12.92 : pow((s + 0.055) / 1.055, 2.4) }
        return 0.2126 * f(r) + 0.7152 * f(g) + 0.0722 * f(b)
    }
    public static func contrast(_ a: String, _ b: String) -> Double {
        let la = luminance(a), lb = luminance(b)
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }
    public static func isDark(_ hex: String) -> Bool { luminance(hex) < 0.22 }

    public static func hex(_ r: Double, _ g: Double, _ b: Double) -> String {
        String(format: "#%02x%02x%02x", Int((min(1, max(0, r)) * 255).rounded()), Int((min(1, max(0, g)) * 255).rounded()), Int((min(1, max(0, b)) * 255).rounded()))
    }

    /// The text color nearest to `text` (same hue, moved toward black or white) that reaches
    /// `target` contrast on `page`; returns it with the new ratio.
    public static func readable(_ text: String, on page: String, target: Double = 4.5) -> (hex: String, ratio: Double) {
        if contrast(text, page) >= target { return (text, contrast(text, page)) }
        let (r, g, b) = rgb(text)
        let toward = isDark(page) ? 1.0 : 0.0
        for i in 1...100 {
            let t = Double(i) / 100
            let c = hex(r + (toward - r) * t, g + (toward - g) * t, b + (toward - b) * t)
            if contrast(c, page) >= target { return (c, contrast(c, page)) }
        }
        let c = toward == 1 ? "#ffffff" : "#000000"
        return (c, contrast(c, page))
    }
}

/// Stable per-block variation (hand-made look): the same id always gives the same values.
public enum Variation {
    /// A value in 0..<1 for `id` and `salt` (FNV-1a).
    public static func unit(_ id: String, _ salt: Int = 0) -> Double {
        var h: UInt64 = 0xcbf29ce484222325
        for b in (id + "#\(salt)").utf8 { h ^= UInt64(b); h = h &* 0x100000001b3 }
        return Double(h % 10_000) / 10_000
    }
}
