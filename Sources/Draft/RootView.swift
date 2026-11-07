import SwiftUI
import DraftCore
import DraftEditor

struct RootView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.colorScheme) var systemScheme
    @State private var railOverlay = false

    var isDark: Bool {
        switch model.library.settings.theme {
        case "dark": return true
        case "light": return false
        default: return systemScheme == .dark
        }
    }

    var tint: String? {
        guard model.library.settings.useDocStyleForApp, let id = model.activeDocId, let d = model.docs[id] else { return nil }
        let t = Styles.resolve(d.appearance).shellTint
        // In dark app mode, only dark document tints are applied to avoid a glaring shell.
        return isDark && !ColorMath.isDark(t) ? nil : t
    }

    var body: some View {
        let t = Tokens.make(dark: isDark, accent: model.library.settings.accent, tint: tint)
        GeometryReader { geo in
            let narrow = geo.size.width < 820
            let showRail = !model.library.settings.railCollapsed && !narrow
            ZStack(alignment: .topLeading) {
                t.shell.ignoresSafeArea()
                if let f = model.fatal {
                    FatalView(message: f)
                } else if model.ready {
                    HStack(spacing: 0) {
                        if showRail {
                            RailView(narrow: false).frame(width: min(272, max(236, geo.size.width * 0.19)))
                                .padding(.leading, 8).padding(.vertical, 8)
                                .transition(.move(edge: .leading))
                        }
                        VStack(spacing: 0) {
                            TabStrip(leadingInset: showRail ? 8 : 92, showRailButton: !showRail, onRail: {
                                if narrow { railOverlay.toggle() } else { model.setSettings { $0.railCollapsed = false } }
                            })
                            .frame(height: WindowChrome.height)
                            MainContent()
                                .clipShape(RoundedRectangle(cornerRadius: Tokens.radiusPanel, style: .continuous))
                                .padding(.leading, showRail ? 8 : 8).padding(.trailing, 8).padding(.bottom, 8)
                        }
                    }
                    if narrow && railOverlay {
                        Color.black.opacity(0.2).ignoresSafeArea().onTapGesture { railOverlay = false }
                        RailView(narrow: true).frame(width: 280).padding(8)
                            .shadow(color: .black.opacity(0.25), radius: 24)
                            .transition(.move(edge: .leading))
                    }
                    Overlays()
                } else {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .onChange(of: model.activeTab.id) { _, _ in railOverlay = false }
        }
        .environment(\.tokens, t)
        .preferredColorScheme(model.library.settings.theme == "system" ? nil : (isDark ? .dark : .light))
        .tint(t.accent)
        .animation(model.library.settings.reduceMotion ? nil : .easeOut(duration: 0.18), value: model.library.settings.railCollapsed)
        .onAppear { if !model.ready && model.fatal == nil { model.boot() } }
        .onOpenURL { model.openLink($0) }
        .background(WindowChrome())
        .ignoresSafeArea()
    }
}

/// A transparent unified toolbar area: macOS then places the window buttons with room around
/// them (and keeps them right in full screen), on the same line as the sidebar and tab strip.
struct WindowChrome: NSViewRepresentable {
    static let height: CGFloat = 52
    final class V: NSView {
        override func viewDidMoveToWindow() {
            guard let w = window else { return }
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.styleMask.insert(.fullSizeContentView)
            if w.toolbar == nil {
                let t = NSToolbar(identifier: "draft.window")
                t.showsBaselineSeparator = false
                t.allowsUserCustomization = false
                w.toolbar = t
            }
            w.toolbarStyle = .unified
        }
    }
    func makeNSView(context: Context) -> NSView { V() }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

struct FatalView: View {
    let message: String
    @EnvironmentObject var model: AppModel
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "exclamationmark.triangle").font(.system(size: 32))
            Text("Draft can't open your notes safely").font(.title2.bold())
            Text(message).multilineTextAlignment(.center).frame(maxWidth: 520).foregroundStyle(.secondary)
            Text("Nothing was changed on disk.").font(.callout).foregroundStyle(.secondary)
            Button("Show Data Folder") { model.revealVault() }
        }.padding(40).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct MainContent: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.tokens) var t
    var body: some View {
        let v = model.activeView
        Group {
            switch v.kind {
            case "doc":
                if let id = v.docId { DocumentScreen(docId: id).id(id) }
            case "settings": SettingsView(section: v.section ?? "appearance")
            case "tasks": TasksView(section: v.section).id(v)
            case "calendar": CalendarView(focus: v.section).id(v)
            case "tag": TagView(tag: v.section ?? "").id(v)
            case "collection": CollectionScreen(docId: v.docId ?? "", blockId: v.section ?? "").id(v)
            default: LibraryView(view: v)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Tab strip

struct TabStrip: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.tokens) var t
    var leadingInset: CGFloat
    var showRailButton: Bool
    var onRail: () -> Void

    func title(_ v: ViewRef) -> String {
        switch v.kind {
        case "all": return "All Docs"
        case "unsorted": return "Unsorted"
        case "starred": return "Starred"
        case "shared": return "Shared with Me"
        case "trash": return "Recently Deleted"
        case "settings": return "Settings"
        case "tasks": return "Tasks"
        case "calendar": return "Calendar"
        case "tag": return "#" + (v.section ?? "")
        case "collection": return model.collectionData(v.docId ?? "", v.section ?? "")?.name ?? "Collection"
        case "folder": return model.folderName(v.folderId)
        case "doc": let s = model.library.docs[v.docId ?? ""]?.title ?? ""; return s.isEmpty ? "Untitled" : s
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
                    ForEach(model.library.tabs) { tab in
                        TabItem(tab: tab, title: title(tab.view), icon: icon(tab.view), isActive: tab.id == model.library.activeTabId, isHome: tab.id == model.library.tabs.first?.id)
                    }
                    IconButton(symbol: "plus", label: "New document (⌘N)") { model.createDoc() }
                }.padding(.vertical, 6)
            }
            Spacer(minLength: 0)
        }
        .padding(.leading, leadingInset)
        .padding(.trailing, 10)
        .padding(.top, 2)
    }
}

struct TabItem: View {
    @EnvironmentObject var model: AppModel
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
                    Image(systemName: "xmark").font(.system(size: 9, weight: .bold)).frame(width: 14, height: 14)
                }
                .buttonStyle(.plain)
                .opacity(hover || isActive ? 1 : 0)
                .accessibilityLabel("Close tab \(title)")
            }
            Image(systemName: icon).font(.system(size: 12)).opacity(isActive ? 1 : 0.75)
            if !isHome || isActive {
                Text(title).lineLimit(1).font(.system(size: 13, weight: isActive ? .medium : .regular))
                    .frame(maxWidth: 170, alignment: .leading)
            }
        }
        .foregroundStyle(isActive ? (isHome && t.dark ? Color.white : t.text) : t.secondary)
        .padding(.horizontal, isHome && !isActive ? 10 : 12)
        .frame(height: 32)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(isActive ? (t.dark ? Color.black.opacity(0.55) : Color.white.opacity(0.92)) : (hover ? t.hover : .clear))
                .shadow(color: .black.opacity(isActive && !t.dark ? 0.06 : 0), radius: 3, y: 1)
        )
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .onTapGesture { model.activateTab(tab.id) }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isActive ? [.isButton, .isSelected] : .isButton)
        .accessibilityLabel("Tab \(title)")
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
                .font(.system(size: 13, weight: .medium))
                .frame(width: size, height: size)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(isActive ? t.selected : (hover ? t.hover : .clear)))
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
                Image(systemName: symbol).font(.system(size: 13, weight: .medium))
                if let text { Text(text).font(.system(size: 13, weight: .medium)) }
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
