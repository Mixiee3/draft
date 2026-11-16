import AppKit

/// Shared motion policy for floating editor controls.
enum ContextBarMotion {
    static var duration: TimeInterval {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.16
    }

    static func configure(_ context: NSAnimationContext) {
        context.duration = duration
        context.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.25, 1)
    }
}
