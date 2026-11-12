import SwiftUI
import DraftCore

/// Settings sections, shared by the sidebar (normal width) and the page itself (narrow).
enum SettingsSections {
    static let all: [(id: String, title: String, icon: String)] = [
        ("appearance", "Appearance", "paintpalette"), ("editor", "Editor", "text.cursor"), ("space", "Space", "square.on.circle"),
        ("daily", "Daily Notes & Tasks", "calendar"), ("tags", "Tags", "number"), ("templates", "Templates", "doc.on.doc"),
        ("assistant", "Assistant", "sparkle"), ("agents", "Agents (MCP)", "person.badge.key"), ("advanced", "Advanced", "slider.horizontal.3"), ("data", "Data & Storage", "internaldrive"),
        ("stats", "Stats", "chart.bar"), ("about", "About Draft", "info.circle"),
    ]
    static func title(_ id: String) -> String { all.first { $0.id == id }?.title ?? "Settings" }
}

struct RailVisibleKey: EnvironmentKey { static let defaultValue = true }
extension EnvironmentValues { var railVisible: Bool { get { self[RailVisibleKey.self] } set { self[RailVisibleKey.self] = newValue } } }

/// Settings in the sidebar, in place of the library list, while Settings is open.
struct SettingsRail: View {
    @Environment(AppModel.self) var model
    @Environment(\.tokens) var t
    let section: String
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: DS.s2) {
                    IconButton(symbol: "chevron.left", label: "Close Settings", size: 26) { model.closeTab(model.activeTab.id) }
                    Text("Settings").font(.system(size: DS.headline, weight: .semibold)).foregroundStyle(t.text).accessibilityAddTraits(.isHeader)
                }.padding(.horizontal, 6).padding(.bottom, DS.s2)
                ForEach(SettingsSections.all, id: \.id) { s in
                    RailRow(icon: s.icon, title: s.title, isSelected: section == s.id) { model.showSettings(s.id) }
                }
            }.padding(.horizontal, 8)
        }
    }
}

struct SettingsView: View {
    @Environment(AppModel.self) var model
    @Environment(\.tokens) var t
    @Environment(\.railVisible) var railVisible
    let section: String
    @State private var spaceName = ""
    @State private var ignoreText = ""
    @State private var pendingReminders: [String]? = nil
    @State private var storage: Int64?

    var body: some View {
        HStack(spacing: 0) {
            if !railVisible {
                ScrollView {
                    VStack(alignment: .leading, spacing: 1) {
                        ForEach(SettingsSections.all, id: \.id) { s in RailRow(icon: s.icon, title: s.title, isSelected: section == s.id) { model.showSettings(s.id) } }
                    }.padding(12)
                }.frame(width: 210)
                Divider().opacity(0.4)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: DS.s5) {
                    HStack(spacing: DS.s3) {
                        if !railVisible { PillGroup { PillButton(symbol: "xmark", label: "Close settings") { model.closeTab(model.activeTab.id) } } }
                        Text(SettingsSections.title(section)).font(.system(size: DS.title2, weight: .bold)).foregroundStyle(t.text).accessibilityAddTraits(.isHeader)
                    }
                    content
                }
                .frame(maxWidth: 640, alignment: .leading).padding(.horizontal, DS.s5).padding(.vertical, DS.s5).frame(maxWidth: .infinity)
            }
        }
        .background(t.canvas)
    }

    func bind<V>(_ k: WritableKeyPath<DraftCore.Settings, V>) -> Binding<V> {
        Binding(get: { model.library.settings[keyPath: k] }, set: { v in model.setSettings { $0[keyPath: k] = v } })
    }

    @ViewBuilder var content: some View {
        switch section {
        case "appearance": appearance
        case "editor": editor
        case "space": space
        case "daily": daily
        case "templates": templates
        case "assistant": AssistantSettings(a: model.assistant)
        case "agents": AgentSettings()
        case "tags": tags
        case "advanced": advanced
        case "stats": stats
        case "data": data
        case "about": about
        default: EmptyState(symbol: "questionmark.circle", title: "Nothing here", message: "This section doesn't exist.")
        }
    }

    // MARK: Sections

    var appearance: some View {
        VStack(alignment: .leading, spacing: DS.s5) {
            SettingsSection(title: "Theme") {
                HStack(spacing: DS.s4) {
                    ForEach([("system", "System"), ("light", "Light"), ("dark", "Dark")], id: \.0) { k, label in
                        let on = model.library.settings.theme == k
                        Button { model.setSettings { $0.theme = k } } label: {
                            VStack(spacing: DS.s2) {
                                ThemeThumb(kind: k).frame(width: 120, height: 76)
                                    .overlay(RoundedRectangle(cornerRadius: DS.rCard, style: .continuous).strokeBorder(on ? t.accent : t.line, lineWidth: on ? 2 : 0.5))
                                Text(label).font(.system(size: DS.footnote, weight: on ? .semibold : .medium)).foregroundStyle(on ? t.accent : t.text)
                            }
                        }
                        .buttonStyle(.plain).accessibilityLabel("\(label) theme").accessibilityAddTraits(on ? [.isSelected] : [])
                    }
                }.padding(DS.s3 + 2)
            }
            SettingsSection(title: "Accent color") {
                HStack(spacing: DS.s3) {
                    ForEach([("#5b6cf0", "Indigo"), ("#2f9bd8", "Blue"), ("#e0558f", "Pink"), ("#2fae8c", "Green"), ("#9b6cf0", "Purple"), ("#e0a42e", "Amber"), ("#8a8d94", "Graphite")], id: \.0) { hex, name in
                        let on = model.library.settings.accent == hex
                        Button { model.setSettings { $0.accent = hex } } label: {
                            Circle().fill(Color(hex: hex)).frame(width: 24, height: 24)
                                .overlay(Circle().strokeBorder(t.text.opacity(0.85), lineWidth: on ? 2 : 0).padding(-4))
                                .frame(width: 32, height: 32).contentShape(Circle())
                        }.buttonStyle(.plain).help(name).accessibilityLabel("\(name) accent").accessibilityAddTraits(on ? [.isSelected] : [])
                    }
                }.padding(.horizontal, DS.s3).padding(.vertical, DS.s2)
            }
            SettingsSection(title: "Window and motion") {
                SettingsSwitchRow(title: "Tint the app with the document's style", detail: "The sidebar and tab strip take the open document's colors.", isOn: bind(\.useDocStyleForApp))
                SettingsSwitchRow(title: "Paper follows dark mode", detail: "Documents in the Paper style turn dark with the app. Exports keep the light page.", isOn: bind(\.paperFollowsAppearance))
                SettingsSwitchRow(title: "Reduce animations", detail: "Panels and screens fade instead of moving. macOS Reduce Motion does the same.", isOn: bind(\.reduceMotion))
                SettingsSwitchRow(title: "Simplify text effects with Increase Contrast", detail: "When macOS Increase Contrast is on, show effects as one still, readable color: no gradients, Spectrum motion, glow, shadow or outline. Effect colors are kept readable either way.", isOn: bind(\.simplifyEffectsWithIncreaseContrast))
            }
            SettingsSection(title: "Sidebar", footer: "Hidden items stay reachable from the menus and Quick Open.") {
                ForEach(Self.sidebarItems, id: \.0) { key, title in
                    let order = model.library.settings.sidebarOrder
                    SettingsRow(title: title) {
                        HStack(spacing: DS.s2) {
                            if let i = order.firstIndex(of: key) {
                                IconButton(symbol: "chevron.up", label: "Move \(title) up", size: 24) { moveSection(i, by: -1) }.disabled(i == 0)
                                IconButton(symbol: "chevron.down", label: "Move \(title) down", size: 24) { moveSection(i, by: 1) }.disabled(i == order.count - 1)
                            }
                            Toggle("Show \(title)", isOn: Binding(get: { !model.library.settings.sidebarHidden.contains(key) },
                                                                set: { on in model.setSettings { s in s.sidebarHidden.removeAll { $0 == key }; if !on { s.sidebarHidden.append(key) } } }))
                                .toggleStyle(.switch).controlSize(.small).labelsHidden()
                        }
                    }
                }
            }
            SettingsSection(title: "Getting started") {
                SettingsRow(title: "Welcome and tour", detail: "See the short introduction to Draft again.") {
                    Button("Replay Tour") { model.startTour() }.buttonStyle(.draft)
                }
            }
        }
    }

    static let sidebarItems: [(String, String)] = {
        let fixed = [("shared", "Shared with Me"), ("today", "Today"), ("calendar", "Calendar"), ("tasks", "Tasks")]
        return fixed + [("starred", "Starred"), ("folders", "Folders"), ("tags", "Tags"), ("trash", "Recently Deleted")]
    }()

    func moveSection(_ i: Int, by d: Int) {
        model.setSettings { s in let j = i + d; guard s.sidebarOrder.indices.contains(j) else { return }; s.sidebarOrder.swapAt(i, j) }
    }

    var editor: some View {
        VStack(alignment: .leading, spacing: DS.s5) {
            SettingsSection(title: "Writing") {
                SettingsMenuRow(title: "Completed tasks", detail: "How checked items look in documents.", selection: bind(\.completedTasks), options: [("strike", "Strikethrough"), ("dim", "Dimmed"), ("none", "Unchanged")])
                SettingsMenuRow(title: "Style for new documents", selection: bind(\.defaultStyleId), options: Styles.all.map { ($0.id, $0.name) })
                SettingsMenuRow(title: "Dates in documents", detail: "Only the look changes; the dates stay the same.", selection: bind(\.dateStyle), options: [("chip", "Chips"), ("text", "Plain text")])
            }
            SettingsSection(title: "Keyboard shortcuts", footer: "The Format and Insert menus list every editor shortcut.") {
                ShortcutList(items: [
                    ("⌘N", "New document"), ("⌥⌘T", "New from template"), ("⌘O", "Quick Open"), ("⌘J", "Assistant"), ("⌘F", "Find in page"),
                    ("⇧⌘D", "Today's daily note"), ("⌃⌘S", "Show or hide the sidebar"), ("⌘W", "Close tab"), ("⌥F10", "Focus the formatting bar"),
                    ("⇧⌘B", "Reapply last color"), ("/", "Insert a block (on an empty line)"),
                ])
            }
        }
    }

    var space: some View {
        VStack(alignment: .leading, spacing: DS.s5) {
            SettingsSection(title: "This Space") {
                HStack(spacing: DS.s3) {
                    SpaceAvatar(name: model.library.space.name, size: 40)
                    DraftTextField(placeholder: "Space name", text: $spaceName) { model.renameSpace(spaceName) }
                    Button("Rename") { model.renameSpace(spaceName) }.buttonStyle(.draft).disabled(spaceName == model.library.space.name || spaceName.isEmpty)
                }
                .padding(DS.s3 + 2)
                .onAppear { spaceName = model.library.space.name }
            }
            SettingsSection(title: "All Spaces", footer: "Each Space has its own folders, documents, tags, tasks and tabs, and keeps its own theme, accent, daily-note and tag settings. Templates and styles are shared.") {
                ForEach(model.library.spaces, id: \.id) { s in
                    let current = s.id == model.library.space.id
                    let name = current ? model.library.space.name : s.name
                    SettingsRow(title: name, detail: current ? "Current Space" : nil) {
                        if !current {
                            Button("Switch") { model.switchSpace(s.id) }.buttonStyle(DraftButtonStyle(compact: true))
                            Button("Delete") { model.deleteSpace(s.id) }.buttonStyle(DraftButtonStyle(role: .destructive, compact: true)).disabled(!model.spaceIsEmpty(s.id))
                                .help(model.spaceIsEmpty(s.id) ? "Delete this empty Space" : "Move or delete its documents first")
                        }
                    }
                }
                SettingsRow(title: "New Space") { Button("Create…") { model.createSpace("New Space") }.buttonStyle(DraftButtonStyle(compact: true)) }
            }
        }
    }

    var daily: some View {
        VStack(alignment: .leading, spacing: DS.s5) {
            SettingsSection(title: "Daily notes", footer: "Daily notes are always in Calendar and Quick Open. ⇧⌘D opens today's note; there is never more than one note per day.") {
                SettingsSwitchRow(title: "Show daily notes in All Docs and folders", isOn: bind(\.showDailyNotes))
                SettingsMenuRow(title: "Template for new daily notes", selection: bind(\.dailyTemplateId),
                                options: [(String?.none, "None (empty note)")] + model.library.liveDocs.filter { $0.dailyDate == nil }.sorted { $0.title < $1.title }.prefix(60).map { (Optional($0.id), model.docTitle($0.id)) })
            }
            SettingsSection(title: "Reminders", footer: model.reminders.available ? "Local notifications on this Mac only. Turning reminders off removes every pending one." : "Reminders need the Draft app bundle (scripts/build-app.sh).") {
                SettingsSwitchRow(title: "Remind me when tasks are due", detail: pendingReminders.map { "\($0.count) reminder\($0.count == 1 ? "" : "s") scheduled" }, isOn: bind(\.reminders))
                SettingsMenuRow(title: "Time for tasks with only a date", selection: bind(\.reminderHour), options: (5..<23).map { ($0, String(format: "%02d:00", $0)) }, disabled: !model.library.settings.reminders)
            }
            .onAppear { model.reminders.pending { pendingReminders = $0 } }
            SettingsSection(title: "Calendar", footer: "Optional. Draft asks macOS for access only when you turn this on, reads events on this Mac, and never changes them.") {
                SettingsSwitchRow(title: "Show events from Calendar next to daily notes", isOn: Binding(get: { model.library.settings.calendarEvents }, set: { on in
                    guard on else { model.setSettings { $0.calendarEvents = false }; return }
                    CalendarEvents.shared.request { ok, msg in
                        model.setSettings { $0.calendarEvents = ok }
                        if let msg { model.toast(msg) }
                    }
                }))
                SettingsMenuRow(title: "Week starts on", selection: bind(\.weekStart), options: [(0, "System setting"), (1, "Sunday"), (2, "Monday")])
                SettingsMenuRow(title: "A new day starts at", detail: "Before this hour, Today still means the previous day.", selection: bind(\.dayStartHour), options: (0..<7).map { ($0, String(format: "%02d:00", $0)) })
            }
        }
    }

    var tags: some View {
        VStack(alignment: .leading, spacing: DS.s5) {
            SettingsSection(title: "Words that are not tags") {
                SettingsSwitchRow(title: "Ignore color codes", detail: "Such as #fff and #a1b2c3", isOn: bind(\.tagRules.ignoreHex))
                SettingsSwitchRow(title: "Ignore numbers", detail: "Such as #1 and #2026", isOn: bind(\.tagRules.ignoreNumeric))
                HStack(spacing: DS.s2) {
                    DraftTextField(placeholder: "Also ignore (comma separated, e.g. todo, wip)", text: $ignoreText, onSubmit: saveIgnore).accessibilityLabel("Custom words to ignore")
                    Button("Save", action: saveIgnore).buttonStyle(.draft)
                }
                .padding(DS.s3)
                .onAppear { ignoreText = model.library.settings.tagRules.custom.joined(separator: ", ") }
            }
            let tags = model.index.tagCounts(live: model.liveIds)
            SettingsSection(title: "Tags in this Space") {
                if tags.isEmpty { Text("No tags yet. Type # and a word in any document.").font(.system(size: DS.body)).foregroundStyle(t.secondary).padding(DS.s3 + 2) }
                ForEach(tags, id: \.tag) { tag in
                    SettingsRow(title: "#" + tag.tag, detail: "\(tag.count) block\(tag.count == 1 ? "" : "s")") {
                        Circle().fill(Color(hex: model.tagColor(tag.tag))).frame(width: 10, height: 10).accessibilityHidden(true)
                        if model.library.settings.tagColors[tag.tag.lowercased()] != nil { Button("Default Color") { model.setTagColor(tag.tag, nil) }.buttonStyle(DraftButtonStyle(role: .quiet, compact: true)) }
                        Button("Show") { model.openView(ViewRef(kind: "tag", section: tag.tag)) }.buttonStyle(DraftButtonStyle(compact: true))
                    }
                }
            }
        }
    }

    func saveIgnore() {
        let words = ignoreText.split(separator: ",").map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "# ")) }.filter { !$0.isEmpty }
        model.setSettings { $0.tagRules.custom = words }
    }

    var templates: some View {
        VStack(alignment: .leading, spacing: DS.s5) {
            SettingsSection(title: "Your templates", footer: "Open a document, then Info → Actions → Save as Template.") {
                if model.library.templates.isEmpty { Text("None yet.").font(.system(size: DS.body)).foregroundStyle(t.secondary).padding(DS.s3 + 2) }
                ForEach(model.library.templates.sorted { $0.title < $1.title }) { m in
                    SettingsRow(title: model.docTitle(m.id), detail: m.template) {
                        Button("Edit") { model.openView(.doc(m.id)) }.buttonStyle(DraftButtonStyle(compact: true))
                        Button("Delete") { model.deleteTemplate(m.id) }.buttonStyle(DraftButtonStyle(role: .destructive, compact: true))
                    }
                }
            }
            SettingsSection(title: "Built in") {
                ForEach(BuiltInTemplates.all) { b in SettingsRow(title: b.title, detail: b.category) { EmptyView() } }
                SettingsRow(title: "Start from a template") { Button("New from Template…") { model.templatePicker = true }.buttonStyle(DraftButtonStyle(compact: true)) }
            }
        }
    }

    var advanced: some View {
        VStack(alignment: .leading, spacing: DS.s5) {
            SettingsSection(title: "Online (off by default)", footer: "Draft works fully offline. These send your search words or the pasted address to that website, only when you use them.") {
                SettingsSwitchRow(title: "Search openly licensed images", detail: "Openverse, from the backdrop picker", isOn: bind(\.onlineImageSearch))
                SettingsSwitchRow(title: "Previews for pasted web links", isOn: bind(\.linkPreviews))
            }
            SettingsSection(title: "Index", footer: "Links, tags and tasks are kept in index/index.json, built from your documents. Rebuilding never changes a document.") {
                SettingsRow(title: "Rebuild the index") { Button("Rebuild") { model.rebuildIndex() }.buttonStyle(DraftButtonStyle(compact: true)) }
            }
        }
    }

    var data: some View {
        VStack(alignment: .leading, spacing: DS.s5) {
            SettingsSection(title: "Where your notes live", footer: "library.json is the index, docs/ holds one JSON file per document, assets/ holds images, backups/ holds copies made before any format change. The format is documented in docs/FORMAT.md.") {
                SettingsRow(title: model.vault.dir.lastPathComponent, detail: model.vault.dir.path) {
                    Button("Show in Finder") { model.revealVault() }.buttonStyle(DraftButtonStyle(compact: true))
                }
                SettingsRow(title: "Export everything", detail: "Markdown files with a lossless draft-export.json") {
                    Button("Export…") { model.exportAll() }.buttonStyle(DraftButtonStyle(compact: true))
                }
            }
            vaultCheck
            if let r = model.readOnly { SettingsSection(title: "Read-only mode") { Text(r).font(.system(size: DS.body)).foregroundStyle(.orange).padding(DS.s3 + 2) } }
        }
    }

    var vaultCheck: some View {
        SettingsSection(title: "Vault check", footer: "Checking only reads. Unused files are moved to backups/, never deleted, and Undo puts them back.") {
            SettingsRow(title: "Check Vault", detail: model.vaultReport.map { "\($0.docsChecked) note\($0.docsChecked == 1 ? "" : "s") and \($0.assetsChecked) file\($0.assetsChecked == 1 ? "" : "s") checked" } ?? "Look for missing notes, missing images and files no note uses.") {
                if model.vaultChecking { ProgressView().controlSize(.small).accessibilityLabel("Checking the vault") }
                else { Button("Check Vault") { Task { await model.checkVault() } }.buttonStyle(DraftButtonStyle(compact: true)) }
            }
            if let r = model.vaultReport {
                if r.isClean {
                    checkLine("checkmark.circle", "Everything is in order.", color: .green)
                }
                if !r.libraryReadable { checkLine("exclamationmark.triangle", "library.json can't be read, so notes and unused files weren't compared.", color: .orange) }
                problem(r.missingDocFiles, "listed note has no file", "listed notes have no file")
                problem(r.strayDocFiles, "note file isn't in the library", "note files aren't in the library")
                problem(r.unreadableDocs, "note file can't be read", "note files can't be read")
                problem(r.missingAssets, "image or file a note uses is missing", "images or files notes use are missing")
                if r.problemCount > 0 { checkLine("info.circle", "Draft doesn't change these automatically. Restore them from a backup or Time Machine if you need them.", color: t.secondary) }
                if !r.unusedAssets.isEmpty {
                    SettingsRow(title: "\(r.unusedAssets.count) unused file\(r.unusedAssets.count == 1 ? "" : "s")", detail: "\(ByteCountFormatter.string(fromByteCount: r.unusedBytes, countStyle: .file)) in assets/ that no note, template or deleted note uses") {
                        if model.vaultConfirmMove {
                            HStack(spacing: DS.s2) {
                                Button("Cancel") { model.vaultConfirmMove = false }.buttonStyle(DraftButtonStyle(compact: true)).keyboardShortcut(.cancelAction)
                                Button("Move to Backups") { Task { await model.moveUnusedFiles() } }.buttonStyle(DraftButtonStyle(role: .primary, compact: true))
                            }
                        } else {
                            Button("Move Unused Files…") { model.vaultConfirmMove = true }.buttonStyle(DraftButtonStyle(compact: true)).disabled(model.readOnly != nil)
                                .help(model.readOnly != nil ? "The vault is read-only." : "")
                        }
                    }
                    if model.vaultConfirmMove { checkLine("questionmark.circle", "Move \(r.unusedAssets.count) file\(r.unusedAssets.count == 1 ? "" : "s") to backups/unused-…? You can undo this.", color: t.text) }
                }
            }
        }
    }

    @ViewBuilder func problem(_ ids: [String], _ one: String, _ many: String) -> some View {
        if !ids.isEmpty {
            checkLine("exclamationmark.triangle", "\(ids.count) \(ids.count == 1 ? one : many): \(ids.prefix(3).joined(separator: ", "))\(ids.count > 3 ? " and \(ids.count - 3) more" : "")", color: .orange)
        }
    }

    func checkLine(_ symbol: String, _ text: String, color: Color) -> some View {
        Label { Text(text).foregroundStyle(t.text).textSelection(.enabled) } icon: { Image(systemName: symbol).foregroundStyle(color) }
            .font(.system(size: DS.body)).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, DS.s3 + 2).padding(.vertical, DS.s2)
            .accessibilityElement(children: .combine)
    }

    var stats: some View {
        let metas = model.library.liveDocs
        let words = metas.reduce(0) { $0 + $1.words }
        return SettingsSection(title: nil) {
            SettingsRow(title: "Storage on disk") { Text(storage.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) } ?? "Measuring…").foregroundStyle(t.secondary).monospacedDigit() }
            SettingsRow(title: "Documents") { Text("\(metas.filter { $0.parentDocId == nil }.count)").foregroundStyle(t.secondary).monospacedDigit() }
            SettingsRow(title: "Nested pages") { Text("\(metas.filter { $0.parentDocId != nil }.count)").foregroundStyle(t.secondary).monospacedDigit() }
            SettingsRow(title: "Blocks") { Text("\(metas.reduce(0) { $0 + $1.blocks })").foregroundStyle(t.secondary).monospacedDigit() }
            SettingsRow(title: "Words") { Text("\(words)").foregroundStyle(t.secondary).monospacedDigit() }
            SettingsRow(title: "Reading time") { Text("\(max(1, words / 230)) min").foregroundStyle(t.secondary).monospacedDigit() }
        }
        .task {
            // Walking the vault is file-system work; never in a render.
            let dir = model.vault.dir
            storage = await Task.detached(priority: .utility) {
                (FileManager.default.enumerator(at: dir, includingPropertiesForKeys: [.fileSizeKey])?.allObjects as? [URL] ?? [])
                    .reduce(Int64(0)) { $0 + Int64((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
            }.value
        }
    }

    var about: some View {
        SettingsSection(title: nil, footer: "A free, open-source, local-first notes app. No account and no telemetry; nothing goes online unless you turn on image search, link previews, the Assistant's model download, or the optional OpenAI Assistant (after you review what it will send).") {
            SettingsRow(title: "Draft 0.6", detail: "Your documents are portable JSON with Markdown export.") { EmptyView() }
            SettingsRow(title: "Welcome and tour") { Button("Replay Tour") { model.startTour() }.buttonStyle(DraftButtonStyle(compact: true)) }
            SettingsRow(title: "Third-party notices", detail: "llama.cpp, Libraries.dev, Paper Shaders, Liquid AI models") {
                Button("Open") { if let u = Bundle.main.url(forResource: "THIRD_PARTY_NOTICES", withExtension: "md") { NSWorkspace.shared.open(u) } }.buttonStyle(DraftButtonStyle(compact: true))
            }
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
    @Environment(AppModel.self) var model
    @Environment(\.tokens) var t
    var body: some View {
        ZStack {
            ZStack {
                if model.quickOpen { QuickOpen().transition(.overlayPop) }
                if model.templatePicker { TemplatePicker().transition(.overlayPop) }
                if let c = model.confirm { ConfirmDialog(req: c).transition(.overlayPop) }
                if model.shortcutsSheet { ShortcutsSheet().transition(.overlayPop) }
            }
            .animation(Motion.quick(model.library.settings.reduceMotion), value: [model.quickOpen, model.templatePicker, model.confirm != nil, model.shortcutsSheet])
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
                .animation(Motion.quick(model.library.settings.reduceMotion), value: model.toasts.map(\.id))
            }
            .frame(maxWidth: .infinity) // centered at the bottom of the window
            .allowsHitTesting(!model.toasts.isEmpty)
        }
    }
}

struct ConfirmDialog: View {
    @Environment(AppModel.self) var model
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
            .surface(.floating)
        }
        .accessibilityAddTraits(.isModal)
    }
}

struct QuickOpen: View {
    @Environment(AppModel.self) var model
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
            .surface(.overlay)
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
