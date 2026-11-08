import SwiftUI
import DraftCore

struct SettingsView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.tokens) var t
    let section: String
    @State private var spaceName = ""

    let sections: [(String, String, String, String?)] = [
        ("appearance", "Appearance", "paintpalette", nil), ("editor", "Editor", "text.cursor", nil), ("space", "Space", "square.on.circle", nil),
        ("daily", "Daily Notes & Tasks", "calendar", nil), ("tags", "Tags", "number", nil), ("advanced", "Advanced", "slider.horizontal.3", nil),
        ("stats", "Stats", "chart.bar", nil), ("data", "Data & Storage", "internaldrive", nil), ("about", "About Draft", "info.circle", nil),
        ("templates", "Templates", "doc.on.doc", nil), ("assistant", "Assistant", "sparkle", nil), ("published", "Published Content", "globe", "v1.x"), ("language", "Language & Spelling", "globe.europe.africa", "v0.6"),
    ]

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    PillGroup { PillButton(symbol: "xmark", label: "Close settings") { model.closeTab(model.activeTab.id) } }
                    Text("Settings").font(.system(size: DS.title3, weight: .semibold)).foregroundStyle(t.text)
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
                DraftSegmented("Completed tasks", selection: Binding(get: { model.library.settings.completedTasks }, set: { v in model.setSettings { $0.completedTasks = v } }), options: [("strike", "Strikethrough"), ("dim", "Dimmed"), ("none", "Unchanged")])
            }
            group("Default style for new documents") {
                Picker("", selection: Binding(get: { model.library.settings.defaultStyleId }, set: { v in model.setSettings { $0.defaultStyleId = v } })) {
                    ForEach(Styles.all) { Text($0.name).tag($0.id) }
                }.labelsHidden()
            }
            group("Keyboard") {
                Text("⌘N new document · ⌘O quick open · ⌘W close tab · ⌘F find in page · ⌃⌘S sidebar · ⌥F10 focus the formatting bar · ⌘⇧B reapply last color. The Format and Insert menus list every editor shortcut.")
                    .font(.system(size: DS.body)).foregroundStyle(t.secondary)
            }
        case "space":
            group("Space name") {
                HStack {
                    SpaceAvatar(name: model.library.space.name, size: 44)
                    TextField("Space name", text: $spaceName, onCommit: { model.renameSpace(spaceName) }).textFieldStyle(.roundedBorder)
                    Button("Save") { model.renameSpace(spaceName) }
                }.onAppear { spaceName = model.library.space.name }
            }
            group("All Spaces") {
                ForEach(model.library.spaces, id: \.id) { s in
                    HStack {
                        SpaceAvatar(name: s.id == model.library.space.id ? model.library.space.name : s.name, size: 24)
                        Text(s.id == model.library.space.id ? model.library.space.name : s.name)
                        if s.id == model.library.space.id { Text("current").font(.system(size: DS.caption)).foregroundStyle(t.tertiary) }
                        Spacer()
                        if s.id != model.library.space.id {
                            Button("Switch") { model.switchSpace(s.id) }
                            Button("Delete") { model.deleteSpace(s.id) }.disabled(!model.spaceIsEmpty(s.id))
                                .help(model.spaceIsEmpty(s.id) ? "Delete this empty Space" : "Move or delete its documents first")
                        }
                    }.font(.system(size: DS.body))
                }
                Button("New Space…") { model.createSpace("New Space") }
                Text("Each Space has its own folders, documents, tags, tasks and tabs. Templates and styles are shared.").font(.system(size: DS.footnote)).foregroundStyle(t.tertiary)
            }
        case "daily": daily
        case "templates": templates
        case "assistant": AssistantSettings(a: model.assistant)
        case "tags": tags
        case "advanced": advanced
        case "stats": stats
        case "data":
            group("Where your notes live") {
                Text(model.vault.dir.path).font(.system(size: DS.footnote, design: .monospaced)).textSelection(.enabled).foregroundStyle(t.text)
                Text("library.json is the index, docs/ holds one JSON file per document, assets/ holds images, backups/ holds copies made before any format migration. The format is documented in docs/FORMAT.md.")
                    .font(.system(size: DS.footnote)).foregroundStyle(t.secondary).fixedSize(horizontal: false, vertical: true)
                HStack { Button("Show in Finder") { model.revealVault() }; Button("Export All as Markdown…") { model.exportAll() } }
            }
            if let r = model.readOnly { group("Read-only mode") { Text(r).foregroundStyle(.orange) } }
        case "about":
            group("Draft 0.5.1") {
                Text("A free, open-source, local-first notes app. No account and no telemetry; nothing goes online unless you turn on image search, link previews or the Assistant's model download. Your documents are portable JSON with Markdown export.").font(.system(size: DS.body)).foregroundStyle(t.secondary)
                Button("Third-Party Notices") {
                    if let u = Bundle.main.url(forResource: "THIRD_PARTY_NOTICES", withExtension: "md") { NSWorkspace.shared.open(u) }
                }
            }
        default:
            let p = sections.first { $0.0 == section }
            group(p?.1 ?? "") {
                Text("Not available yet — planned for \(p?.3 ?? "a later version"). See docs/ROADMAP.md for what it will do.").foregroundStyle(t.secondary)
            }
        }
    }

    func bind<V>(_ k: WritableKeyPath<DraftCore.Settings, V>) -> Binding<V> {
        Binding(get: { model.library.settings[keyPath: k] }, set: { v in model.setSettings { $0[keyPath: k] = v } })
    }

    @State private var ignoreText = ""
    @State private var pendingReminders: [String]? = nil

    var daily: some View {
        VStack(alignment: .leading, spacing: 22) {
            group("Daily notes") {
                Toggle("Show daily notes in All Docs and folders", isOn: bind(\.showDailyNotes))
                Text("Daily notes are always in Calendar and in Quick Open. ⇧⌘D opens today's note; there is never more than one note per day.")
                    .font(.system(size: DS.footnote)).foregroundStyle(t.secondary).fixedSize(horizontal: false, vertical: true)
                Picker("Template for new daily notes", selection: bind(\.dailyTemplateId)) {
                    Text("None (empty note)").tag(String?.none)
                    ForEach(model.library.liveDocs.filter { $0.dailyDate == nil }.sorted { $0.title < $1.title }) { Text(model.docTitle($0.id)).tag(Optional($0.id)) }
                }
            }
            group("Reminders") {
                Toggle("Remind me when tasks are due", isOn: bind(\.reminders))
                Picker("Time for tasks with only a date", selection: bind(\.reminderHour)) {
                    ForEach(5..<23) { h in Text(String(format: "%02d:00", h)).tag(h) }
                }.disabled(!model.library.settings.reminders)
                Text(model.reminders.available ? "Local notifications on this Mac only. Turning reminders off removes every pending one."
                     : "Reminders need the Draft app bundle (scripts/build-app.sh); they are unavailable when running with swift run.")
                    .font(.system(size: DS.footnote)).foregroundStyle(t.secondary).fixedSize(horizontal: false, vertical: true)
                if let p = pendingReminders { Text("\(p.count) reminder\(p.count == 1 ? "" : "s") scheduled").font(.system(size: DS.footnote)).foregroundStyle(t.tertiary) }
            }
            .onAppear { model.reminders.pending { pendingReminders = $0 } }
            group("Calendar events") {
                Toggle("Show events from Calendar next to daily notes", isOn: Binding(get: { model.library.settings.calendarEvents }, set: { on in
                    guard on else { model.setSettings { $0.calendarEvents = false }; return }
                    CalendarEvents.shared.request { ok, msg in
                        model.setSettings { $0.calendarEvents = ok }
                        if let msg { model.toast(msg) }
                    }
                }))
                Text("Optional. Draft asks macOS for access only when you turn this on, reads events on this Mac, and never changes them.")
                    .font(.system(size: DS.footnote)).foregroundStyle(t.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    var tags: some View {
        VStack(alignment: .leading, spacing: 22) {
            group("Words that are not tags") {
                Toggle("Ignore color codes such as #fff and #a1b2c3", isOn: bind(\.tagRules.ignoreHex))
                Toggle("Ignore numbers such as #1 and #2026", isOn: bind(\.tagRules.ignoreNumeric))
                HStack {
                    TextField("Also ignore (comma separated, e.g. todo, wip)", text: $ignoreText).textFieldStyle(.roundedBorder)
                        .onSubmit(saveIgnore).accessibilityLabel("Custom words to ignore")
                    Button("Save", action: saveIgnore)
                }.onAppear { ignoreText = model.library.settings.tagRules.custom.joined(separator: ", ") }
            }
            group("Tags in this space") {
                let tags = model.index.tagCounts(live: model.liveIds)
                if tags.isEmpty { Text("No tags yet. Type # and a word in any document.").foregroundStyle(t.secondary) }
                ForEach(tags, id: \.tag) { tag in
                    HStack {
                        Circle().fill(Color(hex: model.tagColor(tag.tag))).frame(width: 10, height: 10)
                        Button("#" + tag.tag) { model.openView(ViewRef(kind: "tag", section: tag.tag)) }.buttonStyle(.link)
                        Text("\(tag.count)").foregroundStyle(t.tertiary)
                        Spacer()
                        if model.library.settings.tagColors[tag.tag.lowercased()] != nil { Button("Default color") { model.setTagColor(tag.tag, nil) }.buttonStyle(.link) }
                    }.font(.system(size: DS.body))
                }
            }
        }
    }

    func saveIgnore() {
        let words = ignoreText.split(separator: ",").map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "# ")) }.filter { !$0.isEmpty }
        model.setSettings { $0.tagRules.custom = words }
    }

    var templates: some View {
        VStack(alignment: .leading, spacing: 22) {
            group("Your templates") {
                if model.library.templates.isEmpty { Text("None yet. Open a document, then Info → Actions → Save as Template.").foregroundStyle(t.secondary) }
                ForEach(model.library.templates.sorted { $0.title < $1.title }) { m in
                    HStack {
                        Text(model.docTitle(m.id)); Text(m.template ?? "").foregroundStyle(t.tertiary)
                        Spacer()
                        Button("Edit") { model.openView(.doc(m.id)) }
                        Button("Delete") { model.deleteTemplate(m.id) }
                    }.font(.system(size: DS.body))
                }
            }
            group("Built in") {
                ForEach(BuiltInTemplates.all) { b in HStack { Text(b.title); Text(b.category).foregroundStyle(t.tertiary); Spacer() }.font(.system(size: DS.body)) }
                Button("New from Template…") { model.templatePicker = true }
            }
        }
    }

    var advanced: some View {
        VStack(alignment: .leading, spacing: 22) {
            group("Week starts on") {
                DraftSegmented("Week starts on", selection: bind(\.weekStart), options: [(0, "System setting"), (1, "Sunday"), (2, "Monday")])
                Text("Used by Calendar and by dates such as @next monday.").font(.system(size: DS.footnote)).foregroundStyle(t.secondary)
            }
            group("Dates in documents") {
                DraftSegmented("Dates", selection: bind(\.dateStyle), options: [("chip", "Chips"), ("text", "Plain text")])
                Text("Only the look changes; the dates themselves stay the same. Type @ and a day, e.g. @tomorrow 3pm.")
                    .font(.system(size: DS.footnote)).foregroundStyle(t.secondary)
            }
            group("A new day starts at") {
                Picker("", selection: bind(\.dayStartHour)) { ForEach(0..<7) { h in Text(String(format: "%02d:00", h)).tag(h) } }.labelsHidden().frame(width: 120)
                Text("Before this hour, Today and ⇧⌘D still mean the previous day — handy if you write after midnight.")
                    .font(.system(size: DS.footnote)).foregroundStyle(t.secondary).fixedSize(horizontal: false, vertical: true)
            }
            group("Online (off by default)") {
                Toggle("Search openly licensed images online (Openverse) from the backdrop picker", isOn: bind(\.onlineImageSearch))
                Toggle("Show previews for pasted web links", isOn: bind(\.linkPreviews))
                Text("Draft works fully offline. These send your search words or the pasted address to that website, only when you use them. Nothing else ever leaves this Mac.")
                    .font(.system(size: DS.footnote)).foregroundStyle(t.secondary).fixedSize(horizontal: false, vertical: true)
            }
            group("Index") {
                Text("Links, tags and tasks are kept in index/index.json, built from your documents. It can always be rebuilt and never changes a document.")
                    .font(.system(size: DS.footnote)).foregroundStyle(t.secondary).fixedSize(horizontal: false, vertical: true)
                Button("Rebuild Index") { model.rebuildIndex() }
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
                                    .overlay(RoundedRectangle(cornerRadius: DS.rCard).strokeBorder(model.library.settings.theme == k ? t.accent : t.line, lineWidth: model.library.settings.theme == k ? 2.5 : 1))
                                Text(label).font(.system(size: DS.body, weight: .medium)).foregroundStyle(model.library.settings.theme == k ? t.accent : t.text)
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
        let metas = model.library.liveDocs
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
        HStack { Text(k).foregroundStyle(t.secondary); Spacer(); Text(v).foregroundStyle(t.text).monospacedDigit() }.font(.system(size: DS.body)).padding(.vertical, 3)
    }

    func group<C: View>(_ title: String, @ViewBuilder _ c: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.system(size: DS.body, weight: .semibold)).foregroundStyle(t.text)
            VStack(alignment: .leading, spacing: 10) { c() }
                .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: DS.rCard, style: .continuous).fill(t.card.opacity(t.dark ? 0.5 : 1)))
                .overlay(RoundedRectangle(cornerRadius: DS.rCard, style: .continuous).strokeBorder(t.line, lineWidth: 0.5))
        }
    }
}

struct ThemeThumb: View {
    let kind: String
    var body: some View {
        let half = { (dark: Bool) in
            ZStack(alignment: .bottomTrailing) {
                SceneView(sceneId: dark ? "night" : "fog")
                RoundedRectangle(cornerRadius: DS.rSmall).fill(dark ? Color(hex: "#25262a") : .white).frame(width: 70, height: 46).offset(x: -8, y: 10)
            }
        }
        Group {
            if kind == "system" { HStack(spacing: 0) { half(false); half(true) } }
            else { half(kind == "dark") }
        }.clipShape(RoundedRectangle(cornerRadius: DS.rCard))
    }
}

// MARK: - Overlays

struct Overlays: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.tokens) var t
    var body: some View {
        ZStack {
            if model.quickOpen { QuickOpen() }
            if model.templatePicker { TemplatePicker() }
            if let c = model.confirm { ConfirmDialog(req: c) }
            VStack {
                Spacer()
                VStack(spacing: 8) {
                    ForEach(model.toasts) { toast in
                        HStack(spacing: 12) {
                            Text(toast.message).font(.system(size: DS.body)).foregroundStyle(.white).lineLimit(3)
                            if let l = toast.actionLabel { Button(l) { toast.action?(); model.toasts.removeAll { $0.id == toast.id } }.buttonStyle(.plain).foregroundStyle(Color(hex: "#a9b4ff")).font(.system(size: DS.body, weight: .semibold)) }
                        }
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .background(Capsule().fill(Color.black.opacity(0.86)))
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .accessibilityElement(children: .combine)
                        .accessibilityAddTraits(.updatesFrequently)
                    }
                }.padding(.bottom, 24)
            }
            .frame(maxWidth: .infinity) // centered at the bottom of the window
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
                Text(req.title).font(.system(size: DS.headline, weight: .semibold)).foregroundStyle(t.text)
                Text(req.detail).font(.system(size: DS.body)).foregroundStyle(t.secondary).fixedSize(horizontal: false, vertical: true)
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
        let all = model.library.liveDocs.sorted { a, b in
            if a.starred != b.starred { return a.starred }
            return a.viewedAt > b.viewedAt
        }
        guard !q.isEmpty else { return Array(all.prefix(12)) }
        return all.filter { $0.title.lowercased().contains(q) }
            .sorted { ($0.title.lowercased().hasPrefix(q) ? 0 : 1, -$0.viewedAt) < ($1.title.lowercased().hasPrefix(q) ? 0 : 1, -$1.viewedAt) }
            .prefix(12).map { $0 }
    }

    var blockResults: [(doc: String, block: IndexedBlock)] {
        query.trimmingCharacters(in: .whitespaces).count < 2 ? [] : model.index.blockHits(query, live: model.liveIds, limit: 8)
    }

    func choose() {
        let r = results, b = blockResults
        if r.indices.contains(index) { model.openView(.doc(r[index].id)) }
        else if b.indices.contains(index - r.count) { let h = b[index - r.count]; model.openBlock(h.doc, h.block.id) }
        else if !query.isEmpty { model.createDoc(title: query) }
        model.quickOpen = false
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.opacity(0.22).ignoresSafeArea().onTapGesture { model.quickOpen = false }
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(t.secondary)
                    TextField("Open a document or find a block…", text: $query)
                        .textFieldStyle(.plain).font(.system(size: DS.headline)).focused($focused)
                        .onSubmit(choose)
                        .onKeyPress(.downArrow) { index = min(index + 1, max(0, results.count + blockResults.count)); return .handled }
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
                        let blocks = blockResults
                        ForEach(Array(blocks.enumerated()), id: \.element.block.id) { i, h in
                            row(icon: h.block.heading == true ? "number" : "text.alignleft", title: h.block.text, sub: model.docTitle(h.doc), selected: results.count + i == index)
                                .onTapGesture { index = results.count + i; choose() }
                        }
                        if !query.isEmpty {
                            row(icon: "plus", title: "Create “\(query)”", sub: "New document", selected: index == results.count + blocks.count)
                                .onTapGesture { index = results.count + blocks.count; choose() }
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
            Text(title).font(.system(size: DS.body)).foregroundStyle(t.text).lineLimit(1)
            Spacer()
            Text(sub).font(.system(size: DS.footnote)).foregroundStyle(t.tertiary)
        }
        .padding(.horizontal, 10).frame(height: 34)
        .background(RoundedRectangle(cornerRadius: DS.rControl).fill(selected ? t.accent.opacity(0.16) : .clear))
        .contentShape(Rectangle())
    }
}
