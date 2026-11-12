import AppKit
import SwiftUI
import DraftCore

/// State for Settings › Recovery, Version History and the startup recovery screen.
@MainActor
@Observable
final class RecoveryState {
    var tab = "check"
    var report: VaultCheck.Report?
    var checking = false
    /// Issues chosen for repair (ids).
    var selected = Set<String>()
    /// The exact plan shown before anything is written.
    var preview: VaultRepair.Plan?
    var working = false
    var lastResult: String?
    var assetFilter = "all"
    var assetConfirmMove = false
    var backups: [BackupCatalog.Item] = []
    var health: BackupCatalog.Health?
    var backupSelection: String?
    var backupFilter = "all"
    var trashConfirm: [BackupCatalog.Item]?
    var restoreConfirm: BackupCatalog.Item?
    var migration: MigrationValidator.Report?
    var rollbackPreview: VaultRepair.Plan?
    /// Version History sheet for this document.
    var historyDoc: HistoryTarget?
    /// Problems found at launch that stop Draft from opening normally.
    var startup: [VaultIssue]?
    var safeMode = false
    /// The startup screen was answered (repaired or continued read-only) for this launch.
    var startupHandled = false
}

struct HistoryTarget: Identifiable, Hashable { let id: String }

extension AppModel {
    // MARK: Safe Mode and startup

    /// Option held at launch, or DRAFT_SAFE_MODE=1: read everything, write nothing.
    static var safeModeRequested: Bool {
        ProcessInfo.processInfo.environment["DRAFT_SAFE_MODE"] == "1" || NSEvent.modifierFlags.contains(.option)
    }

    /// Cheap checks before the library is used: interrupted changes and a library that can't be read.
    func startupProblems() -> [VaultIssue]? {
        let open = VaultRepair.openJournals(vault)
        let libURL = vault.dir.appendingPathComponent("library.json")
        var libraryBad = false
        if let d = try? Data(contentsOf: libURL) {
            do { _ = try Migrations.migrateLibrary(d) } catch is NewerSchemaError { return nil } catch { libraryBad = true }
        }
        guard !open.isEmpty || libraryBad else { return nil }
        return VaultCheck.run(vault).issues.filter { $0.severity == .critical }
    }

    /// Continue after a startup problem without writing anything. An unreadable library is rebuilt in
    /// memory from the note files (and the newest readable backup) for this session only.
    func continueReadOnly() {
        let reason = "Draft opened your notes read-only because of a problem it found at launch. Nothing is written until you repair it in Settings › Recovery."
        vault.openReadOnly(reason)
        readOnly = reason
        recovery.startup = nil
        recovery.startupHandled = true
        var lib: Library? = nil
        if (try? Migrations.migrateLibrary(Data(contentsOf: vault.dir.appendingPathComponent("library.json")))) == nil {
            lib = VaultRepair.rebuildLibrary(vault: vault, base: VaultRepair.newestReadableLibraryBackup(vault)).library
        }
        boot(inMemoryLibrary: lib)
    }

    // MARK: Check and repair

    func checkVault() async {
        flushAll()
        recovery.checking = true
        recovery.preview = nil
        let v = vault
        let r = await Task.detached(priority: .userInitiated) { VaultCheck.run(v) }.value
        recovery.report = r
        // Repairs for critical problems and warnings are chosen by default; tidy-ups are opt-in.
        recovery.selected = Set(r.issues.filter { $0.repair != nil && $0.severity >= .warning }.map(\.id))
        recovery.checking = false
    }

    func reviewRepair() {
        guard let r = recovery.report else { return }
        let chosen = r.issues.filter { recovery.selected.contains($0.id) }
        recovery.preview = VaultRepair.plan(chosen, vault: vault)
    }

    /// Applies the previewed plan: backup first, validate after, all or nothing; one Undo.
    func applyRepair() async {
        guard let plan = recovery.preview, !plan.isEmpty else { return }
        flushAll()
        recovery.working = true
        defer { recovery.working = false }
        let fixes = plan.steps.map(\.issueId)
        do {
            let folder = try VaultRepair.apply(plan, vault: vault, summary: "Repair: \(plan.steps.count) problem\(plan.steps.count == 1 ? "" : "s")", fixes: fixes)
            reloadFromDisk(plan.files + plan.rollbacks.flatMap { _ in ["library.json"] })
            recovery.preview = nil
            recovery.lastResult = "Repaired \(plan.steps.count) problem\(plan.steps.count == 1 ? "" : "s"). The files from before are in backups/\(folder?.lastPathComponent ?? "")."
            await checkVault()
            if let folder { toast("Repaired \(plan.steps.count) problem\(plan.steps.count == 1 ? "" : "s"). A backup was made first.", action: "Undo") { [weak self] in self?.undoVaultChange(folder) } }
        } catch {
            recovery.preview = nil
            recovery.lastResult = error.localizedDescription
            toast(error.localizedDescription)
        }
    }

    func undoVaultChange(_ folder: URL) {
        flushAll()
        do {
            let touched = VaultRepair.allJournals(vault).first { $0.folder.lastPathComponent == folder.lastPathComponent }.map { $0.journal.touched + $0.journal.created } ?? []
            try VaultRepair.undo(folder, vault: vault)
            reloadFromDisk(touched)
            toast("Put back the files from before the change.")
            Task { await checkVault(); refreshBackups() }
        } catch { toast("Could not undo: \(error.localizedDescription)") }
    }

    /// After files changed on disk underneath the app: drop cached notes and editors for them,
    /// reload the library if it changed, rebuild the index if it changed.
    func reloadFromDisk(_ paths: [String]) {
        vault.reopen()
        readOnly = nil
        let touched = Set(paths)
        for p in touched where p.hasPrefix("docs/") {
            let id = String(p.dropFirst(5).dropLast(5))
            docs[id] = nil
            dirtyDocs.remove(id)
            dropEditor(id)
            docRevision[id, default: 0] &+= 1
        }
        if touched.contains("library.json") || library.docs.isEmpty, let lib = try? vault.loadLibrary() {
            library = lib
            tabs = tabs.filter { $0.view.kind != "doc" || lib.docs[$0.view.docId ?? ""] != nil }
            if tabs.first?.view.kind != "all" { tabs.insert(Tab(view: .all), at: 0) }
            if !tabs.contains(where: { $0.id == activeTabId }) { activeTabId = tabs[0].id }
        }
        for p in touched where p.hasPrefix("docs/") {
            let id = String(p.dropFirst(5).dropLast(5))
            if let d = ensureDoc(id), var m = library.docs[id] { m.applyDerived(from: d); library.docs[id] = m }
        }
        if touched.contains("index/index.json") { rebuildIndex() } else { refreshIndex() }
        editorTick &+= 1
    }

    // MARK: Versions

    /// Settings › Recovery and the Info panel: save a version the person asked for.
    func saveVersionNow(_ id: String) {
        saveDirtyDocs()
        guard let d = ensureDoc(id) else { return }
        do {
            try vault.snapshotIfDue(d, force: true, source: "manual")
            docRevision[id, default: 0] &+= 1
            editorTick &+= 1
            toast("Saved a version of “\(d.title.isEmpty ? "Untitled" : d.title)”.")
        } catch { toast("Could not save a version: \(error.localizedDescription)") }
    }

    struct RestoreCheck {
        var diff: VersionDiff
        var lostLinkedBlocks: [String]
        var missingAssets: [String]
        var recoverableAssets: [String]
        var brokenLinks: Int
    }

    /// Everything the restore preview shows, worked out without writing.
    func restoreCheck(_ id: String, _ s: Snapshot) -> RestoreCheck? {
        saveDirtyDocs()
        guard let cur = editors[id].map({ e -> DocFile in var d = docs[id] ?? DocFile.empty(id: id); d.content = e.controller.document(); return d }) ?? ensureDoc(id),
              let old = try? vault.loadSnapshot(s) else { return nil }
        let lost = VersionDiff.lostBlockIds(current: cur, restored: old)
        let linked = lost.filter { b in index.entries.contains { k, e in k != id && e.links.contains { $0.doc == id && $0.target == b } } }
        let assets = VaultCheck.assetIds(in: old)
        let missing = assets.filter { a in (try? vault.assetURL(a)).map { !FileManager.default.fileExists(atPath: $0.path) } ?? true }
        let recoverable = missing.filter { a in VaultCheck.unusedBackupsPublic(vault).contains { FileManager.default.fileExists(atPath: $0.appendingPathComponent(a).path) } }
        var broken = 0
        walk(old.content) { n in n.marks?.forEach { m in if m.type == "docLink", let t = m.attrs?["docId"]?.string, self.library.docs[t] == nil { broken += 1 } } }
        return RestoreCheck(diff: VersionDiff.compute(from: cur, to: old), lostLinkedBlocks: linked.sorted(), missingAssets: missing.sorted(), recoverableAssets: recoverable.sorted(), brokenLinks: broken)
    }

    /// Restores an earlier version through the editor: the current version is saved first
    /// ("Before a restore"), block ids are kept, missing attachments come back from backups/,
    /// and Command-Z (or the toast) undoes it in one step.
    func restoreVersion(_ id: String, _ s: Snapshot) {
        saveDirtyDocs()
        do {
            guard let cur = ensureDoc(id) else { return }
            var current = cur
            if let e = editors[id] { current.content = e.controller.document() }
            try vault.snapshotIfDue(current, force: true, source: "before-restore")
            let old = try vault.loadSnapshot(s)
            // Attachments the old version uses that were moved out as unused come back first.
            for a in VaultCheck.assetIds(in: old) {
                guard let dst = try? vault.assetURL(a), !FileManager.default.fileExists(atPath: dst.path) else { continue }
                if let src = VaultCheck.unusedBackupsPublic(vault).map({ $0.appendingPathComponent(a) }).first(where: { FileManager.default.fileExists(atPath: $0.path) }) {
                    try FileManager.default.copyItem(at: src, to: dst)
                }
            }
            let e = editor(for: id)
            let c = e.controller
            c.undo.beginUndoGrouping()
            c.replaceDocument(old.content, actionName: "Restore Version")
            if old.appearance != current.appearance { updateAppearance(id) { $0 = old.appearance } }
            c.undo.setActionName("Restore Version")
            c.undo.endUndoGrouping()
            if old.title != current.title { setTitle(id, old.title); e.title = old.title }
            markDocDirty(id)
            saveDirtyDocs()
            docRevision[id, default: 0] &+= 1
            editorTick &+= 1
            toast("Restored the version from \(relative(s.savedAt)). The version before it was saved.", action: "Undo") { [weak self] in
                guard let self, let c = self.editors[id]?.controller else { return }
                if c.undo.canUndo { c.undo.undo(); self.markDocDirty(id); self.saveDirtyDocs() }
            }
        } catch { toast("Could not restore: \(error.localizedDescription)") }
    }

    // MARK: Backups and attachments

    func refreshBackups() {
        let v = vault
        Task {
            let items = await Task.detached(priority: .userInitiated) { BackupCatalog.list(v) }.value
            let h = await Task.detached(priority: .utility) { BackupCatalog.health(v, items: items) }.value
            recovery.backups = items
            recovery.health = h
        }
    }

    func docTitle(_ id: String?) -> String {
        guard let id else { return "" }
        return library.docs[id].map { $0.title.isEmpty ? "Untitled" : $0.title } ?? id
    }

    /// Restores a backup through the same confirmed, journaled path as repairs.
    func restoreBackup(_ item: BackupCatalog.Item) {
        flushAll()
        let url = vault.dir.appendingPathComponent(item.path)
        do {
            switch item.kind {
            case .version:
                guard let id = item.docId, let s = vault.snapshots(id).first(where: { $0.url.lastPathComponent == url.lastPathComponent }) else { return }
                restoreVersion(id, s)
            case .change:
                undoVaultChange(url)
            case .unusedFiles:
                let names = (try? FileManager.default.contentsOfDirectory(atPath: url.path)) ?? []
                try VaultCheck.restore(from: url, into: vault)
                toast("Put back \(names.count) file\(names.count == 1 ? "" : "s") into assets/.")
            case .migration:
                guard let m = MigrationValidator.migrationBackups(vault).first(where: { $0.file.lastPathComponent == url.lastPathComponent }) else { return }
                var plan = VaultRepair.Plan()
                plan.writes[m.target] = try Data(contentsOf: m.file)
                let folder = try VaultRepair.apply(plan, vault: vault, kind: "restore", summary: "Restore \(m.target) from \(url.lastPathComponent)", fixes: [])
                reloadFromDisk([m.target])
                if let folder { toast("Restored \(m.target). The version before it was backed up.", action: "Undo") { [weak self] in self?.undoVaultChange(folder) } }
            default:
                toast("This backup can't be restored automatically. Use Show in Finder.")
            }
        } catch { toast("Could not restore: \(error.localizedDescription)") }
        refreshBackups()
    }

    func trashBackups(_ items: [BackupCatalog.Item]) {
        do {
            let n = try BackupCatalog.moveToTrash(items, vault: vault)
            toast("Moved \(n) backup\(n == 1 ? "" : "s") to the Trash. You can put \(n == 1 ? "it" : "them") back from the Trash in Finder.")
        } catch { toast(error.localizedDescription) }
        recovery.backupSelection = nil
        refreshBackups()
    }

    /// Moves the listed unused attachments into a repair backup (one Undo).
    func moveUnusedAssets() async {
        await checkVault()
        guard let r = recovery.report else { return }
        let unused = r.issues.filter { $0.kind == .assetUnused }
        guard !unused.isEmpty else { return }
        recovery.preview = VaultRepair.plan(unused, vault: vault)
        await applyRepair()
        recovery.assetConfirmMove = false
    }

    // MARK: Migration

    func validateMigration() async {
        flushAll()
        let dir = vault.dir
        recovery.working = true
        recovery.migration = await Task.detached(priority: .userInitiated) { try? MigrationValidator.validate(vault: dir) }.value
        recovery.working = false
    }

    func rollBackMigration() async {
        guard let plan = recovery.rollbackPreview, !plan.isEmpty else { return }
        flushAll()
        do {
            let folder = try VaultRepair.apply(plan, vault: vault, kind: "rollback", summary: "Roll back the last migration", fixes: [])
            recovery.rollbackPreview = nil
            toast("Put back \(plan.writes.count) file\(plan.writes.count == 1 ? "" : "s") from before the migration. Quit Draft and open the older version to keep using them.", action: "Undo") { [weak self] in
                if let folder { self?.undoVaultChange(folder) }
            }
            vault.openReadOnly("This vault was rolled back to an older format. Draft opened it read-only so it isn't migrated again until you relaunch.")
            readOnly = vault.readOnlyReason
        } catch { toast(error.localizedDescription) }
    }
}

extension VaultCheck {
    /// Folders under backups/ that may hold attachments moved out as unused.
    static func unusedBackupsPublic(_ vault: Vault) -> [URL] {
        let b = vault.dir.appendingPathComponent("backups")
        return ((try? FileManager.default.contentsOfDirectory(atPath: b.path)) ?? []).filter { $0.hasPrefix("unused-") || $0.hasPrefix("repair-") }
            .map { n in n.hasPrefix("repair-") ? b.appendingPathComponent(n).appendingPathComponent("files/assets") : b.appendingPathComponent(n) }
    }
}

extension String {
    var nonEmptyTitle: String? { isEmpty ? nil : self }
}
