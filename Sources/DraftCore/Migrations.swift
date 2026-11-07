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
    ]

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
