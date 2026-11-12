import AppKit
import SwiftUI
import Observation
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
@Observable
final class AppModel {
    static let shared = AppModel()

    var library = Library.empty() {
        didSet {
            libraryRevision &+= 1
            if library.userStyles != oldValue.userStyles { Styles.user = library.userStyles }
        }
    }
    /// Bumped on every library change; keys the memo below.
    private(set) var libraryRevision = 0
    @ObservationIgnored private var memo: [String: (key: [AnyHashable], value: Any)] = [:]
    /// Per-document edit counter, so cached reads of a document (collections) know when to refresh.
    var docRevision: [String: Int] = [:]
    @ObservationIgnored private var knownCovers: [String: Cover?] = [:]
    @ObservationIgnored private var coverLoads = Set<String>()
    @ObservationIgnored private var croppedCovers: [Cover: NSImage] = [:]
    var coverTick = 0
    /// A Codex edit proposal waiting for review (read from agent-requests/).
    var agentProposal: AgentProposal?
    @ObservationIgnored var agentProposalTimer: Timer?
    /// Undo for accepted create/rename/move proposals (note edits use the note's own undo).
    @ObservationIgnored let agentUndo: UndoManager = { let u = UndoManager(); u.groupsByEvent = false; return u }()
    var agentUndoName: String?
    var pendingAgentCount = 0
    @ObservationIgnored var deferredProposals = Set<String>()

    /// Derived data that views read many times per render (task lists, folder contents,
    /// collections) is computed once per change instead of once per view.
    func memoized<T>(_ name: String, _ key: [AnyHashable], _ make: () -> T) -> T {
        if let m = memo[name], m.key == key, let v = m.value as? T { return v }
        let v = make()
        memo[name] = (key, v)
        return v
    }
    /// Open tabs and the active one live outside `library` so switching tabs doesn't count as a
    /// library change for every view; they're written back into the library when it's saved.
    var tabs: [DraftCore.Tab] = Library.empty().tabs
    var activeTabId: String? = Library.empty().activeTabId
    var docs: [String: DocFile] = [:]
    /// Notes just created keep the library sidebar until you navigate away, so creating a note
    /// doesn't flip the sidebar to an empty outline.
    var freshDocs = Set<String>()
    var onboarding: Onboarding?
    @ObservationIgnored var tourNote: String?
    var ready = false
    var fatal: String?
    var readOnly: String?
    /// Vault check, repair, versions, backups and startup recovery (Recovery.swift).
    let recovery = RecoveryState()
    var panel: Panel?
    var docRailTab: DocRailTab = .outline
    var railShowsFolders = false
    var quickOpen = false
    var templatePicker = false
    var shortcutsSheet = false
    var focusMode = false { didSet { if focusMode != oldValue { focusModeChanged() } } }
    @ObservationIgnored var focusMonitor: Any?
    @ObservationIgnored var presentWindow: NSWindow?
    var styleGallery = false
    var toasts: [Toast] = []
    var confirm: ConfirmRequest?
    var saveState = "saved" // saved | saving | error
    var librarySearch = ""
    var librarySearchOpen = false
    var renamingFolder: String?
    var editorTick = 0
    var findQuery = ""
    var findCount = 0
    var findFocusNonce = 0
    var infoTab = "info"
    var coverEditorDoc: String?
    /// Bumped when the link/tag/task index changes (backlinks, tags, tasks, calendar).
    var indexTick = 0
    var collectionTick = 0
    var searchRegex = false
    var index = VaultIndex()
    /// Full-text search over blocks (index/search.json), apart from rendering and library.json.
    @ObservationIgnored var searchIndex = SearchIndex()
    @ObservationIgnored var blockDoc: [String: String] = [:]
    @ObservationIgnored var indexTimer: Timer?
    @ObservationIgnored var forward: [String: [HistEntry]] = [:]
    @ObservationIgnored var lastIndexSeconds = 0.0
    @ObservationIgnored var linkRefreshTimer: Timer?
    @ObservationIgnored var dayTimer: Timer?
    @ObservationIgnored var watchedDay = ""
    @ObservationIgnored var clock: () -> Date = Date.init // replaced only by automation checks
    @ObservationIgnored let reminders = ReminderScheduler()
    @ObservationIgnored let online = OnlineServices()
    @ObservationIgnored lazy var assistant = AssistantModel(app: self)
    @ObservationIgnored var assistantWindow: NSPanel?

    @ObservationIgnored let vault = Vault(dir: Vault.defaultURL())
    private(set) var editors: [String: DocumentEditorView] = [:]
    @ObservationIgnored private var hosts: [String: EditorHostAdapter] = [:]
    @ObservationIgnored var history: [String: [HistEntry]] = [:]
    @ObservationIgnored private var imageCache: [String: NSImage] = [:]
    @ObservationIgnored var dirtyDocs = Set<String>()
    @ObservationIgnored private var libDirty = false
    @ObservationIgnored private var docTimer: Timer?
    @ObservationIgnored private var libTimer: Timer?

    // MARK: Boot

    func boot(inMemoryLibrary: Library? = nil) {
        if inMemoryLibrary == nil && !recovery.safeMode && Self.safeModeRequested {
            recovery.safeMode = true
            vault.openReadOnly("Safe Mode: Draft opened your notes read-only. Nothing is written until you quit and open Draft normally.")
            readOnly = vault.readOnlyReason
        }
        if inMemoryLibrary == nil, !recovery.startupHandled, let problems = startupProblems(), !problems.isEmpty {
            recovery.startup = problems
            return
        }
        do {
            if !vault.isReadOnly { try vault.prepare() }
            var lib: Library
            if let l = inMemoryLibrary {
                lib = l
            } else if let l = try vault.loadLibrary() {
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
            tabs = lib.tabs
            activeTabId = lib.activeTabId
            Styles.user = lib.userStyles
            let expired = lib.expiredTrash()
            if !expired.isEmpty && !vault.isReadOnly { deleteForever(expired) }
            loadIndex()
            startDayWatch()
            startAgentProposalWatch()
            if activeView.kind == "doc", let id = activeView.docId { _ = ensureDoc(id) }
            ready = true
            showWelcomeIfNeeded()
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

    func saveLibraryNowIfNeeded() { saveLibraryNow() }

    private func saveLibraryNow() {
        libTimer?.invalidate()
        guard libDirty else { return }
        libDirty = false
        var lib = library
        lib.tabs = tabs
        lib.activeTabId = activeTabId
        let v = vault, snapshot = lib
        v.enqueue({ try v.saveLibrary(snapshot) }, failed: { [weak self] e in onMain { self?.reportSaveError(e) } })
        refreshSaveState()
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
        let v = vault, saved = d
        v.enqueue({
            try v.saveDoc(saved)
            _ = try? v.snapshotIfDue(saved) // automatic local backups; never block a save on them
        }, failed: { [weak self] e in onMain { self?.reportSaveError(e) } })
        if var m = library.docs[id] {
            m.applyDerived(from: d)
            m.updatedAt = d.updatedAt
            if m != library.docs[id] { library.docs[id] = m; scheduleLibrarySave() }
            reindex(d)
        }
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
        vault.drain()
    }

    // MARK: Navigation

    var activeTab: DraftCore.Tab { tabs.first { $0.id == activeTabId } ?? tabs.first ?? Tab(view: .all) }
    var activeView: ViewRef { activeTab.view }
    var activeDocId: String? { activeView.kind == "doc" ? activeView.docId : nil }

    @discardableResult
    func ensureDoc(_ id: String) -> DocFile? {
        if let d = docs[id] { return d }
        do {
            if let d = try vault.loadDoc(id) { docs[id] = d; return d }
        } catch {
            toast("“\(library.docs[id]?.title.nonEmptyTitle ?? id)” can't be opened: \(error.localizedDescription) The file is kept as it is.", action: "Recover…") { [weak self] in
                self?.showSettings("recovery"); self?.recovery.tab = "check"; Task { await self?.checkVault() }
            }
        }
        return nil
    }

    func openView(_ view: ViewRef, inPlace: Bool = false, newTab: Bool = false) {
        captureTabStates()
        if !freshDocs.isEmpty { freshDocs.removeAll() }
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
        if view.kind == "settings", !newTab, let existing = tabs.first(where: { $0.view.kind == "settings" }) {
            replaceTabView(existing.id, view)
            activeTabId = existing.id
        } else if let existing = tabs.first(where: { $0.view == view }), !newTab {
            activeTabId = existing.id
        } else if !newTab && view.kind != "doc" && cur.view.kind != "all" && cur.view.kind != "doc" {
            pushHistory(cur)
            replaceTabView(cur.id, view)
            return
        } else {
            let tab = Tab(view: view)
            let idx = tabs.firstIndex { $0.id == cur.id } ?? 0
            tabs.insert(tab, at: idx + 1)
            activeTabId = tab.id
        }
        librarySearch = ""
        librarySearchOpen = false
        scheduleLibrarySave()
    }

    private func replaceTabView(_ tabId: String, _ view: ViewRef) {
        if let i = tabs.firstIndex(where: { $0.id == tabId }) { tabs[i].view = view }
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
            activateTab(tabs[0].id)
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
        for i in tabs.indices {
            guard tabs[i].view.kind == "doc", let d = tabs[i].view.docId, let e = editors[d] else { continue }
            let y = Double(e.scrollView.contentView.bounds.origin.y.rounded())
            let sel = e.controller.textView.selectedRange()
            if tabs[i].scrollY != y || tabs[i].selStart != sel.location || tabs[i].selLength != sel.length {
                tabs[i].scrollY = y
                tabs[i].selStart = sel.location
                tabs[i].selLength = sel.length
                libDirty = true
            }
        }
    }

    private var restoredTabs = Set<String>()

    /// Put a document tab back where it was, once per launch.
    func restoreTabState(_ docId: String) {
        guard let tab = tabs.first(where: { $0.view.kind == "doc" && $0.view.docId == docId }), !restoredTabs.contains(tab.id),
              let e = editors[docId] else { return }
        restoredTabs.insert(tab.id)
        let tv = e.controller.textView
        let len = (tv.string as NSString).length
        // A note without a title starts in the title (new notes always do); otherwise the body.
        if tab.selStart == nil, (docs[docId]?.title ?? "").isEmpty { e.focusTitle(); return }
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

    func showSettings(_ section: String) {
        if let i = tabs.firstIndex(where: { $0.id == activeTabId }), tabs[i].view.kind == "settings" { tabs[i].view = ViewRef(kind: "settings", section: section); scheduleLibrarySave() }
        else { openView(ViewRef(kind: "settings", section: section)) }
    }

    func activateTab(_ id: String) {
        guard id != activeTabId, let t = tabs.first(where: { $0.id == id }) else { return }
        captureTabStates()
        if !freshDocs.isEmpty { freshDocs.removeAll() }
        if let d = t.view.docId, t.view.kind == "doc" {
            _ = ensureDoc(d)
            if railShowsFolders { revealInFolders(d) }
        }
        activeTabId = id
        if panel != nil { panel = nil }
        scheduleLibrarySave()
    }

    /// Opens the sidebar folders down to a note's folder (only when the sidebar shows folders).
    func revealInFolders(_ docId: String) {
        var chain: [String] = [], cur = library.docs[docId]?.folderId
        while let f = cur, !chain.contains(f) { chain.append(f); cur = library.folders.first { $0.id == f }?.parentId }
        let missing = chain.filter { !library.expandedFolders.contains($0) }
        if !missing.isEmpty { library.expandedFolders += missing }
    }

    func closeTab(_ id: String) {
        guard let idx = tabs.firstIndex(where: { $0.id == id }), idx > 0 else { return }
        let closing = tabs[idx]
        tabs.remove(at: idx)
        history[id] = nil
        forward[id] = nil
        if activeTabId == id { activeTabId = tabs[min(idx, tabs.count - 1)].id }
        if closing.view.kind == "doc", let d = closing.view.docId, !tabs.contains(where: { $0.view.docId == d }) {
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
        view.controller.onShowFullEffects = { [weak self] in self?.setSettings { $0.simplifyEffectsWithIncreaseContrast = false }; self?.retheme() }
        view.controller.onCustomizeEffect = { [weak self] in withAnimation(Motion.panel(self?.library.settings.reduceMotion ?? false)) { self?.panel = .format } }
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
        view.controller.focusDimming = focusMode
        editors[id] = view
        return view
    }

    /// Focus mode hides the chrome and fades all but the current block; Escape leaves it.
    func focusModeChanged() {
        if focusMode { panel = nil }
        for e in editors.values { e.controller.focusDimming = focusMode }
        if focusMode, focusMonitor == nil {
            focusMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
                guard let self, e.keyCode == 53, e.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty,
                      self.activeController?.slash.isOpen != true, self.activeController?.mention.isOpen != true else { return e }
                self.focusMode = false
                return nil
            }
        } else if !focusMode, let m = focusMonitor { NSEvent.removeMonitor(m); focusMonitor = nil }
    }

    func dropEditor(_ id: String) { editors[id] = nil; hosts[id] = nil }

    /// Set by the root view from the effective light/dark appearance.
    var appDark = false { didSet { if appDark != oldValue { retheme() } } }

    func displayTokens(_ a: DocumentAppearance) -> StyleTokens { Styles.forDisplay(a, dark: appDark && library.settings.paperFollowsAppearance) }

    func retheme() { for (id, e) in editors { if let d = docs[id] { e.theme = theme(for: d) } } }

    func theme(for doc: DocFile) -> EditorTheme {
        var t = EditorTheme(tokens: displayTokens(doc.appearance), completedTasks: library.settings.completedTasks)
        t.tagRules = library.settings.tagRules
        t.tagColors = library.settings.tagColors
        t.dateChips = library.settings.dateStyle != "text"
        t.animateEffects = !library.settings.reduceMotion && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        t.solidGlass = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
        t.plainEffects = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast && ProcessInfo.processInfo.environment["DRAFT_CAPTURE_STANDARD_CONTRAST"] == nil
            && library.settings.simplifyEffectsWithIncreaseContrast
        return t
    }

    var activeEditor: DocumentEditorView? { activeDocId.flatMap { editors[$0] } }
    var activeController: EditorController? { activeEditor?.controller }

    func editorChanged(_ id: String) {
        docRevision[id, default: 0] &+= 1
        markDocDirty(id)
    }

    /// A document's cover without loading the document: open documents answer directly; others
    /// are read on a background thread, and views refresh once via `coverTick`.
    func cover(of docId: String) -> Cover? {
        if let d = docs[docId] { return d.appearance.cover }
        return knownCovers[docId] ?? nil
    }

    /// Reads the covers of many documents in one background pass (a gallery calls it once when it
    /// appears), then refreshes views once.
    func prefetchCovers(_ ids: [String]) {
        let missing = ids.filter { docs[$0] == nil && knownCovers[$0] == nil && coverLoads.insert($0).inserted }
        guard !missing.isEmpty else { return }
        let v = vault
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let found = missing.map { ($0, v.peekAppearance($0)?.cover) }
            DispatchQueue.main.async {
                guard let self else { return }
                for (id, c) in found { self.knownCovers[id] = .some(c) }
                if found.contains(where: { $0.1 != nil }) { self.coverTick &+= 1 }
            }
        }
    }

    /// The cover as shown: the stored crop (or the default band) cut from the original image.
    /// Cached: galleries and page cards ask for it on every render.
    func coverImage(_ cover: Cover?) -> NSImage? {
        guard let cover else { return nil }
        if let i = croppedCovers[cover] { return i }
        let i = cropCover(cover)
        croppedCovers[cover] = i
        return i
    }

    private func cropCover(_ cover: Cover) -> NSImage? {
        guard let img = image(forAsset: cover.assetId),
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
        meta.spaceId = library.space.id
        meta.applyDerived(from: doc)
        library.docs[id] = meta
        do { try vault.saveDoc(doc) } catch { reportSaveError(error) }
        scheduleLibrarySave()
        if open {
            openView(.doc(id))
            freshDocs = [id] // the caret goes to the title in restoreTabState
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

    var lastStyleUndo: (doc: String, kind: String, at: Date)?

    /// Which parts of the look a change touches (a drag repeats the same kind).
    static func changeKind(_ a: DocumentAppearance, _ b: DocumentAppearance) -> String {
        var k: [String] = []
        if a.styleId != b.styleId { k.append("style") }
        if a.cover != b.cover { k.append("cover") }
        let x = a.overrides, y = b.overrides
        if x.backdrop != y.backdrop { k.append("backdrop") }
        if x.pageColor != y.pageColor { k.append("page") }
        if x.textColor != y.textColor { k.append("text") }
        if x.accent != y.accent { k.append("accent") }
        if x.font != y.font { k.append("font") }
        if x.separator != y.separator { k.append("separator") }
        return k.joined(separator: ",")
    }

    /// Appearance changes are undoable in the document (⌘Z) and never touch its content. Repeats
    /// of the same change within a second (a slider or color drag) are one undo step.
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
        if let um = editors[id]?.controller.undo, registering || um.isUndoing || um.isRedoing {
            let kind = Self.changeKind(old, a)
            let repeatDrag = !um.isUndoing && !um.isRedoing && lastStyleUndo.map { $0.doc == id && $0.kind == kind && Date().timeIntervalSince($0.at) < 1 } == true
            if !repeatDrag {
                um.registerUndo(withTarget: self) { m in onMain {
                    let now = m.docs[id]?.appearance // redo returns to the latest look, including merged drag steps
                    m.setAppearance(id, old, previous: now)
                } }
                um.setActionName("Style Change")
            }
            lastStyleUndo = um.isUndoing || um.isRedoing ? nil : (id, kind, Date())
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
        tabs.removeAll { $0.view.kind == "doc" && ids.contains($0.view.docId ?? "") }
        if !tabs.contains(where: { $0.id == activeTabId }) { activeTabId = tabs[0].id }
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
        meta.spaceId = pm.spaceId ?? library.space.id
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
            tabs.removeAll { $0.view.kind == "doc" && $0.view.docId == id }
            if !tabs.contains(where: { $0.id == activeTabId }) { activeTabId = tabs[0].id }
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

    /// Listing backups reads the disk; panels ask on every render.
    /// Headings and page cards of the saved copy, rebuilt only when that copy changes (not per redraw).
    func outline(_ id: String) -> [OutlineItem] {
        let d = docs[id]
        return memoized("outline.\(id)", [id, d?.updatedAt ?? 0, d?.content.content?.count ?? 0]) { outlineOf(d?.content ?? Node("doc")) }
    }

    func snapshots(_ id: String) -> [Snapshot] {
        memoized("snapshots.\(id)", [id, saveState, docRevision[id] ?? 0]) { vault.snapshots(id) }
    }

    /// Word and block counts of the open editor, not the last save.
    func liveStats(_ id: String) -> (words: Int, blocks: Int)? {
        guard let c = editors[id]?.controller else { return nil }
        return memoized("stats.\(id)", [id, docRevision[id] ?? 0]) { let s = docStats(c.document()); return (s.words, s.blocks) }
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
        let f = Folder(name: "New Folder", order: Double(library.spaceFolders.count), spaceId: library.space.id)
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
            self.tabs.removeAll { $0.view.kind == "folder" && $0.view.folderId == id }
            if !self.tabs.contains(where: { $0.id == self.activeTabId }) { self.activeTabId = self.tabs[0].id }
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
        if before.completedTasks != now.completedTasks || before.tagRules != now.tagRules || before.tagColors != now.tagColors || before.dateStyle != now.dateStyle || before.paperFollowsAppearance != now.paperFollowsAppearance {
            retheme()
        }
        if before.tagRules != now.tagRules { saveDirtyDocs(); refreshIndex() }
        if before.reminders != now.reminders || before.reminderHour != now.reminderHour { syncReminders(requestIfNeeded: now.reminders && !before.reminders) }
        if before.dayStartHour != now.dayStartHour || before.weekStart != now.weekStart { indexTick &+= 1 }
        scheduleLibrarySave()
    }

    func renameSpace(_ n: String) {
        let t = n.trimmingCharacters(in: .whitespaces)
        if !t.isEmpty {
            library.space.name = t
            if let i = library.spaces.firstIndex(where: { $0.id == library.space.id }) { library.spaces[i].name = t }
            scheduleLibrarySave()
        }
    }

    // MARK: Toasts

    func toast(_ message: String, action: String? = nil, run: (() -> Void)? = nil) {
        let t = Toast(message: message, actionLabel: action, action: run)
        // No withAnimation here: callers (a Space switch) change the whole window in the same turn,
        // and an animation transaction made SwiftUI render all of it synchronously. The toast
        // overlay animates itself.
        toasts = [t] // one message at a time: a new one replaces the old
        DispatchQueue.main.asyncAfter(deadline: .now() + (action == nil ? 3.2 : 7)) { self.toasts.removeAll { $0.id == t.id } }
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
                let b = try ExportBuilder.build(rootIds: docIds, metas: self.library.docs, folders: self.library.folders, groupByFolder: groupByFolder, styles: self.library.userStyles, load: { self.ensureDoc($0) })
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
        memoized("docsFor-\(view.kind)-\(view.folderId ?? "")", [libraryRevision, librarySearch]) { computeDocsFor(view) }
    }

    private func computeDocsFor(_ view: ViewRef) -> [DocMeta] {
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
        guard case .success(var q) = searchQuery else { return [] }
        let _ = indexTick
        // link:<note> matches a note id, or titles that start with the text.
        q.links = q.linkTerms.compactMap { t in library.docs[t] != nil ? t : library.liveDocs.first { $0.title.range(of: t, options: [.caseInsensitive, .diacriticInsensitive, .anchored]) != nil }?.id }
        if !q.linkTerms.isEmpty && q.links.isEmpty { return [] }
        return searchIndex.search(q, in: library.liveDocs)
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

    func image(forAsset id: String) -> NSImage? { onMain { model.image(forAsset: id) } }
    func pageInfo(docId: String) -> (title: String, excerpt: String, tint: NSColor)? {
        onMain {
            guard let m = model.library.docs[docId], m.deletedAt == nil else { return nil }
            return (m.title, m.excerpt, NSColor(hex: m.tint))
        }
    }
    func openPage(docId: String) { onMain { model.openView(.doc(docId), inPlace: true) } }
    func createChildPage() -> (docId: String, title: String)? {
        onMain {
            let parent = model.library.docs[docId]
            guard let id = model.createDoc(folderId: .some(parent?.folderId), parentDocId: docId, open: false) else { return nil }
            return (id, "")
        }
    }
    func pickImage(_ completion: @escaping (String?) -> Void) { onMain { model.pickImage(completion) } }
    func storeImage(data: Data, ext: String) -> String? { onMain { model.storeImage(data: data, ext: ext) } }
    func open(url: URL) {
        if url.scheme == "draft" { onMain { model.openLink(url) } } else { NSWorkspace.shared.open(url) }
    }
    func createGroupedPage(title: String, content: Node) -> String? {
        onMain { model.createNestedPage(parent: docId, title: title, content: content) }
    }
    func setGroupedPage(_ id: String, active: Bool) { onMain { model.setGroupedPage(id, active: active, parent: docId) } }
    func pageDocument(docId: String) -> (title: String, content: Node)? { onMain { model.pageDocument(docId) } }
    func link(toBlock blockId: String) -> URL? { AppModel.blockLink(doc: docId, block: blockId) }
    func pickFile(_ completion: @escaping ((assetId: String, name: String, size: Int)?) -> Void) { onMain { model.pickFile(completion) } }
    func storeFile(at url: URL) -> (assetId: String, name: String, size: Int)? { onMain { model.storeFile(at: url) } }
    func openAttachment(assetId: String, name: String) { onMain { model.openAttachment(assetId: assetId, name: name) } }
    func moveTargets() -> [(id: String, title: String)] {
        onMain { model.moveTargets(excluding: docId).map { ($0.id, $0.title.isEmpty ? "Untitled" : $0.title) } }
    }
    func appendBlocks(_ content: Node, toDocument target: String) -> Bool {
        onMain {
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
        onMain { model.removeBlocks(ids, from: target, returningPagesTo: docId) }
    }
    func editorDidChange() { onMain { model.editorChanged(docId) } }
    /// Only panels that mirror the caret's formatting need live updates.
    func editorStateDidChange() { onMain { if model.panel == .format || model.panel == .info { model.editorTick &+= 1 } } }
}

/// Main-actor work called from AppKit on the main thread. `onMain` asks the
/// Swift runtime for the current executor, and that lookup crashed when AppKit drew or dispatched
/// events from inside a task; the thread check is enough here.
@inline(__always)
func onMain<T>(_ body: @MainActor () throws -> T) rethrows -> T {
    precondition(Thread.isMainThread, "main-thread only")
    return try withoutActuallyEscaping(body) { b in
        try unsafeBitCast(b, to: (() throws -> T).self)()
    }
}
