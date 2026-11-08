import SwiftUI
import DraftCore
import DraftEditor

struct EditorHostView: NSViewRepresentable {
    let view: DocumentEditorView
    func makeNSView(context: Context) -> DocumentEditorView { view }
    func updateNSView(_ nsView: DocumentEditorView, context: Context) {}
}

struct DocumentScreen: View {
    @Environment(AppModel.self) var model
    @Environment(\.tokens) var t
    let docId: String

    var body: some View {
        let doc = model.docs[docId]
        let tokens = doc.map { Styles.resolve($0.appearance) } ?? Styles.builtIn[0].tokens
        let backdropAsset = tokens.backdrop.image.flatMap { $0.hasPrefix("asset:") ? model.image(forAsset: String($0.dropFirst(6))) : nil }
        let darkPage = ColorMath.isDark(tokens.pageColor)
        ZStack(alignment: .top) {
            BackdropView(backdrop: tokens.backdrop, assetImage: backdropAsset)
            EditorHostView(view: model.editor(for: docId))
                .accessibilityLabel("Document")
                .tourAnchor(.page)
                // Text fades out as it scrolls under the top controls, like paper sliding away.
                .mask(VStack(spacing: 0) {
                    Color.clear.frame(height: 58)
                    LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom).frame(height: 14)
                    Color.black
                })
            GeometryReader { g in topBar(tokens: tokens, darkPage: darkPage, narrow: g.size.width < 760) }
            if let p = model.panel { sidePanel(p) }
            if model.styleGallery {
                StyleGallery(docId: docId)
            }
            if model.coverEditorDoc == docId, let cover = model.docs[docId]?.appearance.cover, let img = model.image(forAsset: cover.assetId) {
                CoverCropSheet(docId: docId, cover: cover, image: img)
            }
        }
        .onChange(of: model.panel, initial: true) { old, p in panelChanged(from: old, to: p) }
        .onAppear {
            model.editors[docId]?.controller.refreshPageTitles { model.library.docs[$0]?.title }
            model.editors[docId]?.controller.refreshLinks()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { model.restoreTabState(docId) }
        }
    }

    func topBar(tokens: StyleTokens, darkPage: Bool, narrow: Bool) -> some View {
        HStack(spacing: 8) {
            PillGroup(onBackdrop: true) { PillButton(symbol: "chevron.left", label: "Back", onBackdrop: true) { model.goBack() } }
            PillGroup(onBackdrop: true) {
                DraftIconMenu(symbol: "plus", label: "Insert block", color: Color(hex: "#2a2622")) {
                    ForEach(["Insert", "Text", "Lists"], id: \.self) { g in
                        Section(g == "Insert" ? "Insert" : g) {
                            ForEach(EditorCommands.all.filter { $0.group == g && (g == "Insert" || ["block.code", "list.task", "block.quote"].contains($0.id)) }) { cmd in
                                Button { if let c = model.activeController { cmd.run(c) } } label: {
                                    Label(cmd.plannedFor.map { "\(cmd.title) — planned \($0)" } ?? cmd.title, systemImage: cmd.symbol)
                                }.disabled(cmd.plannedFor != nil)
                            }
                        }
                    }
                }
            }
            if let day = model.library.docs[docId]?.dailyDate {
                PillGroup(onBackdrop: true) {
                    PillButton(symbol: "chevron.backward", label: "Previous day", onBackdrop: true) { model.openDaily(Day.add(day, days: -1), inPlace: true) }
                    PillButton(symbol: "calendar", label: "Open in Calendar", text: narrow ? nil : Day.label(day, today: model.todayKey), onBackdrop: true) { model.openView(ViewRef(kind: "calendar", section: day)) }
                    PillButton(symbol: "chevron.forward", label: "Next day", onBackdrop: true) { model.openDaily(Day.add(day, days: 1), inPlace: true) }
                    if day != model.todayKey { PillButton(symbol: "sun.max", label: "Today’s note", onBackdrop: true) { model.openDaily(inPlace: true) } }
                }
            } else if !narrow { Breadcrumb(docId: docId, light: darkPage || tokens.backdrop.kind == "image") }
            Spacer()
            PillGroup(onBackdrop: true) {
                PillButton(symbol: "square.and.arrow.up", label: "Share and export", text: "Share", isActive: model.panel == .share, onBackdrop: true) { toggle(.share) }
            }
            PillGroup(onBackdrop: true) {
                PillButton(symbol: "textformat", label: "Format block (Aa)", isActive: model.panel == .format, onBackdrop: true) { toggle(.format) }
                PillButton(symbol: "paintbrush", label: "Document style (⇧⌘S)", isActive: model.panel == .style, onBackdrop: true) { toggle(.style) }
                PillButton(symbol: "info.circle", label: "Document info and actions", isActive: model.panel == .info, onBackdrop: true) { toggle(.info) }
            }
            .tourAnchor(.style)
        }
        .padding(.horizontal, 14).padding(.top, 12)
    }

    func sidePanel(_ p: Panel) -> some View {
        HStack {
            Spacer()
            Group {
                switch p {
                case .format: FormatPanel(docId: docId)
                case .style: StylePanel(docId: docId)
                case .info: InfoPanel(docId: docId, tab: Binding(get: { model.infoTab }, set: { model.infoTab = $0 }))
                case .share: SharePanel(docId: docId)
                }
            }
            .frame(width: 304)
            .surface(.floating)
            .padding(.top, 58).padding(.trailing, 12).padding(.bottom, 12)
        }
        .panelTransition(reduce: model.library.settings.reduceMotion)
    }

    func panelChanged(from old: Panel?, to p: Panel?) {
        let animated = (old == nil) != (p == nil) && !Motion.reduced(model.library.settings.reduceMotion)
        model.editors[docId]?.setTrailingInset(p == nil ? 0 : 304 + 24, animated: animated)
    }

    func toggle(_ p: Panel) {
        withAnimation(Motion.panel(model.library.settings.reduceMotion)) { model.panel = model.panel == p ? nil : p }
    }
}

struct Breadcrumb: View {
    @Environment(AppModel.self) var model
    @Environment(\.tokens) var t
    let docId: String
    var light: Bool
    var body: some View {
        let ancestors = model.ancestors(docId)
        HStack(spacing: 4) {
            Image(systemName: "folder").font(.system(size: DS.caption))
            Text(model.folderName(model.library.docs[docId]?.folderId)).lineLimit(1)
            ForEach(ancestors) { a in
                Image(systemName: "chevron.right").font(.system(size: DS.micro, weight: .bold)).opacity(0.7)
                Button(a.title.isEmpty ? "Untitled" : a.title) { model.openView(.doc(a.id), inPlace: true) }.buttonStyle(.plain).lineLimit(1)
            }
        }
        .font(.system(size: DS.footnote, weight: .medium))
        .foregroundStyle(t.pillText.opacity(0.85))
        .padding(.horizontal, DS.s3).frame(height: DS.controlSmall + 4)
        .background(Capsule().fill(t.pill.opacity(0.88)))
        .overlay(Capsule().strokeBorder(t.pillBorder, lineWidth: 0.5))
        .padding(.leading, DS.s1)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Location")
    }
}

// MARK: - Shared panel pieces

struct PanelSection<Content: View>: View {
    @Environment(\.tokens) var t
    var title: String
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased()).font(.system(size: DS.caption, weight: .semibold)).tracking(0.6).foregroundStyle(t.tertiary)
            content
        }
    }
}

struct ChipButton: View {
    @Environment(\.tokens) var t
    var title: String
    var symbol: String? = nil
    var font: Font = .system(size: DS.body, weight: .medium)
    var isActive = false
    var isEnabled = true
    var height: CGFloat = 34
    /// Spoken name for icon-only chips.
    var label: String? = nil
    var action: () -> Void
    @State private var hover = false
    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let symbol { Image(systemName: symbol).font(.system(size: DS.body)) }
                if !title.isEmpty { Text(title).font(font).lineLimit(1).minimumScaleFactor(0.8) }
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: height)
            .background(RoundedRectangle(cornerRadius: DS.rControl, style: .continuous).fill(isActive ? t.accent.opacity(t.dark ? 0.45 : 0.16) : (hover ? t.selected : t.hover)))
            .overlay(RoundedRectangle(cornerRadius: DS.rControl, style: .continuous).strokeBorder(isActive ? t.accent.opacity(0.6) : .clear, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(isActive ? (t.dark ? .white : t.accent) : t.text)
        .opacity(isEnabled ? 1 : 0.45)
        .disabled(!isEnabled)
        .onHover { hover = $0 }
        .help(label ?? title)
        .accessibilityLabel(label ?? (title.isEmpty ? (symbol ?? "") : title))
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }
}

struct PanelHeader: View {
    @Environment(\.tokens) var t
    @Environment(AppModel.self) var model
    var title: String
    var body: some View {
        HStack {
            Text(title).font(.system(size: DS.headline, weight: .semibold)).foregroundStyle(t.text)
            Spacer()
            IconButton(symbol: "xmark", label: "Close panel", size: 24) { model.panel = nil }
        }
    }
}
