import SwiftUI
import AppKit

/// Draft's design system: the only type sizes, spacing, radii, control sizes, shadows and motion
/// timings the app uses. Colors live in `Tokens` (Theme.swift).
enum DS {
    // Type scale, in points.
    static let micro: CGFloat = 9
    static let caption: CGFloat = 11
    static let footnote: CGFloat = 12
    static let body: CGFloat = 13
    static let headline: CGFloat = 15
    static let title3: CGFloat = 17
    static let title2: CGFloat = 20
    static let display: CGFloat = 30

    // Spacing on a 4-point grid.
    static let s1: CGFloat = 4
    static let s2: CGFloat = 8
    static let s3: CGFloat = 12
    static let s4: CGFloat = 16
    static let s5: CGFloat = 24
    static let s6: CGFloat = 32

    // Corner radii.
    static let rSmall: CGFloat = 6
    static let rControl: CGFloat = Tokens.radiusControl
    static let rCard: CGFloat = Tokens.radiusCard
    static let rPanel: CGFloat = Tokens.radiusPanel

    // Control heights.
    static let controlSmall: CGFloat = 24
    static let control: CGFloat = 30
    static let controlLarge: CGFloat = 36
    static let toolbarPill: CGFloat = 46

    // Motion, in seconds.
    static let quick = 0.12
    static let standard = 0.18
    static let panel = 0.24

    /// Floating surfaces (panels, popovers, the Assistant) share one shadow.
    static func floatingShadow(dark: Bool) -> (Color, CGFloat, CGFloat) { (.black.opacity(dark ? 0.38 : 0.14), 22, 8) }
}

/// One answer to "should this move?": Draft's Reduce Animations setting or macOS Reduce Motion.
enum Motion {
    static var systemReduce: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    static func reduced(_ setting: Bool) -> Bool { setting || systemReduce }

    // Shared timing (see docs/UI_AUDIT_V06.md §4.2). Reduce Motion keeps short fades, never movement.
    static func standard(_ setting: Bool) -> Animation { reduced(setting) ? .easeOut(duration: 0.1) : .easeOut(duration: DS.standard) }
    static func quick(_ setting: Bool) -> Animation { reduced(setting) ? .easeOut(duration: 0.08) : .timingCurve(0.2, 0, 0, 1, duration: DS.quick) }
    static func panel(_ setting: Bool) -> Animation { reduced(setting) ? .easeOut(duration: 0.12) : .spring(response: 0.26, dampingFraction: 0.9) }
    static func navigate(_ setting: Bool) -> Animation { reduced(setting) ? .easeOut(duration: 0.1) : .timingCurve(0.2, 0, 0, 1, duration: 0.18) }
    static func emphasis(_ setting: Bool) -> Animation { reduced(setting) ? .easeOut(duration: 0.15) : .spring(response: 0.34, dampingFraction: 0.86) }
}

/// Draft's segmented control: a quiet track with the chosen segment raised, in place of the
/// AppKit control whose dark selection matched nothing else in the app.
struct DraftSegmented<T: Hashable>: View {
    @Environment(\.tokens) var t
    @Binding var selection: T
    let options: [(value: T, title: String, symbol: String?)]
    var label: String
    var stretch = false
    var iconOnly = false

    init(_ label: String, selection: Binding<T>, options: [(T, String)], stretch: Bool = false) {
        self.label = label; _selection = selection; self.options = options.map { ($0.0, $0.1, nil) }; self.stretch = stretch
    }
    init(_ label: String, selection: Binding<T>, symbols: [(T, String, String)], stretch: Bool = false, iconOnly: Bool = false) {
        self.label = label; _selection = selection; self.options = symbols.map { ($0.0, $0.1, $0.2) }; self.stretch = stretch; self.iconOnly = iconOnly
    }

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(options.enumerated()), id: \.offset) { _, o in
                let on = o.value == selection
                Button { selection = o.value } label: {
                    HStack(spacing: 5) {
                        if let s = o.symbol { Image(systemName: s).font(.system(size: DS.footnote, weight: .medium)) }
                        if o.symbol == nil || !iconOnly { Text(o.title).font(.system(size: DS.footnote, weight: on ? .semibold : .medium)).lineLimit(1) }
                    }
                    .padding(.horizontal, DS.s3)
                    .frame(maxWidth: stretch ? .infinity : nil, minHeight: DS.controlSmall)
                    .background(RoundedRectangle(cornerRadius: DS.rControl - 3, style: .continuous)
                        .fill(on ? (t.dark ? Color.white.opacity(0.16) : Color.white) : .clear)
                        .shadow(color: .black.opacity(on && !t.dark ? 0.1 : 0), radius: 1.5, y: 0.5))
                    .foregroundStyle(on ? t.text : t.secondary)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(o.title)
                .accessibilityLabel(o.title)
                .accessibilityAddTraits(on ? [.isSelected] : [])
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: DS.rControl, style: .continuous).fill(t.dark ? Color.white.opacity(0.07) : Color.black.opacity(0.055)))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(label)
    }
}

/// A labelled on/off chip, in place of the AppKit checkbox in toolbars.
struct DraftToggleChip: View {
    @Environment(\.tokens) var t
    let title: String
    @Binding var isOn: Bool
    var body: some View {
        Button { isOn.toggle() } label: {
            HStack(spacing: 5) {
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle").foregroundStyle(isOn ? t.accent : t.tertiary)
                Text(title)
            }
            .font(.system(size: DS.footnote, weight: .medium))
            .foregroundStyle(isOn ? t.text : t.secondary)
            .padding(.horizontal, DS.s3).frame(minHeight: DS.control - 2)
            .background(RoundedRectangle(cornerRadius: DS.rControl, style: .continuous).fill(isOn ? t.accent.opacity(0.12) : t.hover))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(isOn ? "On" : "Off")
        .accessibilityAddTraits(.isToggle)
    }
}
