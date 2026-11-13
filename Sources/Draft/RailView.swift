import SwiftUI
import DraftCore
import DraftEditor

private let relativeFormatter: RelativeDateTimeFormatter = { let f = RelativeDateTimeFormatter(); f.unitsStyle = .full; return f }()

func relative(_ ms: Double) -> String {
    let d = Date(timeIntervalSince1970: ms / 1000)
    if abs(d.timeIntervalSinceNow) < 60 { return "just now" }
    return relativeFormatter.localizedString(for: d, relativeTo: Date())
}

struct RailView: View {
    @Environment(AppModel.self) var model
    @Environment(\.tokens) var t
    var narrow: Bool

    var body: some View {
        let docId = model.activeDocId
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Spacer().frame(width: narrow ? 0 : 76) // window buttons
                Spacer()
                HStack(spacing: 6) {
                    if docId != nil {
                        Menu {
                            Picker("Show in sidebar", selection: Binding(get: { model.railShowsFolders }, set: { model.railShowsFolders = $0 })) {
                                Text("Document").tag(false)
                                Text("Folders").tag(true)
                            }.pickerStyle(.inline)
                        } label: {
                            Image(systemName: model.railShowsFolders ? "folder" : "list.bullet.indent")
                        }
                        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.visible).fixedSize()
                        .foregroundStyle(t.secondary).tint(t.secondary)
                        .help("Choose what the sidebar shows")
                    }
                    IconButton(symbol: "sidebar.left", label: "Hide sidebar (⌃⌘S)") { model.setSettings { $0.railCollapsed = true } }
                }
                
            }
            .frame(height: WindowChrome.height - 16)
            .padding(.horizontal, 8)
            .background(TitleBarArea())
            if model.activeView.kind == "settings" {
                SettingsRail(section: model.activeView.section ?? "appearance")
            } else if let id = docId, !model.railShowsFolders, !model.freshDocs.contains(id) {
                DocumentRail(docId: id).id(id)
            } else {
                LibraryRail()
            }
        }
        .background(RoundedRectangle(cornerRadius: Tokens.radiusPanel, style: .continuous).fill(t.rail))
        .overlay(RoundedRectangle(cornerRadius: Tokens.radiusPanel, style: .continuous).strokeBorder(t.line, lineWidth: 0.5))
    }
}

struct RailRow: View {
    @Environment(\.tokens) var t
    var icon: String
    var title: LocalizedStringKey
    var isSelected = false
    var indent: CGFloat = 0
    var trailing: AnyView? = nil
    var tint: Color? = nil
    var action: () -> Void
    @State private var hover = false
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: DS.body)).frame(width: 18).foregroundStyle(tint ?? t.secondary)
            Text(title).font(.system(size: DS.body)).lineLimit(1).foregroundStyle(t.text)
            Spacer(minLength: 0)
            trailing
        }
        .padding(.leading, 8 + indent).padding(.trailing, 6)
        .frame(height: 30)
        .background(RoundedRectangle(cornerRadius: DS.rControl, style: .continuous).fill(isSelected ? t.selected : (hover ? t.hover : .clear)))
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .onTapGesture(perform: action)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

struct SectionHeader: View {
    @Environment(\.tokens) var t
    var title: LocalizedStringKey
    var action: (() -> Void)? = nil
    var actionLabel = ""
    var body: some View {
        HStack {
            Text(title).font(.system(size: DS.footnote, weight: .semibold)).foregroundStyle(t.secondary)
            Spacer()
            if let action { IconButton(symbol: "plus", label: actionLabel, size: 22, action: action) }
        }
        .padding(.horizontal, 10).padding(.top, 14).padding(.bottom, 4)
    }
}

struct SpaceAvatar: View {
    var name: String
    var size: CGFloat = 22
    var body: some View {
        // Original generated mark: two overlapping soft shapes in the space's colors.
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous).fill(LinearGradient(colors: [Color(hex: "#7f8cf5"), Color(hex: "#f0a37c")], startPoint: .topLeading, endPoint: .bottomTrailing))
            Text(String(name.prefix(1)).uppercased()).font(.system(size: size * 0.5, weight: .bold, design: .rounded)).foregroundStyle(.white)
        }.frame(width: size, height: size)
    }
}

struct LibraryRail: View {
    @Environment(AppModel.self) var model
    @Environment(\.tokens) var t
    @State private var renameText = ""

    var body: some View {
        let v = model.activeView
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 1) {
                    SpaceSwitcher().padding(.horizontal, 4).padding(.bottom, 6)
                    RailRow(icon: "square.grid.2x2", title: "All Docs", isSelected: v.kind == "all") { model.activateTab(model.tabs[0].id) }
                    RailRow(icon: "magnifyingglass", title: "Quick Open", trailing: AnyView(Text("⌘O").font(.system(size: DS.caption)).foregroundStyle(t.tertiary))) { model.quickOpen = true }
                    if shown("shared") { RailRow(icon: "person.2", title: "Shared with Me", isSelected: v.kind == "shared") { model.openView(ViewRef(kind: "shared")) } }
                    let _ = model.indexTick
                    if shown("today") { RailRow(icon: "sun.max", title: "Today", isSelected: model.activeDocId != nil && model.library.docs[model.activeDocId!]?.dailyDate == model.todayKey,
                            trailing: AnyView(Text("⇧⌘D").font(.system(size: DS.caption)).foregroundStyle(t.tertiary))) { model.openDaily() } }
                    if shown("calendar") { RailRow(icon: "calendar", title: "Calendar", isSelected: v.kind == "calendar") { model.openView(ViewRef(kind: "calendar")) } }
                    let due = model.tasks(.today).count + model.tasks(.overdue).count
                    if shown("tasks") { RailRow(icon: "checklist", title: "Tasks", isSelected: v.kind == "tasks",
                            trailing: due == 0 ? nil : AnyView(Text("\(due)").font(.system(size: DS.caption)).foregroundStyle(t.tertiary))) { model.openView(ViewRef(kind: "tasks")) } }

                    ForEach(model.library.settings.sidebarOrder.filter(shown), id: \.self) { key in
                        switch key {
                        case "starred": starredSection(v)
                        case "folders": foldersSection(v)
                        default: tagsSection(v)
                        }
                    }
                    if shown("trash") { trashRow(v) }
                }.padding(.horizontal, 6)
            }
            Spacer(minLength: 0)
            VaultCard()
            HStack(spacing: 2) {
                IconButton(symbol: "gearshape", label: "Settings (⌘,)") { model.openView(ViewRef(kind: "settings", section: "appearance")) }
                IconButton(symbol: "square.and.arrow.up.on.square", label: "Export all documents") { model.exportAll() }
                IconButton(symbol: "folder", label: "Show data folder in Finder") { model.revealVault() }
                Spacer()
            }.padding(.horizontal, 10).padding(.bottom, 10)
        }
    }

    func shown(_ key: String) -> Bool { !model.library.settings.sidebarHidden.contains(key) }

    @ViewBuilder func starredSection(_ v: ViewRef) -> some View {
            SectionHeader(title: "Starred")
            let starred = model.library.liveDocs.filter(\.starred).sorted { $0.title < $1.title }
            if starred.isEmpty {
                Text("Star documents to keep them close").font(.system(size: DS.footnote)).italic().foregroundStyle(t.tertiary).padding(.horizontal, 10).padding(.vertical, 4)
            }
            ForEach(starred) { m in
                RailRow(icon: "star.fill", title: LocalizedStringKey(m.title.isEmpty ? "Untitled" : m.title), isSelected: model.activeDocId == m.id) { model.openView(.doc(m.id)) }
            }
    }

    @ViewBuilder func foldersSection(_ v: ViewRef) -> some View {
            SectionHeader(title: "Folders", action: { renameText = "New Folder"; model.createFolder() }, actionLabel: "New folder (⇧⌘N)")
            RailRow(icon: "tray", title: "Unsorted", isSelected: v.kind == "unsorted") { model.openView(ViewRef(kind: "unsorted")) }
            ForEach(model.library.spaceFolders.sorted { $0.order < $1.order }) { f in
                folderRow(f)
            }
    }

    @ViewBuilder func trashRow(_ v: ViewRef) -> some View {
            RailRow(icon: "trash", title: "Recently Deleted", isSelected: v.kind == "trash",
                    trailing: model.library.trashedDocs.isEmpty ? nil : AnyView(Text("\(model.library.trashedDocs.count)").font(.system(size: DS.caption)).foregroundStyle(t.tertiary))) {
                model.openView(ViewRef(kind: "trash"))
            }
    }

    @ViewBuilder func tagsSection(_ v: ViewRef) -> some View {
            SectionHeader(title: "Tags")
            let tags = model.index.tagCounts(live: model.liveIds)
            if tags.isEmpty {
                Text("Type # and a word in any document").font(.system(size: DS.footnote)).italic().foregroundStyle(t.tertiary).padding(.horizontal, 10).padding(.vertical, 4)
            }
            ForEach(tags, id: \.tag) { tag in
                RailRow(icon: "number", title: LocalizedStringKey(tag.tag), isSelected: v.kind == "tag" && v.section?.lowercased() == tag.tag.lowercased(),
                        trailing: AnyView(Text("\(tag.count)").font(.system(size: DS.caption)).foregroundStyle(t.tertiary)), tint: Color(hex: model.tagColor(tag.tag))) {
                    model.openView(ViewRef(kind: "tag", section: tag.tag))
                }
            }
    }

    @ViewBuilder func folderRow(_ f: Folder) -> some View {
        let expanded = model.library.expandedFolders.contains(f.id)
        let v = model.activeView
        if model.renamingFolder == f.id {
            TextField("Folder name", text: $renameText, onCommit: { model.renameFolder(f.id, renameText) })
                .textFieldStyle(.roundedBorder).padding(.horizontal, 8)
                .onAppear { renameText = f.name }
                .onExitCommand { model.renamingFolder = nil }
        } else {
            RailRow(icon: expanded ? "folder.fill" : "folder", title: LocalizedStringKey(f.name), isSelected: v.kind == "folder" && v.folderId == f.id,
                    trailing: AnyView(Button { model.toggleExpanded(f.id) } label: {
                        Image(systemName: "chevron.right").font(.system(size: DS.micro, weight: .bold)).rotationEffect(.degrees(expanded ? 90 : 0)).frame(width: 18, height: 18)
                    }.buttonStyle(.plain).foregroundStyle(t.tertiary).accessibilityLabel(expanded ? "Collapse \(f.name)" : "Expand \(f.name)"))) {
                model.openView(.folder(f.id))
            }
            .contextMenu {
                Button("Rename") { renameText = f.name; model.renamingFolder = f.id }
                Button("New Document in Folder") { model.createDoc(folderId: .some(f.id)) }
                Divider()
                Button("Remove Folder…", role: .destructive) { model.requestDeleteFolder(f.id) }
            }
            if expanded {
                ForEach(model.docsByFolder[f.id] ?? []) { m in
                    RailRow(icon: "doc.text", title: LocalizedStringKey(m.title.isEmpty ? "Untitled" : m.title), isSelected: model.activeDocId == m.id, indent: 18) { model.openView(.doc(m.id)) }
                }
            }
        }
    }
}

/// Honest local-first card in place of an upgrade prompt.
struct VaultCard: View {
    @Environment(AppModel.self) var model
    @Environment(\.tokens) var t
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "internaldrive").foregroundStyle(t.accent)
                Text("Stored on this Mac").font(.system(size: DS.body, weight: .semibold)).foregroundStyle(t.text)
            }
            Text("\(model.library.liveDocs.count) documents · plain files you own. No account, no cloud.")
                .font(.system(size: DS.footnote)).foregroundStyle(t.secondary).fixedSize(horizontal: false, vertical: true)
            Button("Show in Finder") { model.revealVault() }.buttonStyle(.link).font(.system(size: DS.footnote))
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: DS.rCard, style: .continuous).fill(t.dark ? Color.white.opacity(0.05) : Color.white.opacity(0.7)))
        .overlay(RoundedRectangle(cornerRadius: DS.rCard, style: .continuous).strokeBorder(t.line, lineWidth: 0.5))
        .padding(.horizontal, 10).padding(.bottom, 8)
    }
}

// MARK: - Document rail

struct DocumentRail: View {
    @Environment(AppModel.self) var model
    @Environment(\.tokens) var t
    let docId: String

    var body: some View {
        let meta = model.library.docs[docId]
        let _ = model.editorTick
        let content = model.docs[docId]?.content ?? Node("doc") // the saved snapshot (≤0.5 s behind typing), not a per-keystroke conversion
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                MiniPage(meta: meta, size: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text((meta?.title.isEmpty ?? true) ? "Untitled" : meta!.title).font(.system(size: DS.body, weight: .semibold)).lineLimit(1).foregroundStyle(t.text)
                    HStack(spacing: 4) {
                        Text(meta.map { "Edited " + relative($0.updatedAt) } ?? "").font(.system(size: DS.footnote)).foregroundStyle(t.secondary)
                        SaveBadge()
                    }
                }
            }.padding(.horizontal, 14).padding(.bottom, 12)

            HStack(spacing: 2) {
                ForEach([(DocRailTab.outline, "list.bullet", "Outline"), (.backlinks, "arrow.uturn.backward", "Backlinks"), (.tasks, "checkmark.circle", "Tasks"), (.attachments, "paperclip", "Attachments"), (.find, "doc.text.magnifyingglass", "Find in Page (⌘F)")], id: \.0) { tab, icon, label in
                    let on = model.docRailTab == tab
                    Button { model.docRailTab = tab } label: {
                        Image(systemName: icon).font(.system(size: DS.body, weight: .medium))
                            .frame(maxWidth: .infinity, minHeight: 26)
                            .background(Capsule(style: .continuous).fill(on ? (t.dark ? Color.white.opacity(0.16) : Color.white) : .clear).shadow(color: .black.opacity(on && !t.dark ? 0.08 : 0), radius: 2, y: 1))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain).foregroundStyle(on ? t.text : t.secondary)
                    .help(loc(label)).accessibilityLabel(loc(label)).accessibilityAddTraits(on ? .isSelected : [])
                }
            }
            .padding(3)
            .background(Capsule(style: .continuous).fill(t.dark ? Color.white.opacity(0.06) : Color.black.opacity(0.06)))
            .padding(.horizontal, 12).padding(.bottom, 12)
            .accessibilityElement(children: .contain).accessibilityLabel("Document sidebar pane")

            switch model.docRailTab {
            case .outline: OutlinePane(docId: docId, content: content)
            case .backlinks: BacklinksPane(docId: docId)
            case .tasks: TasksPane(docId: docId, content: content)
            case .attachments: AttachmentsPane(docId: docId, content: content)
            case .find: FindPane(docId: docId)
            }
            Spacer(minLength: 0)
        }
    }
}

struct SaveBadge: View {
    @Environment(AppModel.self) var model
    @Environment(\.tokens) var t
    var body: some View {
        switch model.saveState {
        case "saving": Text("· Saving…").font(.system(size: DS.footnote)).foregroundStyle(t.tertiary)
        case "error": Text("· Not saved").font(.system(size: DS.footnote, weight: .semibold)).foregroundStyle(.red)
        default: Text("· Saved").font(.system(size: DS.footnote)).foregroundStyle(t.tertiary)
        }
    }
}

struct PaneTitle: View {
    @Environment(\.tokens) var t
    var title: LocalizedStringKey
    var body: some View { Text(title).font(.system(size: DS.body, weight: .semibold)).foregroundStyle(t.text).padding(.horizontal, 16).padding(.bottom, 6) }
}

struct EmptyHint: View {
    @Environment(\.tokens) var t
    var text: LocalizedStringKey
    var body: some View { Text(text).font(.system(size: DS.footnote)).foregroundStyle(t.secondary).padding(.horizontal, 16).fixedSize(horizontal: false, vertical: true) }
}

struct OutlinePane: View {
    @Environment(AppModel.self) var model
    @Environment(\.tokens) var t
    let docId: String
    let content: Node
    var body: some View {
        let items = model.outline(docId)
        PaneTitle(title: "Table of Contents")
        if items.isEmpty { EmptyHint(text: "Headings and pages in this document will appear here.") }
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 1) {
                ForEach(items) { it in
                    RailRow(icon: it.kind == "page" ? "doc.text" : "number", title: LocalizedStringKey(it.text), indent: CGFloat(it.kind == "page" ? 8 : (it.level - 1) * 12)) {
                        if it.kind == "page", let d = it.docId { model.openView(.doc(d), inPlace: true) }
                        else { model.editors[docId]?.controller.scrollTo(blockId: it.id) }
                    }
                }
            }.padding(.horizontal, 6)
        }
    }
}

struct TasksPane: View {
    @Environment(AppModel.self) var model
    @Environment(\.tokens) var t
    let docId: String
    let content: Node
    var body: some View {
        let tasks = tasksOf(content)
        PaneTitle(title: "Tasks")
        if tasks.isEmpty { EmptyHint(text: "Checklist items in this document will appear here. Type [] and a space to start one.") }
        else {
            Text("\(tasks.filter(\.checked).count) of \(tasks.count) done").font(.system(size: DS.footnote)).foregroundStyle(t.secondary).padding(.horizontal, 16).padding(.bottom, 4)
        }
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 2) {
                ForEach(tasks) { task in
                    HStack(alignment: .top, spacing: 8) {
                        Button { model.editors[docId]?.controller.toggleTask(blockId: task.id) } label: {
                            Image(systemName: task.checked ? "checkmark.circle.fill" : "circle").foregroundStyle(task.checked ? t.accent : t.secondary)
                        }.buttonStyle(.plain).accessibilityLabel(task.checked ? "Mark not done" : "Mark done")
                        Text(task.text.isEmpty ? "Empty task" : task.text).font(.system(size: DS.body)).foregroundStyle(task.checked ? t.tertiary : t.text)
                            .strikethrough(task.checked).onTapGesture { model.editors[docId]?.controller.scrollTo(blockId: task.id) }
                        Spacer()
                    }.padding(.horizontal, 10).padding(.vertical, 5)
                }
            }.padding(.horizontal, 6)
        }
    }
}

struct AttachmentsPane: View {
    @Environment(AppModel.self) var model
    @Environment(\.tokens) var t
    let docId: String
    let content: Node
    var body: some View {
        let items = attachmentsOf(content)
        PaneTitle(title: "Attachments")
        if items.isEmpty { EmptyHint(text: "Images, links and files added to this document will appear here.") }
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 6) {
                ForEach(items) { a in
                    HStack(spacing: 10) {
                        if a.kind == "image", let img = model.image(forAsset: a.ref) {
                            Image(nsImage: img).resizable().aspectRatio(contentMode: .fill).frame(width: 40, height: 40).clipShape(RoundedRectangle(cornerRadius: DS.rSmall))
                        } else {
                            Image(systemName: a.kind == "link" ? "link" : a.kind == "file" ? "doc" : "photo").frame(width: 40, height: 40).background(RoundedRectangle(cornerRadius: DS.rSmall).fill(t.hover))
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(a.label).font(.system(size: DS.body)).lineLimit(1).foregroundStyle(t.text)
                            Text(a.kind == "link" ? a.ref : a.kind == "file" ? "File" : "Image").font(.system(size: DS.caption)).lineLimit(1).foregroundStyle(t.secondary)
                        }
                        Spacer()
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { model.editors[docId]?.controller.scrollTo(blockId: a.blockId) }
                    .accessibilityAddTraits(.isButton)
                    .padding(.horizontal, 10)
                }
            }
        }
    }
}

struct FindPane: View {
    @Environment(AppModel.self) var model
    @Environment(\.tokens) var t
    let docId: String
    @State private var replacement = ""
    @State private var showReplace = false
    @FocusState private var focused: Bool

    var body: some View {
        let c = model.editors[docId]?.controller
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Find").font(.system(size: DS.body, weight: .semibold)).foregroundStyle(t.text)
                Spacer()
                Toggle("Replace", isOn: $showReplace).toggleStyle(.switch).controlSize(.mini).font(.system(size: DS.footnote))
            }
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(t.secondary)
                TextField("Text in page", text: Binding(get: { model.findQuery }, set: { model.findQuery = $0 }))
                    .textFieldStyle(.plain).focused($focused)
                    .onSubmit { c?.findStep(1) }
                    .accessibilityLabel("Find in page")
            }
            .padding(8)
            .background(RoundedRectangle(cornerRadius: DS.rControl).fill(t.hover))
            if showReplace {
                TextField("Replace with", text: $replacement).textFieldStyle(.plain).padding(8).background(RoundedRectangle(cornerRadius: DS.rControl).fill(t.hover))
                HStack {
                    Button("Replace") { c?.replace(query: model.findQuery, with: replacement, all: false); model.findCount = c?.findMatches.count ?? 0 }.disabled(model.findCount == 0)
                    Button("Replace All") { let n = c?.replace(query: model.findQuery, with: replacement, all: true) ?? 0; model.findCount = c?.findMatches.count ?? 0; model.toast("Replaced \(n) matches") }.disabled(model.findCount == 0)
                }.controlSize(.small)
            }
            HStack {
                Text(model.findQuery.isEmpty ? " " : (model.findCount == 0 ? "No results on page" : "\(min((c?.findIndex ?? 0) + 1, model.findCount)) of \(model.findCount)"))
                    .font(.system(size: DS.footnote)).foregroundStyle(t.secondary)
                Spacer()
                IconButton(symbol: "chevron.up", label: "Previous match", size: 24) { c?.findStep(-1); model.editorTick &+= 1 }
                IconButton(symbol: "chevron.down", label: "Next match (Return)", size: 24) { c?.findStep(1); model.editorTick &+= 1 }
            }
        }
        .padding(.horizontal, 14)
        .onChange(of: model.findQuery) { _, q in model.findCount = c?.find(q) ?? 0 }
        .onChange(of: model.findFocusNonce) { _, _ in focused = true }
        .onAppear { focused = true; if !model.findQuery.isEmpty { model.findCount = c?.find(model.findQuery) ?? 0 } }
        .onDisappear { c?.clearFindHighlights() }
    }
}

/// Tiny page thumbnail tinted by the document's style.
struct MiniPage: View {
    var meta: DocMeta?
    var size: CGFloat
    var body: some View {
        let tint = Color(hex: meta?.tint ?? "#d9d4ca")
        RoundedRectangle(cornerRadius: size * 0.18, style: .continuous).fill(tint.opacity(0.9))
            .overlay(
                RoundedRectangle(cornerRadius: size * 0.1, style: .continuous).fill(Color.white.opacity(0.95))
                    .overlay(VStack(alignment: .leading, spacing: size * 0.06) {
                        ForEach(0..<4, id: \.self) { i in Capsule().fill(Color.black.opacity(i == 0 ? 0.35 : 0.14)).frame(width: size * (i == 0 ? 0.32 : 0.42), height: max(1, size * 0.04)) }
                    }.padding(size * 0.1), alignment: .topLeading)
                    .padding(size * 0.12)
            )
            .frame(width: size * 0.82, height: size)
    }
}

/// The Space name in the sidebar is a menu: switch Spaces, create one, or open its settings.
struct SpaceSwitcher: View {
    @Environment(AppModel.self) var model
    @Environment(\.tokens) var t
    @State private var naming = false
    @State private var name = ""
    var body: some View {
        Menu {
            Section("Spaces") {
                ForEach(model.library.spaces, id: \.id) { s in
                    Button { model.switchSpace(s.id) } label: {
                        if s.id == model.library.space.id { Label(s.name, systemImage: "checkmark") } else { Text(s.id == model.library.space.id ? model.library.space.name : s.name) }
                    }
                }
            }
            Divider()
            Button("New Space…") { name = ""; naming = true }
            Button("Space Settings…") { model.openView(ViewRef(kind: "settings", section: "space")) }
        } label: {
            HStack(spacing: 8) {
                SpaceAvatar(name: model.library.space.name)
                Text(model.library.space.name).font(.system(size: DS.body, weight: .semibold)).foregroundStyle(t.text).lineLimit(1)
                Image(systemName: "chevron.up.chevron.down").font(.system(size: DS.micro, weight: .semibold)).foregroundStyle(t.tertiary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 6).frame(height: 34).contentShape(Rectangle())
        }
        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden)
        .accessibilityLabel("Space: \(model.library.space.name). Switch or create Spaces")
        .alert("New Space", isPresented: $naming) {
            TextField("Name", text: $name)
            Button("Create") { model.createSpace(name) }
            Button("Cancel", role: .cancel) {}
        } message: { Text("A Space has its own folders, documents, tags and tasks.") }
    }
}
