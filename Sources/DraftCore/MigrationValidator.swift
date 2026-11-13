import Foundation

/// Tries a migration on a copy of the vault: nothing is written to the real vault. Reports the
/// schemas found, what would change, fields this Draft doesn't know (they are kept), and whether
/// the migrated copy still has every note, title, text, block id and link.
public enum MigrationValidator {
    public struct Report: Sendable {
        public var librarySchema: Int?
        public var docSchemas: [Int: Int] = [:] // schema → count
        public var expectedChanges: [String] = []
        public var unknownFields: [String] = []
        public var problems: [String] = []
        public var documents = 0
        public var needsMigration: Bool { (librarySchema ?? librarySchemaVersion) < librarySchemaVersion || docSchemas.keys.contains { $0 < docSchemaVersion } }
        public var ok: Bool { problems.isEmpty }
    }

    static let libraryNotes: [Int: String] = [
        0: String(localized: "library 0 → 1: the document list becomes a table keyed by id; a default Space, folders and tabs are added"),
        1: String(localized: "library 1 → 2: every note and folder is placed in the Space that held it"),
    ]
    static let docNotes: [Int: String] = [
        0: String(localized: "document 0 → 1: schema number, appearance (style) and created/updated times are added"),
    ]

    public static func validate(vault dir: URL) throws -> Report {
        var r = Report()
        let fm = FileManager.default
        let tmp = fm.temporaryDirectory.appendingPathComponent("draft-migration-check-" + UUID().uuidString, isDirectory: true)
        defer { try? fm.removeItem(at: tmp) }
        try fm.createDirectory(at: tmp.appendingPathComponent("docs"), withIntermediateDirectories: true)
        let libURL = dir.appendingPathComponent("library.json")
        guard let libData = try? Data(contentsOf: libURL) else { r.problems.append(String(localized: "library.json is missing")); return r }
        try libData.write(to: tmp.appendingPathComponent("library.json"))
        let rawLib = (try? JSONDecoder().decode(JSONValue.self, from: libData))?.object
        guard let rawLib else { r.problems.append(String(localized: "library.json is not a JSON object")); return r }
        let libFrom = rawLib["schemaVersion"]?.int ?? 0
        r.librarySchema = libFrom
        if libFrom > librarySchemaVersion { r.problems.append(String(localized: "library.json is schema \(libFrom); this Draft supports up to \(librarySchemaVersion). Update Draft; nothing was changed.")) }
        for v in libFrom..<max(libFrom, librarySchemaVersion) { if let n = libraryNotes[v] { r.expectedChanges.append(n) } }
        // Unknown fields (kept as they are).
        let libKnown = Set(["schemaVersion", "docs", "folders", "space", "spaces", "tabs", "activeTabId", "expandedFolders", "settings", "userStyles"])
        if let l = try? Migrations.migrateLibrary(libData).library {
            for k in l.extra.keys.sorted() where !libKnown.contains(k) { r.unknownFields.append(String(localized: "library.json: \(k)")) }
        }
        let docNames = ((try? fm.contentsOfDirectory(atPath: dir.appendingPathComponent("docs").path)) ?? []).filter { $0.hasSuffix(".json") && !$0.hasPrefix(".") }
        var docFrom = Set<Int>()
        var copies: [(String, Data)] = []
        for n in docNames {
            let data = try Data(contentsOf: dir.appendingPathComponent("docs/\(n)"))
            copies.append((n, data))
            guard let raw = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { r.problems.append(String(localized: "docs/\(n) is not a JSON object")); continue }
            let s = (raw["schemaVersion"] as? NSNumber)?.intValue ?? 0
            r.docSchemas[s, default: 0] += 1
            docFrom.insert(s)
            if s > docSchemaVersion { r.problems.append(String(localized: "docs/\(n) is schema \(s); this Draft supports up to \(docSchemaVersion).")) }
            let docKnown: Set<String> = ["schemaVersion", "id", "title", "content", "appearance", "createdAt", "updatedAt", "styleId"]
            for k in raw.keys.sorted() where !docKnown.contains(k) { r.unknownFields.append(String(localized: "docs/\(n): \(k)")) }
        }
        for v in (docFrom.min() ?? docSchemaVersion)..<docSchemaVersion { if let n = docNotes[v] { r.expectedChanges.append(n + " (\(docFrom.filter { $0 <= v }.reduce(0) { $0 + (r.docSchemas[$1] ?? 0) }) notes)") } }
        guard r.problems.isEmpty else { return r }
        if !r.needsMigration {
            // Already current: nothing would be migrated, so check that every note decodes and stop.
            r.documents = docNames.count
            for n in docNames {
                guard let d = try? Data(contentsOf: dir.appendingPathComponent("docs/\(n)")) else { continue }
                if case .ok = VaultCheck.readDoc(d) {} else { r.problems.append(String(localized: "docs/\(n) can't be read")) }
            }
            return r
        }
        for (n, data) in copies { try data.write(to: tmp.appendingPathComponent("docs/\(n)")) }
        // Dry run in memory, then a real migration of the copy, then a fresh read of the copy.
        let dry = try Migrations.dryRun(vault: tmp)
        r.documents = dry.documents
        r.problems += dry.differences.map { "Dry run: \($0)" }
        // Migrate the copy the way Vault does (library, then each older note), write it, read it back.
        let (migrated, _, _) = try Migrations.migrateLibrary(libData)
        try Vault.writeAtomic(try DraftJSON.encode(migrated, pretty: true), to: tmp.appendingPathComponent("library.json"))
        var olderDocs: [(String, Data)] = []
        for (n, data) in copies {
            guard let raw = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any], ((raw["schemaVersion"] as? NSNumber)?.intValue ?? 0) < docSchemaVersion else { continue }
            let (doc, _, _) = try Migrations.migrateDoc(data)
            try Vault.writeAtomic(try DraftJSON.encode(doc), to: tmp.appendingPathComponent("docs/\(n)"))
            olderDocs.append((n, data))
        }
        guard let again = try Vault(dir: tmp).loadLibrary() else { r.problems.append(String(localized: "The migrated library can't be read back")); return r }
        if again.docs.count != migrated.docs.count { r.problems.append(String(localized: "The migrated library lost entries (\(migrated.docs.count) → \(again.docs.count))")) }
        let rawDocs: [String: JSONValue] = rawLib["docs"]?.object ?? Dictionary((rawLib["docs"]?.items ?? []).compactMap { v in v.object?["id"]?.string.map { ($0, v) } }, uniquingKeysWith: { a, _ in a })
        for (id, v) in rawDocs where again.docs[id]?.title != v.object?["title"]?.string ?? "" { r.problems.append(String(localized: "\(id): title changed in the library")) }
        for (n, original) in olderDocs {
            guard let back = try? Data(contentsOf: tmp.appendingPathComponent("docs/\(n)")), case .ok(let d, _) = VaultCheck.readDoc(back),
                  let raw = (try? JSONSerialization.jsonObject(with: original)) as? [String: Any], let oldNode = raw["content"].flatMap({ Node(foundation: $0) }) else {
                r.problems.append(String(localized: "docs/\(n) can't be read back after migration")); continue
            }
            if d.schemaVersion != docSchemaVersion { r.problems.append(String(localized: "docs/\(n): still schema \(d.schemaVersion) after migration")) }
            if d.title != (raw["title"] as? String ?? "") { r.problems.append(String(localized: "docs/\(n): title changed after writing")) }
            if docPlainText(oldNode) != docPlainText(d.content) { r.problems.append(String(localized: "docs/\(n): text changed after writing")) }
            var oldIds = Set<String>(); walk(oldNode) { if let i = $0.id { oldIds.insert(i) } }
            var newIds = Set<String>(); walk(d.content) { if let i = $0.id { newIds.insert(i) } }
            if !oldIds.isSubset(of: newIds) { r.problems.append(String(localized: "docs/\(n): block ids changed after writing")) }
        }
        return r
    }

    /// Copies Draft made before migrating (`backups/<time>-library.vN.json`, `…-doc-<id>.vN.json`),
    /// newest first. Restoring them (through `VaultRepair`) rolls a migration back.
    public static func migrationBackups(_ vault: Vault) -> [(file: URL, target: String, schema: Int)] {
        let b = vault.dir.appendingPathComponent("backups")
        return ((try? FileManager.default.contentsOfDirectory(atPath: b.path)) ?? []).sorted(by: >).compactMap { n in
            guard let r = n.range(of: #"-(library|doc-([A-Za-z0-9_-]+))\.v(\d+)\.json$"#, options: .regularExpression) else { return nil }
            let core = String(n[r]).dropFirst()
            let schema = Int(core.split(separator: ".").last { $0.hasPrefix("v") }?.dropFirst() ?? "") ?? 0
            let target = core.hasPrefix("library") ? "library.json" : "docs/" + core.dropFirst(4).split(separator: ".").first! + ".json"
            return (b.appendingPathComponent(n), String(target), schema)
        }
    }

    /// A plan that puts the newest pre-migration copy of each file back.
    public static func rollbackPlan(_ vault: Vault) -> VaultRepair.Plan {
        var p = VaultRepair.Plan()
        for (file, target, schema) in migrationBackups(vault) where p.writes[target] == nil {
            guard let d = try? Data(contentsOf: file) else { continue }
            p.writes[target] = d
            p.steps.append(VaultRepair.Step(issueId: "rollback:" + target, text: "\(target): put back the schema \(schema) copy from \(file.lastPathComponent).", files: [target]))
        }
        return p
    }
}
