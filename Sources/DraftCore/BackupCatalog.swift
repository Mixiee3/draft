import Foundation

/// Everything Draft keeps for recovery: note versions under `history/`, and under `backups/` the
/// copies made before migrations, repair/restore/rollback folders, unused-file folders and copies of
/// files that couldn't be read. Listing reads file attributes only; `health` decodes on demand.
public enum BackupCatalog {
    public struct Item: Identifiable, Hashable, Sendable {
        public enum Kind: String, Sendable, CaseIterable { case version, migration, change, unusedFiles, unreadableCopy, other }
        public var id: String { path }
        /// Relative to the vault.
        public var path: String
        public var kind: Kind
        public var source: String
        public var date: Date
        public var bytes: Int64
        public var docId: String?
        public var isFolder: Bool
        /// For a change folder: its journal state (done, undone, rolledBack, writing).
        public var state: String?
    }

    public struct Health: Sendable, Equatable {
        public var items = 0
        public var bytes: Int64 = 0
        public var unreadable: [String] = []
        public var oldest: Date?
        public var newest: Date?
        public var notesWithVersions = 0
    }

    static func size(_ url: URL) -> Int64 {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else { return 0 }
        if !isDir.boolValue { return (try? fm.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0 }
        return (fm.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey])?.allObjects as? [URL] ?? [])
            .reduce(0) { $0 + Int64((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
    }

    public static func list(_ vault: Vault) -> [Item] {
        vault.drain()
        let fm = FileManager.default
        var out: [Item] = []
        let hist = vault.dir.appendingPathComponent("history")
        for doc in (try? fm.contentsOfDirectory(atPath: hist.path)) ?? [] where !doc.hasPrefix(".") {
            for s in vault.snapshots(doc) {
                out.append(Item(path: "history/\(doc)/\(s.url.lastPathComponent)", kind: .version, source: s.sourceLabel,
                                date: Date(timeIntervalSince1970: s.savedAt / 1000), bytes: size(s.url), docId: doc, isFolder: false))
            }
        }
        let b = vault.dir.appendingPathComponent("backups")
        let journals = Dictionary(VaultRepair.allJournals(vault).map { ($0.folder.lastPathComponent, $0.journal) }, uniquingKeysWith: { a, _ in a })
        for n in (try? fm.contentsOfDirectory(atPath: b.path)) ?? [] where !n.hasPrefix(".") {
            let u = b.appendingPathComponent(n)
            var isDir: ObjCBool = false
            fm.fileExists(atPath: u.path, isDirectory: &isDir)
            let mtime = (try? fm.attributesOfItem(atPath: u.path)[.modificationDate] as? Date) ?? Date.distantPast
            var item = Item(path: "backups/\(n)", kind: .other, source: "Backup", date: mtime, bytes: size(u), docId: nil, isFolder: isDir.boolValue)
            if let j = journals[n] {
                item.kind = .change; item.source = j.summary; item.state = j.state
                item.date = Date(timeIntervalSince1970: j.startedAt / 1000)
            } else if n.hasPrefix("unused-") {
                item.kind = .unusedFiles; item.source = "Unused files moved out of assets/"
            } else if n.contains(".unreadable.") {
                item.kind = .unreadableCopy; item.source = "Copy of a file Draft couldn't read"
            } else if let m = MigrationValidator.migrationBackups(vault).first(where: { $0.file.lastPathComponent == n }) {
                item.kind = .migration; item.source = "Before updating \(m.target) from schema \(m.schema)"
                if m.target.hasPrefix("docs/") { item.docId = String(m.target.dropFirst(5).dropLast(5)) }
            }
            out.append(item)
        }
        return out.sorted { $0.date > $1.date }
    }

    /// Decodes every backup that should be a note or library and reports the ones that don't.
    public static func health(_ vault: Vault, items: [Item]) -> Health {
        var h = Health()
        h.items = items.count
        h.bytes = items.reduce(0) { $0 + $1.bytes }
        h.oldest = items.map(\.date).min(); h.newest = items.map(\.date).max()
        h.notesWithVersions = Set(items.filter { $0.kind == .version }.compactMap(\.docId)).count
        for i in items where !i.isFolder && i.path.hasSuffix(".json") && i.kind != .unreadableCopy {
            guard let d = try? Data(contentsOf: vault.dir.appendingPathComponent(i.path)) else { h.unreadable.append(i.path); continue }
            let ok = i.path.contains("library") ? (try? Migrations.migrateLibrary(d)) != nil : { if case .ok = VaultCheck.readDoc(d) { return true }; return false }()
            if !ok { h.unreadable.append(i.path) }
        }
        return h
    }

    /// A short, readable description of what the backup holds.
    public static func preview(_ vault: Vault, _ item: Item) -> [String] {
        let url = vault.dir.appendingPathComponent(item.path)
        let fm = FileManager.default
        switch item.kind {
        case .version, .migration where item.docId != nil:
            guard let d = try? Data(contentsOf: url), case .ok(let doc, _) = VaultCheck.readDoc(d) else { return ["This copy can't be read."] }
            let s = docStats(doc.content)
            let lines = docPlainText(doc.content).split(separator: "\n").prefix(4).map { String($0.prefix(140)) }
            return ["“\(doc.title.isEmpty ? "Untitled" : doc.title)” · \(s.words) words · \(s.blocks) blocks"] + lines
        case .change:
            guard let j = VaultRepair.allJournals(vault).first(where: { $0.folder.lastPathComponent == url.lastPathComponent })?.journal else { return [] }
            let state = ["done": "Applied", "undone": "Undone", "rolledBack": "Rolled back (nothing changed)", "writing": "Interrupted"][j.state] ?? j.state
            return ["\(state) · \(j.touched.count) files saved, \(j.created.count) created"] + j.touched.prefix(6).map { "• " + $0 }
        case .unusedFiles:
            let names = (try? fm.contentsOfDirectory(atPath: url.path)) ?? []
            return ["\(names.count) files"] + names.prefix(6).map { "• " + $0 }
        default:
            if item.path.contains("library"), let d = try? Data(contentsOf: url) {
                if let l = try? Migrations.migrateLibrary(d).library { return ["Library with \(l.docs.count) notes and \(l.folders.count) folders"] }
                return ["\(ByteCountFormatter.string(fromByteCount: Int64(d.count), countStyle: .file)), not readable as a library"]
            }
            return [ByteCountFormatter.string(fromByteCount: item.bytes, countStyle: .file)]
        }
    }

    /// Backups older than `days`, never the newest version of a note and never an interrupted change.
    public static func cleanupCandidates(_ items: [Item], olderThan days: Double = 30, now: Date = Date()) -> [Item] {
        let cutoff = now.addingTimeInterval(-days * 86_400)
        var newestVersion: [String: Date] = [:]
        for i in items where i.kind == .version { if let d = i.docId { newestVersion[d] = max(newestVersion[d] ?? .distantPast, i.date) } }
        return items.filter { i in
            i.date < cutoff && i.state != "writing" && !(i.kind == .version && newestVersion[i.docId ?? ""] == i.date)
        }
    }

    /// Moves backups to the macOS Trash (recoverable from Finder), never deleting outright.
    public static func moveToTrash(_ items: [Item], vault: Vault) throws -> Int {
        var n = 0
        for i in items {
            guard i.state != "writing" else { throw MigrationError(message: "\(i.path) belongs to an interrupted change. Roll it back first.") }
            let u = vault.dir.appendingPathComponent(i.path)
            guard u.standardizedFileURL.path.hasPrefix(vault.dir.standardizedFileURL.path + "/backups/") || u.standardizedFileURL.path.hasPrefix(vault.dir.standardizedFileURL.path + "/history/") else {
                throw MigrationError(message: "\(i.path) is not a backup.")
            }
            try FileManager.default.trashItem(at: u, resultingItemURL: nil)
            n += 1
        }
        return n
    }
}

/// Every attachment: used, unused or missing, with kind, size, last reference and the notes using it.
public enum AssetCatalog {
    public struct Item: Identifiable, Hashable, Sendable {
        public enum Status: String, Sendable, CaseIterable { case used, unused, missing }
        public var id: String { name }
        public var name: String
        public var status: Status
        public var kind: String
        public var bytes: Int64
        public var users: [String]
        public var lastReference: Date?
    }

    public static func kind(_ name: String) -> String {
        let ext = (name as NSString).pathExtension.lowercased()
        switch ext {
        case "png", "jpg", "jpeg", "gif", "webp", "heic", "tiff": return "Image (\(ext.uppercased()))"
        case "pdf": return "PDF"
        case "mp4", "mov", "m4v": return "Video"
        case "mp3", "m4a", "wav", "aac": return "Audio"
        case "zip": return "Archive"
        default: return ext.isEmpty ? "File" : ext.uppercased() + " file"
        }
    }

    public static func list(_ vault: Vault, report: VaultCheck.Report, library: Library?) -> [Item] {
        let fm = FileManager.default
        let dir = vault.dir.appendingPathComponent("assets")
        let present = Set((try? fm.contentsOfDirectory(atPath: dir.path)) ?? []).filter { !$0.hasPrefix(".") }
        let unused = Set(report.unusedAssets)
        var out: [Item] = []
        for n in present.union(report.assetUsers.keys) {
            let users = report.assetUsers[n] ?? []
            let status: Item.Status = !present.contains(n) ? .missing : unused.contains(n) || users.isEmpty ? .unused : .used
            let bytes = (try? fm.attributesOfItem(atPath: dir.appendingPathComponent(n).path)[.size] as? Int64) ?? 0
            let last = users.compactMap { library?.docs[$0]?.updatedAt }.max().map { Date(timeIntervalSince1970: $0 / 1000) }
            out.append(Item(name: n, status: status, kind: kind(n), bytes: bytes, users: users, lastReference: last))
        }
        return out.sorted { ($0.status.rawValue, $1.bytes) < ($1.status.rawValue, $0.bytes) }
    }
}
