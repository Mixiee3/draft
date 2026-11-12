import AppKit
import SwiftUI
import DraftCore

/// Severity is shown with an icon and a word, never color alone.
struct SeverityBadge: View {
    let severity: IssueSeverity
    var body: some View {
        Label(severity.label, systemImage: Self.symbol(severity))
            .font(.system(size: DS.caption, weight: .semibold))
            .foregroundStyle(Self.color(severity))
            .labelStyle(.titleAndIcon)
    }
    static func symbol(_ s: IssueSeverity) -> String { ["sparkles", "exclamationmark.triangle.fill", "xmark.octagon.fill"][s.rawValue] }
    static func color(_ s: IssueSeverity) -> Color { [Color.blue, .orange, .red][s.rawValue] }
}

/// Settings › Recovery: Check & Repair, Attachments, Backups, Migration.
struct RecoveryView: View {
    @Environment(AppModel.self) var model
    @Environment(\.tokens) var t
    var body: some View {
        @Bindable var r = model.recovery
        VStack(alignment: .leading, spacing: DS.s5) {
            if r.safeMode || model.readOnly != nil {
                SettingsSection(title: r.safeMode ? "Safe Mode" : "Read-only") {
                    Label(model.readOnly ?? "", systemImage: "lock.fill").font(.system(size: DS.body)).foregroundStyle(t.text)
                        .padding(DS.s3 + 2).frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true)
                }
            }
            Picker("Recovery section", selection: $r.tab) {
                Text("Check & Repair").tag("check")
                Text("Attachments").tag("assets")
                Text("Backups").tag("backups")
                Text("Migration").tag("migration")
            }
            .pickerStyle(.segmented).labelsHidden().frame(maxWidth: 520)
            switch r.tab {
            case "assets": RecoveryAssets()
            case "backups": RecoveryBackups()
            case "migration": RecoveryMigration()
            default: RecoveryCheck()
            }
        }
    }
}

struct RecoveryCheck: View {
    @Environment(AppModel.self) var model
    @Environment(\.tokens) var t
    var body: some View {
        let r = model.recovery
        VStack(alignment: .leading, spacing: DS.s5) {
            SettingsSection(title: "Vault Check", footer: "Checking only reads your vault. Nothing changes until you review a repair and confirm it; the files it touches are copied to backups/ first, and Undo puts them back.") {
                SettingsRow(title: "Check Vault", detail: summary(r.report)) {
                    if r.checking { ProgressView().controlSize(.small).accessibilityLabel("Checking the vault") }
                    else { Button("Check Vault") { Task { await model.checkVault() } }.buttonStyle(DraftButtonStyle(compact: true)).keyboardShortcut("r", modifiers: [.command]) }
                }
                if let rep = r.report, rep.isClean {
                    Label("Everything is in order. \(rep.docsChecked) notes and \(rep.assetsChecked) attachments checked.", systemImage: "checkmark.seal.fill")
                        .font(.system(size: DS.body)).foregroundStyle(t.text).padding(DS.s3 + 2).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            SettingsSection(title: "Rebuild", footer: "Both start with a dry run. Rebuilding the library keeps every note's folder, Space, star, nesting and unknown fields; it only adds notes the library is missing and refreshes titles and counts from the note files.") {
                SettingsRow(title: "Rebuild library.json from notes", detail: "Shows the exact difference first; backed up and undoable.") {
                    Button("Review…") { r.preview = VaultRepair.rebuildPlan(model.vault) }.buttonStyle(DraftButtonStyle(compact: true)).disabled(r.working)
                }
                SettingsRow(title: "Rebuild search and link index", detail: "Search, backlinks, tags and tasks are rebuilt from your notes. Nothing in a note changes.") {
                    Button("Rebuild") { model.rebuildIndex(); model.toast("Rebuilt the search and link index from your notes.") }.buttonStyle(DraftButtonStyle(compact: true))
                }
            }
            if let plan = r.preview { RepairPreview(plan: plan) }
            else if let rep = r.report, !rep.isClean {
                ForEach(IssueSeverity.allCases.reversed(), id: \.self) { sev in
                    let list = rep.issues.filter { $0.severity == sev }
                    if !list.isEmpty {
                        SettingsSection(title: "\(sev.label) · \(list.count)") {
                            ForEach(list.prefix(sev == .info ? 40 : 200)) { IssueRow(issue: $0) }
                            if sev == .info && list.count > 40 { Text("and \(list.count - 40) more").font(.system(size: DS.footnote)).foregroundStyle(t.secondary).padding(DS.s3) }
                        }
                    }
                }
                HStack {
                    Text("\(r.selected.count) repair\(r.selected.count == 1 ? "" : "s") chosen").font(.system(size: DS.footnote)).foregroundStyle(t.secondary)
                    Spacer()
                    Button("Review Repair…") { model.reviewRepair() }.buttonStyle(DraftButtonStyle(role: .primary, compact: true))
                        .disabled(r.selected.isEmpty || r.working).keyboardShortcut(.defaultAction)
                }
            }
            if let last = r.lastResult { Text(last).font(.system(size: DS.footnote)).foregroundStyle(t.secondary).textSelection(.enabled) }
        }
        .task { if r.report == nil { await model.checkVault() } }
    }

    func summary(_ rep: VaultCheck.Report?) -> String {
        guard let rep else { return "Looks for damaged or missing notes, repeated ids, broken links and pages, missing or unused attachments, a damaged index and interrupted changes." }
        if rep.isClean { return "No problems" }
        return IssueSeverity.allCases.reversed().compactMap { s in rep.count(s) > 0 ? "\(rep.count(s)) \(s.label.lowercased())" : nil }.joined(separator: " · ")
    }
}

struct IssueRow: View {
    @Environment(AppModel.self) var model
    @Environment(\.tokens) var t
    let issue: VaultIssue
    var body: some View {
        let on = model.recovery.selected.contains(issue.id)
        HStack(alignment: .top, spacing: DS.s3) {
            if issue.repair != nil {
                Toggle(isOn: Binding(get: { on }, set: { v in if v { model.recovery.selected.insert(issue.id) } else { model.recovery.selected.remove(issue.id) } })) { EmptyView() }
                    .toggleStyle(.checkbox).labelsHidden().accessibilityLabel("Repair: \(issue.title)")
            } else {
                Image(systemName: "hand.raised").foregroundStyle(t.tertiary).frame(width: 16).accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: DS.s2) {
                    SeverityBadge(severity: issue.severity)
                    Text(issue.title).font(.system(size: DS.body, weight: .medium)).foregroundStyle(t.text)
                }
                Text(issue.detail).font(.system(size: DS.footnote)).foregroundStyle(t.secondary).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                Text(issue.repair.map { "Repair: " + $0 } ?? "No automatic repair. Draft leaves this as it is.")
                    .font(.system(size: DS.footnote)).foregroundStyle(issue.repair == nil ? t.tertiary : t.text).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            if let d = issue.docId, model.library.docs[d] != nil, issue.kind != .docMissing {
                Button("Open") { model.openView(.doc(d)) }.buttonStyle(DraftButtonStyle(role: .quiet, compact: true)).accessibilityLabel("Open \(model.docTitle(d))")
            }
        }
        .padding(.horizontal, DS.s3 + 2).padding(.vertical, DS.s2 + 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(issue.severity.label): \(issue.title). \(issue.detail). \(issue.repair.map { "Repair: " + $0 } ?? "No automatic repair.")")
        .accessibilityAddTraits(issue.repair != nil && on ? [.isSelected] : [])
    }
}

/// The exact list of changes, shown before anything is written. Return repairs, Escape cancels.
struct RepairPreview: View {
    @Environment(AppModel.self) var model
    @Environment(\.tokens) var t
    let plan: VaultRepair.Plan
    var body: some View {
        let r = model.recovery
        SettingsSection(title: "Repair preview", footer: "Before writing, Draft copies these \(plan.files.count) file\(plan.files.count == 1 ? "" : "s") to backups/repair-<time>/. After writing it checks the vault again; if anything is wrong, every file is put back and nothing changes.") {
            ForEach(plan.steps) { s in
                Label { Text(s.text).font(.system(size: DS.body)).foregroundStyle(t.text).fixedSize(horizontal: false, vertical: true).textSelection(.enabled) }
                    icon: { Image(systemName: "wrench.and.screwdriver").foregroundStyle(t.accent) }
                    .padding(.horizontal, DS.s3 + 2).padding(.vertical, DS.s2).frame(maxWidth: .infinity, alignment: .leading)
            }
            ForEach(plan.skipped) { i in
                Label { Text("Left as it is: \(i.title)").font(.system(size: DS.footnote)).foregroundStyle(t.secondary) } icon: { Image(systemName: "hand.raised").foregroundStyle(t.tertiary) }
                    .padding(.horizontal, DS.s3 + 2).padding(.vertical, DS.s2).frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack(spacing: DS.s2) {
                Text("Files: " + plan.files.prefix(4).joined(separator: ", ") + (plan.files.count > 4 ? " and \(plan.files.count - 4) more" : ""))
                    .font(.system(size: DS.caption, design: .monospaced)).foregroundStyle(t.secondary).lineLimit(2)
                Spacer()
                Button("Cancel") { r.preview = nil }.buttonStyle(DraftButtonStyle(compact: true)).keyboardShortcut(.cancelAction)
                Button(plan.steps.count == 1 ? "Repair" : "Repair \(plan.steps.count) Problems") { Task { await model.applyRepair() } }
                    .buttonStyle(DraftButtonStyle(role: .primary, compact: true)).keyboardShortcut(.defaultAction).disabled(plan.isEmpty || r.working)
            }.padding(DS.s3)
        }
    }
}

struct RecoveryAssets: View {
    @Environment(AppModel.self) var model
    @Environment(\.tokens) var t
    var body: some View {
        @Bindable var r = model.recovery
        let all = r.report.map { AssetCatalog.list(model.vault, report: $0, library: model.library) } ?? []
        let shown = r.assetFilter == "all" ? all : all.filter { $0.status.rawValue == r.assetFilter }
        let unused = all.filter { $0.status == .unused }
        VStack(alignment: .leading, spacing: DS.s4) {
            HStack {
                Picker("Show", selection: $r.assetFilter) {
                    Text("All \(all.count)").tag("all")
                    Text("Used \(all.filter { $0.status == .used }.count)").tag("used")
                    Text("Unused \(unused.count)").tag("unused")
                    Text("Missing \(all.filter { $0.status == .missing }.count)").tag("missing")
                }.pickerStyle(.segmented).labelsHidden().frame(maxWidth: 420)
                Spacer()
                if r.checking { ProgressView().controlSize(.small) } else { Button("Check Again") { Task { await model.checkVault() } }.buttonStyle(DraftButtonStyle(compact: true)) }
            }
            if !unused.isEmpty {
                SettingsSection(title: nil) {
                    SettingsRow(title: "\(unused.count) unused file\(unused.count == 1 ? "" : "s") · \(ByteCountFormatter.string(fromByteCount: unused.reduce(0) { $0 + $1.bytes }, countStyle: .file))",
                                detail: r.assetConfirmMove ? "Move them to backups/? Nothing is deleted; Undo puts them back. To remove them for good, use Backups › Move to Trash." : "No note, template or deleted note uses them.") {
                        if r.assetConfirmMove {
                            HStack(spacing: DS.s2) {
                                Button("Cancel") { r.assetConfirmMove = false }.buttonStyle(DraftButtonStyle(compact: true)).keyboardShortcut(.cancelAction)
                                Button("Move to Backups") { Task { await model.moveUnusedAssets() } }.buttonStyle(DraftButtonStyle(role: .primary, compact: true)).keyboardShortcut(.defaultAction)
                            }
                        } else {
                            Button("Move Unused Files…") { r.assetConfirmMove = true }.buttonStyle(DraftButtonStyle(compact: true)).disabled(model.readOnly != nil)
                        }
                    }
                }
            }
            SettingsSection(title: "Attachments", footer: "Last reference is the most recent edit of a note that uses the file.") {
                if shown.isEmpty { Text(r.report == nil ? "Checking…" : "Nothing here.").font(.system(size: DS.body)).foregroundStyle(t.secondary).padding(DS.s3 + 2) }
                ForEach(shown.prefix(300)) { a in AssetRow(item: a) }
            }
        }
        .task { if r.report == nil { await model.checkVault() } }
    }
}

struct AssetRow: View {
    @Environment(AppModel.self) var model
    @Environment(\.tokens) var t
    let item: AssetCatalog.Item
    var body: some View {
        let (sym, color, word): (String, Color, String) = item.status == .used ? ("checkmark.circle", .green, "Used") : item.status == .unused ? ("tray", .blue, "Unused") : ("exclamationmark.triangle.fill", .orange, "Missing")
        HStack(alignment: .top, spacing: DS.s3) {
            AssetThumb(name: item.name, missing: item.status == .missing).frame(width: 36, height: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name).font(.system(size: DS.footnote, design: .monospaced)).foregroundStyle(t.text).lineLimit(1).truncationMode(.middle).textSelection(.enabled)
                Text([item.kind, item.status == .missing ? nil : ByteCountFormatter.string(fromByteCount: item.bytes, countStyle: .file),
                      item.lastReference.map { "last used " + $0.formatted(date: .abbreviated, time: .omitted) }].compactMap { $0 }.joined(separator: " · "))
                    .font(.system(size: DS.caption)).foregroundStyle(t.secondary)
                if !item.users.isEmpty {
                    Text("In " + item.users.prefix(3).map { "“\(model.docTitle($0))”" }.joined(separator: ", ") + (item.users.count > 3 ? " and \(item.users.count - 3) more" : ""))
                        .font(.system(size: DS.caption)).foregroundStyle(t.secondary).lineLimit(2)
                }
            }
            Spacer(minLength: DS.s2)
            Label(word, systemImage: sym).font(.system(size: DS.caption, weight: .semibold)).foregroundStyle(color)
        }
        .padding(.horizontal, DS.s3 + 2).padding(.vertical, DS.s2)
        .accessibilityElement(children: .combine)
    }
}

struct AssetThumb: View {
    @Environment(AppModel.self) var model
    @Environment(\.tokens) var t
    let name: String
    let missing: Bool
    var body: some View {
        let img: NSImage? = missing || !AssetCatalog.kind(name).hasPrefix("Image") ? nil : (try? model.vault.assetURL(name)).flatMap { NSImage(contentsOf: $0) }
        ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous).fill(t.hover)
            if let img { Image(nsImage: img).resizable().aspectRatio(contentMode: .fill) }
            else { Image(systemName: missing ? "questionmark" : "doc").foregroundStyle(t.tertiary) }
        }.clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous)).accessibilityHidden(true)
    }
}

struct RecoveryBackups: View {
    @Environment(AppModel.self) var model
    @Environment(\.tokens) var t
    var body: some View {
        @Bindable var r = model.recovery
        let items = r.backupFilter == "all" ? r.backups : r.backups.filter { $0.kind.rawValue == r.backupFilter }
        VStack(alignment: .leading, spacing: DS.s4) {
            SettingsSection(title: "Backup health", footer: "Draft keeps the newest \(Vault.snapshotsKept) automatic versions of each note (one every 10 minutes while you edit) plus every version you save yourself; notes stay in Recently Deleted for \(Int(Library.trashRetentionDays)) days. Other backups stay until you remove them.") {
                if let h = r.health {
                    SettingsRow(title: "\(h.items) backups · \(ByteCountFormatter.string(fromByteCount: h.bytes, countStyle: .file))",
                                detail: "\(h.notesWithVersions) notes have versions" + (h.oldest.map { " · oldest \($0.formatted(date: .abbreviated, time: .omitted))" } ?? "")) {
                        if h.unreadable.isEmpty { Label("All readable", systemImage: "checkmark.seal").font(.system(size: DS.footnote, weight: .medium)).foregroundStyle(.green) }
                        else { Label("\(h.unreadable.count) can't be read", systemImage: "exclamationmark.triangle.fill").font(.system(size: DS.footnote, weight: .medium)).foregroundStyle(.orange) }
                    }
                    let old = BackupCatalog.cleanupCandidates(r.backups)
                    SettingsRow(title: "Clean up backups older than 30 days", detail: old.isEmpty ? "Nothing that old. The newest version of each note is always kept." : "\(old.count) backup\(old.count == 1 ? "" : "s"), \(ByteCountFormatter.string(fromByteCount: old.reduce(0) { $0 + $1.bytes }, countStyle: .file)). They go to the macOS Trash, so you can still put them back from Finder.") {
                        Button("Review…") { r.trashConfirm = old }.buttonStyle(DraftButtonStyle(compact: true)).disabled(old.isEmpty)
                    }
                } else { ProgressView().controlSize(.small).padding(DS.s3) }
            }
            if let list = r.trashConfirm { TrashConfirm(items: list) }
            if let item = r.restoreConfirm { RestoreBackupConfirm(item: item) }
            HStack {
                Picker("Kind", selection: $r.backupFilter) {
                    Text("All").tag("all"); Text("Versions").tag("version"); Text("Changes").tag("change")
                    Text("Migrations").tag("migration"); Text("Unused files").tag("unusedFiles")
                }.pickerStyle(.segmented).labelsHidden().frame(maxWidth: 520)
                Spacer()
            }
            SettingsSection(title: "Backups") {
                if items.isEmpty { Text("No backups of this kind yet.").font(.system(size: DS.body)).foregroundStyle(t.secondary).padding(DS.s3 + 2) }
                ForEach(items.prefix(400)) { BackupRow(item: $0) }
            }
        }
        .onAppear { model.refreshBackups() }
    }
}

struct BackupRow: View {
    @Environment(AppModel.self) var model
    @Environment(\.tokens) var t
    let item: BackupCatalog.Item
    var body: some View {
        let r = model.recovery
        let open = r.backupSelection == item.id
        VStack(alignment: .leading, spacing: DS.s2) {
            Button { r.backupSelection = open ? nil : item.id } label: {
                HStack(spacing: DS.s3) {
                    Image(systemName: Self.symbol(item.kind)).foregroundStyle(t.secondary).frame(width: 18)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title).font(.system(size: DS.body)).foregroundStyle(t.text).lineLimit(1)
                        Text("\(item.date.formatted(date: .abbreviated, time: .shortened)) · \(ByteCountFormatter.string(fromByteCount: item.bytes, countStyle: .file))" + (item.state == "writing" ? " · interrupted" : item.state == "undone" ? " · undone" : ""))
                            .font(.system(size: DS.caption)).foregroundStyle(item.state == "writing" ? .orange : t.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").rotationEffect(.degrees(open ? 90 : 0)).foregroundStyle(t.tertiary).accessibilityHidden(true)
                }.contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel("\(title), \(item.date.formatted(date: .abbreviated, time: .shortened))").accessibilityHint(open ? "Hides the preview" : "Shows a preview and actions")
            if open {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(Array(BackupCatalog.preview(model.vault, item).enumerated()), id: \.offset) { i, line in
                        Text(line).font(.system(size: i == 0 ? DS.footnote : DS.caption, weight: i == 0 ? .medium : .regular)).foregroundStyle(i == 0 ? t.text : t.secondary).lineLimit(2).textSelection(.enabled)
                    }
                }.padding(DS.s2 + 2).frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: DS.rControl, style: .continuous).fill(t.hover))
                HStack(spacing: DS.s2) {
                    if [.version, .change, .unusedFiles, .migration].contains(item.kind) && item.state != "undone" && item.state != "rolledBack" {
                        Button(item.kind == .change ? (item.state == "writing" ? "Roll Back…" : "Undo This Change…") : "Restore…") { r.restoreConfirm = item }
                            .buttonStyle(DraftButtonStyle(compact: true)).disabled(model.readOnly != nil && !r.safeMode && item.kind != .change)
                    }
                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([model.vault.dir.appendingPathComponent(item.path)]) }.buttonStyle(DraftButtonStyle(compact: true))
                    Spacer()
                    Button("Move to Trash…") { r.trashConfirm = [item] }.buttonStyle(DraftButtonStyle(role: .destructive, compact: true)).disabled(item.state == "writing")
                }
            }
        }
        .padding(.horizontal, DS.s3 + 2).padding(.vertical, DS.s2)
    }

    var title: String {
        switch item.kind {
        case .version: return "“\(model.docTitle(item.docId))” · \(item.source)"
        case .migration where item.docId != nil: return "“\(model.docTitle(item.docId))” · \(item.source)"
        default: return item.source
        }
    }
    static func symbol(_ k: BackupCatalog.Item.Kind) -> String {
        switch k {
        case .version: return "clock.arrow.circlepath"
        case .migration: return "arrow.up.doc"
        case .change: return "wrench.and.screwdriver"
        case .unusedFiles: return "tray.full"
        case .unreadableCopy: return "exclamationmark.triangle"
        case .other: return "doc"
        }
    }
}

/// Second confirmation before backups leave Draft (they go to the macOS Trash, never deleted).
struct TrashConfirm: View {
    @Environment(AppModel.self) var model
    @Environment(\.tokens) var t
    let items: [BackupCatalog.Item]
    var body: some View {
        SettingsSection(title: "Move to Trash?", footer: "These backups leave Draft's vault and go to the macOS Trash. They are gone for good only when you empty the Trash.") {
            ForEach(items.prefix(8)) { i in
                Text("• \(i.path)").font(.system(size: DS.caption, design: .monospaced)).foregroundStyle(t.secondary).lineLimit(1).truncationMode(.middle)
                    .padding(.horizontal, DS.s3 + 2).padding(.vertical, 2).frame(maxWidth: .infinity, alignment: .leading)
            }
            if items.count > 8 { Text("and \(items.count - 8) more").font(.system(size: DS.caption)).foregroundStyle(t.secondary).padding(.horizontal, DS.s3 + 2) }
            HStack {
                Spacer()
                Button("Cancel") { model.recovery.trashConfirm = nil }.buttonStyle(DraftButtonStyle(compact: true)).keyboardShortcut(.cancelAction)
                Button("Move \(items.count) to Trash") { model.recovery.trashConfirm = nil; model.trashBackups(items) }.buttonStyle(DraftButtonStyle(role: .destructive, compact: true))
            }.padding(DS.s3)
        }
    }
}

struct RestoreBackupConfirm: View {
    @Environment(AppModel.self) var model
    @Environment(\.tokens) var t
    let item: BackupCatalog.Item
    var body: some View {
        SettingsSection(title: item.kind == .change ? "Undo this change?" : "Restore this backup?", footer: item.kind == .version ? "The current version of the note is saved first, so you can switch back." : "The files it replaces are copied to backups/ first; Undo puts them back.") {
            ForEach(Array(BackupCatalog.preview(model.vault, item).prefix(5).enumerated()), id: \.offset) { _, line in
                Text(line).font(.system(size: DS.footnote)).foregroundStyle(t.text).padding(.horizontal, DS.s3 + 2).padding(.vertical, 2).frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack {
                Spacer()
                Button("Cancel") { model.recovery.restoreConfirm = nil }.buttonStyle(DraftButtonStyle(compact: true)).keyboardShortcut(.cancelAction)
                Button(item.kind == .change ? "Put Files Back" : "Restore") { model.recovery.restoreConfirm = nil; model.restoreBackup(item) }
                    .buttonStyle(DraftButtonStyle(role: .primary, compact: true)).keyboardShortcut(.defaultAction)
            }.padding(DS.s3)
        }
    }
}

struct RecoveryMigration: View {
    @Environment(AppModel.self) var model
    @Environment(\.tokens) var t
    var body: some View {
        let r = model.recovery
        let backups = MigrationValidator.migrationBackups(model.vault)
        VStack(alignment: .leading, spacing: DS.s5) {
            SettingsSection(title: "Migration check", footer: "Draft copies the vault to a temporary folder, updates the copy to this version's format, reads it back and compares every note, title, block id and link. The real vault is never touched.") {
                SettingsRow(title: "Validate Migration", detail: "This Draft writes library schema \(librarySchemaVersion) and note schema \(docSchemaVersion).") {
                    if r.working { ProgressView().controlSize(.small) } else { Button("Validate") { Task { await model.validateMigration() } }.buttonStyle(DraftButtonStyle(compact: true)) }
                }
                if let m = r.migration {
                    line(m.ok ? "checkmark.seal.fill" : "xmark.octagon.fill", m.ok ? .green : .red,
                         m.ok ? "The copy migrated and read back with nothing lost (\(m.documents) notes)." : "\(m.problems.count) problem\(m.problems.count == 1 ? "" : "s"): " + m.problems.prefix(3).joined(separator: "; "))
                    line("info.circle", t.secondary, "Found: library schema \(m.librarySchema.map(String.init) ?? "?"); notes " + m.docSchemas.sorted { $0.key < $1.key }.map { "schema \($0.key) × \($0.value)" }.joined(separator: ", "))
                    line(m.needsMigration ? "arrow.up.circle" : "checkmark.circle", t.secondary, m.needsMigration ? "Expected changes: " + m.expectedChanges.joined(separator: "; ") : "Already in the current format; nothing would change.")
                    line("questionmark.circle", t.secondary, m.unknownFields.isEmpty ? "No fields this Draft doesn't know." : "Kept as they are (unknown to this Draft): " + m.unknownFields.prefix(6).joined(separator: ", "))
                }
            }
            SettingsSection(title: "Roll back", footer: "Draft copies every file before it updates its format. Rolling back puts those copies back (after backing up the current files) and opens the vault read-only so it isn't updated again.") {
                SettingsRow(title: backups.isEmpty ? "No migration copies" : "\(backups.count) copies from earlier migrations", detail: backups.first.map { "Newest: \($0.file.lastPathComponent)" }) {
                    Button("Review…") { r.rollbackPreview = MigrationValidator.rollbackPlan(model.vault) }.buttonStyle(DraftButtonStyle(compact: true)).disabled(backups.isEmpty)
                }
                if let p = r.rollbackPreview {
                    ForEach(p.steps) { s in line("arrow.uturn.backward", t.accent, s.text) }
                    HStack {
                        Spacer()
                        Button("Cancel") { r.rollbackPreview = nil }.buttonStyle(DraftButtonStyle(compact: true)).keyboardShortcut(.cancelAction)
                        Button("Roll Back") { Task { await model.rollBackMigration() } }.buttonStyle(DraftButtonStyle(role: .destructive, compact: true))
                    }.padding(DS.s3)
                }
            }
        }
    }
    func line(_ sym: String, _ c: Color, _ text: String) -> some View {
        Label { Text(text).font(.system(size: DS.footnote)).foregroundStyle(t.text).fixedSize(horizontal: false, vertical: true).textSelection(.enabled) } icon: { Image(systemName: sym).foregroundStyle(c) }
            .padding(.horizontal, DS.s3 + 2).padding(.vertical, DS.s2).frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Shown instead of the library when Draft finds, at launch, a change that never finished or a
/// library it can't read. Nothing has been written.
struct StartupRecoveryView: View {
    @Environment(AppModel.self) var model
    @Environment(\.tokens) var t
    let issues: [VaultIssue]
    @State private var plan: VaultRepair.Plan?
    @State private var error: String?
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.s4) {
                Label("Draft found a problem before opening your notes", systemImage: "cross.case.fill").font(.title2.bold()).foregroundStyle(t.text)
                Text("Nothing has been changed. Your notes are separate files and the originals are kept. Choose how to continue.")
                    .font(.system(size: DS.body)).foregroundStyle(t.secondary).fixedSize(horizontal: false, vertical: true)
                SettingsSection(title: "What happened") {
                    ForEach(issues) { i in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack { SeverityBadge(severity: i.severity); Text(i.title).font(.system(size: DS.body, weight: .medium)).foregroundStyle(t.text) }
                            Text(i.detail).font(.system(size: DS.footnote)).foregroundStyle(t.secondary).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                            if let r = i.repair { Text("Recovery: " + r).font(.system(size: DS.footnote)).foregroundStyle(t.text).fixedSize(horizontal: false, vertical: true) }
                        }.padding(.horizontal, DS.s3 + 2).padding(.vertical, DS.s2).accessibilityElement(children: .combine)
                    }
                }
                if let plan { RecoveryPlanList(plan: plan) }
                if let error { Text(error).font(.system(size: DS.footnote)).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true) }
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: DS.s2) { buttons }
                    VStack(alignment: .leading, spacing: DS.s2) { buttons }
                }
            }
            .padding(DS.s6).frame(maxWidth: 680, alignment: .leading).frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder var buttons: some View {
        if plan == nil {
            Button("Review Recovery…") { plan = VaultRepair.plan(issues.filter { $0.repair != nil }, vault: model.vault) }
                .buttonStyle(DraftButtonStyle(role: .primary)).keyboardShortcut(.defaultAction).disabled(!issues.contains { $0.repair != nil })
        } else {
            Button("Recover") { recover() }.buttonStyle(DraftButtonStyle(role: .primary)).keyboardShortcut(.defaultAction)
            Button("Back") { plan = nil }.buttonStyle(DraftButtonStyle()).keyboardShortcut(.cancelAction)
        }
        Button("Open Read-Only") { model.continueReadOnly() }.buttonStyle(DraftButtonStyle())
        Button("Show Data Folder") { model.revealVault() }.buttonStyle(DraftButtonStyle(role: .quiet))
    }

    func recover() {
        guard let plan else { return }
        do {
            _ = try VaultRepair.apply(plan, vault: model.vault, summary: "Recovery at launch", fixes: plan.steps.map(\.issueId).filter { !$0.hasPrefix("journalOpen") })
            model.recovery.startup = nil
            model.recovery.startupHandled = true
            model.vault.reopen()
            if !model.recovery.safeMode { model.readOnly = nil }
            model.boot()
            model.toast("Recovered. The files from before are in backups/.")
        } catch { self.error = error.localizedDescription }
    }
}

struct RecoveryPlanList: View {
    @Environment(\.tokens) var t
    let plan: VaultRepair.Plan
    var body: some View {
        SettingsSection(title: "Recovery preview", footer: "The files this touches are copied to backups/ first. If the result doesn't check out, everything is put back.") {
            ForEach(plan.steps) { s in
                Label { Text(s.text).font(.system(size: DS.body)).foregroundStyle(t.text).fixedSize(horizontal: false, vertical: true) } icon: { Image(systemName: "arrow.uturn.backward").foregroundStyle(t.accent) }
                    .padding(.horizontal, DS.s3 + 2).padding(.vertical, DS.s2).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}
