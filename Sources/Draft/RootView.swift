import SwiftUI
import DraftCore
import DraftEditor

struct RootView: View {
    @Environment(AppModel.self) var model
    @Environment(\.colorScheme) var systemScheme
    @State private var railOverlay = false

    var isDark: Bool {
        switch model.library.settings.theme {
        case "dark": return true
        case "light": return false
        default: return systemScheme == .dark
        }
    }

    var pinnedAssistant: Bool { model.assistant.isOpen && model.library.settings.assistantPinned }

    var tint: String? {
        guard model.library.settings.useDocStyleForApp, let id = model.activeDocId, let d = model.docs[id] else { return nil }
        let t = model.displayTokens(d.appearance).shellTint
        // In dark app mode, only dark document tints are applied to avoid a glaring shell.
        return isDark && !ColorMath.isDark(t) ? nil : t
    }

    var body: some View {
        let t = Tokens.make(dark: isDark, accent: model.library.settings.accent, tint: tint)
        GeometryReader { geo in
            let narrow = geo.size.width < 820
            let focus = model.focusMode && model.activeDocId != nil
            let showRail = !model.library.settings.railCollapsed && !narrow && !focus
            ZStack(alignment: .topLeading) {
                t.shell.ignoresSafeArea()
                if let issues = model.recovery.startup {
                    StartupRecoveryView(issues: issues)
                } else if let f = model.fatal {
                    FatalView(message: f)
                } else if model.ready {
                    HStack(spacing: 0) {
                        if showRail {
                            RailView(narrow: false).frame(width: min(272, max(236, geo.size.width * 0.19)))
                                .tourAnchor(.sidebar)
                                .padding(.leading, 8).padding(.vertical, 8)
                                .transition(.move(edge: .leading))
                        }
                        VStack(spacing: 0) {
                            TabStrip(leadingInset: showRail ? 8 : 92, showRailButton: !showRail, compact: geo.size.width < 900, onRail: {
                                if narrow { railOverlay.toggle() } else { model.setSettings { $0.railCollapsed = false } }
                            })
                            .frame(height: WindowChrome.height)
                            .background(TitleBarArea())
                            .opacity(focus ? 0 : 1).allowsHitTesting(!focus)
                            .animation(nil, value: pinnedAssistant)
                            MainContent()
                                .environment(\.railVisible, showRail)
                                .animation(nil, value: pinnedAssistant) // one re-wrap when the Assistant opens, not one per frame
                                .clipShape(RoundedRectangle(cornerRadius: Tokens.radiusPanel, style: .continuous))
                                .padding(.leading, showRail ? 8 : 8).padding(.trailing, 8).padding(.bottom, 8)
                        }
                        if pinnedAssistant && !narrow && !focus {
                            AssistantView(a: model.assistant)
                                .clipShape(RoundedRectangle(cornerRadius: Tokens.radiusPanel, style: .continuous))
                                .frame(width: 360)
                                .padding(.top, WindowChrome.height).padding(.trailing, 8).padding(.bottom, 8)
                                .panelTransition(reduce: model.library.settings.reduceMotion)
                        }
                    }
                    if pinnedAssistant && narrow {
                        HStack {
                            Spacer()
                            AssistantView(a: model.assistant)
                                .clipShape(RoundedRectangle(cornerRadius: Tokens.radiusPanel, style: .continuous))
                                .surface(.floating)
                                .frame(width: min(360, geo.size.width - 32))
                                .padding(.top, WindowChrome.height).padding(.trailing, 12).padding(.bottom, 12)
                        }
                        .panelTransition(reduce: model.library.settings.reduceMotion)
                    }
                    if narrow && railOverlay {
                        Color.black.opacity(0.2).ignoresSafeArea().onTapGesture { railOverlay = false }
                        RailView(narrow: true).frame(width: 280).padding(8)
                            .shadow(color: .black.opacity(0.25), radius: 24)
                            .transition(.move(edge: .leading))
                    }
                    Overlays()
                    if model.onboarding == .welcome { WelcomeView().transition(.opacity) }
                } else {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .onChange(of: model.activeTab.id) { _, _ in railOverlay = false }
            .onChange(of: isDark, initial: true) { _, d in model.appDark = d }
            .modifier(TourLayer(step: model.onboarding.flatMap { if case .tour(let i) = $0 { i } else { nil } }))
            .animation(Motion.emphasis(model.library.settings.reduceMotion), value: model.onboarding)
        }
        .environment(\.tokens, t)
        .preferredColorScheme(model.library.settings.theme == "system" ? nil : (isDark ? .dark : .light))
        .tint(t.accent)
        .animation(Motion.standard(model.library.settings.reduceMotion), value: model.library.settings.railCollapsed)
        .animation(Motion.panel(model.library.settings.reduceMotion), value: pinnedAssistant)
        .onAppear { if !model.ready && model.fatal == nil && model.recovery.startup == nil { model.boot() } }
        .onOpenURL { model.openLink($0) }
        .sheet(item: Binding(get: { model.agentProposal }, set: { model.agentProposal = $0 })) { proposal in
            AgentProposalReview(proposal: proposal).environment(model).environment(\.tokens, t)
        }
        .sheet(item: Binding(get: { model.recovery.historyDoc }, set: { model.recovery.historyDoc = $0 })) { h in
            VersionHistoryView(docId: h.id).environment(model).environment(\.tokens, t)
        }
        .background(WindowChrome())
        .ignoresSafeArea()
    }
}

/// A 52 pt title band with the window buttons centred on the tab-strip line. Done by enlarging the
/// standard title bar rather than adding an empty toolbar: a toolbar's view swallowed clicks on the
/// tab strip under it on every screen except a document, where a SwiftUI platform view happened to
/// catch them first.
struct WindowChrome: NSViewRepresentable {
    static let height: CGFloat = 52
    final class V: NSView {
        private var observers: [NSObjectProtocol] = []
        override func viewDidMoveToWindow() {
            guard let w = window else { return }
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.styleMask.insert(.fullSizeContentView)
            w.toolbar = nil
            observers.forEach(NotificationCenter.default.removeObserver)
            observers = [NSWindow.didResizeNotification, NSWindow.didEndLiveResizeNotification, NSWindow.didExitFullScreenNotification,
                         NSWindow.didEnterFullScreenNotification, NSWindow.didBecomeKeyNotification].map {
                NotificationCenter.default.addObserver(forName: $0, object: w, queue: .main) { [weak w] _ in if let w { Self.placeButtons(w) } }
            }
            // AppKit lays the title bar out again on its own (appearance changes, activation, layout
            // passes) and puts it back to its native height, which pushed the buttons above the
            // window. Re-apply whenever it does.
            if let bar = w.standardWindowButton(.closeButton)?.superview, let container = bar.superview {
                for v in [container, bar] {
                    v.postsFrameChangedNotifications = true
                    observers.append(NotificationCenter.default.addObserver(forName: NSView.frameDidChangeNotification, object: v, queue: .main) { [weak w] _ in
                        if let w { Self.placeButtons(w) }
                    })
                }
            }
            Self.placeButtons(w)
        }
        override func viewDidChangeEffectiveAppearance() { if let w = window { Self.placeButtons(w) } }
        deinit { observers.forEach(NotificationCenter.default.removeObserver) }

        static func placeButtons(_ w: NSWindow) {
            guard !w.styleMask.contains(.fullScreen), let close = w.standardWindowButton(.closeButton),
                  let bar = close.superview, let container = bar.superview else { return }
            let h = WindowChrome.height
            let target = NSRect(x: 0, y: w.frame.height - h, width: w.frame.width, height: h)
            if container.frame != target { container.frame = target } // only when AppKit moved it, so the frame observer settles
            if bar.frame != container.bounds { bar.frame = container.bounds }
            for (i, type) in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton].enumerated() {
                guard let b = w.standardWindowButton(type) else { continue }
                b.setFrameOrigin(NSPoint(x: 20 + CGFloat(i) * 20, y: ((h - b.frame.height) / 2).rounded()))
            }
        }
    }
    func makeNSView(context: Context) -> NSView { V() }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

/// The empty parts of the tab row and sidebar header behave like a title bar: drag moves the window,
/// a double click zooms or minimises as set in System Settings › Desktop & Dock. Controls in front of
/// it keep their own clicks.
struct TitleBarArea: NSViewRepresentable {
    final class V: NSView {
        override var mouseDownCanMoveWindow: Bool { true }
        override func mouseDown(with e: NSEvent) {
            guard let w = window else { return }
            if e.clickCount == 2 {
                switch UserDefaults.standard.string(forKey: "AppleActionOnDoubleClick") ?? "Maximize" {
                case "Minimize": w.performMiniaturize(nil)
                case "None": break
                default: w.performZoom(nil)
                }
            }
        }
        // The drag starts once the mouse moves, so a double click is never swallowed by a drag loop.
        override func mouseDragged(with e: NSEvent) { window?.performDrag(with: e) }
    }
    func makeNSView(context: Context) -> NSView { V() }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

struct FatalView: View {
    let message: String
    @Environment(AppModel.self) var model
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "exclamationmark.triangle").font(.system(size: DS.display))
            Text("Draft can't open your notes safely").font(.title2.bold())
            Text(message).multilineTextAlignment(.center).frame(maxWidth: 520).foregroundStyle(.secondary)
            Text("Nothing was changed on disk.").font(.callout).foregroundStyle(.secondary)
            Button("Show Data Folder") { model.revealVault() }
        }.padding(40).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct MainContent: View {
    @Environment(AppModel.self) var model
    @Environment(\.tokens) var t
    var body: some View {
        let v = model.activeView
        ZStack {
            switch v.kind {
            case "doc":
                if let id = v.docId {
                    if let meta = model.library.docs[id], meta.deletedAt == nil, model.docs[id] != nil { DocumentScreen(docId: id).id(id) }
                    else { MissingDocument(docId: id) }
                }
            case "settings": SettingsView(section: v.section ?? "appearance")
            case "tasks": TasksView(section: v.section).id(v)
            case "calendar": CalendarView(focus: v.section).id(v)
            case "tag": TagView(tag: v.section ?? "").id(v)
            case "collection": CollectionScreen(docId: v.docId ?? "", blockId: v.section ?? "").id(v)
            default: LibraryView(view: v)
            }
        }
        .transition(.screenArrival)
        .id(v.kind == "doc" ? (v.docId ?? "") : v.kind + (v.section ?? "") + (v.folderId ?? ""))
        .animation(Motion.navigate(model.library.settings.reduceMotion), value: v)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// A tab whose note was deleted or can't be read: say so, instead of showing nothing.
struct MissingDocument: View {
    @Environment(AppModel.self) var model
    let docId: String
    var body: some View {
        let meta = model.library.docs[docId]
        let trashed = meta?.deletedAt != nil
        EmptyState(symbol: trashed ? "trash" : "doc.questionmark",
                   title: trashed ? "“\(meta?.title.isEmpty == false ? meta!.title : "Untitled")” is in Recently Deleted" : "This note isn't available",
                   message: trashed ? "Restore it to keep working, or close this tab." : "It may have been deleted permanently or its file can't be read.") {
            HStack(spacing: DS.s2) {
                if trashed { Button("Restore") { model.restore(docId); _ = model.ensureDoc(docId) }.buttonStyle(.draftPrimary) }
                Button("Close Tab") { model.closeTab(model.activeTab.id) }.buttonStyle(.draft)
            }
        }
    }
}

// MARK: - Tab strip

struct TabStrip: View {
    @Environment(AppModel.self) var model
    @Environment(\.tokens) var t
    var leadingInset: CGFloat
    var showRailButton: Bool
    var compact = false
    var onRail: () -> Void

    func title(_ v: ViewRef) -> String {
        switch v.kind {
        case "all": return String(localized: "All Docs")
        case "unsorted": return String(localized: "Unsorted")
        case "starred": return String(localized: "Starred")
        case "shared": return String(localized: "Shared with Me")
        case "trash": return String(localized: "Recently Deleted")
        case "settings": return String(localized: "Settings")
        case "tasks": return String(localized: "Tasks")
        case "calendar": return String(localized: "Calendar")
        case "tag": return "#" + (v.section ?? "")
        case "collection": return model.collectionData(v.docId ?? "", v.section ?? "")?.name ?? String(localized: "Collection")
        case "folder": return model.folderName(v.folderId)
        case "doc": let s = model.library.docs[v.docId ?? ""]?.title ?? ""; return s.isEmpty ? String(localized: "Untitled") : s
        default: return ""
        }
    }

    func icon(_ v: ViewRef) -> String {
        switch v.kind {
        case "all": return "house"
        case "unsorted": return "tray"
        case "starred": return "star"
        case "shared": return "person.2"
        case "trash": return "trash"
        case "settings": return "gearshape"
        case "tasks": return "checklist"
        case "calendar": return "calendar"
        case "tag": return "number"
        case "collection": return "square.grid.3x2"
        case "folder": return "folder"
        default: return "doc.text"
        }
    }

    var body: some View {
        HStack(spacing: 4) {
            if showRailButton {
                IconButton(symbol: "sidebar.left", label: "Show sidebar", action: onRail)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 2) {
                    ForEach(model.tabs) { tab in
                        TabItem(tab: tab, title: title(tab.view), icon: icon(tab.view), isActive: tab.id == model.activeTabId, isHome: tab.id == model.tabs.first?.id)
                    }
                    IconButton(symbol: "plus", label: "New document (⌘N)") { model.createDoc() }
                }.padding(.vertical, 6).padding(.trailing, 18)
            }
            // Tabs that run past the edge fade out instead of being cut mid-word.
            .mask(HStack(spacing: 0) { Color.black; LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing).frame(width: 18) })
            
            Spacer(minLength: 0)
            AssistantToolbarButton(compact: compact).tourAnchor(.assistant)
        }
        .padding(.leading, leadingInset)
        .padding(.trailing, 10)
        .padding(.top, 2)
    }
}

struct TabItem: View {
    @Environment(AppModel.self) var model
    @Environment(\.tokens) var t
    let tab: DraftCore.Tab
    let title: String
    let icon: String
    let isActive: Bool
    let isHome: Bool
    @State private var hover = false

    var body: some View {
        HStack(spacing: 6) {
            if !isHome {
                Button { model.closeTab(tab.id) } label: {
                    Image(systemName: "xmark").font(.system(size: DS.micro, weight: .bold)).frame(width: 14, height: 14)
                }
                .buttonStyle(.plain)
                .opacity(hover || isActive ? 1 : 0)
                .accessibilityLabel("Close tab \(title)")
            }
            // A real button, not a tap gesture: the strip sits in the title bar, where AppKit takes a
            // click on bare SwiftUI content as a window drag, so tapping a tab did nothing on every
            // screen except a document.
            Button { model.activateTab(tab.id) } label: {
                HStack(spacing: 6) {
                    Image(systemName: icon).font(.system(size: DS.footnote)).opacity(isActive ? 1 : 0.75)
                    if !isHome || isActive {
                        Text(title).lineLimit(1).font(.system(size: DS.body, weight: isActive ? .medium : .regular))
                            .frame(maxWidth: 170, alignment: .leading)
                    }
                }
                .frame(height: 32)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Tab \(title)")
            .accessibilityAddTraits(isActive ? [.isSelected] : [])
        }
        .foregroundStyle(isActive ? (isHome && t.dark ? Color.white : t.text) : t.secondary)
        .padding(.horizontal, isHome && !isActive ? 10 : 12)
        .frame(height: 32)
        .background(
            RoundedRectangle(cornerRadius: DS.rControl, style: .continuous)
                .fill(isActive ? (t.dark ? Color.black.opacity(0.55) : Color.white.opacity(0.92)) : (hover ? t.hover : .clear))
                .shadow(color: .black.opacity(isActive && !t.dark ? 0.06 : 0), radius: 3, y: 1)
        )
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .accessibilityElement(children: .contain)
    }
}

// MARK: - Shared controls

struct IconButton: View {
    @Environment(\.tokens) var t
    var symbol: String
    var label: String
    var size: CGFloat = 28
    var isActive = false
    var action: () -> Void
    @State private var hover = false
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: DS.body, weight: .medium))
                .frame(width: size, height: size)
                .background(RoundedRectangle(cornerRadius: DS.rControl, style: .continuous).fill(isActive ? t.selected : (hover ? t.hover : .clear)))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(t.secondary)
        .onHover { hover = $0 }
        .help(label)
        .accessibilityLabel(label)
    }
}

/// Black (dark) / white (light) pill group used for library and document controls.
struct PillGroup<Content: View>: View {
    @Environment(\.tokens) var t
    var onBackdrop = false
    @ViewBuilder var content: Content
    var body: some View {
        HStack(spacing: 2) { content }
            .padding(3)
            .background(Capsule(style: .continuous).fill(onBackdrop ? Color.white.opacity(0.82) : t.pill))
            .overlay(Capsule(style: .continuous).strokeBorder(onBackdrop ? Color.black.opacity(0.06) : t.pillBorder, lineWidth: 0.5))
            .shadow(color: .black.opacity(onBackdrop ? 0.08 : 0), radius: 6, y: 2)
    }
}

struct PillButton: View {
    @Environment(\.tokens) var t
    var symbol: String
    var label: String
    var text: String? = nil
    var isActive = false
    var onBackdrop = false
    var action: () -> Void
    @State private var hover = false
    var fg: Color { onBackdrop ? Color(hex: "#2a2622") : t.pillText }
    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: symbol).font(.system(size: DS.body, weight: .medium))
                if let text { Text(text).font(.system(size: DS.body, weight: .medium)) }
            }
            .padding(.horizontal, text == nil ? 0 : 10)
            .frame(minWidth: 32, minHeight: 30)
            .background(Capsule(style: .continuous).fill(isActive ? fg.opacity(0.14) : (hover ? fg.opacity(0.08) : .clear)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .foregroundStyle(fg)
        .onHover { hover = $0 }
        .help(label)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }
}
