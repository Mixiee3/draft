import AppKit
import DraftCore

/// `chrome-test`: where the window buttons sit after launch, resize, zoom, theme changes, focus
/// changes, sheets and full screen. Each must be fully inside the window and centred on the
/// 52 pt tab row.
extension Automation {
    static func chromeTest() async {
        guard let w = NSApp.windows.first(where: { $0.isVisible }) else { return }
        var r: [String: String] = [:]
        defer { if let d = try? JSONSerialization.data(withJSONObject: r, options: [.prettyPrinted, .sortedKeys]) { try? d.write(to: out.appendingPathComponent("chrome-test.json")) } }
        func measure(_ name: String) async {
            await wait(0.6)
            guard !w.styleMask.contains(.fullScreen) else { r[name] = "fullscreen"; return }
            var bad: [String] = []
            for t in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
                guard let b = w.standardWindowButton(t), let sv = b.superview else { bad.append("missing"); continue }
                let f = sv.convert(b.frame, to: nil) // window coordinates, origin bottom-left
                let fromTop = w.frame.height - f.maxY
                if f.minX < 0 || f.maxX > w.frame.width || f.minY < 0 || f.maxY > w.frame.height { bad.append("\(t.rawValue) outside \(f)") }
                if abs(fromTop + f.height / 2 - WindowChrome.height / 2) > 1.5 { bad.append("\(t.rawValue) centre \(fromTop + f.height / 2)") }
                if b.isHidden || b.alphaValue < 0.5 { bad.append("\(t.rawValue) hidden") }
            }
            r[name] = bad.isEmpty ? "ok" : bad.joined(separator: "; ")
            await shot("chrome-" + name, w, settle: 0)
        }
        w.setFrame(NSRect(x: 60, y: 60, width: 1440, height: 900), display: true); await measure("launch")
        w.setFrame(NSRect(x: 60, y: 60, width: 720, height: 640), display: true); await measure("narrow")
        w.setFrame(NSRect(x: 60, y: 60, width: 1100, height: 760), display: true); await measure("resized")
        m.setSettings { $0.theme = "dark" }; await measure("dark")
        m.setSettings { $0.theme = "light" }; await measure("light")
        w.zoom(nil); await measure("zoomed"); w.zoom(nil)
        m.openView(ViewRef(kind: "settings", section: "general")); await measure("settings")
        m.openView(.all); m.styleGallery = true; await measure("gallery"); m.styleGallery = false
        NSApp.deactivate(); await measure("inactive"); NSApp.activate(ignoringOtherApps: true); w.makeKeyAndOrderFront(nil); await measure("reactivated")
        w.toggleFullScreen(nil); await wait(1.5); r["fullscreenEntered"] = w.styleMask.contains(.fullScreen) ? "yes" : "no"
        if let b = w.standardWindowButton(.closeButton) { r["fullscreenButtons"] = b.window == w ? "in window" : "in title bar overlay" }
        w.toggleFullScreen(nil); await wait(1.5); await measure("afterFullscreen")
        w.setFrame(NSRect(x: 80, y: 80, width: 900, height: 700), display: true); await measure("afterFullscreenResize")
        // An empty spot of the title row: the window, not a SwiftUI control, owns it (dragging), and
        // a double click zooms like any Mac window.
        m.openView(.all); await wait(0.4)
        let empty = NSPoint(x: 250, y: w.frame.height - WindowChrome.height / 2)
        let owner = w.contentView?.superview?.hitTest(empty)
        r["titleRowOwner"] = owner.map { String(describing: Swift.type(of: $0)) } ?? "nil"
        r["movable"] = w.isMovable ? "yes" : "no"
        let before = w.frame
        for count in [1, 2] {
            for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                if let e = NSEvent.mouseEvent(with: type, location: empty, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: w.windowNumber,
                                              context: nil, eventNumber: 0, clickCount: count, pressure: type == .leftMouseUp ? 0 : 1) { w.sendEvent(e) }
            }
        }
        await wait(1.0)
        r["doubleClickZooms"] = w.frame != before ? "yes" : "no"
        await measure("afterDoubleClick")
    }
}
