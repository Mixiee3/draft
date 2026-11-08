import SwiftUI
import AppKit
import DraftCore

extension AppModel {
    /// ⌘J and the toolbar button: pinned beside the content, or in its own floating window.
    func toggleAssistant() {
        assistant.toggle()
        objectWillChange.send()
        if assistant.isOpen && !library.settings.assistantPinned { showAssistantWindow() } else { assistantWindow?.orderOut(nil) }
    }

    func setAssistantPinned(_ pinned: Bool) {
        setSettings { $0.assistantPinned = pinned }
        if pinned { assistantWindow?.orderOut(nil) } else if assistant.isOpen { showAssistantWindow() }
    }

    func showAssistantWindow() {
        if assistantWindow == nil {
            let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 380, height: 640), styleMask: [.titled, .closable, .resizable, .fullSizeContentView, .utilityWindow],
                            backing: .buffered, defer: false)
            p.title = "Assistant"
            p.titlebarAppearsTransparent = true
            p.isFloatingPanel = true
            p.hidesOnDeactivate = false
            p.becomesKeyOnlyIfNeeded = false
            p.minSize = NSSize(width: 320, height: 420)
            p.isReleasedWhenClosed = false
            p.setFrameAutosaveName("DraftAssistant")
            p.contentView = NSHostingView(rootView: AssistantWindowRoot().environmentObject(self))
            NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: p, queue: .main) { [weak self] _ in
                onMain { if self?.assistant.isOpen == true && self?.library.settings.assistantPinned == false { self?.assistant.toggle(); self?.objectWillChange.send() } }
            }
            if let main = NSApp.windows.first(where: { $0.isVisible && $0 !== p }) {
                p.setFrameTopLeftPoint(NSPoint(x: main.frame.maxX - 400, y: main.frame.maxY - 60))
            }
            assistantWindow = p
        }
        assistantWindow?.makeKeyAndOrderFront(nil)
    }
}

/// The floating window's root: the same tokens as the main window.
struct AssistantWindowRoot: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.colorScheme) var scheme
    var body: some View {
        let s = model.library.settings
        let dark = s.theme == "dark" || (s.theme == "system" && scheme == .dark)
        AssistantView(a: model.assistant, floating: true)
            .padding(.top, 28)
            .background(Tokens.make(dark: dark, accent: s.accent, tint: nil).canvas)
            .environment(\.tokens, Tokens.make(dark: dark, accent: s.accent, tint: nil))
            .preferredColorScheme(s.theme == "system" ? nil : (dark ? .dark : .light))
            .ignoresSafeArea()
    }
}

/// The Assistant's toolbar button, at the trailing end of the tab strip (⌘J).
struct AssistantToolbarButton: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.tokens) var t
    @State private var hover = false
    var body: some View {
        let on = model.assistant.isOpen
        Button { model.toggleAssistant() } label: {
            HStack(spacing: 6) {
                Image(systemName: "sparkle").font(.system(size: DS.footnote, weight: .semibold)).foregroundStyle(on ? Color.white : t.accent)
                Text("Assistant").font(.system(size: DS.footnote, weight: .semibold)).foregroundStyle(on ? Color.white : t.text)
            }
            .padding(.horizontal, DS.s3).frame(height: DS.control)
            .background(Capsule().fill(on ? t.accent : (hover ? t.selected : t.hover)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help("Assistant (⌘J)")
        .accessibilityLabel("Assistant")
        .accessibilityValue(on ? "Open" : "Closed")
    }
}
