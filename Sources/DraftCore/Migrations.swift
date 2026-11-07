import Foundation

public struct NewerSchemaError: LocalizedError {
    public let what: String, found: Int, supported: Int
    public var errorDescription: String? {
        "\(what) was written by a newer Draft (schema \(found); this app supports \(supported)). Draft opened it read-only so nothing is lost. Please update Draft."
    }
}

public struct MigrationError: LocalizedError {
    public let message: String
    public var errorDescription: String? { message }
}

/// Explicit, ordered migrations operating on raw JSON. Each step takes the object at version N
/// and returns version N+1, spreading the input so unknown fields survive.
/// Version 0 = the pre-release prototype format (no schemaVersion, docs as an array).
public enum Migrations {
    typealias Step = ([String: JSONValue]) -> [String: JSONValue]

    static let librarySteps: [Int: Step] = [
        0: { raw in
            var out = raw
            let base = Library.empty()
            var docs: [String: JSONValue] = [:]
            let list: [JSONValue]
            switch raw["docs"] {
            case .array(let a): list = a
            case .object(let o): list = Array(o.values)
            default: list = []
            }
            for d in list {
                guard var o = d.object, let id = o["id"]?.string else { continue }
                if o["title"] == nil { o["title"] = "" }
                if o["styleId"] == nil { o["styleId"] = "paper" }
                docs[id] = .object(o)
            }
            out["docs"] = .object(docs)
            out["schemaVersion"] = 1
            if out["space"] == nil { out["space"] = .object(["id": .string(base.space.id), "name": "My Space"]) }
            if out["folders"] == nil { out["folders"] = .array([]) }
            if out["tabs"] == nil { out["tabs"] = .array([]) }
            if out["expandedFolders"] == nil { out["expandedFolders"] = .array([]) }
            return out
        },
        1: toSpaces,
    ]

    /// 1 → 2: Spaces. Every folder and document belongs to the Space that held them.
    static let toSpaces: Step = { raw in
        var out = raw
        let space = raw["space"]?.object ?? ["id": .string(newId("s_")), "name": "My Space"]
        let sid = space["id"] ?? .string(newId("s_"))
        out["space"] = .object(space)
        if out["spaces"] == nil { out["spaces"] = .array([.object(space)]) }
        if case .object(var docs)? = raw["docs"] {
            for (k, v) in docs { if var o = v.object, o["spaceId"] == nil { o["spaceId"] = sid; docs[k] = .object(o) } }
            out["docs"] = .object(docs)
        }
        if case .array(let fs)? = raw["folders"] {
            out["folders"] = .array(fs.map { f in guard var o = f.object else { return f }; if o["spaceId"] == nil { o["spaceId"] = sid }; return .object(o) })
        }
        out["schemaVersion"] = 2
        return out
    }

    static let docSteps: [Int: Step] = [
        0: { raw in
            var out = raw
            out["schemaVersion"] = 1
            if out["title"] == nil { out["title"] = "" }
            if out["content"]?.object?["type"]?.string != "doc" {
                out["content"] = .object(["type": "doc", "content": .array([.object(["type": "paragraph"])])])
            }
            if out["appearance"] == nil {
                out["appearance"] = .object(["styleId": raw["styleId"] ?? "paper", "overrides": .object([:])])
            }
            let now = JSONValue.number(nowMs())
            if out["createdAt"] == nil { out["createdAt"] = now }
            if out["updatedAt"] == nil { out["updatedAt"] = out["createdAt"] }
            return out
        },
    ]

    static func run(_ raw: [String: JSONValue], target: Int, steps: [Int: Step], what: String) throws -> (value: [String: JSONValue], from: Int) {
        var v = raw["schemaVersion"]?.int ?? 0
        let from = v
        if v > target { throw NewerSchemaError(what: what, found: v, supported: target) }
        var cur = raw
        while v < target {
            guard let step = steps[v] else { throw MigrationError(message: "No migration for \(what) from schema \(v)") }
            cur = step(cur)
            v = cur["schemaVersion"]?.int ?? (v + 1)
        }
        return (cur, from)
    }

    static func decode<T: Decodable>(_ raw: [String: JSONValue], as: T.Type) throws -> T {
        let data = try JSONEncoder().encode(JSONValue.object(raw))
        return try JSONDecoder().decode(T.self, from: data)
    }

    public static func migrateLibrary(_ data: Data) throws -> (library: Library, migrated: Bool, from: Int) {
        guard let raw = try JSONDecoder().decode(JSONValue.self, from: data).object else { throw MigrationError(message: "library.json is not an object") }
        let (value, from) = try run(raw, target: librarySchemaVersion, steps: librarySteps, what: "The library")
        return (try decode(value, as: Library.self), from != librarySchemaVersion, from)
    }

    public static func migrateDoc(_ data: Data) throws -> (doc: DocFile, migrated: Bool, from: Int) {
        guard let raw = try JSONDecoder().decode(JSONValue.self, from: data).object else { throw MigrationError(message: "document is not an object") }
        let (value, from) = try run(raw, target: docSchemaVersion, steps: docSteps, what: "A document")
        var doc = try decode(value, as: DocFile.self)
        doc.content = ensureBlockIds(doc.content) // cheap, idempotent repair
        return (doc, from != docSchemaVersion, from)
    }
}

public enum DraftJSON {
    public static func encode<T: Encodable>(_ v: T, pretty: Bool = false) throws -> Data {
        let e = JSONEncoder()
        e.outputFormatting = pretty ? [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes] : [.sortedKeys, .withoutEscapingSlashes]
        return try e.encode(v)
    }
}

/// What a migration would change, worked out without writing anything.
public struct MigrationReport: Sendable {
    public var from: Int
    public var to: Int
    public var documents: Int
    public var differences: [String]
    public var ok: Bool { differences.isEmpty }
}

public extension Migrations {
    /// Migrate a vault in memory and compare every document's title, style, folder, nesting,
    /// trash state, block ids, text and link targets before and after. Writes nothing.
    static func dryRun(vault dir: URL) throws -> MigrationReport {
        let libData = try Data(contentsOf: dir.appendingPathComponent("library.json"))
        guard let raw = try JSONDecoder().decode(JSONValue.self, from: libData).object else { throw MigrationError(message: "library.json is not an object") }
        let from = raw["schemaVersion"]?.int ?? 0
        let (lib, _, _) = try migrateLibrary(libData)
        var diffs: [String] = []
        let before = raw["docs"]?.object ?? [:]
        if Set(before.keys) != Set(lib.docs.keys) { diffs.append("Document list changed (\(before.count) → \(lib.docs.count))") }
        for (id, v) in before {
            guard let o = v.object, let m = lib.docs[id] else { continue }
            func same(_ k: String, _ now: String?) { if o[k]?.string != now { diffs.append("\(id): \(k) changed") } }
            same("title", m.title); same("styleId", m.styleId); same("folderId", m.folderId); same("parentDocId", m.parentDocId)
            if o["deletedAt"]?.double != m.deletedAt { diffs.append("\(id): trash state changed") }
            if m.spaceId == nil { diffs.append("\(id): no Space") }
        }
        let oldFolders = raw["folders"]?.items?.compactMap { $0.object.flatMap { o in o["id"]?.string.map { ($0, o["name"]?.string ?? "") } } } ?? []
        if oldFolders.map(\.0) != lib.folders.map(\.id) || oldFolders.map(\.1) != lib.folders.map(\.name) { diffs.append("Folders changed") }
        var n = 0
        for id in lib.docs.keys {
            let url = dir.appendingPathComponent("docs/\(id).json")
            guard let data = try? Data(contentsOf: url), let rawDoc = try? JSONDecoder().decode(JSONValue.self, from: data).object else { continue }
            n += 1
            let (doc, _, _) = try migrateDoc(data)
            guard let content = rawDoc["content"], let oldNode = try? JSONDecoder().decode(Node.self, from: JSONEncoder().encode(content)) else { diffs.append("\(id): content unreadable"); continue }
            var oldIds: [String] = [], newIds: [String] = []
            walk(oldNode) { if let i = $0.id { oldIds.append(i) } }
            walk(doc.content) { if let i = $0.id { newIds.append(i) } }
            if !oldIds.allSatisfy(Set(newIds).contains) { diffs.append("\(id): block ids changed") }
            if docPlainText(oldNode) != docPlainText(doc.content) { diffs.append("\(id): text changed") }
            func links(_ n: Node) -> [String] { var o: [String] = []; walk(n) { $0.marks?.forEach { m in if m.type == "docLink" || m.type == "link" { o.append(m.attrs?["docId"]?.string ?? m.attrs?["href"]?.string ?? "") } } }; return o }
            if links(oldNode) != links(doc.content) { diffs.append("\(id): links changed") }
            if rawDoc["appearance"]?.object?["styleId"]?.string != doc.appearance.styleId { diffs.append("\(id): style changed") }
        }
        return MigrationReport(from: from, to: librarySchemaVersion, documents: n, differences: diffs)
    }
}
