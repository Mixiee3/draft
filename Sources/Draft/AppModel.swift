import AppKit
import SwiftUI
import UniformTypeIdentifiers
import DraftCore
import DraftEditor

enum Panel: String { case format, style, info, share }
enum DocRailTab: String, CaseIterable { case outline, backlinks, tasks, attachments, find }

/// A place in a tab's back/forward history.
struct HistEntry: Equatable { var view: ViewRef; var scrollY: Double? }

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

    @Published var library = Library.empty() { didSet { if library.userStyles != oldValue.userStyles { Styles.user = library.userStyles } } }
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
    @Published var infoTab = "info"
    @Published var coverEditorDoc: String?
    /// Bumped when the link/tag/task index changes (backlinks, tags, tasks, calendar).
    @Published var indexTick = 0
    @Published var searchRegex = false
    var index = VaultIndex()
    var blockDoc: [String: String] = [:]
    var indexTimer: Timer?
    var forward: [String: [HistEntry]] = [:]
    var lastIndexSeconds = 0.0
    var linkRefreshTimer: Timer?
    var dayTimer: Timer?
    var watchedDay = ""
    var clock: () -> Date = Date.init // replaced only by automation checks
    let reminders = ReminderScheduler()
    let online = OnlineServices()

    let vault = Vault(dir: Vault.defaultURL())
    private(set) var editors: [String: DocumentEditorView] = [:]
    private var hosts: [String: EditorHostAdapter] = [:]
    var history: [String: [HistEntry]] = [:]
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
            Styles.user = lib.userStyles
            let expired = lib.expiredTrash()
            if !expired.isEmpty { deleteForever(expired) }
            loadIndex()
            startDayWatch()
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

    func scheduleLibrarySave() {
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
        if saveState != "saving" { saveState = "saving" } // publish only real changes: every publish re-renders the window
        docTimer?.invalidate()
        docTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { _ in Task { @MainActor in self.saveDirtyDocs() } }
    }

    func saveDirtyDocs() {
        docTimer?.invalidate()
        for id in dirtyDocs { saveDocNow(id) }
        dirtyDocs.removeAll()
        refreshSaveState()
    }

    private func saveDocNow(_ id: String) {
        guard var d = docs[id] else { return }
        if let ed = editors[id] { d.content = ed.controller.document(); d.updatedAt = nowMs() }
        docs[id] = d
        do {
            try vault.saveDoc(d)
            try? vault.snapshotIfDue(d) // automatic local backups; never block a save on them
            if var m = library.docs[id] {
                m.applyDerived(from: d)
                m.updatedAt = d.updatedAt
                library.docs[id] = m
                scheduleLibrarySave()
                reindex(d)
            }
        } catch { reportSaveError(error) }
    }

    private func refreshSaveState() {
        if saveState != "error" { saveState = (dirtyDocs.isEmpty && !libDirty) ? "saved" : "saving" }
    }

    func reportSaveError(_ e: Error) {
        saveState = "error"
        toast("Could not save: \(e.localizedDescription). Your text is still open; export it to be safe.")
    }

    /// Called before quitting and by automation. Synchronous: the vault uses plain file IO.
    func flushAll() {
        captureTabStates()
        saveDirtyDocs()
        saveLibraryNow()
        saveIndexNow()
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
        captureTabStates()
        if view.kind == "doc", let id = view.docId {
            guard let meta = library.docs[id] else { return }
            if meta.deletedAt != nil {
                toast("“\(meta.title.isEmpty ? "Untitled" : meta.title)” is in Recently Deleted.", action: "Restore") { self.restore(id) }
                return
            }
            guard ensureDoc(id) != nil else { return }
            library.docs[id]?.viewedAt = nowMs()
        }
        let cur = activeTab
        panel = nil
        if inPlace && cur.view.kind != "all" {
            if cur.view == view { return }
            pushHistory(cur)
            replaceTabView(cur.id, view)
            return
        }
        if let existing = library.tabs.first(where: { $0.view == view }), !newTab {
            library.activeTabId = existing.id
        } else if !newTab && view.kind != "doc" && cur.view.kind != "all" && cur.view.kind != "doc" {
            pushHistory(cur)
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
    var canGoForward: Bool { !(forward[activeTab.id] ?? []).isEmpty }

    func entry(_ t: DraftCore.Tab) -> HistEntry {
        HistEntry(view: t.view, scrollY: t.view.docId.flatMap { editors[$0] }.map { Double($0.scrollView.contentView.bounds.origin.y) })
    }

    func pushHistory(_ t: DraftCore.Tab) {
        history[t.id, default: []].append(entry(t))
        forward[t.id] = []
    }

    /// ⌘[: the previous place in this tab, at the scroll position it had.
    func goBack() {
        let cur = activeTab
        captureTabStates()
        if var stack = history[cur.id], let prev = stack.popLast() {
            history[cur.id] = stack
            forward[cur.id, default: []].append(entry(cur))
            go(to: prev, in: cur.id)
        } else {
            activateTab(library.tabs[0].id)
        }
        panel = nil
    }

    /// ⌘]
    func goForward() {
        let cur = activeTab
        guard var stack = forward[cur.id], let next = stack.popLast() else { return }
        captureTabStates()
        forward[cur.id] = stack
        history[cur.id, default: []].append(entry(cur))
        go(to: next, in: cur.id)
        panel = nil
    }

    private func go(to e: HistEntry, in tabId: String) {
        if e.view.kind == "doc", let id = e.view.docId {
            guard library.docs[id]?.deletedAt == nil, ensureDoc(id) != nil else { toast("That document is no longer available."); return }
        }
        replaceTabView(tabId, e.view)
        if let y = e.scrollY, let id = e.view.docId {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in self?.scroll(id, to: y) }
        }
    }

    func scroll(_ docId: String, to y: Double) {
        guard let e = editors[docId], let doc = e.scrollView.documentView else { return }
        e.layoutSubtreeIfNeeded()
        let maxY = max(0, doc.frame.height - e.scrollView.contentSize.height)
        e.scrollView.contentView.scroll(to: NSPoint(x: 0, y: min(CGFloat(y), maxY)))
        e.scrollView.reflectScrolledClipView(e.scrollView.contentView)
    }

    /// Remember scroll position and selection of every open document tab.
    func captureTabStates() {
        for i in library.tabs.indices {
            guard library.tabs[i].view.kind == "doc", let d = library.tabs[i].view.docId, let e = editors[d] else { continue }
            let y = Double(e.scrollView.contentView.bounds.origin.y.rounded())
            let sel = e.controller.textView.selectedRange()
            if library.tabs[i].scrollY != y || library.tabs[i].selStart != sel.location || library.tabs[i].selLength != sel.length {
                library.tabs[i].scrollY = y
                library.tabs[i].selStart = sel.location
                library.tabs[i].selLength = sel.length
                libDirty = true
            }
        }
    }

    private var restoredTabs = Set<String>()

    /// Put a document tab back where it was, once per launch.
    func restoreTabState(_ docId: String) {
        guard let tab = library.tabs.first(where: { $0.view.kind == "doc" && $0.view.docId == docId }), !restoredTabs.contains(tab.id),
              let e = editors[docId] else { return }
        restoredTabs.insert(tab.id)
        let tv = e.controller.textView
        let len = (tv.string as NSString).length
        if let start = tab.selStart {
            let loc = min(start, len)
            tv.setSelectedRange(NSRange(location: loc, length: min(tab.selLength ?? 0, len - loc)))
        }
        e.window?.makeFirstResponder(tv)
        if let y = tab.scrollY {
            e.layoutSubtreeIfNeeded()
            let maxY = max(0, e.scrollView.documentView!.frame.height - e.scrollView.contentSize.height)
            e.scrollView.contentView.scroll(to: NSPoint(x: 0, y: min(CGFloat(y), maxY)))
            e.scrollView.reflectScrolledClipView(e.scrollView.contentView)
        }
    }

    func activateTab(_ id: String) {
        captureTabStates()
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
        forward[id] = nil
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
        view.topInset = 58
        view.theme = theme(for: doc)
        view.controller.load(doc.content)
        view.title = doc.title
        view.coverImage = coverImage(doc.appearance.cover)
        view.controller.refreshPageTitles { self.library.docs[$0]?.title }
        view.controller.refreshLinks(afterLoad: true)
        view.onTitleChange = { [weak self] t in self?.setTitle(id, t) }
        view.onEditCover = { [weak self] in self?.coverEditorDoc = id }
        view.onRemoveCover = { [weak self] in self?.updateAppearance(id) { $0.cover = nil } }
        editors[id] = view
        return view
    }

    func theme(for doc: DocFile) -> EditorTheme {
        var t = EditorTheme(tokens: Styles.resolve(doc.appearance), completedTasks: library.settings.completedTasks)
        t.tagRules = library.settings.tagRules
        t.tagColors = library.settings.tagColors
        t.dateChips = library.settings.dateStyle != "text"
        return t
    }

    var activeEditor: DocumentEditorView? { activeDocId.flatMap { editors[$0] } }
    var activeController: EditorController? { activeEditor?.controller }

    func editorChanged(_ id: String) {
        markDocDirty(id)
    }

    /// The cover as shown: the stored crop (or the default band) cut from the original image.
    func coverImage(_ cover: Cover?) -> NSImage? {
        guard let cover, let img = image(forAsset: cover.assetId),
              let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let a = Double(cg.width) / Double(max(1, cg.height))
        let c = CoverCrop.effective(cover, imageAspect: a)
        let r = CGRect(x: c.x * Double(cg.width), y: c.y * Double(cg.height), width: c.w * Double(cg.width), height: c.h * Double(cg.height)).integral
        guard let cut = cg.cropping(to: r) else { return img }
        return NSImage(cgImage: cut, size: NSSize(width: cut.width, height: cut.height))
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
        // Keep page cards and link chips in other open documents in sync.
        for (_, e) in editors { e.controller.refreshPageTitles { self.library.docs[$0]?.title } }
        // Link chips elsewhere follow once typing pauses: one undo step per rename, not per letter.
        linkRefreshTimer?.invalidate()
        linkRefreshTimer = Timer.scheduledTimer(withTimeInterval: 0.6, repeats: false) { _ in
            Task { @MainActor in for (eid, e) in self.editors where eid != id { e.controller.refreshLinks() } }
        }
    }

    func updateAppearance(_ id: String, _ f: (inout DocumentAppearance) -> Void) {
        guard var d = docs[id], readOnly == nil else { return }
        let old = d.appearance
        f(&d.appearance)
        guard d.appearance != old else { return }
        setAppearance(id, d.appearance, previous: old)
    }

    private var lastStyleUndo: (doc: String, at: Date)?

    /// Appearance changes are undoable in the document (⌘Z) and never touch its content. A run of
    /// changes within a second (a slider or color drag) is one undo step.
    func setAppearance(_ id: String, _ a: DocumentAppearance, previous: DocumentAppearance?, registering: Bool = true) {
        guard var d = docs[id] else { return }
        let old = previous ?? d.appearance
        d.appearance = a
        d.updatedAt = nowMs()
        docs[id] = d
        library.docs[id]?.styleId = a.styleId
        if let e = editors[id] {
            e.theme = theme(for: d)
            e.coverImage = coverImage(d.appearance.cover)
        }
        if registering, let um = editors[id]?.controller.undo, !(um.isUndoing || um.isRedoing) {
            if lastStyleUndo?.doc != id || Date().timeIntervalSince(lastStyleUndo!.at) > 1 {
                um.registerUndo(withTarget: self) { m in MainActor.assumeIsolated { m.setAppearance(id, old, previous: a) } }
                um.setActionName("Style Change")
            }
            lastStyleUndo = (id, Date())
        } else if let um = editors[id]?.controller.undo {
            um.registerUndo(withTarget: self) { m in MainActor.assumeIsolated { m.setAppearance(id, old, previous: a) } }
            um.setActionName("Style Change")
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

    /// Delete = move to Recently Deleted (with its nested pages). Recoverable for 30 days.
    func requestDelete(_ id: String) {
        saveDirtyDocs()
        let ids = library.trash(id)
        guard !ids.isEmpty else { return }
        for i in ids { editors[i] = nil; hosts[i] = nil }
        panel = nil
        scheduleLibrarySave()
        let t = library.docs[id]?.title ?? ""
        toast("Moved “\(t.isEmpty ? "Untitled" : t)”\(ids.count > 1 ? " and \(ids.count - 1) nested page\(ids.count > 2 ? "s" : "")" : "") to Recently Deleted", action: "Undo") { self.restore(id) }
    }

    func restore(_ id: String) {
        let ids = library.restore(id)
        guard !ids.isEmpty else { return }
        scheduleLibrarySave()
        for (_, e) in editors { e.controller.layout.invalidateDisplay(forCharacterRange: NSRange(location: 0, length: e.controller.storage.length)) }
        toast("Restored “\(library.docs[id]?.title.isEmpty == false ? library.docs[id]!.title : "Untitled")”")
    }

    func requestDeleteForever(_ ids: [String]) {
        guard !ids.isEmpty else { return }
        let all = ids + ids.flatMap { library.descendants(of: $0) }.filter { library.docs[$0]?.deletedAt != nil }
        let unique = Array(Set(all))
        confirm = ConfirmRequest(title: unique.count == 1 ? "Delete permanently?" : "Delete \(unique.count) documents permanently?",
                                 detail: "Their files and automatic backups are removed from this Mac. This cannot be undone.",
                                 confirmLabel: "Delete Permanently", destructive: true, onConfirm: { [weak self] in self?.deleteForever(unique) })
    }

    func deleteForever(_ ids: [String]) {
        for id in ids {
            library.docs[id] = nil
            docs[id] = nil
            editors[id] = nil
            hosts[id] = nil
            dirtyDocs.remove(id)
            index.entries[id] = nil
            do { try vault.purgeDoc(id) } catch { reportSaveError(error) }
        }
        library.tabs.removeAll { $0.view.kind == "doc" && ids.contains($0.view.docId ?? "") }
        if !library.tabs.contains(where: { $0.id == library.activeTabId }) { library.activeTabId = library.tabs[0].id }
        scheduleLibrarySave()
    }

    // MARK: Grouped pages and block links

    func cardDocIds(_ n: Node) -> [String] {
        var out: [String] = []
        walk(n) { if $0.type == "pageCard", let d = $0.attrs?["docId"]?.string { out.append(d) } }
        return out
    }

    func reparent(_ ids: [String], to parent: String) {
        for k in ids where library.docs[k] != nil { library.docs[k]?.parentDocId = parent }
    }

    /// New nested page of `parent` holding `content` exactly as given (block ids kept).
    func createNestedPage(parent: String, title: String, content: Node, nested: Bool = true) -> String? {
        guard let pm = library.docs[parent], readOnly == nil else { return nil }
        let id = newId("d_")
        var doc = DocFile.empty(id: id, title: title, styleId: docs[parent]?.appearance.styleId ?? library.settings.defaultStyleId)
        doc.content = content
        docs[id] = doc
        var meta = DocMeta(id: id, folderId: pm.folderId, parentDocId: nested ? parent : nil)
        meta.applyDerived(from: doc)
        library.docs[id] = meta
        reparent(cardDocIds(content), to: id)
        reindex(doc) // pages that moved along now live under the new page
        do { try vault.saveDoc(doc) } catch { reportSaveError(error) }
        scheduleLibrarySave()
        return id
    }

    /// Pages taken out by undoing a group (or by ungroup) are held here, not in Recently Deleted:
    /// their content lives on in the parent, and redo puts them back.
    private var heldPages: [String: (meta: DocMeta, doc: DocFile)] = [:]

    func setGroupedPage(_ id: String, active: Bool, parent: String) {
        if active {
            var nested = true
            if let held = heldPages.removeValue(forKey: id) {
                library.docs[id] = held.meta
                docs[id] = held.doc
                nested = held.meta.parentDocId != nil // Move to New Document makes top-level documents
                do { try vault.saveDoc(held.doc) } catch { reportSaveError(error) }
                reindex(held.doc)
            } else {
                library.restore(id) // pages trashed by earlier builds
            }
            if nested { library.docs[id]?.parentDocId = parent }
            if let d = docs[id] { reparent(cardDocIds(d.content), to: id) }
        } else {
            saveDirtyDocs()
            guard var d = ensureDoc(id), let meta = library.docs[id] else { return }
            if let e = editors[id] { d.content = e.controller.document() }
            reparent(cardDocIds(d.content), to: parent) // nested pages stay live under the parent
            heldPages[id] = (meta, d)
            library.docs[id] = nil
            docs[id] = nil
            editors[id] = nil
            hosts[id] = nil
            library.tabs.removeAll { $0.view.kind == "doc" && $0.view.docId == id }
            if !library.tabs.contains(where: { $0.id == library.activeTabId }) { library.activeTabId = library.tabs[0].id }
            index.entries[id] = nil
            indexChanged()
            do { try vault.purgeDoc(id) } catch { reportSaveError(error) }
        }
        scheduleLibrarySave()
        editorTick &+= 1
    }

    // MARK: Moving blocks between documents

    func moveTargets(excluding id: String) -> [DocMeta] {
        Array(library.liveDocs.filter { $0.id != id }.sorted { $0.viewedAt > $1.viewedAt }.prefix(15))
    }

    /// Append top-level blocks to another document (open editor or file). Returns false if it can't.
    func appendBlocks(_ content: Node, to target: String) -> Bool {
        guard library.docs[target]?.deletedAt == nil, var d = ensureDoc(target) else { return false }
        if let e = editors[target] {
            e.controller.appendBlocks(content)
        } else {
            var blocks = d.content.content ?? []
            if blocks.count == 1, blocks[0].type == "paragraph", blocks[0].content == nil { blocks = [] } // replace an empty page
            d.content.content = blocks + (content.content ?? [])
            d.updatedAt = nowMs()
            docs[target] = d
            markDocDirty(target)
        }
        reparent(cardDocIds(content), to: target)
        scheduleLibrarySave()
        return true
    }

    func removeBlocks(_ ids: [String], from target: String, returningPagesTo parent: String) {
        guard var d = ensureDoc(target) else { return }
        let moved = editors[target].map { $0.controller.document() } ?? d.content
        let pages = Set(cardDocIds(moved)).subtracting(cardDocIds(moved.removingBlocks(Set(ids))))
        if let e = editors[target] {
            e.controller.removeBlocks(ids: Set(ids))
        } else {
            d.content = d.content.removingBlocks(Set(ids))
            d.updatedAt = nowMs()
            docs[target] = d
            markDocDirty(target)
        }
        reparent(Array(pages), to: parent)
        scheduleLibrarySave()
    }

    func pageDocument(_ id: String) -> (title: String, content: Node)? {
        guard let d = ensureDoc(id), library.docs[id]?.deletedAt == nil else { return nil }
        return (d.title, editors[id]?.controller.document() ?? d.content)
    }

    nonisolated static func blockLink(doc: String, block: String) -> URL? { URL(string: "draft://open?doc=\(doc)&block=\(block)") }

    /// Opens `draft://open?doc=…&block=…` links (from Copy Link to Block, other apps, or links in notes).
    func openLink(_ url: URL) {
        guard url.scheme == "draft", let q = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
              let doc = q.first(where: { $0.name == "doc" })?.value, library.docs[doc] != nil else {
            toast("This Draft link points to a document that isn't in this vault."); return
        }
        openView(.doc(doc))
        if let block = q.first(where: { $0.name == "block" })?.value {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in self?.editors[doc]?.controller.scrollTo(blockId: block) }
        }
    }

    // MARK: Backups

    func snapshots(_ id: String) -> [Snapshot] { vault.snapshots(id) }

    func restoreSnapshot(_ id: String, _ s: Snapshot) {
        saveDirtyDocs()
        do {
            if let cur = docs[id] { try vault.snapshotIfDue(cur, force: true) } // restoring is itself reversible
            var old = try vault.loadSnapshot(s)
            old.id = id
            old.updatedAt = nowMs()
            docs[id] = old
            try vault.saveDoc(old)
            if let e = editors[id] {
                e.controller.load(old.content)
                e.title = old.title
                e.theme = theme(for: old)
                e.coverImage = coverImage(old.appearance.cover)
            }
            if var m = library.docs[id] { m.applyDerived(from: old); m.updatedAt = old.updatedAt; library.docs[id] = m }
            scheduleLibrarySave()
            editorTick &+= 1
            toast("Restored the version from \(relative(s.savedAt)). The previous version was backed up.")
        } catch { toast("Could not restore backup: \(error.localizedDescription)") }
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
        let count = library.liveDocs.filter { $0.folderId == id && $0.parentDocId == nil }.count
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
        let before = library.settings
        f(&library.settings)
        let now = library.settings
        if before.completedTasks != now.completedTasks || before.tagRules != now.tagRules || before.tagColors != now.tagColors || before.dateStyle != now.dateStyle {
            for (id, e) in editors { if let d = docs[id] { e.theme = theme(for: d) } }
        }
        if before.tagRules != now.tagRules { saveDirtyDocs(); refreshIndex() }
        if before.reminders != now.reminders || before.reminderHour != now.reminderHour { syncReminders(requestIfNeeded: now.reminders && !before.reminders) }
        if before.dayStartHour != now.dayStartHour || before.weekStart != now.weekStart { indexTick &+= 1 }
        scheduleLibrarySave()
    }

    func renameSpace(_ n: String) {
        let t = n.trimmingCharacters(in: .whitespaces)
        if !t.isEmpty { library.space.name = t; scheduleLibrarySave() }
    }

    // MARK: Toasts

    func toast(_ message: String, action: String? = nil, run: (() -> Void)? = nil) {
        let t = Toast(message: message, actionLabel: action, action: run)
        withAnimation(.easeOut(duration: 0.15)) { toasts = [t] } // one message at a time: a new one replaces the old
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

    static let maxFileBytes = 512 * 1024 * 1024

    func storeFile(at url: URL) -> (assetId: String, name: String, size: Int)? {
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        guard size <= Self.maxFileBytes else { toast("“\(url.lastPathComponent)” is larger than 512 MB and was not added."); return nil }
        do {
            let data = try Data(contentsOf: url, options: .mappedIfSafe)
            return (try vault.putAsset(data, ext: url.pathExtension), url.lastPathComponent, data.count)
        } catch { toast("Could not add “\(url.lastPathComponent)”: \(error.localizedDescription)"); return nil }
    }

    func pickFile(_ completion: @escaping ((assetId: String, name: String, size: Int)?) -> Void) {
        let p = NSOpenPanel()
        p.allowsMultipleSelection = false
        p.message = "Choose a file. Draft copies it into your vault."
        p.begin { r in completion(r == .OK ? p.url.flatMap { self.storeFile(at: $0) } : nil) }
    }

    /// Opens a stored file under its original name (a read-only copy in the temporary folder).
    func openAttachment(assetId: String, name: String) {
        do {
            let src = try vault.assetURL(assetId)
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent("Draft Files/\((assetId as NSString).deletingPathExtension)", isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let dest = dir.appendingPathComponent(Markdown.safeFileName(name, fallback: assetId))
            if !FileManager.default.fileExists(atPath: dest.path) { try FileManager.default.copyItem(at: src, to: dest) }
            NSWorkspace.shared.open(dest)
        } catch { toast("Could not open “\(name)”: \(error.localizedDescription)") }
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
        let roots = library.liveDocs.filter { $0.parentDocId == nil }.sorted { $0.title < $1.title }.map(\.id)
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
        var list = library.liveDocs.filter { $0.parentDocId == nil && (library.settings.showDailyNotes || $0.dailyDate == nil) }
        switch view.kind {
        case "unsorted": list = list.filter { $0.folderId == nil }
        case "starred": list = library.liveDocs.filter { $0.starred }
        case "folder": list = list.filter { $0.folderId == view.folderId }
        case "shared": list = []
        case "trash": return library.trashedDocs.sorted { ($0.deletedAt ?? 0) > ($1.deletedAt ?? 0) }
        default: break
        }
        if !librarySearch.trimmingCharacters(in: .whitespaces).isEmpty { return searchHits.map(\.meta) }
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

    var searchQuery: Result<Search.Query, Search.QueryError> {
        do { return .success(try Search.parse(librarySearch, regex: searchRegex)) } catch { return .failure(error as? Search.QueryError ?? Search.QueryError(message: "Invalid search")) }
    }

    var searchHits: [SearchHit] {
        guard case .success(let q) = searchQuery else { return [] }
        return Search.hits(q, in: library.liveDocs) { [self] m in
            (editors[m.id]?.controller.document() ?? ensureDoc(m.id)?.content).map(docPlainText)
        }
    }

    /// Open a search result and land on the first match: Find in Page is pre-filled, so every
    /// match is highlighted and the first one is scrolled into view.
    func openSearchResult(_ id: String) {
        let q = librarySearch
        openView(.doc(id))
        railShowsFolders = false
        docRailTab = .find
        findQuery = (try? Search.parse(q))?.include.first ?? q
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let self, let c = self.editors[id]?.controller else { return }
            self.findCount = c.find(self.findQuery)
        }
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
            guard let m = model.library.docs[docId], m.deletedAt == nil else { return nil }
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
    func open(url: URL) {
        if url.scheme == "draft" { MainActor.assumeIsolated { model.openLink(url) } } else { NSWorkspace.shared.open(url) }
    }
    func createGroupedPage(title: String, content: Node) -> String? {
        MainActor.assumeIsolated { model.createNestedPage(parent: docId, title: title, content: content) }
    }
    func setGroupedPage(_ id: String, active: Bool) { MainActor.assumeIsolated { model.setGroupedPage(id, active: active, parent: docId) } }
    func pageDocument(docId: String) -> (title: String, content: Node)? { MainActor.assumeIsolated { model.pageDocument(docId) } }
    func link(toBlock blockId: String) -> URL? { AppModel.blockLink(doc: docId, block: blockId) }
    func pickFile(_ completion: @escaping ((assetId: String, name: String, size: Int)?) -> Void) { MainActor.assumeIsolated { model.pickFile(completion) } }
    func storeFile(at url: URL) -> (assetId: String, name: String, size: Int)? { MainActor.assumeIsolated { model.storeFile(at: url) } }
    func openAttachment(assetId: String, name: String) { MainActor.assumeIsolated { model.openAttachment(assetId: assetId, name: name) } }
    func moveTargets() -> [(id: String, title: String)] {
        MainActor.assumeIsolated { model.moveTargets(excluding: docId).map { ($0.id, $0.title.isEmpty ? "Untitled" : $0.title) } }
    }
    func appendBlocks(_ content: Node, toDocument target: String) -> Bool {
        MainActor.assumeIsolated {
            guard target != docId else { return false }
            let ok = model.appendBlocks(content, to: target)
            if ok {
                let n = content.content?.count ?? 0, t = model.library.docs[target]?.title ?? ""
                model.toast("Moved \(n) block\(n == 1 ? "" : "s") to “\(t.isEmpty ? "Untitled" : t)”", action: "Open") { [model] in model.openView(.doc(target)) }
            }
            return ok
        }
    }
    func removeBlocks(_ ids: [String], fromDocument target: String) {
        MainActor.assumeIsolated { model.removeBlocks(ids, from: target, returningPagesTo: docId) }
    }
    func editorDidChange() { MainActor.assumeIsolated { model.editorChanged(docId) } }
    /// Only panels that mirror the caret's formatting need live updates.
    func editorStateDidChange() { MainActor.assumeIsolated { if model.panel == .format || model.panel == .info { model.editorTick &+= 1 } } }
}
