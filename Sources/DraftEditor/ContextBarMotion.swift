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

/// Shared look for the floating editor glass: the system lens, appearance matched to the page (not
/// the window), and a light tint so controls stay legible over dense text without turning the glass
/// into an opaque plate.
enum ContextBarGlass {
    static func apply(to view: NSView, darkPage: Bool) {
        view.appearance = NSAppearance(named: darkPage ? .darkAqua : .aqua)
        if #available(macOS 26.0, *), let glass = view as? NSGlassEffectView {
            glass.tintColor = darkPage ? NSColor.black.withAlphaComponent(0.3) : NSColor.white.withAlphaComponent(0.5)
        }
    }
}
