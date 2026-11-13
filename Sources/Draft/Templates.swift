import SwiftUI
import UniformTypeIdentifiers
import DraftCore
import DraftEditor

extension AppModel {
    // MARK: Templates

    /// A copy of the document saved as a template (editing either never changes the other).
    @discardableResult
    func saveAsTemplate(_ docId: String, category: String) -> String? {
        saveDirtyDocs()
        guard let src = ensureDoc(docId), let meta = library.docs[docId] else { return nil }
        let id = newId("d_")
        var copy = src
        copy.id = id; copy.content = reId(editors[docId]?.controller.document() ?? src.content)
        copy.createdAt = nowMs(); copy.updatedAt = copy.createdAt
        docs[id] = copy
        var m = meta
        m.id = id; m.template = category.trimmingCharacters(in: .whitespaces).isEmpty ? "General" : category
        m.parentDocId = nil; m.folderId = nil; m.dailyDate = nil; m.starred = false; m.spaceId = nil
        m.applyDerived(from: copy)
        library.docs[id] = m
        do { try vault.saveDoc(copy) } catch { reportSaveError(error) }
        scheduleLibrarySave()
        toast("Saved “\(docTitle(docId))” as a template")
        return id
    }

    /// A new document from a template: fresh block ids, the template's style, its title.
    @discardableResult
    func createFromTemplate(_ templateId: String, open: Bool = true) -> String? {
        let content: Node, title: String, appearance: DocumentAppearance
        if let b = BuiltInTemplates.all.first(where: { $0.id == templateId }) {
            content = BuiltInTemplates.content(b); title = b.title; appearance = DocumentAppearance(styleId: settings.defaultStyleId)
        } else if let t = ensureDoc(templateId) {
            content = reId(t.content); title = t.title; appearance = t.appearance
        } else { return nil }
        guard let id = createDoc(open: false, title: title) else { return nil }
        docs[id]?.content = content
        docs[id]?.appearance = appearance
        markDocDirty(id); saveDirtyDocs()
        if open { openView(.doc(id)) }
        return id
    }

    func deleteTemplate(_ id: String) {
        guard library.docs[id]?.template != nil else { return }
        library.docs[id] = nil; docs[id] = nil
        try? vault.purgeDoc(id)
        scheduleLibrarySave()
    }

    // MARK: Import

    func chooseImport() {
        let p = NSOpenPanel()
        p.canChooseDirectories = true; p.canChooseFiles = true; p.allowsMultipleSelection = true
        p.allowedContentTypes = [UTType(filenameExtension: "md")!, UTType(filenameExtension: "markdown")!, .html, .json, UTType(filenameExtension: "opml") ?? .xml, .folder]
        p.prompt = "Import"
        p.message = "Markdown files or folders, HTML, OPML, or a Draft export (draft-export.json). Imported notes are added to this Space."
        p.begin { r in if r == .OK { self.previewImport(p.urls) } }
    }

    /// Reads what an import would add without writing anything, and shows it for review.
    func previewImport(_ urls: [URL]) {
        let (r, failed) = parseImport(urls, storeAssets: false)
        let titles = Set(library.liveDocs.map { $0.title.lowercased() })
        importPreview = ImportPreview(urls: urls, titles: r.metas.filter { $0.parentDocId == nil }.map(\.title), duplicates: Set(r.metas.map(\.title).filter { titles.contains($0.lowercased()) }),
                                      notes: r.docs.count, folders: r.folders.count, warnings: r.warnings, failed: failed)
    }

    /// Import files and folders into the active Space. Returns the imported document ids.
    @discardableResult
    func importFiles(_ urls: [URL], skipDuplicates: Bool = false) -> [String] {
        var (all, failed) = parseImport(urls, storeAssets: true)
        for f in failed { toast("\(f)") }
        if skipDuplicates {
            let titles = Set(library.liveDocs.map { $0.title.lowercased() })
            let drop = Set(all.metas.filter { titles.contains($0.title.lowercased()) }.map(\.id))
            all.docs.removeAll { drop.contains($0.id) }; all.metas.removeAll { drop.contains($0.id) }
        }
        return commitImport(all)
    }

    /// Parses files; `storeAssets` false reads only (for the preview).
    func parseImport(_ urls: [URL], storeAssets: Bool) -> (ImportResult, [String]) {
        var all = ImportResult()
        var failed: [String] = []
        let put: (Data, String) -> String? = { [vault] data, ext in storeAssets ? try? vault.putAsset(data, ext: ext) : "preview.\(ext)" }
        let sid = library.space.id
        for url in urls {
            var isDir: ObjCBool = false
            FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
            do {
                let r: ImportResult
                switch isDir.boolValue ? "folder" : url.pathExtension.lowercased() {
                case "folder":
                    let e = FileManager.default.enumerator(at: url, includingPropertiesForKeys: nil)
                    var files: [(String, String)] = []
                    while let f = e?.nextObject() as? URL {
                        guard ["md", "markdown"].contains(f.pathExtension.lowercased()), let t = try? String(contentsOf: f, encoding: .utf8) else { continue }
                        files.append((String(f.standardizedFileURL.path.dropFirst(url.standardizedFileURL.path.count + 1)), t))
                    }
                    r = Importer.markdown(files: files.sorted { $0.0 < $1.0 }, spaceId: sid) { rel, ext in
                        (try? Data(contentsOf: url.appendingPathComponent(rel))).flatMap { put($0, ext) }
                    }
                case "md", "markdown":
                    let dir = url.deletingLastPathComponent()
                    r = Importer.markdown(files: [(url.lastPathComponent, try String(contentsOf: url, encoding: .utf8))], spaceId: sid) { rel, ext in
                        (try? Data(contentsOf: dir.appendingPathComponent(rel))).flatMap { put($0, ext) }
                    }
                case "opml":
                    r = try Importer.opml(try Data(contentsOf: url), fallbackTitle: url.deletingPathExtension().lastPathComponent, spaceId: sid)
                case "json":
                    r = try Importer.draftJSON(try Data(contentsOf: url), existingDocs: Set(library.docs.keys), existingFolders: Set(library.folders.map(\.id)), existingStyles: Set(library.userStyles.map(\.id)), spaceId: sid)
                    // Assets referenced by the export sit next to it.
                    let assets = url.deletingLastPathComponent().appendingPathComponent("assets")
                    for d in r.docs { for a in attachmentsOf(d.content) where a.kind != "link" { if let data = try? Data(contentsOf: assets.appendingPathComponent(a.ref)) { _ = put(data, (a.ref as NSString).pathExtension) } } }
                case "html", "htm":
                    let data = try Data(contentsOf: url)
                    var x = ImportResult()
                    var doc = DocFile.empty(id: newId("d_"), title: url.deletingPathExtension().lastPathComponent)
                    if let n = HTMLImport.document(data) { doc.content = n }
                    var meta = DocMeta(id: doc.id, title: doc.title); meta.spaceId = sid; meta.applyDerived(from: doc)
                    x.docs = [doc]; x.metas = [meta]
                    r = x
                default:
                    failed.append(String(localized: "Draft can't import “\(url.lastPathComponent)”.")); continue
                }
                all.docs += r.docs; all.metas += r.metas; all.folders += r.folders; all.styles += r.styles; all.warnings += r.warnings
            } catch { failed.append(String(localized: "Import failed for “\(url.lastPathComponent)”: \(error.localizedDescription)")) }
        }
        return (all, failed)
    }

    func commitImport(_ all: ImportResult) -> [String] {
        guard !all.docs.isEmpty else { return [] }
        for f in all.folders where !library.folders.contains(where: { $0.id == f.id }) { library.folders.append(f) }
        for s in all.styles { library.userStyles.append(s) }
        for d in all.docs { docs[d.id] = d; try? vault.saveDoc(d) }
        for m in all.metas { library.docs[m.id] = m }
        for d in all.docs { reindex(d) }
        scheduleLibrarySave()
        let n = all.docs.count
        toast(all.warnings.isEmpty ? "Imported \(n) documents" : "Imported \(n) documents. \(all.warnings[0])", action: "Open") { [weak self] in
            if let first = all.metas.first(where: { $0.parentDocId == nil }) ?? all.metas.first { self?.openView(.doc(first.id)) }
        }
        return all.docs.map(\.id)
    }
}

/// New → From Template: search, categories, built-in and saved templates.
struct TemplatePicker: View {
    @Environment(AppModel.self) var model
    @Environment(\.tokens) var t
    @State private var query = ""
    @State private var category = "All"
    @State private var index = 0
    @FocusState private var focused: Bool

    struct Row: Identifiable { let id: String; let title: String; let category: String; let builtIn: Bool }

    var rows: [Row] {
        let mine = model.library.templates.map { Row(id: $0.id, title: model.docTitle($0.id), category: $0.template ?? "General", builtIn: false) }
        let all = mine.sorted { $0.title < $1.title } + BuiltInTemplates.all.map { Row(id: $0.id, title: $0.title, category: $0.category, builtIn: true) }
        return all.filter { (category == "All" || $0.category == category) && (query.isEmpty || $0.title.localizedCaseInsensitiveContains(query)) }
    }
    var categories: [String] { ["All"] + Array(Set(model.library.templates.compactMap(\.template) + BuiltInTemplates.all.map(\.category))).sorted() }

    func choose(_ r: Row) { model.templatePicker = false; model.createFromTemplate(r.id) }

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.opacity(0.22).ignoresSafeArea().onTapGesture { model.templatePicker = false }
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("New from Template").font(.system(size: DS.headline, weight: .semibold)).accessibilityAddTraits(.isHeader)
                    Spacer()
                    IconButton(symbol: "xmark", label: "Close", size: 26) { model.templatePicker = false }
                }
                TextField("Search templates", text: $query).textFieldStyle(.roundedBorder).focused($focused)
                    .onSubmit { if rows.indices.contains(index) { choose(rows[index]) } }
                    .onKeyPress(.downArrow) { index = min(index + 1, max(0, rows.count - 1)); return .handled }
                    .onKeyPress(.upArrow) { index = max(index - 1, 0); return .handled }
                    .onExitCommand { model.templatePicker = false }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) { ForEach(categories, id: \.self) { c in ChipButton(title: c, font: .system(size: DS.footnote, weight: .medium), isActive: category == c, height: 28) { category = c; index = 0 } } }
                }
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(Array(rows.enumerated()), id: \.element.id) { i, r in
                            HStack(spacing: 10) {
                                Image(systemName: r.builtIn ? "doc.text" : "doc.badge.gearshape").frame(width: 20).foregroundStyle(t.secondary)
                                Text(r.title).font(.system(size: DS.body)).foregroundStyle(t.text)
                                Spacer()
                                Text(r.builtIn ? r.category : "\(r.category) · yours").font(.system(size: DS.footnote)).foregroundStyle(t.tertiary)
                            }
                            .padding(.horizontal, 10).frame(height: 34)
                            .background(RoundedRectangle(cornerRadius: DS.rControl).fill(i == index ? t.accent.opacity(0.16) : .clear))
                            .contentShape(Rectangle()).onTapGesture { choose(r) }
                            .accessibilityElement().accessibilityLabel("\(r.title), \(r.category)").accessibilityAddTraits(.isButton).accessibilityAction { choose(r) }
                        }
                        if rows.isEmpty { Text("No templates match.").foregroundStyle(t.secondary).padding() }
                    }
                }.frame(maxHeight: 340)
                Text("Save any document as a template from its Info panel (Actions → Save as Template).").font(.system(size: DS.caption)).foregroundStyle(t.tertiary)
            }
            .padding(16).frame(width: 520).surface(.overlay).padding(.top, 90)
        }
        .onAppear { focused = true }
        .onChange(of: query) { _, _ in index = 0 }
    }
}

struct ImportPreview: Identifiable {
    let id = UUID()
    let urls: [URL]
    let titles: [String]
    let duplicates: Set<String>
    let notes: Int
    let folders: Int
    let warnings: [String]
    let failed: [String]
}

/// What an import would add, reviewed before anything is written.
struct ImportPreviewView: View {
    @Environment(AppModel.self) var model
    @Environment(\.tokens) var t
    @Environment(\.dismiss) var dismiss
    let preview: ImportPreview
    @State private var skipDuplicates = true
    var body: some View {
        let n = preview.notes - (skipDuplicates ? preview.duplicates.count : 0)
        VStack(alignment: .leading, spacing: DS.s3) {
            Text("Import Preview").font(.system(size: DS.title2, weight: .bold)).foregroundStyle(t.text).accessibilityAddTraits(.isHeader)
            Text("\(preview.notes) notes in \(preview.folders) folders from \(preview.urls.count) items. Nothing is added until you click Import.").font(.system(size: DS.footnote)).foregroundStyle(t.secondary)
            List {
                ForEach(preview.titles.prefix(300), id: \.self) { title in
                    HStack {
                        Image(systemName: "doc.text").foregroundStyle(t.secondary).accessibilityHidden(true)
                        Text(verbatim: title.isEmpty ? String(localized: "Untitled") : title).lineLimit(1)
                        Spacer()
                        if preview.duplicates.contains(title) { Label("Same title exists", systemImage: "doc.on.doc").font(.system(size: DS.caption)).foregroundStyle(.orange) }
                    }
                }
            }.frame(height: 220)
            if !preview.duplicates.isEmpty {
                Toggle("Skip \(preview.duplicates.count) notes whose title already exists in this Space", isOn: $skipDuplicates).toggleStyle(.checkbox)
            }
            ForEach(preview.failed + preview.warnings, id: \.self) { w in Label(w, systemImage: "exclamationmark.triangle").font(.system(size: DS.footnote)).foregroundStyle(.orange) }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.buttonStyle(DraftButtonStyle(compact: true)).keyboardShortcut(.cancelAction)
                Button("Import \(n) Notes") { model.importFiles(preview.urls, skipDuplicates: skipDuplicates); dismiss() }
                    .buttonStyle(DraftButtonStyle(role: .primary, compact: true)).keyboardShortcut(.defaultAction).disabled(n == 0)
            }
        }
        .padding(DS.s5).frame(width: 560).background(t.canvas)
    }
}
