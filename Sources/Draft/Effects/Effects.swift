import SwiftUI
import ThinkingOrbsKit
import BorderBeamKit

/// Decorative motion runs only when the window is active and neither Draft's Reduce Animations
/// nor macOS Reduce Motion is on; otherwise every effect shows a still, plain version.
struct EffectsAllowed: EnvironmentKey { static let defaultValue = true }
extension EnvironmentValues {
    var effectsAllowed: Bool { get { self[EffectsAllowed.self] } set { self[EffectsAllowed.self] = newValue } }
}

struct EffectsGate: ViewModifier {
    let reduce: Bool
    @Environment(\.controlActiveState) var active
    @Environment(\.scenePhase) var phase
    func body(content: Content) -> some View {
        content.environment(\.effectsAllowed, !Motion.reduced(reduce) && active != .inactive && phase != .background)
    }
}

enum LiquidMetalShader {
    /// The shader library compiled into Draft's resource bundle; nil means use the plain fallback.
    static let available: Bool = Bundle.module.url(forResource: "default", withExtension: "metallib") != nil
}

/// A liquid-metal edge (Libraries.dev's material, vendored) around one important control.
struct LiquidMetalEdge: View {
    @Environment(\.effectsAllowed) var allowed
    @Environment(\.tokens) var t
    var cornerRadius: CGFloat
    var lineWidth: CGFloat = 1.6
    var lively: Bool

    var body: some View {
        if LiquidMetalShader.available {
            GeometryReader { g in
                let size = g.size
                if allowed && lively {
                    TimelineView(.animation) { tl in ring(size, time: tl.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1000)) }
                } else {
                    ring(size, time: 12)
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        } else {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).strokeBorder(t.accent.opacity(0.7), lineWidth: lineWidth).accessibilityHidden(true)
        }
    }

    func ring(_ size: CGSize, time: Double) -> some View {
        let scale = 1.6
        let fx = min(1, size.width / (140 * scale)), fy = min(1, size.height / (40 * scale))
        let tint: (Double, Double, Double, Double) = t.dark ? (0.53, 0.8, 1, 0.18) : (0.4, 0.69, 1, 0.6)
        let shift = t.dark ? 0.75 : 0.6
        return RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .strokeBorder(Color.white, lineWidth: lineWidth)
            .colorEffect(ShaderLibrary.bundle(.module).mfxLiquidMetal(
                .float2(0.5 - 0.5 * fx, 0.5 - 0.5 * fy), .float2(fx / max(1, size.width), fy / max(1, size.height)),
                .float(time), .float4(0, 0, 0, 0), .float4(tint.0, tint.1, tint.2, tint.3),
                .float(t.dark ? 2 : 1.5), .float(t.dark ? 0.09 : 0.05), .float(shift), .float(shift),
                .float(0.1), .float(0.4), .float(90), .float(1), .float(1)))
    }
}

/// Assistant activity, shown with a Thinking Orb (or a still symbol when motion is off).
struct AssistantOrb: View {
    @Environment(\.effectsAllowed) var allowed
    var state: OrbState
    var side: Double = 20
    var body: some View {
        ThinkingOrb(state: state, size: side > 32 ? .px64 : .px20, paused: !allowed, displaySize: side)
            .frame(width: side, height: side)
            .accessibilityHidden(true)
    }
}

/// A Border Beam around the active Assistant surface; a hairline when effects are off.
struct ActiveBeam<Content: View>: View {
    @Environment(\.effectsAllowed) var allowed
    @Environment(\.tokens) var t
    var active: Bool
    var radius: CGFloat
    @ViewBuilder var content: Content
    var body: some View {
        if allowed {
            BorderBeam(size: .line, colorVariant: .ocean, theme: t.dark ? .dark : .light, active: active, borderRadius: radius, strength: 0.8) { content }
        } else {
            content.overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(active ? t.accent.opacity(0.5) : .clear, lineWidth: 1))
        }
    }
}
