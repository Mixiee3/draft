import AppKit
import SwiftUI
import UniformTypeIdentifiers
import DraftCore
import DraftEditor

enum Panel: String { case format, style, info, share }
enum DocRailTab: String, CaseIterable { case outline, tasks, attachments, find }

struct Toast: Identifiable, Equatable {
    let id = UUID()
    var message: String
    var actionLabel: String?
    var action: (() -> Void)?
    static func == (a: Toast, b: Toast) -> Bool { a.id == b.id }
}

struct ConfirmRequest: Identifiable {
    let id = UUID()
    var title: String
    var detail: String
    var confirmLabel: String
    var destructive: Bool
    var onConfirm: () -> Void
}

/// App state and every user action. Persistence is debounced and flushed on quit.
@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    @Published var library = Library.empty()
    @Published var docs: [String: DocFile] = [:]
    @Published var ready = false
    @Published var fatal: String?
    @Published var readOnly: String?
    @Published var panel: Panel?
    @Published var docRailTab: DocRailTab = .outline
    @Published var railShowsFolders = false
    @Published var quickOpen = false
    @Published var styleGallery = false
    @Published var toasts: [Toast] = []
    @Published var confirm: ConfirmRequest?
    @Published var saveState = "saved" // saved | saving | error
    @Published var librarySearch = ""
    @Published var librarySearchOpen = false
    @Published var renamingFolder: String?
    @Published var editorTick = 0
    @Published var findQuery = ""
    @Published var findCount = 0
    @Published var findFocusNonce = 0

    let vault = Vault(dir: Vault.defaultURL())
    private(set) var editors: [String: DocumentEditorView] = [:]
    private var hosts: [String: EditorHostAdapter] = [:]
    private var history: [String: [ViewRef]] = [:]
    private var imageCache: [String: NSImage] = [:]
    private var dirtyDocs = Set<String>()
    private var libDirty = false
    private var docTimer: Timer?
    private var libTimer: Timer?

    // MARK: Boot

    func boot() {
        do {
            try vault.prepare()
            var lib: Library
            if let l = try vault.loadLibrary() {
                lib = l
            } else {
                let seed = Seed.firstRun()
                lib = seed.library
                for d in seed.docs { try vault.saveDoc(d) }
                try vault.saveLibrary(lib)
            }
            lib.tabs = lib.tabs.filter { $0.view.kind != "doc" || lib.docs[$0.view.docId ?? ""] != nil }
            if lib.tabs.first?.view.kind != "all" { lib.tabs.insert(Tab(view: .all), at: 0) }
            if !lib.tabs.contains(where: { $0.id == lib.activeTabId }) { lib.activeTabId = lib.tabs[0].id }
            library = lib
            if activeView.kind == "doc", let id = activeView.docId { _ = ensureDoc(id) }
            ready = true
        } catch let e as NewerSchemaError {
            readOnly = e.localizedDescription
            fatal = e.localizedDescription
        } catch {
            fatal = "Draft could not open its vault at \(vault.dir.path): \(error.localizedDescription)"
        }
    }

    // MARK: Persistence

    private func scheduleLibrarySave() {
        libDirty = true
        libTimer?.invalidate()
        libTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: false) { _ in Task { @MainActor in self.saveLibraryNow() } }
    }

    private func saveLibraryNow() {
        libTimer?.invalidate()
        guard libDirty else { return }
        libDirty = false
        do { try vault.saveLibrary(library); refreshSaveState() } catch { reportSaveError(error) }
    }

    func markDocDirty(_ id: String) {
        dirtyDocs.insert(id)
        saveState = "saving"
        docTimer?.invalidate()
        docTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { _ in Task { @MainActor in self.saveDirtyDocs() } }
    }

    private func saveDirtyDocs() {
        docTimer?.invalidate()
        for id in dirtyDocs { saveDocNow(id) }
        dirtyDocs.removeAll()
        refreshSaveState()
    }

    private func saveDocNow(_ id: String) {
        guard var d = docs[id] else { return }
        if let ed = editors[id] { d.content = ed.controller.document() }
        docs[id] = d
        do {
            try vault.saveDoc(d)
            if var m = library.docs[id] {
                m.applyDerived(from: d)
                m.updatedAt = d.updatedAt
                library.docs[id] = m
                scheduleLibrarySave()
            }
        } catch { reportSaveError(error) }
    }

    private func refreshSaveState() {
        if saveState != "error" { saveState = (dirtyDocs.isEmpty && !libDirty) ? "saved" : "saving" }
    }

    private func reportSaveError(_ e: Error) {
        saveState = "error"
        toast("Could not save: \(e.localizedDescription). Your text is still open; export it to be safe.")
    }

    /// Called before quitting and by automation. Synchronous: the vault uses plain file IO.
    func flushAll() {
        saveDirtyDocs()
        saveLibraryNow()
    }

    // MARK: Navigation

    var activeTab: DraftCore.Tab { library.tabs.first { $0.id == library.activeTabId } ?? library.tabs[0] }
    var activeView: ViewRef { activeTab.view }
    var activeDocId: String? { activeView.kind == "doc" ? activeView.docId : nil }

    @discardableResult
    func ensureDoc(_ id: String) -> DocFile? {
        if let d = docs[id] { return d }
        do {
            if let d = try vault.loadDoc(id) { docs[id] = d; return d }
        } catch { toast("Could not open document: \(error.localizedDescription)") }
        return nil
    }

    func openView(_ view: ViewRef, inPlace: Bool = false, newTab: Bool = false) {
        if view.kind == "doc", let id = view.docId {
            guard library.docs[id] != nil, ensureDoc(id) != nil else { return }
            library.docs[id]?.viewedAt = nowMs()
        }
        let cur = activeTab
        panel = nil
        if inPlace && cur.view.kind != "all" {
            if cur.view == view { return }
            history[cur.id, default: []].append(cur.view)
            replaceTabView(cur.id, view)
            return
        }
        if let existing = library.tabs.first(where: { $0.view == view }), !newTab {
            library.activeTabId = existing.id
        } else if !newTab && view.kind != "doc" && cur.view.kind != "all" && cur.view.kind != "doc" {
            history[cur.id, default: []].append(cur.view)
            replaceTabView(cur.id, view)
            return
        } else {
            let tab = Tab(view: view)
            let idx = library.tabs.firstIndex { $0.id == cur.id } ?? 0
            library.tabs.insert(tab, at: idx + 1)
            library.activeTabId = tab.id
        }
        librarySearch = ""
        librarySearchOpen = false
        scheduleLibrarySave()
    }

    private func replaceTabView(_ tabId: String, _ view: ViewRef) {
        if let i = library.tabs.firstIndex(where: { $0.id == tabId }) { library.tabs[i].view = view }
        scheduleLibrarySave()
    }

    var canGoBack: Bool { !(history[activeTab.id] ?? []).isEmpty || activeTab.view.kind != "all" }

    func goBack() {
        let cur = activeTab
        if var stack = history[cur.id], let prev = stack.popLast() {
            history[cur.id] = stack
            if prev.kind == "doc", let id = prev.docId { _ = ensureDoc(id) }
            replaceTabView(cur.id, prev)
        } else {
            activateTab(library.tabs[0].id)
        }
        panel = nil
    }

    func activateTab(_ id: String) {
        guard let t = library.tabs.first(where: { $0.id == id }) else { return }
        if let d = t.view.docId, t.view.kind == "doc" { _ = ensureDoc(d) }
        library.activeTabId = id
        panel = nil
        scheduleLibrarySave()
    }

    func closeTab(_ id: String) {
        guard let idx = library.tabs.firstIndex(where: { $0.id == id }), idx > 0 else { return }
        let closing = library.tabs[idx]
        library.tabs.remove(at: idx)
        history[id] = nil
        if library.activeTabId == id { library.activeTabId = library.tabs[min(idx, library.tabs.count - 1)].id }
        if closing.view.kind == "doc", let d = closing.view.docId, !library.tabs.contains(where: { $0.view.docId == d }) {
            saveDirtyDocs()
            editors[d] = nil
            hosts[d] = nil
        }
        scheduleLibrarySave()
    }

    // MARK: Editors

    func editor(for id: String) -> DocumentEditorView {
        if let e = editors[id] { return e }
        let doc = docs[id] ?? DocFile.empty(id: id)
        let view = DocumentEditorView(frame: NSRect(x: 0, y: 0, width: 900, height: 700))
        let host = EditorHostAdapter(model: self, docId: id)
        hosts[id] = host
        view.controller.host = host
        view.theme = theme(for: doc)
        view.controller.load(doc.content)
        view.title = doc.title
        view.coverImage = doc.appearance.cover.flatMap { image(forAsset: $0.assetId) }
        view.controller.refreshPageTitles { self.library.docs[$0]?.title }
        view.onTitleChange = { [weak self] t in self?.setTitle(id, t) }
        editors[id] = view
        return view
    }

    func theme(for doc: DocFile) -> EditorTheme {
        EditorTheme(tokens: Styles.resolve(doc.appearance), completedTasks: library.settings.completedTasks)
    }

    var activeEditor: DocumentEditorView? { activeDocId.flatMap { editors[$0] } }
    var activeController: EditorController? { activeEditor?.controller }

    func editorChanged(_ id: String) {
        docs[id]?.updatedAt = nowMs()
        markDocDirty(id)
        editorTick &+= 1
    }

    func image(forAsset assetId: String) -> NSImage? {
        if let i = imageCache[assetId] { return i }
        guard let url = try? vault.assetURL(assetId), let img = NSImage(contentsOf: url) else { return nil }
        imageCache[assetId] = img
        return img
    }

    // MARK: Documents

    @discardableResult
    func createDoc(folderId: String?? = nil, parentDocId: String? = nil, open: Bool = true, title: String = "") -> String? {
        guard readOnly == nil else { return nil }
        let id = newId("d_")
        let fid: String? = folderId ?? (activeView.kind == "folder" ? activeView.folderId : nil)
        let doc = DocFile.empty(id: id, title: title, styleId: library.settings.defaultStyleId)
        docs[id] = doc
        var meta = DocMeta(id: id, folderId: fid, parentDocId: parentDocId)
        meta.applyDerived(from: doc)
        library.docs[id] = meta
        do { try vault.saveDoc(doc) } catch { reportSaveError(error) }
        scheduleLibrarySave()
        if open {
            openView(.doc(id))
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { self.editors[id]?.focusTitle() }
        }
        return id
    }

    func setTitle(_ id: String, _ title: String) {
        guard docs[id] != nil else { return }
        docs[id]!.title = title
        docs[id]!.updatedAt = nowMs()
        library.docs[id]?.title = title
        markDocDirty(id)
        // Keep page cards in open parent documents in sync.
        for (_, e) in editors { e.controller.refreshPageTitles { self.library.docs[$0]?.title } }
    }

    func updateAppearance(_ id: String, _ f: (inout DocumentAppearance) -> Void) {
        guard var d = docs[id], readOnly == nil else { return }
        f(&d.appearance)
        d.updatedAt = nowMs()
        docs[id] = d
        if let e = editors[id] {
            e.theme = theme(for: d)
            e.coverImage = d.appearance.cover.flatMap { image(forAsset: $0.assetId) }
        }
        markDocDirty(id)
        editorTick &+= 1
    }

    func descendants(_ id: String) -> [String] {
        var out: [String] = []
        func visit(_ p: String) { for m in library.docs.values where m.parentDocId == p { out.append(m.id); visit(m.id) } }
        visit(id)
        return out
    }

    func requestDelete(_ id: String) {
        guard let m = library.docs[id] else { return }
        let kids = descendants(id)
        confirm = ConfirmRequest(
            title: "Delete “\(m.title.isEmpty ? "Untitled" : m.title)”?",
            detail: (kids.isEmpty ? "" : "This also deletes \(kids.count) nested page\(kids.count > 1 ? "s" : ""). ") + "Deleted documents cannot be recovered in this version (Recently Deleted arrives in v0.2). Export first if unsure.",
            confirmLabel: "Delete", destructive: true, onConfirm: { [weak self] in self?.deleteDocs([id] + kids) })
    }

    func deleteDocs(_ ids: [String]) {
        for id in ids {
            library.docs[id] = nil
            docs[id] = nil
            editors[id] = nil
            hosts[id] = nil
            dirtyDocs.remove(id)
            do { try vault.deleteDoc(id) } catch { reportSaveError(error) }
        }
        library.tabs.removeAll { $0.view.kind == "doc" && ids.contains($0.view.docId ?? "") }
        if !library.tabs.contains(where: { $0.id == library.activeTabId }) { library.activeTabId = library.tabs[0].id }
        panel = nil
        scheduleLibrarySave()
        toast(ids.count > 1 ? "Deleted \(ids.count) documents" : "Document deleted")
    }

    func duplicate(_ id: String) {
        saveDirtyDocs()
        guard let src = ensureDoc(id), let meta = library.docs[id] else { return }
        let nid = newId("d_")
        let now = nowMs()
        var copy = src
        copy.id = nid
        copy.title = (src.title.isEmpty ? "Untitled" : src.title) + " copy"
        copy.content = reId(src.content)
        copy.createdAt = now; copy.updatedAt = now
        docs[nid] = copy
        var m = meta
        m.id = nid; m.createdAt = now; m.updatedAt = now; m.viewedAt = now; m.starred = false
        m.applyDerived(from: copy)
        library.docs[nid] = m
        do { try vault.saveDoc(copy) } catch { reportSaveError(error) }
        openView(.doc(nid))
        toast("Duplicated. Nested pages still open the original pages.")
    }

    func move(_ id: String, to folderId: String?) {
        for d in [id] + descendants(id) { library.docs[d]?.folderId = folderId }
        scheduleLibrarySave()
        toast("Moved to \(folderId.flatMap { f in library.folders.first { $0.id == f }?.name } ?? "Unsorted")")
    }

    func toggleStar(_ id: String) {
        library.docs[id]?.starred.toggle()
        scheduleLibrarySave()
    }

    // MARK: Folders

    @discardableResult
    func createFolder() -> String {
        let f = Folder(name: "New Folder", order: Double(library.folders.count))
        library.folders.append(f)
        renamingFolder = f.id
        scheduleLibrarySave()
        return f.id
    }

    func renameFolder(_ id: String, _ name: String) {
        let n = name.trimmingCharacters(in: .whitespaces)
        if let i = library.folders.firstIndex(where: { $0.id == id }), !n.isEmpty { library.folders[i].name = n }
        renamingFolder = nil
        scheduleLibrarySave()
    }

    func requestDeleteFolder(_ id: String) {
        guard let f = library.folders.first(where: { $0.id == id }) else { return }
        let count = library.docs.values.filter { $0.folderId == id && $0.parentDocId == nil }.count
        let run = { [weak self] in
            guard let self else { return }
            for k in self.library.docs.keys where self.library.docs[k]?.folderId == id { self.library.docs[k]?.folderId = nil }
            self.library.folders.removeAll { $0.id == id }
            self.library.tabs.removeAll { $0.view.kind == "folder" && $0.view.folderId == id }
            if !self.library.tabs.contains(where: { $0.id == self.library.activeTabId }) { self.library.activeTabId = self.library.tabs[0].id }
            self.scheduleLibrarySave()
            self.toast("Folder “\(f.name)” removed")
        }
        if count == 0 { run(); return }
        confirm = ConfirmRequest(title: "Remove folder “\(f.name)”?", detail: "Its \(count) document\(count > 1 ? "s" : "") will move to Unsorted. No documents are deleted.", confirmLabel: "Remove Folder", destructive: false, onConfirm: run)
    }

    func toggleExpanded(_ id: String) {
        if let i = library.expandedFolders.firstIndex(of: id) { library.expandedFolders.remove(at: i) } else { library.expandedFolders.append(id) }
        scheduleLibrarySave()
    }

    // MARK: Settings

    func setSettings(_ f: (inout DraftCore.Settings) -> Void) {
        let before = library.settings.completedTasks
        f(&library.settings)
        if before != library.settings.completedTasks {
            for (id, e) in editors { if let d = docs[id] { e.theme = theme(for: d) } }
        }
        scheduleLibrarySave()
    }

    func renameSpace(_ n: String) {
        let t = n.trimmingCharacters(in: .whitespaces)
        if !t.isEmpty { library.space.name = t; scheduleLibrarySave() }
    }

    // MARK: Toasts

    func toast(_ message: String, action: String? = nil, run: (() -> Void)? = nil) {
        let t = Toast(message: message, actionLabel: action, action: run)
        withAnimation(.easeOut(duration: 0.15)) { toasts.append(t) }
        DispatchQueue.main.asyncAfter(deadline: .now() + (action == nil ? 3.2 : 7)) {
            withAnimation { self.toasts.removeAll { $0.id == t.id } }
        }
    }

    // MARK: Assets

    func storeImage(data: Data, ext: String) -> String? {
        do { return try vault.putAsset(data, ext: ext) } catch { toast("Could not add image: \(error.localizedDescription)"); return nil }
    }

    func pickImage(_ completion: @escaping (String?) -> Void) {
        let p = NSOpenPanel()
        p.allowedContentTypes = [.png, .jpeg, .gif, .heic, .webP, .tiff]
        p.allowsMultipleSelection = false
        p.message = "Choose an image. Draft copies it into your vault."
        p.begin { r in
            guard r == .OK, let url = p.url, let data = try? Data(contentsOf: url) else { return completion(nil) }
            var ext = url.pathExtension.lowercased()
            if ext == "jpeg" { ext = "jpg" }
            completion(self.storeImage(data: data, ext: ext.isEmpty ? "png" : ext))
        }
    }

    func revealVault() { NSWorkspace.shared.activateFileViewerSelecting([vault.dir]) }

    // MARK: Export

    func export(docIds: [String], name: String, groupByFolder: Bool, to parent: URL? = nil) {
        saveDirtyDocs()
        let go: (URL) -> Void = { parent in
            do {
                let b = try ExportBuilder.build(rootIds: docIds, metas: self.library.docs, folders: self.library.folders, groupByFolder: groupByFolder, load: { self.ensureDoc($0) })
                let url = try self.vault.writeExport(parent: parent, name: name, files: b.files, assets: b.assets)
                let note = b.lossy.isEmpty ? "" : " Some styling isn't representable in Markdown; it's kept in draft-export.json."
                self.toast("Exported to \(url.lastPathComponent).\(note)", action: "Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                self.lastExportURL = url
            } catch { self.toast("Export failed: \(error.localizedDescription)") }
        }
        if let parent { go(parent); return }
        let p = NSOpenPanel()
        p.canChooseDirectories = true
        p.canChooseFiles = false
        p.canCreateDirectories = true
        p.prompt = "Export Here"
        p.message = "Draft writes a new folder with Markdown files, an assets folder and a lossless draft-export.json."
        p.begin { r in if r == .OK, let u = p.url { go(u) } }
    }
    var lastExportURL: URL?

    func exportDoc(_ id: String) {
        let t = library.docs[id]?.title ?? ""
        export(docIds: [id], name: Markdown.safeFileName(t), groupByFolder: false)
    }

    func exportAll() {
        let roots = library.docs.values.filter { $0.parentDocId == nil }.sorted { $0.title < $1.title }.map(\.id)
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        export(docIds: roots, name: "Draft export \(f.string(from: Date()))", groupByFolder: true)
    }

    func copyMarkdown(_ id: String) {
        saveDirtyDocs()
        guard let d = ensureDoc(id) else { return }
        let r = Markdown.render(d, assetPath: { "assets/" + $0 }, pageLink: { _, t in Markdown.safeFileName(t) + ".md" })
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(r.markdown, forType: .string)
        toast("Markdown copied to the clipboard")
    }

    // MARK: Library queries

    func docsFor(_ view: ViewRef) -> [DocMeta] {
        var list = library.docs.values.filter { $0.parentDocId == nil }
        switch view.kind {
        case "unsorted": list = list.filter { $0.folderId == nil }
        case "starred": list = library.docs.values.filter { $0.starred }
        case "folder": list = list.filter { $0.folderId == view.folderId }
        case "shared": list = []
        default: break
        }
        let q = librarySearch.trimmingCharacters(in: .whitespaces).lowercased()
        if !q.isEmpty {
            let terms = q.split(separator: " ").map(String.init)
            list = library.docs.values.filter { m in terms.allSatisfy { m.searchText.contains($0) } }
            // Title matches first.
            return list.sorted { a, b in
                let ta = a.title.lowercased().contains(q), tb = b.title.lowercased().contains(q)
                return ta != tb ? ta : a.updatedAt > b.updatedAt
            }
        }
        let s = library.settings.sort
        list.sort { a, b in
            let asc: Bool
            switch s.key {
            case .name: asc = a.title.localizedCaseInsensitiveCompare(b.title) == .orderedAscending
            case .createdAt: asc = a.createdAt < b.createdAt
            case .viewedAt: asc = a.viewedAt < b.viewedAt
            case .updatedAt: asc = a.updatedAt < b.updatedAt
            }
            return s.dir == "asc" ? asc : !asc
        }
        return list
    }

    func folderName(_ id: String?) -> String { id.flatMap { f in library.folders.first { $0.id == f }?.name } ?? "Unsorted" }

    func ancestors(_ id: String) -> [DocMeta] {
        var out: [DocMeta] = []
        var cur = library.docs[id]?.parentDocId
        while let c = cur, let m = library.docs[c], out.count < 20 { out.insert(m, at: 0); cur = m.parentDocId }
        return out
    }
}

/// Bridges one open document's editor to the app.
final class EditorHostAdapter: EditorHost {
    unowned let model: AppModel
    let docId: String
    init(model: AppModel, docId: String) { self.model = model; self.docId = docId }

    func image(forAsset id: String) -> NSImage? { MainActor.assumeIsolated { model.image(forAsset: id) } }
    func pageInfo(docId: String) -> (title: String, excerpt: String, tint: NSColor)? {
        MainActor.assumeIsolated {
            guard let m = model.library.docs[docId] else { return nil }
            return (m.title, m.excerpt, NSColor(hex: m.tint))
        }
    }
    func openPage(docId: String) { MainActor.assumeIsolated { model.openView(.doc(docId), inPlace: true) } }
    func createChildPage() -> (docId: String, title: String)? {
        MainActor.assumeIsolated {
            let parent = model.library.docs[docId]
            guard let id = model.createDoc(folderId: .some(parent?.folderId), parentDocId: docId, open: false) else { return nil }
            return (id, "")
        }
    }
    func pickImage(_ completion: @escaping (String?) -> Void) { MainActor.assumeIsolated { model.pickImage(completion) } }
    func storeImage(data: Data, ext: String) -> String? { MainActor.assumeIsolated { model.storeImage(data: data, ext: ext) } }
    func open(url: URL) { NSWorkspace.shared.open(url) }
    func editorDidChange() { MainActor.assumeIsolated { model.editorChanged(docId) } }
    func editorStateDidChange() { MainActor.assumeIsolated { model.editorTick &+= 1 } }
}
