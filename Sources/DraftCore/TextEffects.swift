import Foundation

/// Inline text effects, stored as an `effect` mark (`{"type":"effect","attrs":{"kind":"glow"}}`).
/// The text itself never changes; removing the mark removes the effect.
public enum TextEffects {
    /// kind, menu name, where it fits (shown in the formatting guide).
    public static let all: [(kind: String, name: String, use: String)] = [
        ("accent", "Accent", "a key term or a short heading in the document's accent color"),
        ("gradient", "Gradient", "one short title or phrase; at most one per section"),
        ("glow", "Glow", "a single word that should stand out on dark pages"),
        ("shadow", "Shadow", "short headings on busy or image backdrops"),
        ("outline", "Outline", "large display words only; avoid in body text"),
        ("lift", "Lift", "a playful 3D offset for a title or label"),
        ("emboss", "Emboss", "a quiet pressed-in look for labels and captions"),
        ("spectrum", "Spectrum", "a slowly moving multi-colour gradient for one title or decorative label (value spectrum:<aurora|prism|sunset|ocean|neon>:<still|slow|normal|fast>:<forward|backward>); never body text, at most one per note, 200 characters at most"),
    ]
    public static let kinds = all.map(\.kind)

    /// Both ends of every effect color meet 4.5:1 on the page, so no effect can make text unreadable.
    public static func colors(accent: String, text: String, page: String) -> (start: String, end: String) {
        let a = ColorMath.readable(accent, on: page).hex
        let mid = Backdrop.mix(accent, text, 0.55)
        return (a, ColorMath.readable(mid, on: page).hex)
    }
}

/// Block decorations (`decoration` attribute). Content and block IDs never change; removing the
/// decoration restores the plain block.
public enum BlockEffects {
    public static let all: [(kind: String, name: String, use: String)] = [
        ("focus", "Focus", "an accent bar for the one paragraph to remember"),
        ("block", "Block", "a quiet tinted box (pairs with block_color)"),
        ("gradient", "Gradient", "a soft accent wash for a summary or key definition"),
        ("glass", "Glass", "a frosted card for a short aside on image or field backdrops"),
        ("glow", "Glow", "a lit edge for a single warning or decision; at most one per note"),
        ("accent", "Accent", "an accent outline; on a heading, an accent underline for section titles"),
    ]
    public static let kinds = all.map(\.kind)
    /// Drawn as a box behind the block, so the text is inset.
    public static func isBoxed(_ d: String?, heading: Bool) -> Bool {
        guard let d else { return false }
        return ["block", "gradient", "glass", "glow"].contains(d) || (d == "accent" && !heading)
    }
}

/// Animated gradient text (`effect` mark with `kind: "spectrum"`). Stored as a value like
/// `spectrum:aurora:slow:forward`; every part after `spectrum` is optional. One continuous gradient
/// runs across the whole phrase; exports show it still.
public struct Spectrum: Hashable, Sendable {
    public var palette: String
    public var speed: String
    public var direction: String

    public static let palettes: [(id: String, name: String, colors: [String])] = [
        ("aurora", "Aurora", ["#2fbf9a", "#3f8fd8", "#8b5cf6", "#2fbf9a"]),
        ("prism", "Prism", ["#e5484d", "#f5a524", "#3fb950", "#3a8ee6", "#8e4ec6", "#e5484d"]),
        ("sunset", "Sunset Spectrum", ["#f2994a", "#eb5757", "#bb6bd9", "#f2994a"]),
        ("ocean", "Ocean Rainbow", ["#0ea5b7", "#2f80ed", "#56ccf2", "#27ae60", "#0ea5b7"]),
        ("neon", "Neon Dusk", ["#ff4fd8", "#7b61ff", "#00d4ff", "#ff4fd8"]),
    ]
    /// Seconds for one full cycle; 0 = still.
    public static let speeds: [(id: String, name: String, seconds: Double)] = [("still", "Still", 0), ("slow", "Slow", 9), ("normal", "Normal", 6), ("fast", "Fast", 3.5)]
    public static let directions = ["forward", "backward"]
    /// The effect is for titles, headings and short labels, never whole passages.
    public static let maxLength = 200

    public init(palette: String = "aurora", speed: String = "slow", direction: String = "forward") {
        self.palette = palette; self.speed = speed; self.direction = direction
    }

    public init?(_ value: String) {
        let parts = value.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        guard parts.first == "spectrum", parts.count <= 4 else { return nil }
        self.init()
        if parts.count > 1 { guard Self.palettes.contains(where: { $0.id == parts[1] }) else { return nil }; palette = parts[1] }
        if parts.count > 2 { guard Self.speeds.contains(where: { $0.id == parts[2] }) else { return nil }; speed = parts[2] }
        if parts.count > 3 { guard Self.directions.contains(parts[3]) else { return nil }; direction = parts[3] }
    }

    public var value: String { "spectrum:\(palette):\(speed):\(direction)" }
    public var seconds: Double { Self.speeds.first { $0.id == speed }?.seconds ?? 0 }
    public var name: String { Self.palettes.first { $0.id == palette }?.name ?? "Spectrum" }

    /// The palette with every colour pushed to 4.5:1 on the page (darker on light pages, lighter on
    /// dark ones), so the text stays readable at every moment of the animation.
    public func colors(page: String) -> [String] {
        (Self.palettes.first { $0.id == palette }?.colors ?? Self.palettes[0].colors).map { ColorMath.readable($0, on: page).hex }
    }
}

public extension TextEffects {
    /// A stored effect value is a plain kind or a spectrum value.
    static func isValid(_ value: String) -> Bool { kinds.contains(value) || Spectrum(value) != nil }
}
