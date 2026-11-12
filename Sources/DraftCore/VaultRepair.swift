import Foundation

/// Turns chosen `VaultIssue`s into an exact list of file changes, and applies them all or nothing:
/// every file it touches is copied to `backups/<kind>-<time>/files/` with a `journal.json` first,
/// then written atomically, then the vault is checked again. Any failure puts every file back.
/// `undo` puts the copies back later (also after relaunch). Nothing here runs without a person's OK.
public enum VaultRepair {
    public struct Step: Identifiable, Hashable, Sendable {
        public var id: String { issueId }
        public var issueId: String
        public var text: String
        public var files: [String]
    }

    public struct Plan: Sendable {
        public var steps: [Step] = []
        /// Path relative to the vault → new contents; nil removes the file (it is kept in the backup).
        public var writes: [String: Data?] = [:]
        /// Interrupted changes to roll back first (their backup folders).
        public var rollbacks: [URL] = []
        /// Issues that have no safe repair and are left alone.
        public var skipped: [VaultIssue] = []
        public var files: [String] { writes.keys.sorted() }
        public var isEmpty: Bool { writes.isEmpty && rollbacks.isEmpty }
    }

    public struct Journal: Codable, Sendable {
        public var kind: String
        public var summary: String
        public var startedAt: Double
        public var state: String // writing, done, rolledBack, undone
        public var touched: [String]
        public var created: [String]
        public var fixes: [String]
    }

    public static func openJournals(_ vault: Vault) -> [(folder: URL, journal: Journal)] {
        allJournals(vault).filter { $0.journal.state == "writing" }
    }

    public static func allJournals(_ vault: Vault) -> [(folder: URL, journal: Journal)] {
        let b = vault.dir.appendingPathComponent("backups")
        return ((try? FileManager.default.contentsOfDirectory(atPath: b.path)) ?? []).sorted().compactMap { n in
            let f = b.appendingPathComponent(n)
            guard let d = try? Data(contentsOf: f.appendingPathComponent("journal.json")), let j = try? JSONDecoder().decode(Journal.self, from: d) else { return nil }
            return (f, j)
        }
    }

    // MARK: Planning (reads only)

    public static func plan(_ issues: [VaultIssue], vault: Vault) -> Plan {
        var p = Plan()
        let dir = vault.dir
        let libData = try? Data(contentsOf: dir.appendingPathComponent("library.json"))
        var lib: Library? = libData.flatMap { try? Migrations.migrateLibrary($0).library }
        let original = lib
        if issues.contains(where: { $0.kind == .libraryNewer }) {
            p.skipped = issues
            return p // a newer Draft owns this vault: change nothing
        }
        func docData(_ id: String) -> Data? { try? Data(contentsOf: dir.appendingPathComponent("docs/\(id).json")) }
        func step(_ i: VaultIssue, _ text: String, _ files: [String]) { p.steps.append(Step(issueId: i.id, text: text, files: files)) }
        for i in issues.sorted(by: { $0.kind == .libraryUnreadable && $1.kind != .libraryUnreadable }) {
            switch i.kind {
            case .libraryUnreadable:
                let rebuilt = rebuildLibrary(vault: vault, base: newestReadableLibraryBackup(vault))
                lib = rebuilt.library
                step(i, "library.json: rebuilt from \(rebuilt.library.docs.count) note files (" + rebuilt.changes.prefix(3).joined(separator: "; ") + (rebuilt.changes.count > 3 ? "; …" : "") + ").", ["library.json"])
            case .docUnlisted:
                guard lib != nil, let data = docData(i.subject), case .ok(let d, _) = VaultCheck.readDoc(data) else { p.skipped.append(i); continue }
                var m = DocMeta(id: i.subject)
                m.spaceId = lib!.space.id
                m.applyDerived(from: d)
                m.createdAt = d.createdAt; m.updatedAt = d.updatedAt
                m.parentDocId = parentFromPageCards(i.subject, vault: vault, lib: lib!)
                lib!.docs[i.subject] = m
                step(i, "library.json: add “\(m.title.nonEmpty ?? i.subject)”" + (m.parentDocId.map { " as a nested page of \(lib!.docs[$0]?.title.nonEmpty ?? $0)" } ?? "") + ".", ["library.json"])
            case .docMissing:
                guard lib != nil else { p.skipped.append(i); continue }
                if let s = vault.snapshots(i.subject).first, var d = try? vault.loadSnapshot(s) {
                    d.id = i.subject
                    guard let enc = try? DraftJSON.encode(d) else { p.skipped.append(i); continue }
                p.writes["docs/\(i.subject).json"] = enc
                    step(i, "docs/\(i.subject).json: recreated from the version of \(stamp(s.savedAt)).", ["docs/\(i.subject).json"])
                } else {
                    lib!.docs[i.subject] = nil
                    step(i, "library.json: remove the entry “\(original?.docs[i.subject]?.title.nonEmpty ?? i.subject)” (no file, no earlier version).", ["library.json"])
                }
            case .parentMissing:
                guard lib?.docs[i.subject] != nil else { p.skipped.append(i); continue }
                lib!.docs[i.subject]!.parentDocId = nil
                step(i, "library.json: “\(lib!.docs[i.subject]!.title.nonEmpty ?? i.subject)” becomes a top-level note.", ["library.json"])
            case .folderMissing:
                guard lib?.docs[i.subject] != nil else { p.skipped.append(i); continue }
                lib!.docs[i.subject]!.folderId = nil
                step(i, "library.json: “\(lib!.docs[i.subject]!.title.nonEmpty ?? i.subject)” moves to Unsorted.", ["library.json"])
            case .docMalformed, .docUnreadable:
                guard let s = vault.snapshots(i.subject).first, var d = try? vault.loadSnapshot(s) else { p.skipped.append(i); continue }
                d.id = i.subject
                guard let enc = try? DraftJSON.encode(d) else { p.skipped.append(i); continue }
                p.writes["docs/\(i.subject).json"] = enc
                step(i, "docs/\(i.subject).json: replaced by the version of \(stamp(s.savedAt)); the damaged file goes to the backup.", ["docs/\(i.subject).json"])
            case .docIdMismatch, .docIdDuplicate:
                guard let data = docData(i.subject), case .ok(var d, _) = VaultCheck.readDoc(data) else { p.skipped.append(i); continue }
                let old = d.id
                d.id = i.subject
                guard let enc = try? DraftJSON.encode(d) else { p.skipped.append(i); continue }
                p.writes["docs/\(i.subject).json"] = enc
                step(i, "docs/\(i.subject).json: id \(old) → \(i.subject).", ["docs/\(i.subject).json"])
            case .blockIdDuplicate:
                guard let data = docData(i.subject), case .ok(var d, let raw) = VaultCheck.readDoc(data) else { p.skipped.append(i); continue }
                d.content = ensureBlockIds(raw)
                var before: [String] = [], after: [String] = []
                walk(raw) { if blockTypes.contains($0.type) { before.append($0.id ?? "") } }
                walk(d.content) { if blockTypes.contains($0.type) { after.append($0.id ?? "") } }
                let changed = zip(before, after).filter { $0 != $1 }.count
                guard let enc = try? DraftJSON.encode(d) else { p.skipped.append(i); continue }
                p.writes["docs/\(i.subject).json"] = enc
                step(i, "docs/\(i.subject).json: \(changed) repeated block id\(changed == 1 ? "" : "s") renamed; first copies keep theirs.", ["docs/\(i.subject).json"])
            case .tempFile:
                p.writes[i.subject] = .some(nil)
                step(i, "\(i.subject): moved to the backup.", [i.subject])
            case .assetUnused:
                p.writes["assets/\(i.subject)"] = .some(nil)
                step(i, "assets/\(i.subject): moved to the backup.", ["assets/\(i.subject)"])
            case .assetMissing:
                guard let src = VaultCheck.unusedBackups(vault).map({ $0.appendingPathComponent(i.subject) }).first(where: { FileManager.default.fileExists(atPath: $0.path) }),
                      let data = try? Data(contentsOf: src) else { p.skipped.append(i); continue }
                p.writes["assets/\(i.subject)"] = data
                step(i, "assets/\(i.subject): copied back from \(src.deletingLastPathComponent().lastPathComponent).", ["assets/\(i.subject)"])
            case .indexInvalid:
                p.writes["index/index.json"] = .some(nil)
                step(i, "index/index.json: moved to the backup; Draft rebuilds search, backlinks and tasks from the notes.", ["index/index.json"])
            case .journalOpen:
                let f = dir.appendingPathComponent("backups/\(i.subject)")
                p.rollbacks.append(f)
                step(i, "Roll back the interrupted change using backups/\(i.subject).", [])
            case .libraryNewer, .docNewer, .linkBroken, .pageCardBroken:
                p.skipped.append(i)
            }
        }
        if let lib, lib != original, let data = try? DraftJSON.encode(lib, pretty: true) { p.writes["library.json"] = data }
        return p
    }

    static func stamp(_ ms: Double) -> String { Date(timeIntervalSince1970: ms / 1000).formatted(date: .abbreviated, time: .shortened) }

    /// The page card that shows a note, if any other note has one.
    static func parentFromPageCards(_ id: String, vault: Vault, lib: Library) -> String? {
        for other in lib.docs.keys.sorted() where other != id {
            guard let data = try? Data(contentsOf: vault.dir.appendingPathComponent("docs/\(other).json")), case .ok(let d, _) = VaultCheck.readDoc(data) else { continue }
            var found = false
            walk(d.content) { if $0.type == "pageCard", $0.attrs?["docId"]?.string == id { found = true } }
            if found { return other }
        }
        return nil
    }

    // MARK: Library rebuild

    /// The newest library copy under backups/ that still decodes.
    public static func newestReadableLibraryBackup(_ vault: Vault) -> Library? {
        let b = vault.dir.appendingPathComponent("backups")
        let fm = FileManager.default
        var candidates: [(Date, URL)] = []
        for n in (try? fm.contentsOfDirectory(atPath: b.path)) ?? [] {
            let u = b.appendingPathComponent(n)
            let file = n.hasSuffix(".json") && n.contains("library") && !n.contains("unreadable") ? u : u.appendingPathComponent("files/library.json")
            if let d = (try? fm.attributesOfItem(atPath: file.path))?[.modificationDate] as? Date { candidates.append((d, file)) }
        }
        for (_, u) in candidates.sorted(by: { $0.0 > $1.0 }) {
            if let data = try? Data(contentsOf: u), let l = try? Migrations.migrateLibrary(data).library { return l }
        }
        return nil
    }

    /// library.json rebuilt from the note files. Entries the base already has keep their folder,
    /// Space, star, nesting, trash state and unknown fields; derived fields are refreshed; notes the
    /// base doesn't list are added from their own titles (nesting from page cards).
    public static func rebuildLibrary(vault: Vault, base: Library?) -> (library: Library, changes: [String]) {
        var lib = base ?? Library.empty()
        let fm = FileManager.default
        let files = ((try? fm.contentsOfDirectory(atPath: vault.dir.appendingPathComponent("docs").path)) ?? [])
            .filter { $0.hasSuffix(".json") && !$0.hasPrefix(".") }.map { String($0.dropLast(5)) }
        var docs: [String: DocFile] = [:]
        for id in files { if let data = try? Data(contentsOf: vault.dir.appendingPathComponent("docs/\(id).json")), case .ok(let d, _) = VaultCheck.readDoc(data) { docs[id] = d } }
        var changes: [String] = []
        var cardParent: [String: String] = [:]
        for (id, d) in docs { walk(d.content) { if $0.type == "pageCard", let c = $0.attrs?["docId"]?.string { cardParent[c] = id } } }
        var added = 0, kept = 0
        for (id, d) in docs {
            var m = lib.docs[id] ?? {
                added += 1
                var n = DocMeta(id: id); n.spaceId = lib.space.id; n.createdAt = d.createdAt
                n.parentDocId = cardParent[id]
                return n
            }()
            if lib.docs[id] != nil { kept += 1 }
            m.applyDerived(from: d)
            m.updatedAt = d.updatedAt
            lib.docs[id] = m
        }
        let gone = lib.docs.keys.filter { docs[$0] == nil }
        for id in gone { lib.docs[id] = nil }
        changes.append("\(kept) entr\(kept == 1 ? "y" : "ies") kept")
        if added > 0 { changes.append("\(added) added from note files") }
        if !gone.isEmpty { changes.append("\(gone.count) without a readable file left out") }
        if base == nil { changes.append("folders and settings start empty (no readable backup)") }
        return (lib, changes)
    }

    // MARK: Applying

    public static func apply(_ plan: Plan, vault: Vault, kind: String = "repair", summary: String, fixes: [String], now: Date = Date()) throws -> URL? {
        let fm = FileManager.default
        for f in plan.rollbacks { try undo(f, vault: vault) }
        guard !plan.writes.isEmpty else { return plan.rollbacks.first }
        let stamp = ISO8601DateFormatter().string(from: now).replacingOccurrences(of: ":", with: "-")
        var folder = vault.dir.appendingPathComponent("backups/\(kind)-\(stamp)", isDirectory: true)
        var n = 2
        while fm.fileExists(atPath: folder.path) { folder = vault.dir.appendingPathComponent("backups/\(kind)-\(stamp)-\(n)", isDirectory: true); n += 1 }
        let files = folder.appendingPathComponent("files", isDirectory: true)
        var j = Journal(kind: kind, summary: summary, startedAt: now.timeIntervalSince1970 * 1000, state: "copying", touched: [], created: [], fixes: fixes)
        // 1. Copy everything that will change. Until the journal says "writing", nothing was written.
        for rel in plan.files {
            let src = vault.dir.appendingPathComponent(rel)
            if fm.fileExists(atPath: src.path) {
                let dst = files.appendingPathComponent(rel)
                try fm.createDirectory(at: dst.deletingLastPathComponent(), withIntermediateDirectories: true)
                try fm.copyItem(at: src, to: dst)
                j.touched.append(rel)
            } else if plan.writes[rel] != .some(nil) {
                j.created.append(rel)
            }
        }
        j.state = "writing"
        try writeJournal(j, folder)
        // 2. Write.
        do {
            for (rel, data) in plan.writes {
                let url = vault.dir.appendingPathComponent(rel)
                if let data { try Vault.writeAtomic(data, to: url) } else if fm.fileExists(atPath: url.path) { try fm.removeItem(at: url) }
            }
            // 3. Validate: every written file decodes and the fixed problems are gone.
            for (rel, data) in plan.writes where data != nil {
                let d = try Data(contentsOf: vault.dir.appendingPathComponent(rel))
                if rel == "library.json" { _ = try Migrations.migrateLibrary(d) }
                else if rel.hasPrefix("docs/") { guard case .ok = VaultCheck.readDoc(d) else { throw MigrationError(message: "\(rel) doesn't decode after the repair") } }
            }
            if !fixes.isEmpty {
                let left = Set(VaultCheck.run(vault).issues.map(\.id)).intersection(fixes)
                if !left.isEmpty { throw MigrationError(message: "The check still finds \(left.count) of the problems after the change (\(left.sorted().first!)).") }
            }
        } catch {
            try? putBack(j, folder, vault: vault)
            j.state = "rolledBack"
            try? writeJournal(j, folder)
            throw MigrationError(message: "Nothing was changed: \(error.localizedDescription) Every file was put back.")
        }
        j.state = "done"
        try writeJournal(j, folder)
        return folder
    }

    /// Puts back the files from before a change (Undo, or rolling back an interrupted one).
    public static func undo(_ folder: URL, vault: Vault) throws {
        guard let d = try? Data(contentsOf: folder.appendingPathComponent("journal.json")), var j = try? JSONDecoder().decode(Journal.self, from: d) else {
            throw MigrationError(message: "\(folder.lastPathComponent) has no journal, so Draft can't tell what to put back.")
        }
        guard j.state != "undone" && j.state != "rolledBack" else { return }
        try putBack(j, folder, vault: vault)
        j.state = "undone"
        try writeJournal(j, folder)
    }

    static func putBack(_ j: Journal, _ folder: URL, vault: Vault) throws {
        let fm = FileManager.default
        for rel in j.touched {
            let data = try Data(contentsOf: folder.appendingPathComponent("files").appendingPathComponent(rel))
            try Vault.writeAtomic(data, to: vault.dir.appendingPathComponent(rel))
        }
        for rel in j.created { let u = vault.dir.appendingPathComponent(rel); if fm.fileExists(atPath: u.path) { try fm.removeItem(at: u) } }
    }

    static func writeJournal(_ j: Journal, _ folder: URL) throws {
        try Vault.writeAtomic(try DraftJSON.encode(j, pretty: true), to: folder.appendingPathComponent("journal.json"))
    }
}
