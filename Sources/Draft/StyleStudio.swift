import SwiftUI
import DraftCore

/// Saved styles: save, duplicate, rename, pin, delete, default.
extension AppModel {
    func baseStyle(of id: String) -> String { library.userStyles.first { $0.id == id }?.base ?? id }

    /// Save the document's current look (style + tweaks) as a new style and use it there.
    @discardableResult
    func saveStyle(from docId: String, name: String) -> String? {
        guard let d = docs[docId] else { return nil }
        let n = name.trimmingCharacters(in: .whitespaces)
        let u = UserStyle(name: n.isEmpty ? "My Style" : n, base: baseStyle(of: d.appearance.styleId), tokens: Styles.resolve(d.appearance))
        library.userStyles.append(u)
        updateAppearance(docId) { $0.styleId = u.id; $0.overrides = StyleOverrides() }
        scheduleLibrarySave()
        toast("Saved style “\(u.name)”")
        return u.id
    }

    @discardableResult
    func duplicateStyle(_ id: String) -> String {
        let s = Styles.style(id)
        let u = UserStyle(name: s.name + " copy", base: baseStyle(of: id), tokens: s.tokens)
        library.userStyles.append(u)
        scheduleLibrarySave()
        return u.id
    }

    func renameStyle(_ id: String, _ name: String) {
        let n = name.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty, let i = library.userStyles.firstIndex(where: { $0.id == id }) else { return }
        library.userStyles[i].name = n
        scheduleLibrarySave()
    }

    func togglePin(_ id: String) {
        guard let i = library.userStyles.firstIndex(where: { $0.id == id }) else { return }
        library.userStyles[i].pinned = library.userStyles[i].pinned == true ? nil : true
        scheduleLibrarySave()
    }

    /// Documents using the style fall back to its base style; their content is never touched.
    func deleteStyle(_ id: String) {
        guard let u = library.userStyles.first(where: { $0.id == id }) else { return }
        saveDirtyDocs()
        var n = 0
        for m in library.docs.values where m.styleId == id {
            guard var d = ensureDoc(m.id) else { continue }
            d.appearance.styleId = u.base
            setAppearance(m.id, d.appearance, previous: nil, registering: false)
            n += 1
        }
        if library.settings.defaultStyleId == id { library.settings.defaultStyleId = u.base }
        library.userStyles.removeAll { $0.id == id }
        saveDirtyDocs()
        scheduleLibrarySave()
        toast("Deleted style “\(u.name)”" + (n > 0 ? ". \(n) document\(n == 1 ? "" : "s") now use\(n == 1 ? "s" : "") \(Styles.style(u.base).name)." : ""))
    }
}

/// Browse built-in and saved styles; the selected one is previewed with this document's title
/// before it is applied.
struct StyleGallery: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.tokens) var t
    let docId: String
    @State private var query = ""
    @State private var selected: String?
    @State private var renaming: String?
    @State private var newName = ""

    var body: some View {
        let current = model.docs[docId]?.appearance.styleId ?? "paper"
        let pick = selected ?? current
        let builtIn = Styles.builtIn.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }
        let mine = Styles.all.filter { $0.id.hasPrefix("u_") && (query.isEmpty || $0.name.localizedCaseInsensitiveContains(query)) }
        ZStack {
            Color.black.opacity(0.28).onTapGesture { model.styleGallery = false }
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Style Gallery").font(.system(size: DS.headline, weight: .semibold)).accessibilityAddTraits(.isHeader)
                    Spacer()
                    IconButton(symbol: "xmark", label: "Close gallery", size: 26) { model.styleGallery = false }
                }
                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack { Image(systemName: "magnifyingglass").foregroundStyle(t.secondary); TextField("Search styles", text: $query).textFieldStyle(.plain) }
                            .padding(9).background(RoundedRectangle(cornerRadius: DS.rControl).fill(t.hover))
                        ScrollView {
                            VStack(alignment: .leading, spacing: 10) {
                                if !mine.isEmpty {
                                    Text("MY STYLES").font(.system(size: DS.caption, weight: .semibold)).foregroundStyle(t.tertiary)
                                    grid(mine, current: current, pick: pick)
                                }
                                Text("DRAFT STYLES").font(.system(size: DS.caption, weight: .semibold)).foregroundStyle(t.tertiary)
                                grid(builtIn, current: current, pick: pick)
                            }
                        }
                    }
                    .frame(minWidth: 280)
                    preview(pick, current: current).frame(width: 220)
                }
            }
            .padding(18)
            .frame(maxWidth: 760, maxHeight: 640)
            .background(PanelBackground())
            .padding(30)
        }
        .onExitCommand { model.styleGallery = false }
        .alert("Rename Style", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $newName)
            Button("Rename") { if let r = renaming { model.renameStyle(r, newName) }; renaming = nil }
            Button("Cancel", role: .cancel) { renaming = nil }
        }
    }

    func grid(_ styles: [StyleDef], current: String, pick: String) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 12)], spacing: 12) {
            ForEach(styles) { s in
                Button { selected = s.id } label: {
                    VStack(alignment: .leading, spacing: 5) {
                        StylePreviewCard(tokens: s.tokens, name: s.name, height: 130)
                            .overlay(RoundedRectangle(cornerRadius: DS.rCard).strokeBorder(pick == s.id ? t.accent : (current == s.id ? t.line : .clear), lineWidth: pick == s.id ? 3 : 1.5))
                        HStack(spacing: 4) {
                            if model.library.userStyles.first(where: { $0.id == s.id })?.pinned == true { Image(systemName: "pin.fill").font(.system(size: DS.micro)).foregroundStyle(t.secondary) }
                            Text(s.name).font(.system(size: DS.footnote)).foregroundStyle(t.text).lineLimit(1)
                            if model.library.settings.defaultStyleId == s.id { Text("Default").font(.system(size: DS.micro, weight: .semibold)).foregroundStyle(t.accent) }
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Style \(s.name)\(current == s.id ? ", in use" : "")")
                .accessibilityAddTraits(pick == s.id ? .isSelected : [])
                .contextMenu { menu(s) }
            }
        }
    }

    @ViewBuilder func menu(_ s: StyleDef) -> some View {
        Button("Apply") { apply(s.id) }
        Button("Use for New Documents") { model.setSettings { $0.defaultStyleId = s.id } }
        Button("Duplicate") { selected = model.duplicateStyle(s.id) }
        if s.id.hasPrefix("u_") {
            Button(model.library.userStyles.first { $0.id == s.id }?.pinned == true ? "Unpin" : "Pin to Top") { model.togglePin(s.id) }
            Button("Rename…") { newName = s.name; renaming = s.id }
            Divider()
            Button("Delete Style", role: .destructive) { model.deleteStyle(s.id); selected = nil }
        }
    }

    func preview(_ id: String, current: String) -> some View {
        let s = Styles.style(id)
        let title = model.library.docs[docId]?.title ?? ""
        return VStack(alignment: .leading, spacing: 10) {
            Text("PREVIEW").font(.system(size: DS.caption, weight: .semibold)).foregroundStyle(t.tertiary)
            StylePreviewCard(tokens: s.tokens, name: title.isEmpty ? s.name : title, height: 260)
            Text(s.name).font(.system(size: DS.body, weight: .semibold)).foregroundStyle(t.text)
            Text(String(format: "Text contrast %.1f:1", ColorMath.contrast(s.tokens.textColor, s.tokens.pageColor))).font(.system(size: DS.footnote)).foregroundStyle(t.secondary)
            Button(id == current ? "In Use" : "Apply to This Document") { apply(id) }
                .keyboardShortcut(.defaultAction).disabled(id == current)
            HStack {
                Button("Duplicate") { selected = model.duplicateStyle(id) }
                if id.hasPrefix("u_") {
                    Button("Rename…") { newName = s.name; renaming = id }
                    Button(model.library.userStyles.first { $0.id == id }?.pinned == true ? "Unpin" : "Pin") { model.togglePin(id) }
                }
            }.controlSize(.small)
        }
    }

    func apply(_ id: String) {
        model.updateAppearance(docId) { $0.styleId = id; $0.overrides = StyleOverrides() }
        model.styleGallery = false
    }
}

/// Spaces: separate trees of folders and documents (with their own tags, tasks and tabs).
extension AppModel {
    func createSpace(_ name: String) {
        let n = name.trimmingCharacters(in: .whitespaces)
        let s = Space(id: newId("s_"), name: n.isEmpty ? "New Space" : n)
        library.spaces.append(s)
        switchSpace(s.id)
    }

    /// Everything is saved before the switch; each Space keeps its own tabs.
    func switchSpace(_ id: String) {
        guard id != library.space.id, let target = library.spaces.first(where: { $0.id == id }) else { return }
        flushAll()
        if let i = library.spaces.firstIndex(where: { $0.id == library.space.id }) {
            library.spaces[i].tabs = library.tabs
            library.spaces[i].activeTabId = library.activeTabId
            library.spaces[i].name = library.space.name
        }
        library.space = target
        var tabs = target.tabs ?? []
        tabs.removeAll { $0.view.kind == "doc" && library.docs[$0.view.docId ?? ""].map { library.inSpace($0) && $0.deletedAt == nil } != true }
        if tabs.first?.view.kind != "all" { tabs.insert(Tab(view: .all), at: 0) }
        library.tabs = tabs
        library.activeTabId = tabs.contains { $0.id == target.activeTabId } ? target.activeTabId : tabs[0].id
        panel = nil
        librarySearch = ""
        scheduleLibrarySave()
        saveLibraryNowIfNeeded()
        indexTick &+= 1
        assistant.spaceChanged()
        toast("Switched to \(target.name)")
    }

    func deleteSpace(_ id: String) {
        guard library.spaces.count > 1, id != library.space.id, !library.docs.values.contains(where: { ($0.spaceId ?? library.spaces.first?.id) == id }) else { return }
        library.spaces.removeAll { $0.id == id }
        library.folders.removeAll { $0.spaceId == id }
        scheduleLibrarySave()
    }

    func spaceIsEmpty(_ id: String) -> Bool { !library.docs.values.contains { ($0.spaceId ?? library.spaces.first?.id) == id } }
}
