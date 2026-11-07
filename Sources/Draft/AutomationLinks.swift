import AppKit
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
}
