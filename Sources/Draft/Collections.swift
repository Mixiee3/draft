import SwiftUI
import UniformTypeIdentifiers
import DraftCore
import DraftEditor

/// Collections: data lives in the `collection` block; every item is a nested page.
extension AppModel {
    func collectionNode(_ docId: String, _ blockId: String) -> Node? {
        if let c = editors[docId]?.controller { return c.attachmentNode(blockId: blockId) ?? c.document().block(blockId) }
        return ensureDoc(docId)?.content.block(blockId)
    }

    /// Decoded once per edit of the hosting document: views ask for it many times per render.
    func collectionData(_ docId: String, _ blockId: String) -> CollectionData? {
        memoized("collection-\(docId)-\(blockId)", [docRevision[docId] ?? 0, collectionTick, editors[docId] == nil]) {
            collectionNode(docId, blockId).flatMap { CollectionData(node: $0) }
        }
    }

    func pageTitle(_ id: String) -> String { docTitle(id) }

    func writeCollection(_ docId: String, _ blockId: String, _ data: CollectionData) {
        let node = data.node(id: blockId)
        if let e = editors[docId], e.controller.replaceAttachmentQuietly(blockId: blockId, with: node) {
        } else if var d = ensureDoc(docId), let c = d.content.replacingBlock(blockId, with: node) {
            d.content = c; d.updatedAt = nowMs(); docs[docId] = d; markDocDirty(docId)
        }
        saveDirtyDocs()
        collectionTick &+= 1
    }

    /// Change a collection as one undo step on `undo` (the collection screen's).
    func updateCollection(_ docId: String, _ blockId: String, _ action: String, undo: UndoManager?, _ f: (inout CollectionData) -> Void) {
        guard var data = collectionData(docId, blockId) else { return }
        let old = data
        f(&data)
        guard data != old else { return }
        writeCollection(docId, blockId, data)
        registerCollectionUndo(docId, blockId, old, data, action, undo)
    }

    private func registerCollectionUndo(_ docId: String, _ blockId: String, _ old: CollectionData, _ new: CollectionData, _ action: String, _ undo: UndoManager?) {
        undo?.registerUndo(withTarget: self) { m in onMain {
            m.restoreItemPages(old, comparedTo: new)
            m.writeCollection(docId, blockId, old)
            m.registerCollectionUndo(docId, blockId, new, old, action, undo)
        } }
        undo?.setActionName(action)
    }

    /// Item pages follow their items through undo and redo: removed items' pages go to Recently
    /// Deleted, restored items bring theirs back.
    private func restoreItemPages(_ target: CollectionData, comparedTo current: CollectionData) {
        let keep = Set(target.items.map(\.docId)), now = Set(current.items.map(\.docId))
        for id in keep.subtracting(now) where library.docs[id]?.deletedAt != nil { library.restore(id) }
        for id in now.subtracting(keep) where library.docs[id]?.deletedAt == nil { library.trash(id) }
        scheduleLibrarySave()
    }

    @discardableResult
    func addCollectionItem(_ docId: String, _ blockId: String, title: String = "", values: [String: JSONValue] = [:], undo: UndoManager?) -> String? {
        guard let page = createNestedPage(parent: docId, title: title, content: Node("doc", content: [Node("paragraph", attrs: ["id": .string(newId("b_"))])])) else { return nil }
        let item = CollectionItem(docId: page, values: values)
        updateCollection(docId, blockId, "New Item", undo: undo) { $0.items.append(item) }
        return item.id
    }

    func deleteCollectionItems(_ docId: String, _ blockId: String, _ ids: Set<String>, undo: UndoManager?) {
        guard let data = collectionData(docId, blockId) else { return }
        let pages = data.items.filter { ids.contains($0.id) }.map(\.docId)
        updateCollection(docId, blockId, "Delete Item", undo: undo) { $0.items.removeAll { ids.contains($0.id) } }
        for p in pages { library.trash(p) }
        scheduleLibrarySave()
    }

    func exportCSV(_ docId: String, _ blockId: String, to url: URL) throws {
        guard let data = collectionData(docId, blockId) else { return }
        try Data(data.csv(title: pageTitle).utf8).write(to: url, options: .atomic)
    }

    /// Rows of a CSV become new items (columns matched to fields by name); one undo step.
    @discardableResult
    func importCSV(_ docId: String, _ blockId: String, from url: URL, undo: UndoManager?) throws -> Int {
        guard let data = collectionData(docId, blockId) else { return 0 }
        let rows = CollectionData.parseCSV(try String(contentsOf: url, encoding: .utf8))
        guard let header = rows.first else { return 0 }
        var items: [CollectionItem] = []
        for r in rows.dropFirst() where !r.allSatisfy({ $0.isEmpty }) {
            let (t, v) = data.values(fromCSV: header, r)
            if let page = createNestedPage(parent: docId, title: t, content: Node("doc", content: [Node("paragraph", attrs: ["id": .string(newId("b_"))])])) { items.append(CollectionItem(docId: page, values: v)) }
        }
        updateCollection(docId, blockId, "Import CSV", undo: undo) { $0.items += items }
        return items.count
    }

    func openCollection(_ docId: String, _ blockId: String) { openView(ViewRef(kind: "collection", docId: docId, section: blockId)) }
}

struct CollectionScreen: View {
    @Environment(AppModel.self) var model
    @Environment(\.tokens) var t
    @Environment(\.undoManager) var undo
    let docId: String
    let blockId: String
    @State private var filtersOpen = false
    @State private var fieldsOpen = false
    @State private var name = ""

    var body: some View {
        let _ = model.collectionTick
        if let data = model.collectionData(docId, blockId), let view = data.view {
            VStack(spacing: 0) {
                header(data, view)
                Divider().opacity(0.4)
                Group {
                    switch view.type {
                    case "gallery": CollectionGallery(docId: docId, blockId: blockId, data: data, view: view)
                    case "kanban": CollectionBoard(docId: docId, blockId: blockId, data: data, view: view)
                    default: CollectionTable(docId: docId, blockId: blockId, data: data, view: view)
                    }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(t.canvas)
            .onAppear { name = data.name }
        } else {
            EmptyLibrary(message: "This collection is no longer in its document.").background(t.canvas)
        }
    }

    func update(_ action: String, _ f: (inout CollectionData) -> Void) { model.updateCollection(docId, blockId, action, undo: undo, f) }
    func updateView(_ action: String, _ f: @escaping (inout CollectionView) -> Void) {
        update(action) { d in if let i = d.views.firstIndex(where: { $0.id == (d.activeView ?? d.views.first?.id) }) { f(&d.views[i]) } }
    }

    func header(_ data: CollectionData, _ view: CollectionView) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                PillGroup { PillButton(symbol: "chevron.left", label: "Back (⌘[)") { model.goBack() } }
                TextField("Collection name", text: $name).textFieldStyle(.plain).font(.system(size: DS.title2, weight: .bold)).foregroundStyle(t.text)
                    .onSubmit { update("Rename Collection") { $0.name = name } }.accessibilityLabel("Collection name")
                Spacer(minLength: 8)
                Text("\(data.rows(view, title: model.pageTitle).count) of \(data.items.count)").font(.system(size: DS.footnote)).foregroundStyle(t.secondary)
                Button { model.addCollectionItem(docId, blockId, undo: undo) } label: { Label("New Item", systemImage: "plus") }
                    .buttonStyle(.borderedProminent).controlSize(.regular).keyboardShortcut("n", modifiers: [.command, .option, .shift])
                Menu {
                    Button("Export CSV…") { exportCSV(data) }
                    Button("Import CSV…") { importCSV() }
                    Divider()
                    Button("Open Document") { model.openView(.doc(docId)) }
                } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 28).accessibilityLabel("More")
            }
            HStack(spacing: 8) {
                DraftSegmented("View", selection: Binding(get: { view.id }, set: { v in update("Switch View") { $0.activeView = v } }),
                               symbols: data.views.map { v in (v.id, v.name, v.type == "kanban" ? "rectangle.split.3x1" : v.type == "gallery" ? "square.grid.2x2" : "tablecells") })
                Menu {
                    ForEach([("table", "Table"), ("gallery", "Gallery"), ("kanban", "Board")], id: \.0) { k, label in
                        Button(label) { update("Add View") { var v = CollectionView(name: label, type: k); if k == "kanban" { v.groupBy = $0.fields.first { $0.type == "select" }?.id }; $0.views.append(v); $0.activeView = v.id } }
                    }
                    if data.views.count > 1 { Divider(); Button("Delete “\(view.name)”", role: .destructive) { update("Delete View") { d in d.views.removeAll { $0.id == view.id }; d.activeView = d.views.first?.id } } }
                } label: { Image(systemName: "plus.rectangle.on.rectangle") }.menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 28).accessibilityLabel("Add or delete views")
                Spacer()
                sortMenu(data, view)
                Button { filtersOpen.toggle() } label: { Label(view.filters.isEmpty ? "Filter" : "Filter (\(view.filters.count))", systemImage: "line.3.horizontal.decrease.circle") }
                    .popover(isPresented: $filtersOpen) { FilterEditor(data: data, view: view) { f in updateView("Change Filter", f) } }
                if view.type == "kanban" {
                    Menu {
                        ForEach(data.fields.filter { ["select", "multiSelect", "checkbox"].contains($0.type) }) { f in Button(f.name) { updateView("Group Board") { $0.groupBy = f.id } } }
                    } label: { Label("Group: \(view.groupBy.flatMap { data.field($0)?.name } ?? "None")", systemImage: "square.split.2x1") }.fixedSize()
                }
                Button { fieldsOpen.toggle() } label: { Label("Fields", systemImage: "slider.horizontal.3") }
                    .popover(isPresented: $fieldsOpen) { FieldsEditor(data: data, view: view, update: update, updateView: updateView) }
            }
            .buttonStyle(.borderless).font(.system(size: DS.body))
        }
        .padding(.horizontal, 18).padding(.vertical, 12)
    }

    func sortMenu(_ data: CollectionData, _ view: CollectionView) -> some View {
        Menu {
            ForEach([CollectionField(id: CollectionData.titleField, name: "Name", type: "text")] + data.fields) { f in
                let current = view.sort.first { $0.field == f.id }
                Button((current.map { $0.ascending ? "↑ " : "↓ " } ?? "") + f.name) {
                    updateView("Sort") { v in
                        if let i = v.sort.firstIndex(where: { $0.field == f.id }) { if v.sort[i].ascending { v.sort[i].ascending = false } else { v.sort.remove(at: i) } }
                        else { v.sort.append(SortRule(field: f.id)) }
                    }
                }
            }
            if !view.sort.isEmpty { Divider(); Button("Clear Sort") { updateView("Clear Sort") { $0.sort = [] } } }
        } label: { Label(view.sort.isEmpty ? "Sort" : "Sort (\(view.sort.count))", systemImage: "arrow.up.arrow.down") }.fixedSize()
        .help("Click a field to sort ascending, again for descending, a third time to remove. Several fields sort in order.")
    }

    func exportCSV(_ data: CollectionData) {
        let p = NSSavePanel()
        p.allowedContentTypes = [.commaSeparatedText]
        p.nameFieldStringValue = Markdown.safeFileName(data.name) + ".csv"
        p.begin { r in
            guard r == .OK, let u = p.url else { return }
            do { try model.exportCSV(docId, blockId, to: u); model.toast("Exported \(u.lastPathComponent)") } catch { model.toast("Export failed: \(error.localizedDescription)") }
        }
    }

    func importCSV() {
        let p = NSOpenPanel()
        p.allowedContentTypes = [.commaSeparatedText, .plainText]
        p.begin { r in
            guard r == .OK, let u = p.url else { return }
            do { let n = try model.importCSV(docId, blockId, from: u, undo: undo); model.toast("Imported \(n) item\(n == 1 ? "" : "s")") } catch { model.toast("Import failed: \(error.localizedDescription)") }
        }
    }
}

/// One editable value.
struct ValueCell: View {
    @Environment(AppModel.self) var model
    @Environment(\.tokens) var t
    let field: CollectionField
    let item: CollectionItem
    let data: CollectionData
    let set: (JSONValue?) -> Void
    @State private var text = ""

    var body: some View {
        let v = item.values[field.id]
        switch field.type {
        case "checkbox":
            Toggle("", isOn: Binding(get: { v?.bool == true }, set: { set(.bool($0)) })).labelsHidden().toggleStyle(.checkbox).accessibilityLabel(field.name)
        case "select":
            Menu {
                ForEach(field.options ?? [], id: \.self) { o in Button(o) { set(.string(o)) } }
                if v != nil { Divider(); Button("Clear") { set(nil) } }
            } label: { chip(v?.string) }.menuStyle(.borderlessButton).menuIndicator(.hidden).accessibilityLabel("\(field.name): \(v?.string ?? "empty")")
        case "multiSelect", "relation":
            let list = v?.items?.compactMap(\.string) ?? []
            Menu {
                let choices = field.type == "relation" ? model.library.liveDocs.sorted { $0.title < $1.title }.prefix(40).map { ($0.id, model.docTitle($0.id)) } : (field.options ?? []).map { ($0, $0) }
                ForEach(choices, id: \.0) { id, label in
                    Button((list.contains(id) ? "✓ " : "") + label) { let n = list.contains(id) ? list.filter { $0 != id } : list + [id]; set(n.isEmpty ? nil : .array(n.map { .string($0) })) }
                }
            } label: { chip(data.display(item, field.id, title: model.pageTitle).nilIfEmpty) }.menuStyle(.borderlessButton).menuIndicator(.hidden).accessibilityLabel("\(field.name): \(data.display(item, field.id, title: model.pageTitle))")
        case "date":
            if let s = v?.string, let d = Day.date(s) {
                DatePicker("", selection: Binding(get: { d }, set: { set(.string(Day.key($0))) }), displayedComponents: .date).labelsHidden().datePickerStyle(.field).accessibilityLabel(field.name)
            } else {
                Button("Add date") { set(.string(model.todayKey)) }.buttonStyle(.borderless).foregroundStyle(t.tertiary).font(.system(size: DS.footnote))
            }
        default:
            TextField("", text: $text).textFieldStyle(.plain).foregroundStyle(field.type == "url" ? t.accent : t.text)
                .onAppear { text = data.display(item, field.id, title: model.pageTitle) }
                .onChange(of: item.values[field.id]) { _, _ in text = data.display(item, field.id, title: model.pageTitle) }
                .onSubmit {
                    if text.isEmpty { set(nil) }
                    else if field.type == "number" { if let d = Double(text.replacingOccurrences(of: ",", with: ".")) { set(.number(d)) } else { text = data.display(item, field.id, title: model.pageTitle) } }
                    else { set(.string(text)) }
                }
                .accessibilityLabel(field.name)
        }
    }

    func chip(_ s: String?) -> some View {
        Text(s ?? "—").font(.system(size: DS.body)).foregroundStyle(s == nil ? t.tertiary : t.text).lineLimit(1)
            .padding(.horizontal, s == nil ? 0 : 7).padding(.vertical, 2)
            .background(Capsule().fill(s == nil ? .clear : Color(hex: Tags.defaultColor(s ?? "")).opacity(0.16)))
    }
}

struct CollectionTable: View {
    @Environment(AppModel.self) var model
    @Environment(\.tokens) var t
    @Environment(\.undoManager) var undo
    let docId: String, blockId: String
    let data: CollectionData
    let view: CollectionView
    static let titleWidth: CGFloat = 260, width: CGFloat = 170, rowHeight: CGFloat = 34

    var fields: [CollectionField] { (view.visible ?? data.fields.map(\.id)).compactMap { data.field($0) } }

    var body: some View {
        let rows = data.rows(view, title: model.pageTitle)
        ScrollView([.horizontal, .vertical]) {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders, .sectionFooters]) {
                Section {
                    ForEach(rows) { it in row(it) }
                    Button { model.addCollectionItem(docId, blockId, undo: undo) } label: { Label("New", systemImage: "plus").font(.system(size: DS.body)) }
                        .buttonStyle(.borderless).foregroundStyle(t.secondary).padding(.horizontal, 12).frame(height: Self.rowHeight)
                } header: { headerRow } footer: { calcRow(rows) }
            }
            .padding(.horizontal, 12).padding(.bottom, 12)
        }
    }

    var headerRow: some View {
        HStack(spacing: 0) {
            Text("Name").frame(width: Self.titleWidth, alignment: .leading).padding(.leading, 12)
            ForEach(fields) { f in Text(f.name).lineLimit(1).frame(width: Self.width, alignment: .leading).padding(.leading, 10) }
        }
        .font(.system(size: DS.footnote, weight: .semibold)).foregroundStyle(t.secondary)
        .frame(height: 30).background(t.canvas)
    }

    /// Rows are plain text (cheap to scroll through thousands); a click edits a cell in place.
    func row(_ it: CollectionItem) -> some View {
        HStack(spacing: 0) {
            HStack(spacing: 6) {
                EditableCell(label: model.pageTitle(it.docId), weight: .medium, a11y: "Name") {
                    VStack(alignment: .leading, spacing: 0) {
                        TitleField(docId: it.docId)
                        Button("Delete Item", role: .destructive) { model.deleteCollectionItems(docId, blockId, [it.id], undo: undo) }.buttonStyle(.borderless).padding([.horizontal, .bottom], 10)
                    }
                }
                Button { model.openView(.doc(it.docId)) } label: { Image(systemName: "arrow.up.right.square") }.buttonStyle(.borderless).foregroundStyle(t.tertiary)
                    .help("Open as page").accessibilityLabel("Open \(model.pageTitle(it.docId))")
            }.frame(width: Self.titleWidth, alignment: .leading).padding(.leading, 12)
            ForEach(fields) { f in
                let set: (JSONValue?) -> Void = { v in model.updateCollection(docId, blockId, "Edit \(f.name)", undo: undo) { d in if let i = d.items.firstIndex(where: { $0.id == it.id }) { d.items[i].values[f.id] = v } } }
                Group {
                    if f.type == "checkbox" {
                        let on = it.values[f.id]?.bool == true
                        Image(systemName: on ? "checkmark.square.fill" : "square").foregroundStyle(on ? t.accent : t.secondary)
                            .contentShape(Rectangle()).onTapGesture { set(.bool(!on)) }
                            .accessibilityElement().accessibilityLabel(f.name).accessibilityValue(on ? "checked" : "unchecked")
                            .accessibilityAddTraits(.isButton).accessibilityAction { set(.bool(!on)) }
                    } else {
                        EditableCell(label: data.display(it, f.id, title: model.pageTitle), a11y: f.name) { ValueCell(field: f, item: it, data: data, set: set).frame(minWidth: 180).padding(10) }
                    }
                }
                .frame(width: Self.width - 10, alignment: .leading).padding(.leading, 10)
            }
        }
        .font(.system(size: DS.body))
        .frame(height: Self.rowHeight)
        .background(alignment: .bottom) { t.line.frame(height: 0.5) }
    }

    func calcRow(_ rows: [CollectionItem]) -> some View {
        HStack(spacing: 0) {
            Text("\(rows.count) item\(rows.count == 1 ? "" : "s")").frame(width: Self.titleWidth, alignment: .leading).padding(.leading, 12)
            ForEach(fields) { f in
                Menu {
                    ForEach(CollectionData.calculations, id: \.self) { k in Button(k.capitalized) { model.updateCollection(docId, blockId, "Calculate", undo: undo) { d in if let i = d.views.firstIndex(where: { $0.id == view.id }) { d.views[i].calc[f.id] = k } } } }
                    if view.calc[f.id] != nil { Divider(); Button("None") { model.updateCollection(docId, blockId, "Calculate", undo: undo) { d in if let i = d.views.firstIndex(where: { $0.id == view.id }) { d.views[i].calc[f.id] = nil } } } }
                } label: {
                    Text(view.calc[f.id].map { "\($0.capitalized) \(data.calculate($0, field: f.id, rows: rows, title: model.pageTitle))" } ?? "Calculate").lineLimit(1)
                }.menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: Self.width - 10, alignment: .leading).padding(.leading, 10)
                .accessibilityLabel("Calculation for \(f.name)")
            }
        }
        .font(.system(size: DS.footnote)).foregroundStyle(t.secondary)
        .frame(height: 30).background(t.canvas)
    }
}

/// The item page's title, edited in place.
struct TitleField: View {
    @Environment(AppModel.self) var model
    @Environment(\.tokens) var t
    let docId: String
    @State private var text = ""
    var body: some View {
        TextField("Untitled", text: $text).textFieldStyle(.roundedBorder).font(.system(size: DS.body, weight: .medium)).frame(width: 260).padding(10)
            .onAppear { text = model.library.docs[docId]?.title ?? "" }
            .onSubmit { model.setTitle(docId, text); model.collectionTick &+= 1 }
            .accessibilityLabel("Name")
    }
}

struct CollectionGallery: View {
    @Environment(AppModel.self) var model
    @Environment(\.tokens) var t
    @Environment(\.undoManager) var undo
    let docId: String, blockId: String
    let data: CollectionData
    let view: CollectionView
    var body: some View {
        let _ = model.coverTick
        let rows = data.rows(view, title: model.pageTitle)
        let fields = (view.visible ?? data.fields.map(\.id)).compactMap { data.field($0) }.prefix(3)
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 210), spacing: 14)], spacing: 14) {
                ForEach(rows) { it in
                    let title = model.pageTitle(it.docId)
                    GalleryCard(title: title, cover: model.cover(of: it.docId).flatMap { model.coverImage($0) },
                                lines: fields.compactMap { f in let s = data.display(it, f.id, title: model.pageTitle); return s.isEmpty ? nil : "\(f.name): \(s)" },
                                tokens: t) { model.openView(.doc(it.docId)) }
                    .equatable()
                    .contextMenu { Button("Delete Item", role: .destructive) { model.deleteCollectionItems(docId, blockId, [it.id], undo: undo) } }
                }
            }.padding(18)
        }
        .onAppear { model.prefetchCovers(data.items.map(\.docId)) }
    }
}

/// A gallery card built from plain values, so scrolling creates cheap views and unchanged cards
/// skip re-rendering.
struct GalleryCard: View, Equatable {
    let title: String
    let cover: NSImage?
    let lines: [String]
    let tokens: Tokens
    let open: () -> Void

    static func == (a: GalleryCard, b: GalleryCard) -> Bool { a.title == b.title && a.cover === b.cover && a.lines == b.lines && a.tokens.dark == b.tokens.dark }

    var body: some View {
        let t = tokens
        Button(action: open) {
            VStack(alignment: .leading, spacing: 8) {
                ZStack {
                    if let cover { Image(nsImage: cover).resizable().aspectRatio(contentMode: .fill) }
                    else {
                        Color(hex: Tags.defaultColor(title)).opacity(0.25)
                        Text(String(title.prefix(1)).uppercased()).font(.system(size: DS.display, weight: .bold)).foregroundStyle(t.secondary)
                    }
                }
                .frame(height: 110).clipped().clipShape(RoundedRectangle(cornerRadius: DS.rControl, style: .continuous))
                Text(title).font(.system(size: DS.headline, weight: .semibold)).foregroundStyle(t.text).lineLimit(2)
                ForEach(lines, id: \.self) { Text($0).font(.system(size: DS.footnote)).foregroundStyle(t.secondary).lineLimit(1) }
                Spacer(minLength: 0)
            }
            .padding(12).frame(maxWidth: .infinity, minHeight: 210, maxHeight: 210, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: DS.rCard, style: .continuous).fill(t.card))
            .contentShape(RoundedRectangle(cornerRadius: DS.rCard, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open \(title)")
    }
}

struct CollectionBoard: View {
    @Environment(AppModel.self) var model
    @Environment(\.tokens) var t
    @Environment(\.undoManager) var undo
    let docId: String, blockId: String
    let data: CollectionData
    let view: CollectionView
    var body: some View {
        let groups = data.groups(view, title: model.pageTitle)
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: 14) {
                ForEach(Array(groups.enumerated()), id: \.offset) { _, g in column(g.key, g.items) }
            }.padding(18)
        }
    }

    func column(_ key: String?, _ items: [CollectionItem]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(key ?? "No value").font(.system(size: DS.body, weight: .semibold)).foregroundStyle(key == nil ? t.tertiary : t.text)
                Text("\(items.count)").font(.system(size: DS.footnote)).foregroundStyle(t.tertiary)
                Spacer()
                Button { addItem(key) } label: { Image(systemName: "plus") }.buttonStyle(.borderless).foregroundStyle(t.secondary).accessibilityLabel("New item in \(key ?? "No value")")
            }
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(items) { it in
                        Button { model.openView(.doc(it.docId)) } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(model.pageTitle(it.docId)).font(.system(size: DS.body, weight: .medium)).foregroundStyle(t.text).lineLimit(3)
                                ForEach(data.fields.filter { $0.id != view.groupBy }.prefix(2)) { f in
                                    let s = data.display(it, f.id, title: model.pageTitle)
                                    if !s.isEmpty { Text(s).font(.system(size: DS.footnote)).foregroundStyle(t.secondary).lineLimit(1) }
                                }
                            }
                            .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                            .background(RoundedRectangle(cornerRadius: DS.rControl, style: .continuous).fill(t.card))
                        }
                        .buttonStyle(.plain)
                        .draggable(it.id)
                        .accessibilityLabel("\(model.pageTitle(it.docId)), in \(key ?? "No value")")
                        .accessibilityActions {
                            ForEach(data.groups(view, title: model.pageTitle).compactMap(\.key).filter { $0 != key }, id: \.self) { k in Button("Move to \(k)") { move(it.id, k) } }
                        }
                    }
                }
            }
        }
        .padding(10).frame(width: 260).frame(maxHeight: .infinity, alignment: .top)
        .background(RoundedRectangle(cornerRadius: DS.rCard, style: .continuous).fill(t.text.opacity(0.04)))
        .dropDestination(for: String.self) { ids, _ in
            guard let id = ids.first else { return false }
            move(id, key)
            return true
        }
    }

    /// A drag changes one field of one record: one undo step.
    func move(_ id: String, _ key: String?) {
        guard let g = view.groupBy else { return }
        model.updateCollection(docId, blockId, "Move Card", undo: undo) { $0.move(id, to: key, groupBy: g) }
    }

    func addItem(_ key: String?) {
        var values: [String: JSONValue] = [:]
        if let g = view.groupBy, let k = key, let f = data.field(g) { values[g] = f.type == "multiSelect" ? .array([.string(k)]) : f.type == "checkbox" ? .bool(k == "Yes") : .string(k) }
        model.addCollectionItem(docId, blockId, values: values, undo: undo)
    }
}

struct FilterEditor: View {
    let data: CollectionData
    let view: CollectionView
    let update: (@escaping (inout CollectionView) -> Void) -> Void
    static let ops: [(String, String)] = [("is", "is"), ("isNot", "is not"), ("contains", "contains"), ("isEmpty", "is empty"), ("isNotEmpty", "is not empty"), ("gt", ">"), ("lt", "<"), ("before", "before"), ("after", "after"), ("checked", "is checked"), ("unchecked", "is unchecked")]

    var body: some View {
        let fields = [CollectionField(id: CollectionData.titleField, name: "Name", type: "text")] + data.fields
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Show items matching").font(.system(size: DS.body, weight: .semibold))
                DraftSegmented("Match", selection: Binding(get: { view.match }, set: { v in update { $0.match = v } }), options: [("all", "all"), ("any", "any")])
                Text("of these:").font(.system(size: DS.body))
            }
            ForEach(view.filters) { r in
                HStack {
                    Picker("", selection: Binding(get: { r.field }, set: { v in update { if let i = $0.filters.firstIndex(where: { $0.id == r.id }) { $0.filters[i].field = v } } })) {
                        ForEach(fields) { Text($0.name).tag($0.id) }
                    }.labelsHidden().frame(width: 120).accessibilityLabel("Field")
                    Picker("", selection: Binding(get: { r.op }, set: { v in update { if let i = $0.filters.firstIndex(where: { $0.id == r.id }) { $0.filters[i].op = v } } })) {
                        ForEach(Self.ops, id: \.0) { Text($0.1).tag($0.0) }
                    }.labelsHidden().frame(width: 120).accessibilityLabel("Condition")
                    if !["isEmpty", "isNotEmpty", "checked", "unchecked"].contains(r.op) {
                        FilterValueField(value: r.value ?? "") { v in update { if let i = $0.filters.firstIndex(where: { $0.id == r.id }) { $0.filters[i].value = v } } }
                    }
                    Button { update { $0.filters.removeAll { $0.id == r.id } } } label: { Image(systemName: "minus.circle") }.buttonStyle(.borderless).accessibilityLabel("Remove condition")
                }
            }
            Button { update { $0.filters.append(FilterRule(field: data.fields.first?.id ?? CollectionData.titleField, op: "is")) } } label: { Label("Add condition", systemImage: "plus") }.buttonStyle(.borderless)
        }
        .padding(16).frame(minWidth: 460)
    }
}

struct FilterValueField: View {
    @State var value: String
    let commit: (String) -> Void
    var body: some View {
        TextField("Value", text: $value).textFieldStyle(.roundedBorder).frame(width: 140).onSubmit { commit(value) }.accessibilityLabel("Value")
    }
}

struct FieldsEditor: View {
    let data: CollectionData
    let view: CollectionView
    let update: (String, (inout CollectionData) -> Void) -> Void
    let updateView: (String, @escaping (inout CollectionView) -> Void) -> Void
    @State private var optionsText: [String: String] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Fields").font(.system(size: DS.body, weight: .semibold))
            ForEach(data.fields) { f in
                HStack(spacing: 8) {
                    Toggle("", isOn: Binding(get: { (view.visible ?? data.fields.map(\.id)).contains(f.id) }, set: { on in
                        updateView("Show Field") { v in var vis = v.visible ?? data.fields.map(\.id); if on { vis.append(f.id) } else { vis.removeAll { $0 == f.id } }; v.visible = vis }
                    })).labelsHidden().toggleStyle(.checkbox).accessibilityLabel("Show \(f.name)")
                    FieldNameField(name: f.name) { n in update("Rename Field") { if let i = $0.fields.firstIndex(where: { $0.id == f.id }) { $0.fields[i].name = n } } }
                    Text(f.type).font(.system(size: DS.caption)).foregroundStyle(.secondary).frame(width: 74, alignment: .leading)
                    if ["select", "multiSelect"].contains(f.type) {
                        FieldNameField(name: (f.options ?? []).joined(separator: ", "), placeholder: "Options, comma separated") { s in
                            update("Edit Options") { if let i = $0.fields.firstIndex(where: { $0.id == f.id }) { $0.fields[i].options = s.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } } }
                        }
                    }
                    Button { update("Delete Field") { d in d.fields.removeAll { $0.id == f.id }; for i in d.items.indices { d.items[i].values[f.id] = nil } } } label: { Image(systemName: "trash") }
                        .buttonStyle(.borderless).accessibilityLabel("Delete field \(f.name)")
                }
            }
            Menu {
                ForEach(CollectionField.types, id: \.self) { k in
                    Button(k) { update("Add Field") { $0.fields.append(CollectionField(name: k.prefix(1).uppercased() + k.dropFirst(), type: k, options: ["select", "multiSelect"].contains(k) ? [] : nil)) } }
                }
            } label: { Label("Add field", systemImage: "plus") }.fixedSize()
        }
        .padding(16).frame(minWidth: 520)
    }
}

struct FieldNameField: View {
    @State var name: String
    var placeholder = "Name"
    let commit: (String) -> Void
    var body: some View { TextField(placeholder, text: $name).textFieldStyle(.roundedBorder).onSubmit { if !name.isEmpty || placeholder != "Name" { commit(name) } }.accessibilityLabel(placeholder) }
}

/// Text that opens its editor in a popover when clicked (or activated with VoiceOver).
struct EditableCell<Editor: View>: View {
    @Environment(\.tokens) var t
    let label: String
    var weight: Font.Weight = .regular
    let a11y: String
    @ViewBuilder let editor: () -> Editor
    @State private var editing = false
    var body: some View {
        Text(label.isEmpty ? "—" : label).font(.system(size: DS.body, weight: weight)).foregroundStyle(label.isEmpty ? t.tertiary : t.text).lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            .onTapGesture { editing = true }
            .popover(isPresented: $editing, arrowEdge: .bottom) { editor().environment(\.tokens, t) }
            .accessibilityElement().accessibilityLabel(a11y).accessibilityValue(label.isEmpty ? "empty" : label)
            .accessibilityAddTraits(.isButton).accessibilityAction { editing = true }
    }
}
