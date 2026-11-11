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
