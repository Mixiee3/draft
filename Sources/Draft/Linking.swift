import AppKit
import SwiftUI
import EventKit
import UserNotifications
import DraftCore
import DraftEditor

/// Links, tags, daily notes, tasks across documents and reminders.
extension AppModel {
    var settings: DraftCore.Settings { library.settings }
    var liveIds: Set<String> { Set(library.liveDocs.map(\.id)) }
    var todayKey: String { Day.today(now: clock(), startHour: settings.dayStartHour) }

    func docTitle(_ id: String) -> String {
        let t = library.docs[id]?.title ?? ""
        return t.isEmpty ? "Untitled" : t
    }

    // MARK: Index

    /// Load `index/index.json` and bring it up to date; a missing or unreadable index is rebuilt.
    func loadIndex() {
        let t0 = Date()
        index = vault.loadIndex() ?? VaultIndex()
        refreshIndex()
        lastIndexSeconds = Date().timeIntervalSince(t0)
    }

    func refreshIndex() {
        let n = index.refresh(docs: library.docs, rules: settings.tagRules) { [vault] id in (try? vault.loadDoc(id)) ?? nil }
        blockDoc = index.blockLocations()
        if n > 0 { saveIndexNow() }
        indexTick &+= 1
    }

    /// Settings → Advanced → Rebuild Index: start from nothing.
    func rebuildIndex() {
        saveDirtyDocs()
        let t0 = Date()
        index = VaultIndex()
        refreshIndex()
        lastIndexSeconds = Date().timeIntervalSince(t0)
        toast("Index rebuilt from \(library.docs.count) documents in \(String(format: "%.1f", lastIndexSeconds)) s")
    }

    /// Re-index one saved document.
    func reindex(_ d: DocFile) {
        guard let m = library.docs[d.id] else { return }
        if let old = index.entries[d.id] { for b in old.blocks where blockDoc[b.id] == d.id { blockDoc[b.id] = nil } }
        var e = VaultIndex.entry(for: d, daily: m.dailyDate, rules: settings.tagRules)
        e.updatedAt = m.updatedAt
        index.entries[d.id] = e
        for b in e.blocks { blockDoc[b.id] = d.id }
        indexChanged()
    }

    func indexChanged() {
        indexTick &+= 1
        indexTimer?.invalidate()
        indexTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: false) { _ in Task { @MainActor in self.saveIndexNow(); if self.settings.reminders { self.syncReminders() } } }
    }

    func saveIndexNow() {
        indexTimer?.invalidate()
        try? vault.saveIndex(index) // derived data: a failed write only means a rebuild next launch
    }

    // MARK: Links

    /// Where a link points now and its live title; nil when the target is gone or deleted.
    func resolveLink(_ docId: String, _ blockId: String?) -> (docId: String, title: String)? {
        if let b = blockId {
            var loc = blockDoc[b]
            if editors[docId]?.controller.paragraph(withId: b) != nil { loc = docId } // not saved yet
            guard let l = loc, let m = library.docs[l], m.deletedAt == nil else { return nil }
            let text = index.entries[l]?.blocks.first { $0.id == b }?.text ?? ""
            return (l, text.isEmpty ? docTitle(l) : text)
        }
        guard let m = library.docs[docId], m.deletedAt == nil else { return nil }
        return (docId, docTitle(m.id))
    }

    /// Follow a link chip: blocks are found wherever they moved; deleted targets explain themselves.
    func openDocLink(_ docId: String, block: String?) {
        var target = docId
        if let b = block, let loc = blockDoc[b] { target = loc }
        guard library.docs[target] != nil else { toast("The linked document was deleted permanently."); return }
        openView(.doc(target), inPlace: true)
        guard let b = block, library.docs[target]?.deletedAt == nil else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let self, let c = self.editors[target]?.controller else { return }
            if c.paragraph(withId: b) != nil { c.scrollTo(blockId: b) } else { self.toast("The linked block was removed from “\(self.docTitle(target))”. Undo there or restore a backup to bring it back.") }
        }
    }

    func openDay(_ day: String) {
        if let id = dailyNote(day, create: false) { openView(.doc(id), inPlace: true) } else { openView(ViewRef(kind: "calendar", section: day)) }
    }

    func mentionItems(from docId: String, trigger: String, query q: String) -> [MentionItem] {
        let ql = q.lowercased().trimmingCharacters(in: .whitespaces)
        let live = liveIds
        func docItems(_ limit: Int) -> [MentionItem] {
            library.liveDocs.filter { $0.id != docId && (ql.isEmpty || $0.title.lowercased().contains(ql)) }
                .sorted { ($0.title.lowercased().hasPrefix(ql) ? 0 : 1, -$0.viewedAt) < ($1.title.lowercased().hasPrefix(ql) ? 0 : 1, -$1.viewedAt) }
                .prefix(limit).map { m in
                    let sub = m.dailyDate != nil ? "Daily note" : m.parentDocId.map { "Page in " + docTitle($0) } ?? folderName(m.folderId)
                    return MentionItem(kind: .doc, title: docTitle(m.id), subtitle: sub, symbol: m.dailyDate != nil ? "calendar" : m.parentDocId == nil ? "doc.text" : "doc.on.doc", docId: m.id)
                }
        }
        switch trigger {
        case "#":
            let tags = index.tagCounts(live: live).filter { ql.isEmpty || $0.tag.lowercased().hasPrefix(ql) }
            var out = tags.prefix(8).map { MentionItem(kind: .tag, title: "#" + $0.tag, subtitle: "Used \($0.count) time\($0.count == 1 ? "" : "s")", symbol: "number", value: $0.tag) }
            if !q.isEmpty, !tags.contains(where: { $0.tag.lowercased() == ql }), Tags.find(in: "#" + q, rules: settings.tagRules).first?.name == q {
                out.append(MentionItem(kind: .tag, title: "#" + q, subtitle: "New tag", symbol: "plus", value: q))
            }
            return out
        case "@":
            let t = todayKey
            var out = DateParse.suggestions(q, today: t, weekStart: settings.weekStart).map { MentionItem(kind: .date, title: Day.label($0, today: t), subtitle: Day.title($0), symbol: "calendar", value: $0) }
            if !ql.isEmpty { out += docItems(5) }
            return out
        default:
            var out = docItems(8)
            if ql.count >= 2 {
                out += index.blockHits(q, live: live, limit: 6).map {
                    MentionItem(kind: .block, title: String($0.block.text.prefix(90)), subtitle: "Block in " + docTitle($0.doc), symbol: $0.block.heading == true ? "number" : "text.alignleft", docId: $0.doc, blockId: $0.block.id)
                }
            }
            if !ql.isEmpty { out.append(MentionItem(kind: .create, title: "New document “\(q.trimmingCharacters(in: .whitespaces))”", symbol: "plus", value: q.trimmingCharacters(in: .whitespaces))) }
            return out
        }
    }

    // MARK: Daily notes

    /// The note for a day; one per date (opening a day twice never creates two notes).
    func dailyNote(_ day: String, create: Bool) -> String? {
        if let m = library.liveDocs.first(where: { $0.dailyDate == day }) { return m.id }
        guard create, readOnly == nil, let id = createDoc(folderId: .some(nil), open: false, title: Day.title(day)) else { return nil }
        library.docs[id]?.dailyDate = day
        if let t = settings.dailyTemplateId, t != id, library.docs[t]?.deletedAt == nil, let src = ensureDoc(t) {
            docs[id]?.content = reId(editors[t]?.controller.document() ?? src.content)
            docs[id]?.appearance = src.appearance
        }
        markDocDirty(id)
        saveDirtyDocs()
        return id
    }

    func openDaily(_ day: String? = nil, inPlace: Bool = false) {
        guard let id = dailyNote(day ?? todayKey, create: true) else { return }
        openView(.doc(id), inPlace: inPlace && activeView.kind == "doc")
    }

    // MARK: Tasks

    /// Check or uncheck a task in its source document. One undo step on `undo` reverts it.
    func setTask(_ docId: String, _ blockId: String, checked: Bool, undo: UndoManager?) {
        var ok = false
        if let e = editors[docId] { ok = e.controller.setTaskChecked(blockId: blockId, checked: checked) }
        else if var d = ensureDoc(docId), let c = d.content.settingTask(blockId, checked: checked) {
            d.content = c; d.updatedAt = nowMs(); docs[docId] = d; markDocDirty(docId); ok = true
        }
        guard ok else { toast("That task is no longer in “\(docTitle(docId))”."); return }
        saveDirtyDocs()
        undo?.registerUndo(withTarget: self) { m in onMain { m.setTask(docId, blockId, checked: !checked, undo: undo) } }
        undo?.setActionName(checked ? "Complete Task" : "Reopen Task")
    }

    /// Set or clear a task's due date (and time) in its source document; one undo on `undo` reverts it.
    func setTaskDue(_ docId: String, _ blockId: String, due: String?, undo: UndoManager?) {
        let old = index.entries[docId]?.tasks.first { $0.block == blockId }?.due
        var ok = false
        if let e = editors[docId] { ok = e.controller.setTaskDue(blockId: blockId, due: due) }
        else if var d = ensureDoc(docId), let c = d.content.settingTaskDue(blockId, due: due, label: Day.chipLabel(due ?? "", today: todayKey)) {
            d.content = c; d.updatedAt = nowMs(); docs[docId] = d; markDocDirty(docId); ok = true
        }
        guard ok else { toast("That task is no longer in “\(docTitle(docId))”."); return }
        saveDirtyDocs()
        undo?.registerUndo(withTarget: self) { m in onMain { m.setTaskDue(docId, blockId, due: old, undo: undo) } }
        undo?.setActionName(due == nil ? "Clear Due Date" : "Set Due Date")
    }

    /// Today, Overdue and date labels follow the clock even while the app sits idle: checked every
    /// 20 s, so a new day (after the start-of-day hour) shows within a minute.
    func startDayWatch() {
        watchedDay = todayKey
        dayTimer?.invalidate()
        dayTimer = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { _ in Task { @MainActor in self.checkDayChange() } }
        dayTimer?.tolerance = 5
    }

    @discardableResult
    func checkDayChange() -> Bool {
        guard todayKey != watchedDay else { return false }
        watchedDay = todayKey
        indexTick &+= 1
        if settings.reminders { syncReminders() }
        return true
    }

    /// Add a task to a day: it goes into that day's daily note, so it is due that day.
    func addTask(_ text: String, on day: String) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, let id = dailyNote(day, create: true) else { return }
        let task = Node("taskList", attrs: ["id": .string(newId("b_"))], content: [
            Node("taskItem", attrs: ["id": .string(newId("b_")), "checked": false], content: [Node("paragraph", attrs: ["id": .string(newId("b_"))], content: [.text(t)])]),
        ])
        guard appendBlocks(Node("doc", content: [task]), to: id) else { return }
        saveDirtyDocs()
    }

    func tasks(_ bucket: TaskBucket) -> [(doc: String, task: IndexedTask)] {
        let today = todayKey
        return index.tasks(live: liveIds).filter { $0.task.bucket(today: today) == bucket }
            .sorted { ($0.task.due ?? "~", docTitle($0.doc), $0.task.text) < ($1.task.due ?? "~", docTitle($1.doc), $1.task.text) }
    }

    func tasks(on day: String) -> [(doc: String, task: IndexedTask)] {
        index.tasks(live: liveIds).filter { $0.task.dueDay == day }.sorted { $0.task.text < $1.task.text }
    }

    func openBlock(_ docId: String, _ blockId: String) {
        openView(.doc(docId))
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in self?.editors[docId]?.controller.scrollTo(blockId: blockId) }
    }

    // MARK: Tags

    func settingBinding<V>(_ k: WritableKeyPath<DraftCore.Settings, V>) -> Binding<V> {
        Binding(get: { self.library.settings[keyPath: k] }, set: { v in self.setSettings { $0[keyPath: k] = v } })
    }

    func tagColor(_ tag: String) -> String { settings.tagColors[tag.lowercased()] ?? Tags.defaultColor(tag) }
    func setTagColor(_ tag: String, _ hex: String?) { setSettings { $0.tagColors[tag.lowercased()] = hex } }

    // MARK: Reminders

    func syncReminders(requestIfNeeded: Bool = false) {
        let plan = Reminders.plan(index.tasks(live: liveIds).map(\.task), hour: settings.reminderHour)
        reminders.sync(plan, enabled: settings.reminders, request: requestIfNeeded) { [weak self] message in
            guard let self else { return }
            self.library.settings.reminders = false
            self.scheduleLibrarySave()
            self.toast(message)
        }
    }
}

/// Local notifications for due tasks (opt-in). Nothing leaves the Mac.
@MainActor
final class ReminderScheduler {
    private(set) var planned: [ReminderPlan] = []
    /// Notifications need the bundled app (an identity the system can attach them to).
    var available: Bool { Bundle.main.bundleIdentifier != nil && Bundle.main.bundleURL.pathExtension == "app" }

    func sync(_ plan: [ReminderPlan], enabled: Bool, request: Bool, failed: @escaping (String) -> Void) {
        planned = enabled ? plan : []
        guard available else {
            if enabled && request { failed("Reminders need the Draft app bundle (scripts/build-app.sh); they can't run from swift run.") }
            return
        }
        let c = UNUserNotificationCenter.current()
        let wanted = planned
        let apply = {
            c.getPendingNotificationRequests { reqs in
                c.removePendingNotificationRequests(withIdentifiers: reqs.map(\.identifier).filter { $0.hasPrefix("task-") })
                for p in wanted {
                    let content = UNMutableNotificationContent()
                    content.title = "Task due"
                    content.body = p.title
                    content.sound = .default
                    let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: p.fire)
                    c.add(UNNotificationRequest(identifier: p.id, content: content, trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)))
                }
            }
        }
        guard enabled, request else { apply(); return }
        c.requestAuthorization(options: [.alert, .sound]) { ok, _ in
            if ok { apply() } else { DispatchQueue.main.async { failed("Notifications for Draft are turned off in System Settings → Notifications, so reminders stay off.") } }
        }
    }

    /// Pending reminder ids (for checks and Settings).
    func pending(_ done: @escaping ([String]) -> Void) {
        guard available else { done([]); return }
        UNUserNotificationCenter.current().getPendingNotificationRequests { r in
            let ids = r.map(\.identifier).filter { $0.hasPrefix("task-") }
            DispatchQueue.main.async { done(ids) }
        }
    }
}

/// Calendar events next to daily notes, only after the user turns them on and macOS grants access.
@MainActor
final class CalendarEvents: ObservableObject {
    static let shared = CalendarEvents()
    let store = EKEventStore()
    @Published var tick = 0

    var authorized: Bool { EKEventStore.authorizationStatus(for: .event) == .fullAccess }
    var canAsk: Bool { Bundle.main.object(forInfoDictionaryKey: "NSCalendarsFullAccessUsageDescription") != nil }

    func request(_ done: @escaping (Bool, String?) -> Void) {
        guard canAsk else { done(false, "Calendar events need the Draft app bundle (scripts/build-app.sh)."); return }
        store.requestFullAccessToEvents { ok, _ in
            DispatchQueue.main.async {
                self.tick &+= 1
                done(ok, ok ? nil : "Draft doesn't have access to Calendars. You can allow it in System Settings → Privacy & Security → Calendars.")
            }
        }
    }

    func events(on day: String) -> [EKEvent] {
        guard authorized, let start = Day.date(day), let end = Calendar.current.date(byAdding: .day, value: 1, to: start) else { return [] }
        return store.events(matching: store.predicateForEvents(withStart: start, end: end, calendars: nil)).sorted { $0.startDate < $1.startDate }
    }
}

extension EditorHostAdapter: LinkHost {
    func mentionItems(trigger: String, query: String) -> [MentionItem] { onMain { model.mentionItems(from: docId, trigger: trigger, query: query) } }
    func createLinkedDocument(title: String) -> String? {
        onMain { model.createDoc(folderId: .some(model.library.docs[docId]?.folderId), open: false, title: title) }
    }
    func openDocLink(docId: String, blockId: String?) { onMain { model.openDocLink(docId, block: blockId) } }
    func openDay(_ day: String) { onMain { model.openDay(day) } }
    func openTag(_ tag: String) { onMain { model.openView(ViewRef(kind: "tag", section: tag)) } }
    func resolveLink(docId: String, blockId: String?) -> (docId: String, title: String)? { onMain { model.resolveLink(docId, blockId) } }
    func todayKey() -> String { onMain { model.todayKey } }
    func createDocument(title: String, content: Node) -> String? {
        onMain { model.createNestedPage(parent: docId, title: title, content: content, nested: false) }
    }
    func pageCover(docId: String) -> NSImage? { onMain { model.ensureDoc(docId).flatMap { model.coverImage($0.appearance.cover) } } }
    func wantsLinkPreviews() -> Bool { onMain { model.settings.linkPreviews } }
    func openCollection(blockId: String) { onMain { model.saveDirtyDocs(); model.openCollection(docId, blockId) } }
    func fetchLinkPreview(_ url: URL, _ done: @escaping (LinkPreview?) -> Void) { onMain { model.online.linkPreview(url, enabled: model.settings.linkPreviews, done) } }
    func dailyNoteId(create: Bool) -> String? {
        onMain {
            let id = model.dailyNote(model.todayKey, create: create)
            return id == docId ? nil : id
        }
    }
}
