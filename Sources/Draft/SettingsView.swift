import SwiftUI
import DraftCore

struct SettingsView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.tokens) var t
    let section: String
    @State private var spaceName = ""

    let sections: [(String, String, String, String?)] = [
        ("appearance", "Appearance", "paintpalette", nil), ("editor", "Editor", "text.cursor", nil), ("space", "Space", "square.on.circle", nil),
        ("stats", "Stats", "chart.bar", nil), ("data", "Data & Storage", "internaldrive", nil), ("about", "About Draft", "info.circle", nil),
        ("templates", "Templates", "doc.on.doc", "v0.5"), ("tags", "Tags", "number", "v0.3"), ("published", "Published Content", "globe", "v1.x"), ("language", "Language & Spelling", "globe.europe.africa", "v0.6"),
    ]

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    PillGroup { PillButton(symbol: "xmark", label: "Close settings") { model.closeTab(model.activeTab.id) } }
                    Text("Settings").font(.system(size: 17, weight: .semibold)).foregroundStyle(t.text)
                }.padding(.bottom, 12)
                ForEach(sections, id: \.0) { id, title, icon, planned in
                    RailRow(icon: icon, title: title + (planned.map { " · \($0)" } ?? ""), isSelected: section == id) {
                        if let i = model.library.tabs.firstIndex(where: { $0.id == model.library.activeTabId }) { model.library.tabs[i].view = ViewRef(kind: "settings", section: id) }
                    }.opacity(planned == nil ? 1 : 0.6)
                }
                Spacer()
            }.frame(width: 230).padding(16)
            Divider().opacity(0.4)
            ScrollView {
                VStack(alignment: .leading, spacing: 22) { content }
                    .frame(maxWidth: 620, alignment: .leading).padding(28).frame(maxWidth: .infinity)
            }
        }.background(t.canvas)
    }

    @ViewBuilder var content: some View {
        switch section {
        case "appearance": appearance
        case "editor":
            group("Completed tasks in documents") {
                Picker("", selection: Binding(get: { model.library.settings.completedTasks }, set: { v in model.setSettings { $0.completedTasks = v } })) {
                    Text("Strikethrough").tag("strike"); Text("Dimmed").tag("dim"); Text("Unchanged").tag("none")
                }.pickerStyle(.segmented).labelsHidden()
            }
            group("Default style for new documents") {
                Picker("", selection: Binding(get: { model.library.settings.defaultStyleId }, set: { v in model.setSettings { $0.defaultStyleId = v } })) {
                    ForEach(Styles.builtIn) { Text($0.name).tag($0.id) }
                }.labelsHidden()
            }
            group("Keyboard") {
                Text("⌘N new document · ⌘O quick open · ⌘W close tab · ⌘F find in page · ⌃⌘S sidebar · ⌥F10 focus the formatting bar · ⌘⇧B reapply last color. The Format and Insert menus list every editor shortcut.")
                    .font(.system(size: 12.5)).foregroundStyle(t.secondary)
            }
        case "space":
            group("Space name") {
                HStack {
                    SpaceAvatar(name: model.library.space.name, size: 44)
                    TextField("Space name", text: $spaceName, onCommit: { model.renameSpace(spaceName) }).textFieldStyle(.roundedBorder)
                    Button("Save") { model.renameSpace(spaceName) }
                }.onAppear { spaceName = model.library.space.name }
                Text("Multiple Spaces arrive in v0.5.").font(.system(size: 11.5)).foregroundStyle(t.tertiary)
            }
        case "stats": stats
        case "data":
            group("Where your notes live") {
                Text(model.vault.dir.path).font(.system(size: 12, design: .monospaced)).textSelection(.enabled).foregroundStyle(t.text)
                Text("library.json is the index, docs/ holds one JSON file per document, assets/ holds images, backups/ holds copies made before any format migration. The format is documented in docs/FORMAT.md.")
                    .font(.system(size: 12)).foregroundStyle(t.secondary).fixedSize(horizontal: false, vertical: true)
                HStack { Button("Show in Finder") { model.revealVault() }; Button("Export All as Markdown…") { model.exportAll() } }
            }
            if let r = model.readOnly { group("Read-only mode") { Text(r).foregroundStyle(.orange) } }
        case "about":
            group("Draft 0.1 — First Light") {
                Text("A free, open-source, local-first notes app. No account, no network, no telemetry. Your documents are portable JSON + Markdown export.").font(.system(size: 12.5)).foregroundStyle(t.secondary)
            }
        default:
            let p = sections.first { $0.0 == section }
            group(p?.1 ?? "") {
                Text("Not available yet — planned for \(p?.3 ?? "a later version"). See docs/ROADMAP.md for what it will do.").foregroundStyle(t.secondary)
            }
        }
    }

    var appearance: some View {
        VStack(alignment: .leading, spacing: 22) {
            group("Theme") {
                HStack(spacing: 14) {
                    ForEach([("system", "System"), ("light", "Light"), ("dark", "Dark")], id: \.0) { k, label in
                        Button { model.setSettings { $0.theme = k } } label: {
                            VStack(spacing: 8) {
                                ThemeThumb(kind: k).frame(width: 130, height: 82)
                                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(model.library.settings.theme == k ? t.accent : t.line, lineWidth: model.library.settings.theme == k ? 2.5 : 1))
                                Text(label).font(.system(size: 12.5, weight: .medium)).foregroundStyle(model.library.settings.theme == k ? t.accent : t.text)
                            }
                        }.buttonStyle(.plain).accessibilityLabel("\(label) theme")
                    }
                }
            }
            group("Interface accent color") {
                HStack(spacing: 12) {
                    ForEach(["#5b6cf0", "#2f9bd8", "#e0558f", "#2fae8c", "#9b6cf0", "#e0a42e", "#8a8d94"], id: \.self) { hex in
                        Button { model.setSettings { $0.accent = hex } } label: {
                            Circle().fill(Color(hex: hex)).frame(width: 28, height: 28)
                                .overlay(Circle().strokeBorder(t.text, lineWidth: model.library.settings.accent == hex ? 2 : 0).padding(-4))
                        }.buttonStyle(.plain).accessibilityLabel("Accent \(hex)")
                    }
                }
            }
            group("Additional options") {
                Toggle("Use document style for the app", isOn: Binding(get: { model.library.settings.useDocStyleForApp }, set: { v in model.setSettings { $0.useDocStyleForApp = v } }))
                Toggle("Reduce animations", isOn: Binding(get: { model.library.settings.reduceMotion }, set: { v in model.setSettings { $0.reduceMotion = v } }))
            }
        }.toggleStyle(.switch)
    }

    var stats: some View {
        let metas = Array(model.library.docs.values)
        let words = metas.reduce(0) { $0 + $1.words }
        let size = (try? FileManager.default.subpathsOfDirectory(atPath: model.vault.dir.path).reduce(0) { acc, p in
            acc + ((try? FileManager.default.attributesOfItem(atPath: model.vault.dir.appendingPathComponent(p).path)[.size] as? Int) ?? 0)
        }) ?? 0
        return group("Stats") {
            statRow("Storage on disk", ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))
            statRow("Documents", "\(metas.filter { $0.parentDocId == nil }.count)")
            statRow("Nested pages", "\(metas.filter { $0.parentDocId != nil }.count)")
            statRow("Blocks", "\(metas.reduce(0) { $0 + $1.blocks })")
            statRow("Words", "\(words)")
            statRow("Reading time", "\(max(1, words / 230)) min")
        }
    }

    func statRow(_ k: String, _ v: String) -> some View {
        HStack { Text(k).foregroundStyle(t.secondary); Spacer(); Text(v).foregroundStyle(t.text).monospacedDigit() }.font(.system(size: 13)).padding(.vertical, 3)
    }

    func group<C: View>(_ title: String, @ViewBuilder _ c: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(t.text)
            VStack(alignment: .leading, spacing: 10) { c() }
                .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(t.card.opacity(t.dark ? 0.5 : 1)))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(t.line, lineWidth: 0.5))
        }
    }
}

struct ThemeThumb: View {
    let kind: String
    var body: some View {
        let half = { (dark: Bool) in
            ZStack(alignment: .bottomTrailing) {
                SceneView(sceneId: dark ? "night" : "fog")
                RoundedRectangle(cornerRadius: 5).fill(dark ? Color(hex: "#25262a") : .white).frame(width: 70, height: 46).offset(x: -8, y: 10)
            }
        }
        Group {
            if kind == "system" { HStack(spacing: 0) { half(false); half(true) } }
            else { half(kind == "dark") }
        }.clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Overlays

struct Overlays: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.tokens) var t
    var body: some View {
        ZStack {
            if model.quickOpen { QuickOpen() }
            if let c = model.confirm { ConfirmDialog(req: c) }
            VStack {
                Spacer()
                VStack(spacing: 8) {
                    ForEach(model.toasts) { toast in
                        HStack(spacing: 12) {
                            Text(toast.message).font(.system(size: 13)).foregroundStyle(.white).lineLimit(3)
                            if let l = toast.actionLabel { Button(l) { toast.action?(); model.toasts.removeAll { $0.id == toast.id } }.buttonStyle(.plain).foregroundStyle(Color(hex: "#a9b4ff")).font(.system(size: 13, weight: .semibold)) }
                        }
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .background(Capsule().fill(Color.black.opacity(0.86)))
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .accessibilityElement(children: .combine)
                        .accessibilityAddTraits(.updatesFrequently)
                    }
                }.padding(.bottom, 24)
            }
            .allowsHitTesting(!model.toasts.isEmpty)
        }
    }
}

struct ConfirmDialog: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.tokens) var t
    let req: ConfirmRequest
    var body: some View {
        ZStack {
            Color.black.opacity(0.3).ignoresSafeArea().onTapGesture { model.confirm = nil }
            VStack(alignment: .leading, spacing: 12) {
                Text(req.title).font(.system(size: 15, weight: .semibold)).foregroundStyle(t.text)
                Text(req.detail).font(.system(size: 12.5)).foregroundStyle(t.secondary).fixedSize(horizontal: false, vertical: true)
                HStack {
                    Spacer()
                    Button("Cancel") { model.confirm = nil }.keyboardShortcut(.cancelAction)
                    Button(req.confirmLabel, role: req.destructive ? .destructive : nil) { model.confirm = nil; req.onConfirm() }
                        .keyboardShortcut(.defaultAction).tint(req.destructive ? .red : t.accent)
                }
            }
            .padding(20).frame(width: 400)
            .background(PanelBackground())
        }
        .accessibilityAddTraits(.isModal)
    }
}

struct QuickOpen: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.tokens) var t
    @State private var query = ""
    @State private var index = 0
    @FocusState private var focused: Bool

    var results: [DocMeta] {
        let q = query.lowercased().trimmingCharacters(in: .whitespaces)
        let all = model.library.docs.values.sorted { a, b in
            if a.starred != b.starred { return a.starred }
            return a.viewedAt > b.viewedAt
        }
        guard !q.isEmpty else { return Array(all.prefix(12)) }
        return all.filter { $0.title.lowercased().contains(q) }
            .sorted { ($0.title.lowercased().hasPrefix(q) ? 0 : 1, -$0.viewedAt) < ($1.title.lowercased().hasPrefix(q) ? 0 : 1, -$1.viewedAt) }
            .prefix(12).map { $0 }
    }

    func choose() {
        let r = results
        if r.indices.contains(index) { model.openView(.doc(r[index].id)) }
        else if !query.isEmpty { model.createDoc(title: query) }
        model.quickOpen = false
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.opacity(0.22).ignoresSafeArea().onTapGesture { model.quickOpen = false }
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(t.secondary)
                    TextField("Open a document by name…", text: $query)
                        .textFieldStyle(.plain).font(.system(size: 16)).focused($focused)
                        .onSubmit(choose)
                        .onKeyPress(.downArrow) { index = min(index + 1, max(0, results.count)); return .handled }
                        .onKeyPress(.upArrow) { index = max(index - 1, 0); return .handled }
                        .onExitCommand { model.quickOpen = false }
                        .accessibilityLabel("Quick Open")
                }.padding(14)
                Divider().opacity(0.5)
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(Array(results.enumerated()), id: \.element.id) { i, m in
                            row(icon: m.parentDocId == nil ? "doc.text" : "doc.on.doc", title: m.title.isEmpty ? "Untitled" : m.title, sub: model.folderName(m.folderId), selected: i == index)
                                .onTapGesture { index = i; choose() }
                        }
                        if !query.isEmpty {
                            row(icon: "plus", title: "Create “\(query)”", sub: "New document", selected: index == results.count)
                                .onTapGesture { index = results.count; choose() }
                        }
                    }.padding(6)
                }.frame(maxHeight: 360)
            }
            .frame(width: 560)
            .background(PanelBackground())
            .padding(.top, 90)
        }
        .onAppear { focused = true }
        .onChange(of: query) { _, _ in index = 0 }
    }

    func row(icon: String, title: String, sub: String, selected: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).frame(width: 20).foregroundStyle(t.secondary)
            Text(title).font(.system(size: 13.5)).foregroundStyle(t.text).lineLimit(1)
            Spacer()
            Text(sub).font(.system(size: 12)).foregroundStyle(t.tertiary)
        }
        .padding(.horizontal, 10).frame(height: 34)
        .background(RoundedRectangle(cornerRadius: 8).fill(selected ? t.accent.opacity(0.16) : .clear))
        .contentShape(Rectangle())
    }
}
