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
        ("spectrum", "Spectrum", "a slowly moving multi-color gradient for one title or decorative label (value spectrum:<aurora|prism|sunset|ocean|neon>:<still|slow|normal|fast>:<forward|backward>); never body text, at most one per note, 200 characters at most"),
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

    /// The palette with every color pushed to 4.5:1 on the page (darker on light pages, lighter on
    /// dark ones), so the text stays readable at every moment of the animation.
    public func colors(page: String) -> [String] {
        (Self.palettes.first { $0.id == palette }?.colors ?? Self.palettes[0].colors).map { ColorMath.readable($0, on: page).hex }
    }
}

public extension TextEffects {
    /// A stored effect value is a plain kind or a spectrum value.
    static func isValid(_ value: String) -> Bool { EffectSpec(value) != nil }
}

/// One text effect with its own colors, kept apart from the text color (the `textStyle` mark).
/// Stored in the editor as `kind`, `kind?color=#rrggbb&stops=#a,#b&angle=30&intensity=0.6`, or a
/// Spectrum value; stored in documents as the `effect` mark's attributes.
public struct EffectSpec: Hashable, Sendable {
    public var kind: String
    /// Glow, shadow, outline, lift and emboss color; for accent, the letters' color.
    public var color: String?
    /// Gradient colors, 2–5, left to right along `angle`.
    public var stops: [String]?
    /// Gradient direction in degrees (0 = left to right, 90 = top to bottom).
    public var angle: Double?
    /// 0…1: how strong the glow, shadow, outline, lift or emboss is.
    public var intensity: Double?
    public var spectrum: Spectrum?

    public init(kind: String, color: String? = nil, stops: [String]? = nil, angle: Double? = nil, intensity: Double? = nil) {
        self.kind = kind; self.color = color; self.stops = stops; self.angle = angle; self.intensity = intensity
    }

    static func hex(_ s: String) -> Bool { s.range(of: "^#[0-9A-Fa-f]{6}$", options: .regularExpression) != nil }

    public init?(_ value: String) {
        if let sp = Spectrum(value) { kind = "spectrum"; spectrum = sp; return }
        let parts = value.split(separator: "?", maxSplits: 1).map(String.init)
        guard let k = parts.first, TextEffects.kinds.contains(k), k != "spectrum" else { return nil }
        kind = k
        guard parts.count == 2 else { return }
        for pair in parts[1].split(separator: "&") {
            let kv = pair.split(separator: "=", maxSplits: 1).map(String.init)
            guard kv.count == 2 else { return nil }
            switch kv[0] {
            case "color": guard Self.hex(kv[1]) else { return nil }; color = kv[1].lowercased()
            case "stops":
                let s = kv[1].split(separator: ",").map { String($0).lowercased() }
                guard (2...5).contains(s.count), s.allSatisfy(Self.hex) else { return nil }; stops = s
            case "angle": guard let a = Double(kv[1]), (0...360).contains(a) else { return nil }; angle = a
            case "intensity": guard let i = Double(kv[1]), (0...1).contains(i) else { return nil }; intensity = i
            default: return nil
            }
        }
    }

    public var value: String {
        if let sp = spectrum { return sp.value }
        var q: [String] = []
        if let c = color { q.append("color=\(c)") }
        if let s = stops { q.append("stops=\(s.joined(separator: ","))") }
        if let a = angle { q.append("angle=\(Int(a))") }
        if let i = intensity { q.append("intensity=\(String(format: "%.2f", i))") }
        return q.isEmpty ? kind : kind + "?" + q.joined(separator: "&")
    }

    /// The document mark for this effect.
    public var mark: Mark {
        if let sp = spectrum { return Mark("effect", attrs: ["kind": "spectrum", "palette": .string(sp.palette), "speed": .string(sp.speed), "direction": .string(sp.direction)]) }
        var a: [String: JSONValue] = ["kind": .string(kind)]
        if let c = color { a["color"] = .string(c) }
        if let s = stops { a["stops"] = .string(s.joined(separator: ",")) }
        if let x = angle { a["angle"] = .number(x) }
        if let i = intensity { a["intensity"] = .number(i) }
        return Mark("effect", attrs: a)
    }

    /// From a document mark; unknown or malformed parts are dropped, never trusted.
    public init?(mark m: Mark) {
        guard m.type == "effect", let k = m.attrs?["kind"]?.string else { return nil }
        if k == "spectrum" {
            guard let sp = Spectrum("spectrum:\(m.attrs?["palette"]?.string ?? "aurora"):\(m.attrs?["speed"]?.string ?? "slow"):\(m.attrs?["direction"]?.string ?? "forward")") ?? Spectrum("spectrum") else { return nil }
            self.init(kind: "spectrum"); spectrum = sp; return
        }
        guard TextEffects.kinds.contains(k) else { return nil }
        self.init(kind: k)
        if let c = m.attrs?["color"]?.string, Self.hex(c) { color = c.lowercased() }
        if let s = m.attrs?["stops"]?.string?.split(separator: ",").map({ String($0).lowercased() }), (2...5).contains(s.count), s.allSatisfy(Self.hex) { stops = s }
        if let a = m.attrs?["angle"]?.double, (0...360).contains(a) { angle = a }
        if let i = m.attrs?["intensity"]?.double, (0...1).contains(i) { intensity = i }
    }

    /// Colors that fill the letters (accent, gradient stops), each pushed to 4.5:1 on the page.
    public func fillColors(accent: String, text: String, page: String) -> [String] {
        let d = TextEffects.colors(accent: accent, text: text, page: page)
        switch kind {
        case "accent": return [ColorMath.readable(color ?? accent, on: page).hex]
        case "gradient": return (stops ?? [d.start, d.end]).map { ColorMath.readable($0, on: page).hex }
        case "spectrum": return spectrum?.colors(page: page) ?? []
        default: return []
        }
    }

    /// True when a chosen fill color had to be darkened or lightened to stay readable.
    public func adjustedForContrast(page: String) -> Bool {
        let chosen = kind == "accent" ? [color].compactMap { $0 } : kind == "gradient" ? (stops ?? []) : []
        return chosen.contains { ColorMath.contrast($0, page) < 4.5 }
    }
}
