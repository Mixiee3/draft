import AppKit
import DraftCore
import DraftEditor

/// v0.8 Trust & Recovery probes, all on the throwaway vault in DRAFT_DATA_DIR:
/// - `trust-shots`: Version History (diff, restore preview, restore, one Undo), a vault with one problem
///   of each kind, Recovery › Check (report, preview, repair, Undo, repair again), Attachments, Backups,
///   cleanup confirmation, Migration, and the startup recovery screen. AUDIT_DARK / AUDIT_NARROW.
/// - `trust-read`: after relaunch on the same vault: the restore and the repair are still there, and the
///   repair can still be undone.
/// - `safe-mode-check`: launched with DRAFT_SAFE_MODE=1; nothing in the vault changes.
extension Automation {
    static func trustSetup() -> (NSWindow, String)? {
        guard let w = NSApp.windows.first(where: { $0.isVisible }) else { return nil }
        let env = ProcessInfo.processInfo.environment
        let narrow = env["AUDIT_NARROW"] != nil, dark = env["AUDIT_DARK"] != nil
        w.setFrame(NSRect(x: 40, y: 40, width: narrow ? 720 : 1280, height: narrow ? 700 : 900), display: true)
        m.setSettings { $0.theme = dark ? "dark" : "light" }
        return (w, (narrow ? "narrow-" : "") + (dark ? "dark-" : ""))
    }

    static func writeResult(_ r: [String: Any], _ name: String) {
        if let d = try? JSONSerialization.data(withJSONObject: r, options: [.prettyPrinted, .sortedKeys]) { try? d.write(to: out.appendingPathComponent(name)) }
    }

    static func mapText(_ n: Node, _ f: (String) -> String) -> Node {
        var o = n
        if let t = n.text { o.text = f(t) }
        o.content = n.content?.map { mapText($0, f) }
        return o
    }

    static func docText(_ id: String) -> String { m.editors[id].map { docPlainText($0.controller.document()) } ?? "" }

    static func trustShots() async {
        guard let (w, p) = trustSetup() else { return }
        var r: [String: Any] = [:]
        defer { writeResult(r, p + "trust.json") }
        let v = m.vault

        // 1. Version History on a note with text, a task, a quote, an image, a table and a nested page.
        guard let id = m.createDoc(title: "Trip plan") else { return }
        let c = m.editor(for: id).controller
        c.pastePlainForAutomation("## Plan\nWe fly on Monday morning and land before lunch.\n- [ ] Book the hotel\n- Pack light\n> Bring the good camera.\n| Day | Place |\n| --- | --- |\n| 1 | Lisbon |")
        let img = (try? v.putAsset(Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==")!, ext: "png")) ?? ""
        var nodes = c.document().content ?? []
        nodes.append(Node("image", attrs: ["id": "b_photo", "assetId": .string(img), "caption": "Harbour"]))
        if let child = m.createDoc(title: "Packing list") { nodes.append(Node("pageCard", attrs: ["id": "b_page", "docId": .string(child), "title": "Packing list"])); m.openView(.doc(id)) }
        c.load(Node("doc", content: nodes)); m.editorChanged(id); m.flushAll()
        m.saveVersionNow(id)
        let firstText = docText(id)
        // Edit: Monday → Tuesday, a new line, bold on a task, another style.
        var edited = mapText(c.document()) { $0.replacingOccurrences(of: "Monday", with: "Tuesday") }
        edited.content?.insert(Node("paragraph", attrs: ["id": "b_budget"], content: [.text("Budget: 900 euros, flights included.")]), at: 2)
        c.load(edited); m.editorChanged(id)
        m.updateAppearance(id) { $0.styleId = "ember" }
        m.flushAll()
        if let d = m.docs[id] { try? v.snapshotIfDue(d, now: nowMs() + 1000, force: true) }
        m.editorTick &+= 1
        let snaps = v.snapshots(id)
        r["history.versions"] = snaps.map(\.source)
        m.recovery.historySelection = snaps.first { $0.source == "manual" }?.id
        m.recovery.historyDoc = HistoryTarget(id: id)
        await wait(1.0)
        await shot(p + "history", w)
        m.recovery.historyConfirming = true
        await shot(p + "history-restore-preview", w)
        if let s = snaps.first(where: { $0.source == "manual" }), let ck = m.restoreCheck(id, s) {
            r["history.diff"] = ck.diff.summary
            r["history.diffEdited"] = ck.diff.count(.edited)
            r["history.diffRemovedInVersion"] = ck.diff.count(.removed)
        }
        m.recovery.historyConfirming = false
        m.recovery.historyDoc = nil
        await wait(0.6)
        if let s = snaps.first(where: { $0.source == "manual" }) {
            m.restoreVersion(id, s)
            await wait(0.4)
            r["restore.text"] = docText(id) == firstText ? "matches the version" : "differs: \(docText(id).prefix(80))"
            r["restore.style"] = m.docs[id]?.appearance.styleId ?? ""
            r["restore.beforeRestoreSaved"] = v.snapshots(id).contains { $0.source == "before-restore" }
            var ids: [String] = []; walk(c.document()) { if let i = $0.id { ids.append(i) } }
            r["restore.idsKept"] = ids.contains("b_photo") && ids.contains("b_page")
            r["restore.attachment"] = FileManager.default.fileExists(atPath: (try? v.assetURL(img).path) ?? "")
            c.undo.undo(); m.markDocDirty(id); m.flushAll()
            r["restore.undoOneStep"] = docText(id).contains("Tuesday") && docText(id).contains("Budget")
            c.undo.redo(); m.markDocDirty(id); m.flushAll()
            r["restore.redo"] = docText(id).contains("Monday")
        }
        await shot(p + "history-restored", w)

        // 2. A vault with one problem of each kind, made on the throwaway vault's files.
        func write(_ rel: String, _ d: Data) { try? Vault.writeAtomic(d, to: v.dir.appendingPathComponent(rel)) }
        func note(_ nid: String, _ title: String, _ blocks: [Node]) -> Data {
            var d = DocFile.empty(id: nid, title: title, styleId: "paper"); d.content = Node("doc", content: blocks); return (try? DraftJSON.encode(d)) ?? Data()
        }
        func para(_ bid: String, _ t: String, _ marks: [Mark]? = nil) -> Node { Node("paragraph", attrs: ["id": .string(bid)], content: [.text(t, marks: marks)]) }
        write("docs/d_broken.json", Data("{\"id\": \"d_broken\", \"title\": \"Reading list\", \"content\": {".utf8))
        write("history/d_broken/\(Int64(nowMs() - 3_600_000)).json", note("d_broken", "Reading list", [para("b_r1", "The Overstory"), para("b_r2", "Piranesi")]))
        write("docs/d_found.json", note("d_found", "Recipe found on disk", [para("b_f1", "Lentil soup")]))
        write("docs/d_dup.json", note("d_dup", "Meeting notes", [para("b_m1", "Agenda"), para("b_m1", "Decisions"),
            Node("image", attrs: ["id": "b_mimg", "assetId": "00112233445566778899aabbccddeeff.png"]),
            para("b_ml", "See the brief", [Mark("docLink", attrs: ["docId": "d_nowhere"])]), Node("pageCard", attrs: ["id": "b_mpc", "docId": "d_lostpage"])]))
        write("docs/d_dup.json.sb-4f2a-tmp", Data("partial".utf8))
        _ = try? v.putAsset(Data("an old screenshot nobody uses".utf8), ext: "png")
        m.library.docs["d_broken"] = DocMeta(id: "d_broken", title: "Reading list")
        m.library.docs["d_dup"] = DocMeta(id: "d_dup", title: "Meeting notes")
        var orphan = DocMeta(id: "d_dup", title: "Meeting notes"); orphan.parentDocId = "d_deletedparent"
        m.library.docs["d_dup"] = orphan
        m.library.docs["d_gone"] = DocMeta(id: "d_gone", title: "Old draft")
        m.scheduleLibrarySave(); m.flushAll()
        let journal = v.dir.appendingPathComponent("backups/restore-2026-11-12T09-00-00Z")
        write("docs/d_partial.json", note("d_partial", "Half-restored", [para("b_p", "x")]))
        try? VaultRepair.writeJournal(VaultRepair.Journal(kind: "restore", summary: "Restore “Half-restored”", startedAt: nowMs() - 600_000, state: "writing", touched: [], created: ["docs/d_partial.json"], fixes: []), journal)
        write("index/index.json", Data("not an index".utf8))

        // 3. Recovery › Check & Repair.
        m.openView(ViewRef(kind: "settings", section: "recovery"))
        m.recovery.tab = "check"
        await m.checkVault()
        write("index/index.json", Data("not an index".utf8)) // flushAll may have rewritten it; the check below reads it
        await m.checkVault()
        let kinds = Set(m.recovery.report?.issues.map(\.kind.rawValue) ?? [])
        r["check.kinds"] = kinds.sorted()
        r["check.critical"] = m.recovery.report?.count(.critical) ?? -1
        await shot(p + "recovery-check", w, settle: 0.8)
        m.reviewRepair()
        r["preview.steps"] = m.recovery.preview?.steps.map(\.text) ?? []
        await shot(p + "recovery-preview", w)
        await m.applyRepair()
        r["repair.result"] = m.recovery.lastResult ?? ""
        r["repair.left"] = m.recovery.report?.issues.filter { $0.repair != nil && $0.severity >= .warning }.map(\.title) ?? []
        r["repair.brokenRestored"] = (try? v.loadDoc("d_broken"))??.title == "Reading list"
        r["repair.foundListed"] = m.library.docs["d_found"] != nil
        r["repair.partialRolledBack"] = !FileManager.default.fileExists(atPath: v.dir.appendingPathComponent("docs/d_partial.json").path)
        await shot(p + "recovery-repaired", w)
        // One Undo puts every file back; then repair again so the relaunch probe has something to undo.
        m.toasts.first?.action?()
        await wait(0.8)
        r["repair.undo"] = (try? String(contentsOf: v.dir.appendingPathComponent("docs/d_broken.json"), encoding: .utf8))?.hasPrefix("{\"id\": \"d_broken\"") ?? false
        await m.checkVault()
        m.reviewRepair()
        await m.applyRepair()
        r["repair.again"] = (try? v.loadDoc("d_broken"))??.title == "Reading list"

        // 4. Attachments, Backups, Migration.
        m.recovery.tab = "assets"
        await shot(p + "recovery-assets", w, settle: 0.8)
        m.recovery.tab = "backups"
        m.refreshBackups()
        await wait(1.2)
        r["backups.kinds"] = Set(m.recovery.backups.map(\.kind.rawValue)).sorted()
        r["backups.health.unreadable"] = m.recovery.health?.unreadable.count ?? -1
        m.recovery.backupSelection = m.recovery.backups.first { $0.kind == .change }?.id
        await shot(p + "recovery-backups", w, settle: 0.6)
        m.recovery.trashConfirm = Array(m.recovery.backups.filter { $0.kind == .version }.suffix(2))
        await shot(p + "recovery-backups-trash-confirm", w)
        m.recovery.trashConfirm = nil
        m.recovery.tab = "migration"
        await m.validateMigration()
        r["migration.ok"] = m.recovery.migration?.ok ?? false
        r["migration.problems"] = m.recovery.migration?.problems ?? []
        await shot(p + "recovery-migration", w, settle: 0.6)

        // 5. The startup screen for an interrupted change (shown, not acted on).
        let j2 = v.dir.appendingPathComponent("backups/repair-2026-11-12T10-00-00Z")
        try? VaultRepair.writeJournal(VaultRepair.Journal(kind: "repair", summary: "Repair: 3 problems", startedAt: nowMs() - 60_000, state: "writing", touched: [], created: [], fixes: []), j2)
        m.recovery.startup = m.startupProblems()
        r["startup.detected"] = m.recovery.startup?.map(\.kind.rawValue) ?? []
        await shot(p + "startup-recovery", w, settle: 0.8)
        m.recovery.startup = nil
        try? FileManager.default.removeItem(at: j2)
        r["noteId"] = id
        m.flushAll()
    }

    static func trustRead() async {
        guard let (_, p) = trustSetup() else { return }
        var r: [String: Any] = [:]
        defer { writeResult(r, p + "trust-read.json") }
        let v = m.vault
        guard let id = m.library.docs.values.first(where: { $0.title == "Trip plan" })?.id else { r["error"] = "no note"; return }
        m.openView(.doc(id))
        await wait(0.6)
        r["relaunch.restoredText"] = docText(id).contains("Monday")
        r["relaunch.versions"] = v.snapshots(id).map(\.source)
        r["relaunch.check.critical"] = VaultCheck.run(v).count(.critical)
        let done = VaultRepair.allJournals(v).filter { $0.journal.state == "done" && $0.journal.kind == "repair" }
        r["relaunch.repairs"] = done.count
        if let last = done.last {
            m.undoVaultChange(last.folder)
            await wait(0.5)
            r["relaunch.undoRepair"] = (try? String(contentsOf: v.dir.appendingPathComponent("docs/d_broken.json"), encoding: .utf8))?.hasPrefix("{\"id\": \"d_broken\"") ?? false
        }
    }

    static func safeModeCheck() async {
        guard let (w, p) = trustSetup() else { return }
        var r: [String: Any] = [:]
        defer { writeResult(r, p + "safe-mode.json") }
        func fingerprint() -> [String: Int] {
            var o: [String: Int] = [:]
            for case let u as URL in FileManager.default.enumerator(at: m.vault.dir, includingPropertiesForKeys: nil)! where !u.hasDirectoryPath { o[u.lastPathComponent] = (try? Data(contentsOf: u))?.hashValue ?? 0 }
            return o
        }
        let before = fingerprint()
        r["safeMode"] = m.recovery.safeMode
        r["readOnly"] = m.readOnly ?? ""
        if let id = m.library.docs.values.first(where: { $0.deletedAt == nil })?.id {
            m.openView(.doc(id))
            await wait(0.5)
            m.saveVersionNow(id)
            m.setTitle(id, "Changed in Safe Mode")
            m.flushAll()
        }
        m.openView(ViewRef(kind: "settings", section: "recovery"))
        await m.checkVault()
        await shot(p + "safe-mode", w, settle: 0.8)
        m.flushAll()
        r["unchanged"] = fingerprint() == before
    }
}
