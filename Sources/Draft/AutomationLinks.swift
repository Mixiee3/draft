import AppKit
import EventKit
import UserNotifications
import DraftCore
import DraftEditor

/// `DRAFT_AUTOMATION=links-write | links-read`: linked thinking end to end, through the real
/// editor and model. links-read runs after a relaunch, and again after `index/` is deleted.
extension Automation {
    static func save(_ r: [String: String], _ name: String) {
        if let d = try? JSONSerialization.data(withJSONObject: r, options: [.prettyPrinted, .sortedKeys]) { try? d.write(to: out.appendingPathComponent(name)) }
    }

    static func until(_ timeout: Double, _ ok: () -> Bool) async -> Double? {
        let t0 = Date()
        while Date().timeIntervalSince(t0) < timeout {
            if ok() { return Date().timeIntervalSince(t0) }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return nil
    }

    static func chips(_ c: EditorController) -> [Node] {
        var out: [Node] = []
        walk(c.document()) { n in if n.type == "text", n.marks?.contains(where: { $0.type == "docLink" }) == true { out.append(n) } }
        return out
    }

    static func linksWrite() async {
        var r: [String: String] = [:]
        guard let b = m.createDoc(title: "Beta") else { return }
        await wait()
        let eb = m.editors[b]!
        eb.focusBody(atStart: true)
        await type("Intro\nGoal: ship linked thinking\nSecond line", into: eb.controller)
        m.flushAll()
        let bBlocks = eb.controller.document().content ?? []
        let introId = bBlocks[0].id!, goalId = bBlocks[1].id!

        guard let a = m.createDoc(title: "Alpha") else { return }
        await wait()
        let ea = m.editors[a]!
        let ca = ea.controller
        ea.focusBody(atStart: true)
        await type("See [[Bet", into: ca)
        r["pickerFirst"] = ca.mention.results.first?.title ?? ""
        ca.textView.insertNewline(nil)
        await type("and [[goal: ship", into: ca)
        if let i = ca.mention.results.firstIndex(where: { $0.kind == .block }) { ca.mention.choose(i) }
        // Backlink appears after the debounced save re-indexes the source (budget: 1 s).
        let t = await until(3) { m.index.backlinks(to: b, live: m.liveIds).count >= 2 }
        r["backlinkMs"] = t.map { String(Int($0 * 1000)) } ?? "timeout"
        await type("#project ", into: ca)
        ca.textView.insertNewline(nil)
        await type("[] call the printer @tomorr", into: ca)
        r["datePick"] = ca.mention.results.first?.value ?? ""
        ca.textView.insertNewline(nil)
        r["backlinks"] = "\(m.index.backlinks(to: b, live: m.liveIds).count)"

        // Rename: the chip in Alpha follows once typing pauses.
        m.setTitle(b, "Beta renamed")
        _ = await until(2) { chips(ca).first?.text == "Beta renamed" }
        r["chipAfterRename"] = chips(ca).first?.text ?? ""
        // Move to a folder.
        let f = m.createFolder(); m.renameFolder(f, "Projects"); m.move(b, to: f)
        // Group Intro + Goal into a nested page: the goal block moves to another document.
        eb.controller.selectBlocks(ids: [introId, goalId])
        eb.controller.groupSelectionIntoPage()
        m.flushAll()
        let page = m.library.docs.values.first { $0.parentDocId == b && $0.title == "Intro" }?.id ?? ""
        r["nestedPage"] = page
        ca.refreshLinks()
        let ref = chips(ca).first { $0.marks?.first?.attrs?["blockId"]?.string == goalId }
        r["blockRefDoc"] = ref?.marks?.first?.attrs?["docId"]?.string ?? ""
        r["blockRefText"] = ref?.text ?? ""

        // Daily notes: one per day.
        let today = m.todayKey
        let d1 = m.dailyNote(today, create: true), d2 = m.dailyNote(today, create: true)
        r["dailyUnique"] = d1 != nil && d1 == d2 ? "yes" : "no"
        r["dailyId"] = d1 ?? ""
        // Calendar: Add Task on a future day.
        let fut = Day.add(today, days: 3)
        m.addTask("Water plants", on: fut)
        r["futureTask"] = m.tasks(on: fut).first?.task.text ?? ""
        r["futureBucket"] = m.tasks(on: fut).first?.task.bucket(today: today).rawValue ?? ""
        r["futureDay"] = fut
        // Tasks view: complete updates the source, one undo reverts it.
        m.flushAll()
        let um = UndoManager(); um.groupsByEvent = false
        if let task = m.tasks(.upcoming).first(where: { $0.task.text.contains("printer") }) {
            r["printerDue"] = task.task.dueDay ?? ""
            um.beginUndoGrouping(); m.setTask(task.doc, task.task.block, checked: true, undo: um); um.endUndoGrouping()
            let snap = ca.document()
            r["checkedInEditor"] = snap.settingTask(task.task.block, checked: true) == snap ? "yes" : "no"
            r["checkedInFile"] = ((try? m.vault.loadDoc(a)) ?? nil).map { $0.content.settingTask(task.task.block, checked: true) == $0.content } == true ? "yes" : "no"
            r["completedListed"] = m.tasks(.completed).contains { $0.task.block == task.task.block } ? "yes" : "no"
            um.undo()
            r["undoSteps"] = um.canUndo ? "more" : "one"
            r["uncheckedAfterUndo"] = ((try? m.vault.loadDoc(a)) ?? nil).map { $0.content.settingTask(task.task.block, checked: false) == $0.content } == true ? "yes" : "no"
        }
        // Missing target, then restore.
        if let cdoc = m.createDoc(open: false, title: "Gamma") {
            ca.insertDocLink(docId: cdoc, title: "Gamma")
            m.flushAll(); m.requestDelete(cdoc); ca.refreshLinks()
            let at = (ca.textView.string as NSString).range(of: "Gamma").location
            r["missingShown"] = at != NSNotFound && ca.storage.attribute(.draftLinkMissing, at: at, effectiveRange: nil) != nil ? "yes" : "no"
            m.restore(cdoc); ca.refreshLinks()
            r["missingCleared"] = ca.storage.attribute(.draftLinkMissing, at: at, effectiveRange: nil) == nil ? "yes" : "no"
        }
        // History: follow a link, scroll, go back and forward.
        m.openDocLink(b, block: nil)
        await wait(0.3)
        r["followed"] = m.activeDocId == b ? "yes" : "no"
        m.goBack(); await wait(0.3)
        r["back"] = m.activeDocId == a ? "yes" : "no"
        m.goForward(); await wait(0.3)
        r["forward"] = m.activeDocId == b ? "yes" : "no"
        // Export writes relative links between exported files.
        m.flushAll()
        let exp = out.appendingPathComponent("export")
        try? FileManager.default.createDirectory(at: exp, withIntermediateDirectories: true)
        m.export(docIds: [a, b], name: "links", groupByFolder: false, to: exp)
        r["exportLink"] = (try? String(contentsOf: exp.appendingPathComponent("links/Alpha.md"), encoding: .utf8)).map { $0.contains("](Beta%20renamed.md)") ? "yes" : $0 } ?? "missing"
        r["reminderPlan"] = "\(Reminders.plan(m.index.tasks(live: m.liveIds).map(\.task)).count)"
        r["alpha"] = a; r["beta"] = b; r["goal"] = goalId
        m.flushAll()
        save(r, "links-write.json")
    }

    static func linksRead() async {
        guard let d = try? Data(contentsOf: out.appendingPathComponent("links-write.json")),
              let w = try? JSONSerialization.jsonObject(with: d) as? [String: String], let a = w["alpha"], let b = w["beta"] else { return }
        var r: [String: String] = ["indexSeconds": String(format: "%.3f", m.lastIndexSeconds)]
        m.openView(.doc(a)); await wait(0.5)
        if let c = m.editors[a]?.controller {
            c.refreshLinks()
            r["chip"] = chips(c).first?.text ?? ""
            r["blockRefDoc"] = chips(c).first { $0.marks?.first?.attrs?["blockId"]?.string == w["goal"] }?.marks?.first?.attrs?["docId"]?.string ?? ""
        }
        r["backlinks"] = "\(m.index.backlinks(to: b, live: m.liveIds).count)"
        r["blockLocation"] = m.blockDoc[w["goal"] ?? ""] ?? ""
        r["tags"] = m.index.tagCounts(live: m.liveIds).map { "\($0.tag):\($0.count)" }.joined(separator: ",")
        r["buckets"] = TaskBucket.allCases.map { "\($0.rawValue):\(m.tasks($0).count)" }.joined(separator: ",")
        r["dailySame"] = m.dailyNote(m.todayKey, create: true) == w["dailyId"] ? "yes" : "no"
        r["dailyCount"] = "\(m.library.liveDocs.filter { $0.dailyDate == m.todayKey }.count)"
        r["futureTask"] = m.tasks(on: w["futureDay"] ?? "").first?.task.text ?? ""
        save(r, ProcessInfo.processInfo.environment["DRAFT_RESULT"] ?? "links-read.json")
    }

    static func screensV03() async {
        guard let w = NSApp.windows.first(where: { $0.isVisible }) else { return }
        m.setSettings { $0.theme = ProcessInfo.processInfo.environment["DRAFT_THEME"] ?? "light" }
        var checks: [String: String] = [:]
        guard let b = m.createDoc(title: "Launch plan") else { return }
        await wait()
        let eb = m.editors[b]!
        eb.focusBody(atStart: true)
        await type("Goal: ship linked thinking #launch\n[] write release notes @tomor", into: eb.controller); eb.controller.textView.insertNewline(nil)
        eb.controller.textView.insertNewline(nil)
        await type("[] book the venue #launch", into: eb.controller)
        let today = m.todayKey
        m.addTask("Review backlinks", on: today)
        m.addTask("Send invites", on: Day.add(today, days: 2))
        guard let a = m.createDoc(title: "Weekly review") else { return }
        await wait()
        let ea = m.editors[a]!, c = ea.controller
        ea.focusBody(atStart: true)
        await type("This week: [[Launch", into: c); c.textView.insertNewline(nil)
        await type("and [[goal: ship", into: c)
        if let i = c.mention.results.firstIndex(where: { $0.kind == .block }) { c.mention.choose(i) }
        await type("#review #launch #fff\n[] call the printer @next mon", into: c); c.textView.insertNewline(nil)
        m.flushAll()
        for (width, height, tag) in [(1440.0, 900.0, ""), (720.0, 640.0, "narrow-")] {
            w.setFrame(NSRect(x: 60, y: 60, width: width, height: height), display: true)
            m.openView(.doc(a)); await wait(0.6)
            await capture(tag + "v03-document-links")
            for (trigger, name) in [("[[La", "link-picker"), ("@nex", "date-picker"), ("#la", "tag-picker")] {
                w.makeFirstResponder(c.textView)
                c.textView.setSelectedRange(NSRange(location: (c.textView.string as NSString).length, length: 0))
                c.textView.insertNewline(nil)
                await type(trigger, into: c)
                c.textView.scrollRangeToVisible(c.textView.selectedRange()); c.mention.position()
                await capture(tag + "v03-" + name)
                checks[tag + name + ".inside"] = c.mention.isOpen && ea.paperView.visibleRect.insetBy(dx: -1, dy: -1).contains(c.mention.frame) ? "yes" : "no \(c.mention.isOpen) \(c.mention.frame)"
                checks[tag + name + ".rows"] = "\(c.mention.results.count)"
                c.mention.close()
                let tv = c.textView, s = tv.string as NSString
                let start = s.range(of: "\n", options: .backwards).location
                if start != NSNotFound { tv.setSelectedRange(NSRange(location: start, length: s.length - start)); tv.delete(nil) }
            }
            m.openView(.doc(b)); await wait(0.4)
            m.docRailTab = .backlinks
            await capture(tag + "v03-backlinks")
            m.docRailTab = .outline
            m.openView(ViewRef(kind: "tag", section: "launch")); await wait(0.4)
            await capture(tag + "v03-tag-view")
            m.openView(ViewRef(kind: "tasks", section: "today")); await wait(0.4)
            await capture(tag + "v03-tasks-today")
            m.openView(ViewRef(kind: "tasks", section: "upcoming")); await wait(0.4)
            await capture(tag + "v03-tasks-upcoming")
            m.openView(ViewRef(kind: "calendar")); await wait(0.6)
            await capture(tag + "v03-calendar")
            m.openDaily(); await wait(0.5)
            await capture(tag + "v03-daily-note")
            m.activateTab(m.library.tabs[0].id)
            m.librarySearchOpen = true; m.searchRegex = true; m.librarySearch = "(unclosed"
            await wait(0.3)
            await capture(tag + "v03-search-regex-error")
            m.librarySearch = ""; m.searchRegex = false; m.librarySearchOpen = false
            m.quickOpen = true
            await wait(0.3)
            await capture(tag + "v03-quick-open")
            m.quickOpen = false
        }
        w.setFrame(NSRect(x: 60, y: 60, width: 1440, height: 900), display: true)
        for sec in ["daily", "tags", "advanced"] {
            m.openView(ViewRef(kind: "settings", section: sec)); await wait(0.3)
            await capture("v03-settings-" + sec)
        }
        m.setSettings { $0.theme = "dark" }
        m.openView(ViewRef(kind: "calendar")); await wait(0.5)
        await capture("v03-calendar-dark")
        m.setSettings { $0.theme = "light" }
        save(checks, "v03-checks.json")
        m.flushAll()
    }

    /// Reports permission state and exercises scheduling/cancelling without showing a prompt.
    static func permissions() async {
        var r: [String: String] = ["bundle": Bundle.main.bundleIdentifier ?? "none", "remindersAvailable": m.reminders.available ? "yes" : "no",
                                   "calendarUsageKey": CalendarEvents.shared.canAsk ? "yes" : "no", "calendarStatus": "\(EKEventStore.authorizationStatus(for: .event).rawValue)"]
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        r["notificationStatus"] = "\(settings.authorizationStatus.rawValue)"
        m.addTask("Reminder probe", on: Day.add(m.todayKey, days: 1))
        m.library.settings.reminders = true
        m.syncReminders(requestIfNeeded: false)
        await wait(1.0)
        r["plan"] = "\(m.reminders.planned.count)"
        r["pendingWhenOn"] = await withCheckedContinuation { c in m.reminders.pending { c.resume(returning: "\($0.count)") } }
        m.setSettings { $0.reminders = false }
        await wait(1.0)
        r["pendingWhenOff"] = await withCheckedContinuation { c in m.reminders.pending { c.resume(returning: "\($0.count)") } }
        save(r, "permissions.json")
    }
}
