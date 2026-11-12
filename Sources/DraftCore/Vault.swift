import Foundation
import CryptoKit

/// The on-disk vault — plain files the user owns:
///
///     <vault>/library.json          index: folders, document metadata, tabs, settings
///     <vault>/docs/<docId>.json     one file per document (content + appearance)
///     <vault>/assets/<sha256>.<ext> content-addressed images and covers
///     <vault>/backups/              copies written before any schema migration
///
/// Every write is atomic (temp file in the same directory + rename), so a crash never leaves
/// a torn file. Files from a newer schema put the vault in read-only mode instead of being
/// overwritten.
public final class Vault: @unchecked Sendable {
    public let dir: URL
    public private(set) var readOnlyReason: String?
    public var isReadOnly: Bool { readOnlyReason != nil }
    private let fm = FileManager.default

    public static let mimeExt: [String: String] = [
        "image/png": "png", "image/jpeg": "jpg", "image/gif": "gif", "image/webp": "webp", "image/heic": "heic", "image/tiff": "tiff",
    ]

    public init(dir: URL) { self.dir = dir; writer.setSpecific(key: Vault.onWriter, value: true) }

    private let writer = DispatchQueue(label: "draft.vault.writer", qos: .userInitiated)
    private static let onWriter = DispatchSpecificKey<Bool>()

    /// Runs a write on the vault's serial queue, so encoding and disk I/O stay off the main thread.
    /// Writes keep their order; `failed` runs on the main queue.
    public func enqueue(_ work: @escaping @Sendable () throws -> Void, failed: @escaping @Sendable (Error) -> Void) {
        writer.async { do { try work() } catch { DispatchQueue.main.async { failed(error) } } }
    }

    /// Waits for queued writes. Every read calls it, so a read never sees an older file.
    public func drain() { if DispatchQueue.getSpecific(key: Vault.onWriter) != true { writer.sync {} } }

    public static func defaultURL() -> URL {
        if let env = ProcessInfo.processInfo.environment["DRAFT_DATA_DIR"], !env.isEmpty { return URL(fileURLWithPath: env) }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Draft/Vault", isDirectory: true)
    }

    var libraryURL: URL { dir.appendingPathComponent("library.json") }
    public func docURL(_ id: String) throws -> URL {
        guard id.range(of: "^[A-Za-z0-9_-]{1,64}$", options: .regularExpression) != nil else { throw MigrationError(message: "Invalid document id") }
        return dir.appendingPathComponent("docs/\(id).json")
    }
    public func assetURL(_ name: String) throws -> URL {
        guard name.range(of: "^[a-f0-9]{16,64}\\.[a-z0-9]{1,10}$", options: .regularExpression) != nil else { throw MigrationError(message: "Invalid asset id") }
        return dir.appendingPathComponent("assets/\(name)")
    }

    public func prepare() throws {
        try fm.createDirectory(at: dir.appendingPathComponent("docs"), withIntermediateDirectories: true)
        try fm.createDirectory(at: dir.appendingPathComponent("assets"), withIntermediateDirectories: true)
    }

    public static func writeAtomic(_ data: Data, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        // Data.write(.atomic) writes to a temporary file and renames it into place.
        try data.write(to: url, options: [.atomic])
    }

    private func backup(_ name: String, _ data: Data) throws {
        let f = ISO8601DateFormatter()
        let stamp = f.string(from: Date()).replacingOccurrences(of: ":", with: "-")
        try Vault.writeAtomic(data, to: dir.appendingPathComponent("backups/\(stamp)-\(name)"))
    }

    /// After an approved repair: writes are allowed again (a newer schema still blocks them on load).
    public func reopen() { readOnlyReason = nil }

    /// Safe Mode, or continuing after a problem: everything is read, nothing is written.
    public func openReadOnly(_ reason: String) { readOnlyReason = reason }

    private func guardWritable() throws {
        if let r = readOnlyReason { throw MigrationError(message: r) }
    }

    /// Returns nil on first run (no library yet).
    public func loadLibrary() throws -> Library? {
        drain()
        guard fm.fileExists(atPath: libraryURL.path) else { return nil }
        let data = try Data(contentsOf: libraryURL)
        do {
            let (lib, migrated, from) = try Migrations.migrateLibrary(data)
            if migrated {
                // Never migrate on trust: a dry run must show nothing but the intended change.
                let report = try Migrations.dryRun(vault: dir)
                guard report.ok else {
                    readOnlyReason = "Draft did not update this vault because a check found a difference (\(report.differences.first ?? "")). Nothing was changed."
                    throw MigrationError(message: readOnlyReason!)
                }
                try backup("library.v\(from).json", data)
                try Vault.writeAtomic(try DraftJSON.encode(lib, pretty: true), to: libraryURL)
            }
            return lib
        } catch let e as NewerSchemaError {
            readOnlyReason = e.localizedDescription
            throw e
        } catch {
            // Never overwrite an unreadable library: keep a copy and refuse writes.
            try? backup("library.unreadable.json", data)
            readOnlyReason = "library.json could not be read (\(error.localizedDescription)). A copy was saved in backups/."
            throw error
        }
    }

    public func saveLibrary(_ lib: Library) throws {
        try guardWritable()
        try Vault.writeAtomic(try DraftJSON.encode(lib, pretty: true), to: libraryURL)
    }

    var indexURL: URL { dir.appendingPathComponent("index/index.json") }

    /// The derived link/tag/task index; nil when missing or unreadable (it is then rebuilt).
    public func loadIndex() -> VaultIndex? {
        drain()
        guard let data = try? Data(contentsOf: indexURL) else { return nil }
        return try? JSONDecoder().decode(VaultIndex.self, from: data)
    }

    public func saveIndex(_ idx: VaultIndex) throws {
        guard !isReadOnly else { return }
        try Vault.writeAtomic(try JSONEncoder().encode(idx), to: indexURL)
    }

    public func loadDoc(_ id: String) throws -> DocFile? {
        drain()
        let url = try docURL(id)
        guard fm.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        do {
            let (doc, migrated, from) = try Migrations.migrateDoc(data)
            if migrated && !isReadOnly {
                try backup("doc-\(id).v\(from).json", data)
                try Vault.writeAtomic(try DraftJSON.encode(doc), to: url)
            }
            return doc
        } catch let e as NewerSchemaError {
            readOnlyReason = e.localizedDescription
            throw e
        }
    }

    /// A document's look without decoding its content (galleries and page cards need only the cover).
    public func peekAppearance(_ id: String) -> DocumentAppearance? {
        struct Look: Decodable { var appearance: DocumentAppearance }
        drain()
        guard let url = try? docURL(id), let data = try? Data(contentsOf: url) else { return nil }
        return (try? JSONDecoder().decode(Look.self, from: data))?.appearance
    }

    public func saveDoc(_ doc: DocFile) throws {
        try guardWritable()
        try Vault.writeAtomic(try DraftJSON.encode(doc), to: try docURL(doc.id))
    }

    public func deleteDoc(_ id: String) throws {
        try guardWritable()
        let url = try docURL(id)
        if fm.fileExists(atPath: url.path) { try fm.removeItem(at: url) }
    }

    /// Content-addressed: identical images are stored once. Returns the asset id (file name).
    public func putAsset(_ data: Data, ext rawExt: String) throws -> String {
        try guardWritable()
        let cleaned = rawExt.lowercased().filter { $0.isASCII && ($0.isLetter || $0.isNumber) }
        let ext = cleaned.isEmpty ? "bin" : String(cleaned.prefix(10))
        let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined().prefix(32)
        let name = "\(hash).\(ext.lowercased())"
        let url = try assetURL(name)
        if !fm.fileExists(atPath: url.path) { try Vault.writeAtomic(data, to: url) }
        return name
    }

    /// Write an export bundle into a new folder `name` inside `parent`; never overwrites.
    public func writeExport(parent: URL, name: String, files: [(path: String, content: String)], assets: [String]) throws -> URL {
        var target = parent.appendingPathComponent(name, isDirectory: true)
        var i = 2
        while fm.fileExists(atPath: target.path) {
            target = parent.appendingPathComponent("\(name) \(i)", isDirectory: true); i += 1
        }
        let root = target.standardizedFileURL.path
        for f in files {
            let dest = target.appendingPathComponent(f.path).standardizedFileURL
            guard dest.path.hasPrefix(root + "/") else { throw MigrationError(message: "Export path escapes target folder") }
            try Vault.writeAtomic(Data(f.content.utf8), to: dest)
        }
        for a in Set(assets) {
            let dest = target.appendingPathComponent("assets/\(a)")
            try fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fm.copyItem(at: try assetURL(a), to: dest)
        }
        return target
    }
}
