import Foundation

public struct StyleDef: Hashable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var tokens: StyleTokens
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
    ]

    public static func style(_ id: String) -> StyleDef { builtIn.first { $0.id == id } ?? builtIn[0] }

    /// Style tokens with the document's sparse overrides applied.
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
    public static let order = ["lagoon", "dusk", "meadow", "ridge", "fog", "night"]
    public static let all: [String: (name: String, seed: Double, palette: ScenePalette)] = [
        "lagoon": ("Lagoon", 1, ScenePalette(sky: ("#8fd3e6", "#e8f6f4"), sun: "#fff6d8", layers: ["#7cc4cf", "#4fa6b6", "#2f8597", "#1f6475"], dots: "#ffffff")),
        "dusk": ("Dusk", 2, ScenePalette(sky: ("#f06a4a", "#f9c79a"), sun: "#fff1c9", layers: ["#f19a7b", "#e0715d", "#c5524b", "#8e3a42"], dots: "#fff4ea")),
        "meadow": ("Meadow", 3, ScenePalette(sky: ("#cfe7c4", "#f6f3dc"), sun: "#fffbe0", layers: ["#b4d69a", "#8dbd77", "#679f5d", "#4a7f4b"], dots: "#ffffff")),
        "ridge": ("Ridge", 4, ScenePalette(sky: ("#a9b5e8", "#efe6f4"), sun: "#fff3f7", layers: ["#b3a6dd", "#8f86c9", "#6b66ad", "#4b4a86"], dots: "#ffffff")),
        "fog": ("Fog", 5, ScenePalette(sky: ("#dfe3e8", "#f6f5f2"), sun: "#ffffff", layers: ["#d3d8de", "#c2c8d0", "#aeb6c0", "#9aa3ae"], dots: "#ffffff")),
        "night": ("Night", 6, ScenePalette(sky: ("#151a33", "#3b3568"), sun: "#f5e9c9", layers: ["#2c2a55", "#232247", "#1b1a39", "#13132b"], dots: "#c9c4ff")),
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
}
