import Foundation

/// A curated look: an effect value with its own name and group. Text presets are `EffectSpec`
/// values; block presets pair a decoration with a tint; highlight presets are colors.
public struct EffectPreset: Hashable, Sendable {
    public let id: String
    public let name: String
    public let group: String
    public let value: String
}

/// Original Draft presets. Combinations, not just hues, differ: color, strength, direction, stop
/// positions, focus and speed are chosen per preset, and tests reject duplicates.
public enum EffectPresets {
    public static let groups = ["Calm", "Warm", "Cool", "Editorial", "Neon", "Nature", "Dark", "Study", "Decorative"]

    static func p(_ kind: String, _ name: String, _ group: String, _ query: String) -> EffectPreset {
        EffectPreset(id: kind + "-" + name.lowercased().replacingOccurrences(of: " ", with: "-"), name: name, group: group, value: query.isEmpty ? kind : kind + "?" + query)
    }

    public static let glow: [EffectPreset] = [
        p("glow", "Moonlight", "Calm", "color=#9fb7ff&intensity=0.45"),
        p("glow", "Candlelight", "Warm", "color=#ffb74d&intensity=0.55"),
        p("glow", "Polar", "Cool", "color=#4dd0e1&intensity=0.60"),
        p("glow", "Neon Kiss", "Neon", "color=#ff4fd8&intensity=0.90"),
        p("glow", "Firefly", "Nature", "color=#c6ff00&intensity=0.70"),
        p("glow", "Coal", "Dark", "color=#ff7043&intensity=0.80"),
        p("glow", "Soft Focus", "Study", "color=#7986cb&intensity=0.30"),
        p("glow", "Halo", "Decorative", "color=#ffd54f&intensity=1.00"),
    ]
    public static let shadow: [EffectPreset] = [
        p("shadow", "Paper", "Calm", "color=#000000&intensity=0.25"),
        p("shadow", "Lamp", "Warm", "color=#6d4c41&intensity=0.50"),
        p("shadow", "Slate", "Cool", "color=#37474f&intensity=0.55"),
        p("shadow", "Ink Drop", "Editorial", "color=#1a237e&intensity=0.70"),
        p("shadow", "Moss", "Nature", "color=#33691e&intensity=0.45"),
        p("shadow", "Night", "Dark", "color=#000000&intensity=1.00"),
        p("shadow", "Plum", "Decorative", "color=#4a148c&intensity=0.60"),
    ]
    public static let outline: [EffectPreset] = [
        p("outline", "Pencil", "Study", "color=#546e7a&intensity=0.20"),
        p("outline", "Ink Rim", "Editorial", "color=#1e3a8a&intensity=0.45"),
        p("outline", "Neon Edge", "Neon", "color=#00e5ff&intensity=0.70"),
        p("outline", "Coral", "Warm", "color=#ff7043&intensity=0.50"),
        p("outline", "Leaf", "Nature", "color=#43a047&intensity=0.40"),
        p("outline", "Gold Leaf", "Decorative", "color=#c9a227&intensity=0.60"),
    ]
    public static let lift: [EffectPreset] = [
        p("lift", "Soft Step", "Calm", "color=#90a4ae&intensity=0.30"),
        p("lift", "Retro", "Warm", "color=#ff7043&intensity=0.80"),
        p("lift", "Pool", "Cool", "color=#26c6da&intensity=0.60"),
        p("lift", "Poster", "Editorial", "color=#000000&intensity=0.70"),
        p("lift", "Arcade", "Neon", "color=#d500f9&intensity=1.00"),
        p("lift", "Moss Step", "Nature", "color=#7cb342&intensity=0.50"),
    ]
    public static let emboss: [EffectPreset] = [
        p("emboss", "Letterpress", "Editorial", "color=#000000&intensity=0.50"),
        p("emboss", "Stone", "Calm", "color=#607d8b&intensity=0.40"),
        p("emboss", "Brass", "Warm", "color=#8d6e63&intensity=0.60"),
        p("emboss", "Frost", "Cool", "color=#b3e5fc&intensity=0.70"),
        p("emboss", "Deep Press", "Dark", "color=#000000&intensity=1.00"),
    ]
    public static let accent: [EffectPreset] = [
        p("accent", "Ink Blue", "Editorial", "color=#2f5bd3"),
        p("accent", "Terracotta", "Warm", "color=#c75a1d"),
        p("accent", "Lagoon", "Cool", "color=#00897b"),
        p("accent", "Fern", "Nature", "color=#2e7d32"),
        p("accent", "Plum", "Decorative", "color=#7b1fa2"),
        p("accent", "Cerise", "Neon", "color=#d81b60"),
        p("accent", "Graphite", "Study", "color=#455a64"),
        p("accent", "Saffron", "Calm", "color=#b8860b"),
    ]

    /// 30 gradients across 15 moods, two each, with explicit stops, positions and directions; some radial.
    public static let gradient: [EffectPreset] = [
        p("gradient", "Quiet Ink", "Editorial", "stops=#1f3b73,#6b7fa8&at=0,100&angle=0"),
        p("gradient", "Byline", "Editorial", "stops=#7a2e3a,#2b4a6f,#3d6b5e&at=0,55,100&angle=15"),
        p("gradient", "First Light", "Warm", "stops=#e8743b,#f2b134,#d1495b&at=0,40,100&angle=0"),
        p("gradient", "Dawn Haze", "Calm", "stops=#c76d8e,#e39b6b&at=10,90&angle=30"),
        p("gradient", "Afterglow", "Warm", "stops=#ff5f6d,#ffc371&at=0,100&angle=180"),
        p("gradient", "Dusk Strip", "Decorative", "stops=#2d1b69,#c2185b,#ff8a65&at=0,50,100&angle=0"),
        p("gradient", "Deep Current", "Cool", "stops=#0b5e8e,#1aa6b7,#2fc4a0&at=0,60,100&angle=0"),
        p("gradient", "Tide Pool", "Cool", "stops=#00796b,#4fc3f7&focus=0.20,0.50"),
        p("gradient", "Canopy", "Nature", "stops=#1b5e20,#689f38,#c0ca33&at=0,45,100&angle=0"),
        p("gradient", "Moss & Bark", "Nature", "stops=#4e6e3a,#8d6e63&at=0,100&angle=90"),
        p("gradient", "Lilac Field", "Calm", "stops=#7e57c2,#ba68c8,#9575cd&at=0,50,100&angle=0"),
        p("gradient", "Iris", "Decorative", "stops=#4527a0,#d81b60&focus=0.50,0.50"),
        p("gradient", "Slate & Copper", "Editorial", "stops=#455a64,#b87333&at=0,100&angle=0"),
        p("gradient", "Malachite", "Nature", "stops=#00695c,#2e7d32,#00838f&at=0,30,100&angle=45"),
        p("gradient", "Sepia", "Study", "stops=#5d4037,#8d6e63&at=0,100&angle=0"),
        p("gradient", "Margin Note", "Study", "stops=#283593,#00897b&at=20,80&angle=0"),
        p("gradient", "Night Ink", "Dark", "stops=#9fa8ff,#80deea&at=0,100&angle=0"),
        p("gradient", "Starfield", "Dark", "stops=#ffe082,#b39ddb,#80cbc4&focus=0.15,0.30"),
        p("gradient", "Hot Wire", "Neon", "stops=#ff00a8,#7c4dff,#00e5ff&at=0,50,100&angle=0"),
        p("gradient", "Acid", "Neon", "stops=#76ff03,#00e5ff&at=0,100&angle=200"),
        p("gradient", "Marquee", "Decorative", "stops=#b71c1c,#ffb300,#b71c1c&at=0,50,100&angle=0"),
        p("gradient", "Teal & Orange", "Warm", "stops=#00838f,#ef6c00&at=0,100&angle=0"),
        p("gradient", "Highlighter Ink", "Study", "stops=#1565c0,#6a1b9a&at=0,100&angle=10"),
        p("gradient", "Chapter", "Editorial", "stops=#212121,#5e35b1,#212121&at=0,50,100&angle=0"),
        p("gradient", "Sea Glass", "Calm", "stops=#26a69a,#80cbc4,#4db6ac,#00897b&at=0,35,65,100&angle=0"),
        p("gradient", "Prism Edge", "Cool", "stops=#3949ab,#00acc1,#7cb342,#fdd835,#e53935&at=0,25,50,75,100&angle=0"),
        p("gradient", "Mesa", "Warm", "stops=#bf360c,#d4a373,#8d6e63&at=0,60,100&angle=0"),
        p("gradient", "Dune", "Calm", "stops=#c19a6b,#e07a5f&focus=0.80,0.20"),
        p("gradient", "Hoarfrost", "Cool", "stops=#5c7c99,#90a4ae,#4fc3f7&at=0,50,100&angle=0"),
        p("gradient", "Snowlight", "Calm", "stops=#78909c,#b0bec5,#81d4fa&at=0,40,100&angle=160"),
    ]

    /// Spectrum: every palette with its own speed and direction.
    public static let spectrum: [EffectPreset] = {
        let feel: [String: (String, String, String)] = [
            "aurora": ("Cool", "slow", "forward"), "prism": ("Decorative", "normal", "forward"), "sunset": ("Warm", "slow", "backward"),
            "ocean": ("Cool", "normal", "backward"), "neon": ("Neon", "fast", "forward"), "ember": ("Warm", "normal", "forward"),
            "citrus": ("Nature", "fast", "backward"), "forest": ("Nature", "slow", "forward"), "glacier": ("Cool", "slow", "backward"),
            "berry": ("Dark", "normal", "forward"), "candy": ("Decorative", "fast", "backward"), "solar": ("Warm", "fast", "forward"),
            "rose": ("Calm", "slow", "forward"), "space": ("Dark", "slow", "backward"), "garden": ("Neon", "normal", "backward"),
            "mineral": ("Study", "slow", "forward"),
        ]
        return Spectrum.palettes.map { pal in
            let f = feel[pal.id] ?? ("Decorative", "slow", "forward")
            return EffectPreset(id: "spectrum-" + pal.id, name: pal.name, group: f.0, value: "spectrum:\(pal.id):\(f.1):\(f.2)")
        }
    }()

    /// Block presets: `decoration|#tint`.
    public static let blocks: [EffectPreset] = [
        EffectPreset(id: "block-gradient-dawn", name: "Dawn Wash", group: "Warm", value: "gradient|#f5cfa0"),
        EffectPreset(id: "block-gradient-tide", name: "Tide Wash", group: "Cool", value: "gradient|#a9dde8"),
        EffectPreset(id: "block-gradient-iris", name: "Iris Wash", group: "Decorative", value: "gradient|#9d9bf2"),
        EffectPreset(id: "block-gradient-meadow", name: "Meadow Wash", group: "Nature", value: "gradient|#a9e2c0"),
        EffectPreset(id: "block-gradient-graphite", name: "Graphite Wash", group: "Editorial", value: "gradient|#8f8e8a"),
        EffectPreset(id: "block-glass-clear", name: "Clear Glass", group: "Calm", value: "glass|"),
        EffectPreset(id: "block-glass-frost", name: "Frost Glass", group: "Cool", value: "glass|#d3d6db"),
        EffectPreset(id: "block-glass-rose", name: "Rose Glass", group: "Decorative", value: "glass|#f0a8b3"),
        EffectPreset(id: "block-glass-sand", name: "Sand Glass", group: "Warm", value: "glass|#d9c7a8"),
        EffectPreset(id: "block-glow-signal", name: "Signal Glow", group: "Study", value: "glow|"),
        EffectPreset(id: "block-glow-amber", name: "Amber Glow", group: "Warm", value: "glow|#f5e48f"),
        EffectPreset(id: "block-glow-orchid", name: "Orchid Glow", group: "Neon", value: "glow|#dcaaf0"),
        EffectPreset(id: "block-glow-glacier", name: "Glacier Glow", group: "Cool", value: "glow|#a8c1f5"),
        EffectPreset(id: "block-accent-ink", name: "Ink Frame", group: "Editorial", value: "accent|"),
        EffectPreset(id: "block-accent-rose", name: "Rose Frame", group: "Decorative", value: "accent|#f0a8b3"),
        EffectPreset(id: "block-accent-mint", name: "Mint Frame", group: "Nature", value: "accent|#a9e2c0"),
        EffectPreset(id: "block-accent-apricot", name: "Apricot Frame", group: "Warm", value: "accent|#f5cfa0"),
        EffectPreset(id: "block-focus-margin", name: "Margin Bar", group: "Study", value: "focus|"),
        EffectPreset(id: "block-focus-iris", name: "Iris Bar", group: "Calm", value: "focus|#9d9bf2"),
    ]

    public static func text(for kind: String) -> [EffectPreset] {
        switch kind {
        case "glow": return glow
        case "shadow": return shadow
        case "outline": return outline
        case "lift": return lift
        case "emboss": return emboss
        case "accent": return accent
        case "gradient": return gradient
        case "spectrum": return spectrum
        default: return []
        }
    }
    public static var allText: [EffectPreset] { ["glow", "shadow", "outline", "lift", "emboss", "accent", "gradient", "spectrum"].flatMap(text(for:)) }
}
