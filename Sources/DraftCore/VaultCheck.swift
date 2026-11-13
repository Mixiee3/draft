import Foundation

/// How bad a vault problem is. Shown with an icon *and* a word, never color alone.
public enum IssueSeverity: Int, Comparable, Sendable, CaseIterable {
    case info, warning, critical
    public static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }
    public var label: String { ["Tidy-up", "Warning", "Critical"][rawValue] }
}

/// One problem found by `VaultCheck`. `repair` says exactly what a repair would do, or nil when
/// there is no safe automatic repair (the person decides).
public struct VaultIssue: Identifiable, Hashable, Sendable {
    public enum Kind: String, Sendable, CaseIterable {
        case libraryUnreadable, libraryNewer, docMissing, docMalformed, docUnreadable, docNewer, docIdMismatch, docIdDuplicate,
             blockIdDuplicate, docUnlisted, assetMissing, assetUnused, parentMissing, folderMissing, pageCardBroken, linkBroken,
             indexInvalid, tempFile, journalOpen
    }
    public var kind: Kind
    public var severity: IssueSeverity
    /// What it is about: a document id, a file name or a path relative to the vault.
    public var subject: String
    public var title: String
    public var detail: String
    public var repair: String?
    public var docId: String?
    public var id: String { kind.rawValue + ":" + subject }
}

/// Reads a vault without changing it and reports what is inconsistent; moves unused attachments to
/// `backups/unused-<time>/` (never deletes) and can move them back.
public enum VaultCheck {
    public struct Report: Sendable, Equatable {
        public var libraryReadable = true
        public var docsChecked = 0
        public var assetsChecked = 0
        /// Notes the library lists whose file is missing.
        public var missingDocFiles: [String] = []
        /// Note files the library doesn't list.
        public var strayDocFiles: [String] = []
        /// Note files that don't decode.
        public var unreadableDocs: [String] = []
        /// Attachments a note points to that aren't in `assets/`.
        public var missingAssets: [String] = []
        /// Files in `assets/` no note (including Recently Deleted and templates) uses.
        public var unusedAssets: [String] = []
        public var unusedBytes: Int64 = 0
        /// Every problem, most severe first.
        public var issues: [VaultIssue] = []
        /// Asset id → documents that use it (for the asset browser).
        public var assetUsers: [String: [String]] = [:]
        public var problemCount: Int { issues.filter { $0.kind != .assetUnused }.count }
        public var isClean: Bool { issues.isEmpty }
        public func count(_ s: IssueSeverity) -> Int { issues.filter { $0.severity == s }.count }
    }

    /// Asset ids a note refers to: image and file blocks, covers and uploaded backdrops.
    public static func assetIds(in doc: DocFile) -> Set<String> {
        var ids = Set<String>()
        walk(doc.content) { n in if let a = n.attrs?["assetId"]?.string { ids.insert(a) } }
        if let c = doc.appearance.cover?.assetId { ids.insert(c) }
        if let img = doc.appearance.overrides.backdrop?.image, img.hasPrefix("asset:") { ids.insert(String(img.dropFirst(6))) }
        return ids
    }

    /// Decodes a note file without writing anything; `raw` keeps block ids exactly as stored.
    enum DocRead { case ok(DocFile, raw: Node), malformed(String), newer(String), unreadable(String) }
    static func readDoc(_ data: Data) -> DocRead {
        guard (try? JSONSerialization.jsonObject(with: data)) is [String: Any] else { return .malformed("The file is not valid JSON.") }
        if let d = Migrations.fastDecode(data) { return .ok(d, raw: d.content) }
        do {
            let (doc, _, _) = try Migrations.migrateDoc(data)
            let raw = (try? JSONDecoder().decode(DocFile.self, from: data))?.content ?? doc.content
            return .ok(doc, raw: raw)
        } catch let e as NewerSchemaError { return .newer(e.localizedDescription) }
        catch { return .unreadable(error.localizedDescription) }
    }

    public static func run(_ vault: Vault) -> Report {
        vault.drain()
        var r = Report()
        var issues: [VaultIssue] = []
        // Messages are localized here (String Catalog); subjects and file names stay as they are.
        func add(_ k: VaultIssue.Kind, _ s: IssueSeverity, _ subject: String, _ title: String.LocalizationValue, _ detail: String.LocalizationValue, repair: String.LocalizationValue? = nil, doc: String? = nil) {
            issues.append(VaultIssue(kind: k, severity: s, subject: subject, title: String(localized: title), detail: String(localized: detail), repair: repair.map { String(localized: $0) }, docId: doc))
        }
        let fm = FileManager.default
        let dir = vault.dir
        // Library: decoded in memory only (Vault.loadLibrary would migrate and write).
        var lib: Library?
        if let data = try? Data(contentsOf: dir.appendingPathComponent("library.json")) {
            do { lib = try Migrations.migrateLibrary(data).library }
            catch let e as NewerSchemaError {
                r.libraryReadable = false
                add(.libraryNewer, .critical, "library.json", "The library was written by a newer Draft", "\(e.localizedDescription) Nothing will be changed.")
            } catch {
                r.libraryReadable = false
                let json = (try? JSONSerialization.jsonObject(with: data)) != nil
                add(.libraryUnreadable, .critical, "library.json", json ? "The library can't be read" : "The library is not valid JSON",
                    "library.json (\(data.count) bytes) doesn't decode: \(error.localizedDescription). Your notes are separate files and are not affected.",
                    repair: "Rebuild library.json from the note files, keeping folders and settings from the newest readable library backup.")
            }
        }
        let snapshotsFor = { (id: String) in vault.snapshots(id) }
        // Note files.
        let docsDir = dir.appendingPathComponent("docs")
        let names = (try? fm.contentsOfDirectory(atPath: docsDir.path)) ?? []
        for n in names where !n.hasSuffix(".json") || n.hasPrefix(".") {
            add(.tempFile, .info, "docs/" + n, "Leftover file from an interrupted save", "docs/\(n) is not a note. It is usually left behind when a save was interrupted.",
                repair: "Move docs/\(n) to the repair backup.")
        }
        let files = names.filter { $0.hasSuffix(".json") && !$0.hasPrefix(".") }.map { String($0.dropLast(5)) }.sorted()
        var decoded: [String: DocFile] = [:]
        var internalIds: [String: [String]] = [:]
        for id in files {
            r.docsChecked += 1
            let title = lib?.docs[id]?.title.nonEmpty ?? id
            guard let data = try? Data(contentsOf: docsDir.appendingPathComponent(id + ".json")) else { r.unreadableDocs.append(id); continue }
            let restore: () -> String.LocalizationValue? = { vault.snapshots(id).first.map { "Restore it from the version of \(Date(timeIntervalSince1970: $0.savedAt / 1000).formatted(Date.FormatStyle(date: .abbreviated, time: .shortened, locale: appLocale))); the damaged file is kept in the repair backup." } }
            switch readDoc(data) {
            case .malformed(let why):
                r.unreadableDocs.append(id)
                add(.docMalformed, .critical, id, "“\(title)” is damaged", damaged(id, why, hasVersion: restore() != nil), repair: restore(), doc: id)
            case .unreadable(let why):
                r.unreadableDocs.append(id)
                add(.docUnreadable, .critical, id, "“\(title)” can't be read", damaged(id, why, hasVersion: restore() != nil), repair: restore(), doc: id)
            case .newer(let why):
                r.unreadableDocs.append(id)
                add(.docNewer, .warning, id, "“\(title)” was written by a newer Draft", "\(why)", doc: id)
            case .ok(let d, let raw):
                decoded[id] = d
                internalIds[d.id, default: []].append(id)
                var seen = Set<String>(), dups = Set<String>()
                walk(raw) { n in if blockTypes.contains(n.type), let b = n.id { if !seen.insert(b).inserted { dups.insert(b) } } }
                if !dups.isEmpty {
                    add(.blockIdDuplicate, .warning, id, "“\(d.title.nonEmpty ?? id)” has repeated block ids", "\(dups.count) block ids are used twice (\(dups.sorted().prefix(3).joined(separator: ", "))). Links to those blocks can land on the wrong one.",
                        repair: "Give the later copies new ids in docs/\(id).json; the first copy keeps its id, so existing links still work.", doc: id)
                }
            }
        }
        for (inner, owners) in internalIds {
            for f in owners where f != inner {
                let dup = owners.count > 1 || decoded[inner] != nil
                add(dup ? .docIdDuplicate : .docIdMismatch, .warning, f, dup ? "Two note files claim the id \(inner)" : "A note's id doesn't match its file name",
                    "docs/\(f).json says its id is \(inner).", repair: "Set the id inside docs/\(f).json to \(f), matching its file name.", doc: f)
            }
        }
        // Library entries.
        if let lib {
            let fileSet = Set(files)
            for (id, m) in lib.docs.sorted(by: { $0.key < $1.key }) {
                if !fileSet.contains(id) {
                    r.missingDocFiles.append(id)
                    let s = snapshotsFor(id).first
                    add(.docMissing, .warning, id, "“\(m.title.nonEmpty ?? id)” has no note file", "The library lists it but docs/\(id).json is missing.",
                        repair: s.map { "Recreate docs/\(id).json from the version of \(Date(timeIntervalSince1970: $0.savedAt / 1000).formatted(Date.FormatStyle(date: .abbreviated, time: .shortened, locale: appLocale)))." }
                            ?? "Remove the entry from library.json (it stays in the repair backup).", doc: id)
                }
                if let p = m.parentDocId, lib.docs[p] == nil {
                    add(.parentMissing, .warning, id, "“\(m.title.nonEmpty ?? id)” is a nested page whose parent is gone", "Its parent \(p) is not in the library, so it can't be reached from a page card.",
                        repair: "Make it a top-level note in library.json.", doc: id)
                }
                if let f = m.folderId, !lib.folders.contains(where: { $0.id == f }) {
                    add(.folderMissing, .warning, id, "“\(m.title.nonEmpty ?? id)” is in a folder that no longer exists", "Folder \(f) is missing.",
                        repair: "Move it to Unsorted in library.json.", doc: id)
                }
            }
            for id in files where lib.docs[id] == nil {
                r.strayDocFiles.append(id)
                let t = decoded[id]?.title.nonEmpty ?? id
                add(.docUnlisted, .warning, id, "“\(t)” isn't in the library", "docs/\(id).json exists but the library doesn't list it, so it doesn't appear anywhere.",
                    repair: decoded[id] != nil ? "Add an entry for “\(t)” to library.json from the note file." : nil, doc: id)
            }
        }
        // Links and page cards.
        let known = Set(files).union(lib.map { Set($0.docs.keys) } ?? [])
        var blocksByDoc: [String: Set<String>] = [:]
        for (id, d) in decoded { var s = Set<String>(); walk(d.content) { if let b = $0.id { s.insert(b) } }; blocksByDoc[id] = s }
        for (id, d) in decoded.sorted(by: { $0.key < $1.key }) {
            var missingDocs = Set<String>(), missingBlocks = Set<String>(), cards = Set<String>()
            walk(d.content) { n in
                if n.type == "pageCard", let t = n.attrs?["docId"]?.string, !known.contains(t) { cards.insert(t) }
                n.marks?.forEach { m in
                    guard m.type == "docLink", let t = m.attrs?["docId"]?.string else { return }
                    if !known.contains(t) { missingDocs.insert(t) }
                    else if let b = m.attrs?["blockId"]?.string, decoded[t] != nil, !blocksByDoc.values.contains(where: { $0.contains(b) }) { missingBlocks.insert(b) }
                }
            }
            if !cards.isEmpty {
                add(.pageCardBroken, .warning, id, "“\(d.title.nonEmpty ?? id)” has a page card for a missing page", "\(cards.count) nested pages (\(cards.sorted().prefix(2).joined(separator: ", "))) can't be found. The card is kept so it works again if the page comes back.", doc: id)
            }
            if !missingDocs.isEmpty || !missingBlocks.isEmpty {
                let n = missingDocs.count + missingBlocks.count
                add(.linkBroken, .info, id, "“\(d.title.nonEmpty ?? id)” links to \(n) things that can't be found",
                    "\(missingDocs.count) missing notes, \(missingBlocks.count) missing blocks. Links are kept so they work again if the target returns.", doc: id)
            }
        }
        // Assets.
        var users: [String: [String]] = [:]
        for (id, d) in decoded { for a in assetIds(in: d) { users[a, default: []].append(id) } }
        let assetsDir = dir.appendingPathComponent("assets")
        let assets = Set((try? fm.contentsOfDirectory(atPath: assetsDir.path)) ?? []).filter { !$0.hasPrefix(".") }
        r.assetsChecked = assets.count
        r.assetUsers = users.mapValues { $0.sorted() }
        r.missingAssets = Set(users.keys).subtracting(assets).sorted()
        for a in r.missingAssets {
            let inUnused = unusedBackups(vault).contains { fm.fileExists(atPath: $0.appendingPathComponent(a).path) }
            add(.assetMissing, .warning, a, "An image or file is missing", "\(a) is used by \(users[a]?.count ?? 0) notes but isn't in assets/.",
                repair: inUnused ? "Bring \(a) back from backups/." : nil, doc: users[a]?.first)
        }
        // Unused only when every note was readable: a note that can't be read might use any file.
        if r.unreadableDocs.isEmpty && r.libraryReadable {
            r.unusedAssets = assets.subtracting(users.keys).sorted()
            for a in r.unusedAssets {
                let size = (try? fm.attributesOfItem(atPath: assetsDir.appendingPathComponent(a).path)[.size] as? Int64) ?? 0
                r.unusedBytes += size
                add(.assetUnused, .info, a, "Unused file", "\(a) (\(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))) isn't used by any note, template or deleted note.",
                    repair: "Move assets/\(a) to the repair backup.")
            }
        }
        // Derived index.
        let idx = dir.appendingPathComponent("index/index.json")
        if let data = try? Data(contentsOf: idx) {
            if let i = try? JSONDecoder().decode(VaultIndex.self, from: data) {
                if i.version != VaultIndex.version { add(.indexInvalid, .info, "index/index.json", "The search index is out of date", "It was built by format \(i.version); this Draft uses \(VaultIndex.version).", repair: "Rebuild the search and link index from the notes.") }
            } else {
                add(.indexInvalid, .warning, "index/index.json", "The search index is damaged", "index/index.json can't be read. Search, backlinks and tasks rebuild from your notes; nothing in them is lost.", repair: "Rebuild the search and link index from the notes.")
            }
        }
        // Repairs or restores that never finished.
        for j in VaultRepair.openJournals(vault) {
            add(.journalOpen, .critical, j.folder.lastPathComponent, "A \(j.journal.kind) was interrupted", "“\(j.journal.summary)” started \(Date(timeIntervalSince1970: j.journal.startedAt / 1000).formatted(Date.FormatStyle(date: .abbreviated, time: .shortened, locale: appLocale))) and didn't finish. The files from before it are in backups/\(j.folder.lastPathComponent).",
                repair: journalRepair(j.journal))
        }
        r.issues = issues.sorted { ($0.severity, $1.title) > ($1.severity, $0.title) }
        return r
    }

    // Plain if/else: chained ternaries of localized interpolations are very slow to type-check.
    static func damaged(_ id: String, _ why: String, hasVersion: Bool) -> String.LocalizationValue {
        if hasVersion { return "docs/\(id).json: \(why)" }
        return "docs/\(id).json: \(why) No earlier version exists; the file is left as it is."
    }

    static func journalRepair(_ j: VaultRepair.Journal) -> String.LocalizationValue {
        let put = j.touched.count, removed = j.created.count
        if put == 0 && removed == 0 { return "Mark it as rolled back; it hadn't changed anything yet." }
        if removed == 0 { return "Put back the \(put) files from before it." }
        if put == 0 { return "Remove the \(removed) files it created." }
        return "Put back the \(put) files from before it and remove the \(removed) files it created."
    }

    static func unusedBackups(_ vault: Vault) -> [URL] {
        let b = vault.dir.appendingPathComponent("backups")
        return ((try? FileManager.default.contentsOfDirectory(atPath: b.path)) ?? []).filter { $0.hasPrefix("unused-") || $0.hasPrefix("repair-") }
            .flatMap { n -> [URL] in
                let f = b.appendingPathComponent(n)
                return n.hasPrefix("repair-") ? [f.appendingPathComponent("files/assets")] : [f]
            }
    }

    /// Moves the given unused attachments into a new backups folder; returns that folder.
    public static func moveUnused(_ names: [String], in vault: Vault, now: Date = Date()) throws -> URL {
        guard !vault.isReadOnly else { throw MigrationError(message: vault.readOnlyReason ?? "The vault is read-only.") }
        let stamp = ISO8601DateFormatter().string(from: now).replacingOccurrences(of: ":", with: "-")
        let dest = vault.dir.appendingPathComponent("backups/unused-\(stamp)", isDirectory: true)
        try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
        for n in names { try FileManager.default.moveItem(at: try vault.assetURL(n), to: dest.appendingPathComponent(n)) }
        return dest
    }

    /// Puts moved attachments back (Undo); files already back are skipped.
    public static func restore(from folder: URL, into vault: Vault) throws {
        let fm = FileManager.default
        for n in (try? fm.contentsOfDirectory(atPath: folder.path)) ?? [] {
            let target = try vault.assetURL(n)
            if !fm.fileExists(atPath: target.path) { try fm.moveItem(at: folder.appendingPathComponent(n), to: target) }
        }
        if ((try? fm.contentsOfDirectory(atPath: folder.path)) ?? []).isEmpty { try? fm.removeItem(at: folder) }
    }
}

extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
