import SwiftUI
import DraftCore

struct LibraryView: View {
    @Environment(AppModel.self) var model
    @Environment(\.tokens) var t
    let view: ViewRef
    @FocusState private var searchFocused: Bool

    var title: String {
        switch view.kind {
        case "unsorted": return "Unsorted"
        case "starred": return "Starred"
        case "shared": return "Shared with Me"
        case "trash": return "Recently Deleted"
        case "folder": return model.folderName(view.folderId)
        default: return "All Docs"
        }
    }

    var body: some View {
        let docs = model.docsFor(view)
        VStack(spacing: 0) {
            header
            if view.kind == "trash" {
                TrashList(docs: docs)
            } else if view.kind == "shared" {
                EmptyLibrary(symbol: "person.2", title: "Nothing shared", message: "Draft is local-first: nothing is shared with you yet. Sharing and collaboration are planned for v2.0, after sync (v1.x).")
            } else if !model.librarySearch.trimmingCharacters(in: .whitespaces).isEmpty && !docs.isEmpty {
                SearchResults(hits: model.searchHits)
            } else if docs.isEmpty {
                EmptyLibrary(symbol: model.librarySearch.isEmpty ? (view.kind == "folder" ? "folder" : "doc.text") : "magnifyingglass",
                             title: model.librarySearch.isEmpty ? "No documents yet" : "No matches",
                             message: searchErrorText.map { "\($0). Check the brackets and escapes, or turn off .* to search for the words." } ?? (!model.librarySearch.isEmpty ? "No documents match “\(model.librarySearch)”." :
                                view.kind == "unsorted" ? "Any documents you haven't moved into a folder will appear here." :
                                view.kind == "folder" ? "This folder is empty. Press ⌘N to write something here." : "No documents yet. Press ⌘N to start writing."))
            } else {
                GeometryReader { geo in
                    ScrollView {
                        switch model.library.settings.libraryView {
                        case .gallery: GalleryLayout(docs: docs, width: geo.size.width)
                        case .grid: GridLayout(docs: docs)
                        case .list: ListLayout(docs: docs, width: geo.size.width)
                        }
                    }
                }
            }
        }
        .background(t.canvas)
    }

    var header: some View {
        HStack(spacing: 10) {
            if view.kind != "all" {
                PillGroup { PillButton(symbol: "chevron.left", label: "Back") { model.goBack() } }
            }
            PillGroup { PillButton(symbol: "plus", label: "New document (⌘N)") { model.createDoc() } }.tourAnchor(.newNote)
            Text(title).font(.system(size: DS.title3, weight: .semibold)).foregroundStyle(t.text)
            Spacer()
            if view.kind != "trash" && view.kind != "shared" {
            PillGroup {
                PillButton(symbol: "rectangle.grid.2x2", label: "Gallery (⌃⌘1)", isActive: model.library.settings.libraryView == .gallery) { model.setSettings { $0.libraryView = .gallery } }
                PillButton(symbol: "square.grid.3x3", label: "Grid (⌃⌘2)", isActive: model.library.settings.libraryView == .grid) { model.setSettings { $0.libraryView = .grid } }
                PillButton(symbol: "list.bullet", label: "List (⌃⌘3)", isActive: model.library.settings.libraryView == .list) { model.setSettings { $0.libraryView = .list } }
            }
            PillGroup {
                DraftIconMenu(symbol: "arrow.up.arrow.down", label: "Sort") {
                    Section("Sort By") {
                        ForEach([(SortKey.name, "Name"), (.viewedAt, "Last Viewed"), (.createdAt, "Date Created"), (.updatedAt, "Date Updated")], id: \.0) { k, label in
                            Button {
                                model.setSettings { s in
                                    if s.sort.key == k { s.sort.dir = s.sort.dir == "asc" ? "desc" : "asc" } else { s.sort = SortSpec(key: k, dir: k == .name ? "asc" : "desc") }
                                }
                            } label: {
                                let s = model.library.settings.sort
                                Text(label + (s.key == k ? (s.dir == "asc" ? " ↑" : " ↓") : ""))
                                if s.key == k { Image(systemName: "checkmark") }
                            }
                        }
                    }
                }
            }
            }
            PillGroup {
                DraftIconMenu(symbol: "ellipsis", label: "More") {
                    Button("New from Template…") { model.templatePicker = true }
                    Button("New Folder") { model.createFolder() }
                    Divider()
                    Button("Export All as Markdown…") { model.exportAll() }
                    Button("Import…") { model.chooseImport() }
                    Button("Show Data Folder in Finder") { model.revealVault() }
                    Divider()
                    Button("Stats") { model.openView(ViewRef(kind: "settings", section: "stats")) }
                }
            }
            searchPill
        }
        .padding(.horizontal, 18).padding(.vertical, 14)
    }

    var searchErrorText: String? {
        if case .failure(let e) = model.searchQuery { return e.message }
        return nil
    }

    @ViewBuilder var searchPill: some View {
        if model.librarySearchOpen {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(t.pillText.opacity(0.7))
                TextField(model.searchRegex ? "Regular expression" : "Words, \"a phrase\", -exclude", text: Binding(get: { model.librarySearch }, set: { model.librarySearch = $0 }))
                    .textFieldStyle(.plain).foregroundStyle(t.pillText).focused($searchFocused).frame(width: 220)
                    .onExitCommand { model.librarySearch = ""; model.librarySearchOpen = false }
                    .onSubmit { if let first = model.searchHits.first { model.openSearchResult(first.meta.id) } }
                    .accessibilityLabel("Search documents")
                Button { model.searchRegex.toggle() } label: { Text(".*").font(.system(size: DS.footnote, weight: .bold, design: .monospaced)).fixedSize().padding(.horizontal, 5).padding(.vertical, 3)
                    .background(Capsule().fill(model.searchRegex ? t.accent.opacity(0.15) : .clear)) }
                    .buttonStyle(.plain).fixedSize().foregroundStyle(model.searchRegex ? t.accent : t.pillText.opacity(0.5))
                    .help("Regular expression").accessibilityLabel("Regular expression").accessibilityAddTraits(model.searchRegex ? .isSelected : [])
                Button { model.librarySearch = ""; model.librarySearchOpen = false } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain).foregroundStyle(t.pillText.opacity(0.5)).accessibilityLabel("Close search")
            }
            .padding(.horizontal, 12).frame(height: 36)
            .background(Capsule().fill(t.pill)).overlay(Capsule().strokeBorder(searchErrorText == nil ? t.pillBorder : Color.red, lineWidth: searchErrorText == nil ? 0.5 : 1.5))
            .onAppear { searchFocused = true }
            if let e = searchErrorText { Text(e).font(.system(size: DS.footnote)).foregroundStyle(.red).accessibilityLabel("Search error: \(e)") }
        } else {
            PillGroup { PillButton(symbol: "magnifyingglass", label: "Search (⌘F)") { model.librarySearchOpen = true } }
                .keyboardShortcut("f", modifiers: .command)
        }
    }
}

/// The quiet empty state for lists; skeleton bars read as "still loading".
struct EmptyLibrary: View {
    var symbol = "doc.text"
    var title = "Nothing here yet"
    var message: String
    var body: some View { EmptyState(symbol: symbol, title: LocalizedStringKey(title), message: LocalizedStringKey(message)) }
}

// MARK: - Cards

struct DocPreview: View {
    @Environment(AppModel.self) var model
    let meta: DocMeta
    var height: CGFloat
    var titleSize: CGFloat = 17
    var body: some View {
        // The same page colors as the open note (Paper follows dark mode when that's on).
        let style = model.displayTokens(DocumentAppearance(styleId: meta.styleId))
        let page = Color(hex: style.pageColor)
        let ink = Color(hex: style.textColor)
        let fontDesign: Font.Design = style.font == "serif" ? .serif : style.font == "mono" ? .monospaced : style.font == "rounded" ? .rounded : .default
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: DS.rCard, style: .continuous).fill(Color(hex: meta.tint))
            RoundedRectangle(cornerRadius: DS.rCard, style: .continuous).fill(page)
                .overlay(alignment: .topLeading) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(meta.title.isEmpty ? "Untitled" : meta.title).font(.system(size: titleSize, weight: .bold, design: fontDesign)).foregroundStyle(ink).lineLimit(2)
                        Text(meta.excerpt).font(.system(size: DS.micro, design: fontDesign)).foregroundStyle(ink.opacity(0.78)).lineSpacing(2)
                    }.padding(14)
                }
                .clipShape(RoundedRectangle(cornerRadius: DS.rCard, style: .continuous))
                .padding(5)
        }
        .frame(height: height)
        .compositingGroup()
        .shadow(color: .black.opacity(0.10), radius: 6, y: 2)
    }
}

struct DocCardMenu: ViewModifier {
    @Environment(AppModel.self) var model
    let meta: DocMeta
    func body(content: Content) -> some View {
        content
            .contentShape(Rectangle())
            .onTapGesture { model.openView(.doc(meta.id)) }
            .contextMenu {
                Button("Open") { model.openView(.doc(meta.id)) }
                Button("Open in New Tab") { model.openView(.doc(meta.id), newTab: true) }
                Button(meta.starred ? "Unstar" : "Star") { model.toggleStar(meta.id) }
                Button("Duplicate") { model.duplicate(meta.id) }
                Menu("Move to") {
                    Button("Unsorted") { model.move(meta.id, to: nil) }
                    ForEach(model.library.spaceFolders) { f in Button(f.name) { model.move(meta.id, to: f.id) } }
                }
                Button("Export as Markdown…") { model.exportDoc(meta.id) }
                Divider()
                Button("Move to Recently Deleted", role: .destructive) { model.requestDelete(meta.id) }
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(meta.title.isEmpty ? "Untitled document" : meta.title)
            .accessibilityHint("Opens the document")
    }
}

struct HoverLift: ViewModifier {
    @State private var hover = false
    func body(content: Content) -> some View {
        content.scaleEffect(hover ? 1.012 : 1).animation(Motion.quick(false), value: hover).onHover { hover = $0 }
    }
}

struct GalleryLayout: View {
    let docs: [DocMeta]
    let width: CGFloat
    var body: some View {
        Group {
            let cols = max(1, Int((width - 36) / 250))
            let w = (width - 36 - CGFloat(cols - 1) * 16) / CGFloat(cols)
            HStack(alignment: .top, spacing: 16) {
                ForEach(0..<cols, id: \.self) { c in
                    VStack(spacing: 16) {
                        ForEach(Array(docs.enumerated()).filter { $0.offset % cols == c }.map(\.element)) { m in
                            DocPreview(meta: m, height: min(380, max(200, w * 0.95 + CGFloat(m.excerpt.count) * 0.35)))
                                .modifier(HoverLift()).modifier(DocCardMenu(meta: m))
                        }
                    }.frame(width: w)
                }
            }.padding(.horizontal, 18).padding(.bottom, 24)
        }
    }
}

func dateBucket(_ ms: Double) -> String {
    let d = Date(timeIntervalSince1970: ms / 1000)
    let cal = Calendar.current
    if cal.isDateInToday(d) { return "Today" }
    if cal.isDateInYesterday(d) { return "Yesterday" }
    if let w = cal.dateInterval(of: .weekOfYear, for: Date()), w.contains(d) { return "This Week" }
    return (cal.isDate(d, equalTo: Date(), toGranularity: .year) ? monthFormatter : yearFormatter).string(from: d)
}

struct GridLayout: View {
    @Environment(AppModel.self) var model
    @Environment(\.tokens) var t
    let docs: [DocMeta]
    var body: some View {
        let key = model.library.settings.sort.key
        let grouped = groupByDate(docs, key: key == .name ? .updatedAt : key)
        LazyVStack(alignment: .leading, spacing: 8) {
            ForEach(grouped, id: \.0) { label, items in
                Text(label).font(.system(size: DS.body, weight: .medium)).foregroundStyle(t.secondary).padding(.leading, 6).padding(.top, 10)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 200, maximum: 260), spacing: 16)], alignment: .leading, spacing: 16) {
                    ForEach(items) { m in
                        DocPreview(meta: m, height: 190, titleSize: 15).modifier(HoverLift()).modifier(DocCardMenu(meta: m))
                    }
                }
            }
        }.padding(.horizontal, 18).padding(.bottom, 24)
    }
}

private let monthFormatter: DateFormatter = { let f = DateFormatter(); f.dateFormat = "LLLL"; return f }()
private let yearFormatter: DateFormatter = { let f = DateFormatter(); f.dateFormat = "yyyy"; return f }()

func groupByDate(_ docs: [DocMeta], key: SortKey) -> [(String, [DocMeta])] {
    var order: [String] = []
    var map: [String: [DocMeta]] = [:]
    for m in docs {
        let v = key == .createdAt ? m.createdAt : key == .viewedAt ? m.viewedAt : m.updatedAt
        let b = dateBucket(v)
        if map[b] == nil { order.append(b) }
        map[b, default: []].append(m)
    }
    return order.map { ($0, map[$0]!) }
}

struct ListLayout: View {
    @Environment(AppModel.self) var model
    @Environment(\.tokens) var t
    let docs: [DocMeta]
    let width: CGFloat

    func header(_ title: String, _ key: SortKey, width: CGFloat?) -> some View {
        let s = model.library.settings.sort
        return Button {
            model.setSettings { st in if st.sort.key == key { st.sort.dir = st.sort.dir == "asc" ? "desc" : "asc" } else { st.sort = SortSpec(key: key, dir: key == .name ? "asc" : "desc") } }
        } label: {
            HStack(spacing: 3) {
                Text(title)
                if s.key == key { Image(systemName: s.dir == "asc" ? "arrow.up" : "arrow.down").font(.system(size: DS.micro, weight: .bold)) }
            }
            .font(.system(size: DS.body, weight: s.key == key ? .semibold : .regular))
            .foregroundStyle(s.key == key ? t.text : t.secondary)
            .frame(width: width, alignment: .leading)
            .frame(maxWidth: width == nil ? .infinity : nil, alignment: .leading)
        }.buttonStyle(.plain)
    }

    var body: some View {
        let key = model.library.settings.sort.key
        Group {
            let compact = width < 720
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 0) {
                    header("Name", .name, width: nil)
                    if !compact { header("Last Viewed", .viewedAt, width: 120) }
                    header("Updated", .updatedAt, width: 120)
                    if !compact { header("Created", .createdAt, width: 110) }
                }.padding(.horizontal, 12).padding(.vertical, 8)
                Divider().opacity(0.5)
                ForEach(groupByDate(docs, key: key == .name ? .updatedAt : key), id: \.0) { label, items in
                    if key != .name { Text(label).font(.system(size: DS.body)).foregroundStyle(t.secondary).padding(.horizontal, 12).padding(.top, 14).padding(.bottom, 4) }
                    ForEach(items) { m in ListRow(meta: m, compact: compact) }
                }
            }.padding(.horizontal, 18).padding(.bottom, 24)
        }
    }
}

struct ListRow: View {
    @Environment(AppModel.self) var model
    @Environment(\.tokens) var t
    let meta: DocMeta
    var compact: Bool
    @State private var hover = false
    var body: some View {
        HStack(spacing: 12) {
            MiniPage(meta: meta, size: 36)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(meta.title.isEmpty ? "Untitled" : meta.title).font(.system(size: DS.body, weight: .medium)).foregroundStyle(t.text).lineLimit(1)
                    if meta.starred { Image(systemName: "star.fill").font(.system(size: DS.micro)).foregroundStyle(.yellow) }
                }
                HStack(spacing: 4) {
                    Image(systemName: "folder").font(.system(size: DS.micro))
                    Text(model.folderName(meta.folderId) + (meta.parentDocId != nil ? " · in \(model.library.docs[meta.parentDocId!]?.title ?? "page")" : "") + (meta.excerpt.isEmpty ? "" : " · " + meta.excerpt))
                        .lineLimit(1)
                }.font(.system(size: DS.footnote)).foregroundStyle(t.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if !compact { Text(relative(meta.viewedAt)).frame(width: 120, alignment: .leading) }
            Text(relative(meta.updatedAt)).frame(width: 120, alignment: .leading)
            if !compact { Text(relative(meta.createdAt)).frame(width: 110, alignment: .leading) }
        }
        .font(.system(size: DS.body)).foregroundStyle(t.secondary)
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: DS.rControl).fill(hover ? t.hover : .clear))
        .overlay(alignment: .bottom) { Rectangle().fill(t.line).frame(height: 0.5).padding(.leading, 60) }
        .onHover { hover = $0 }
        .modifier(DocCardMenu(meta: meta))
    }
}

/// Recently Deleted: restore or delete permanently. Items are purged after 30 days.
struct TrashList: View {
    @Environment(AppModel.self) var model
    @Environment(\.tokens) var t
    let docs: [DocMeta]
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Deleted documents stay here for \(Int(Library.trashRetentionDays)) days, then are removed with their backups.")
                    .font(.system(size: DS.body)).foregroundStyle(t.secondary)
                Spacer()
                Button("Empty Recently Deleted…") { model.requestDeleteForever(docs.map(\.id)) }.disabled(docs.isEmpty)
            }.padding(.horizontal, 18)
            if docs.isEmpty {
                EmptyLibrary(symbol: "trash", title: "Recently Deleted is empty", message: "Deleted documents and pages can be restored from this list.")
            }
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(docs) { m in
                        HStack(spacing: 12) {
                            MiniPage(meta: m, size: 34)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(m.title.isEmpty ? "Untitled" : m.title).font(.system(size: DS.body, weight: .medium)).foregroundStyle(t.text)
                                Text((m.parentDocId != nil ? "Nested page · " : "") + "Deleted " + relative(m.deletedAt ?? 0) + (m.excerpt.isEmpty ? "" : " · " + m.excerpt))
                                    .font(.system(size: DS.footnote)).foregroundStyle(t.tertiary).lineLimit(1)
                            }
                            Spacer()
                            Button("Restore") { model.restore(m.id) }
                            Button("Delete Permanently…", role: .destructive) { model.requestDeleteForever([m.id]) }
                        }
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(RoundedRectangle(cornerRadius: DS.rControl).fill(t.hover.opacity(0.6)))
                    }
                }.padding(.horizontal, 18).padding(.bottom, 24)
            }
        }
    }
}

/// One row per matching document: title, location, match count and a highlighted snippet.
struct SearchResults: View {
    @Environment(AppModel.self) var model
    @Environment(\.tokens) var t
    let hits: [SearchHit]
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(hits.count) documents match “\(model.librarySearch)”").font(.system(size: DS.body)).foregroundStyle(t.secondary).padding(.horizontal, 12).padding(.bottom, 6)
                ForEach(hits) { h in
                    Button { model.openSearchResult(h.meta.id) } label: {
                        HStack(alignment: .top, spacing: 12) {
                            MiniPage(meta: h.meta, size: 36)
                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 6) {
                                    Text(h.meta.title.isEmpty ? "Untitled" : h.meta.title).font(.system(size: DS.body, weight: .semibold)).foregroundStyle(t.text)
                                    if h.count > 0 {
                                        Text("\(h.count)").font(.system(size: DS.caption, weight: .bold)).foregroundStyle(Color(hex: "#3b2f00"))
                                            .padding(.horizontal, 6).padding(.vertical, 1).background(Capsule().fill(Color(hex: "#ffd84d")))
                                            .accessibilityLabel("\(h.count) matches")
                                    }
                                    Text(model.folderName(h.meta.folderId) + (h.meta.parentDocId.flatMap { model.library.docs[$0]?.title }.map { " › \($0)" } ?? ""))
                                        .font(.system(size: DS.footnote)).foregroundStyle(t.tertiary)
                                }
                                if h.blocks.count <= 1 { snippet(h).font(.system(size: DS.body)).foregroundStyle(t.secondary).lineLimit(2) }
                            }
                            Spacer()
                        }
                        .padding(10).contentShape(Rectangle())
                        .background(RoundedRectangle(cornerRadius: DS.rControl).fill(t.hover.opacity(0.5)))
                    }.buttonStyle(.plain)
                    // Matching blocks: each one opens the note at that block.
                    if h.blocks.count > 1 {
                        ForEach(h.blocks.prefix(3)) { b in
                            Button { model.openBlock(h.meta.id, b.id) } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "arrow.turn.down.right").font(.system(size: DS.caption)).foregroundStyle(t.tertiary).accessibilityHidden(true)
                                    snippet(b.snippet, b.match).font(.system(size: DS.footnote)).foregroundStyle(t.secondary).lineLimit(1)
                                    Spacer(minLength: 0)
                                }.padding(.leading, 58).padding(.vertical, 3).contentShape(Rectangle())
                            }.buttonStyle(.plain).accessibilityLabel("Match in \(h.meta.title.isEmpty ? "Untitled" : h.meta.title): \(b.snippet)")
                        }
                        if h.blocks.count > 3 { Text("and more in this note").font(.system(size: DS.caption)).foregroundStyle(t.tertiary).padding(.leading, 58) }
                    }
                }
            }.padding(.horizontal, 18).padding(.bottom, 24)
        }
    }

    func snippet(_ h: SearchHit) -> Text { snippet(h.snippet, h.snippetMatch) }
    func snippet(_ s: String, _ r: Range<String.Index>?) -> Text {
        guard let r else { return Text(s) }
        return Text(String(s[..<r.lowerBound])) + Text(String(s[r])).bold().foregroundColor(t.text) + Text(String(s[r.upperBound...]))
    }
}
