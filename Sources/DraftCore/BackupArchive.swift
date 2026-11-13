import Foundation
import CryptoKit

/// A complete, portable backup of a vault in one `.zip`: library.json (with settings), notes,
/// attachments, versions and backups, plus `manifest.json` with Draft's version, the schemas and the
/// size and SHA-256 of every file. The derived index and system files (.DS_Store, temp files) are left
/// out. Restoring extracts into a new folder, checks every file against the manifest and runs Vault
/// Check — it never writes over a vault.
public enum BackupArchive {
    public struct Manifest: Codable, Equatable, Sendable {
        public var format = 1
        public var appVersion: String
        public var librarySchema: Int
        public var docSchema: Int
        public var createdAt: String
        public var files: [Entry]
        public struct Entry: Codable, Equatable, Sendable { public var path: String; public var size: Int64; public var sha256: String }
    }

    static let included = ["library.json", "docs", "assets", "history", "backups", "agent-requests", "assistant"]

    /// Paths (relative) that belong in the archive.
    public static func files(in vault: URL) -> [String] {
        let fm = FileManager.default
        var out: [String] = []
        for top in included {
            let u = vault.appendingPathComponent(top)
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: u.path, isDirectory: &isDir) else { continue }
            if !isDir.boolValue { out.append(top); continue }
            for case let f as URL in fm.enumerator(at: u, includingPropertiesForKeys: [.isRegularFileKey]) ?? FileManager.DirectoryEnumerator() {
                let name = f.lastPathComponent
                guard (try? f.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true, name != ".DS_Store", !name.hasPrefix(".") else { continue }
                out.append(String(f.standardizedFileURL.path.dropFirst(vault.standardizedFileURL.path.count + 1)))
            }
        }
        return out.sorted()
    }

    static func sha(_ url: URL) throws -> String { SHA256.hash(data: try Data(contentsOf: url)).map { String(format: "%02x", $0) }.joined() }

    /// Writes `Draft Backup <time>.zip` into `folder` and returns it.
    @discardableResult
    public static func create(vault: Vault, into folder: URL, appVersion: String, now: Date = Date()) throws -> URL {
        vault.drain()
        let fm = FileManager.default
        let stamp = ISO8601DateFormatter().string(from: now).replacingOccurrences(of: ":", with: "-")
        let name = "Draft Backup \(stamp)"
        let stage = fm.temporaryDirectory.appendingPathComponent("draft-archive-\(UUID().uuidString)/\(name)", isDirectory: true)
        defer { try? fm.removeItem(at: stage.deletingLastPathComponent()) }
        var entries: [Manifest.Entry] = []
        for rel in files(in: vault.dir) {
            let src = vault.dir.appendingPathComponent(rel), dst = stage.appendingPathComponent("vault/\(rel)")
            try fm.createDirectory(at: dst.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fm.copyItem(at: src, to: dst)
            entries.append(.init(path: rel, size: Int64((try? fm.attributesOfItem(atPath: dst.path)[.size] as? Int) ?? 0), sha256: try sha(dst)))
        }
        let f = ISO8601DateFormatter()
        let m = Manifest(appVersion: appVersion, librarySchema: librarySchemaVersion, docSchema: docSchemaVersion, createdAt: f.string(from: now), files: entries)
        try DraftJSON.encode(m, pretty: true).write(to: stage.appendingPathComponent("manifest.json"))
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        let zip = folder.appendingPathComponent(name + ".zip")
        try ditto(["-c", "-k", "--keepParent", stage.path, zip.path])
        return zip
    }

    public struct Restored: Sendable { public var vault: URL; public var manifest: Manifest; public var check: VaultCheck.Report }

    /// Extracts into `folder/<archive name>/vault`, verifies every file and checks the vault. Throws
    /// (and leaves nothing behind) if a file is missing or changed.
    public static func restore(_ zip: URL, into folder: URL) throws -> Restored {
        let fm = FileManager.default
        let out = folder.appendingPathComponent(zip.deletingPathExtension().lastPathComponent + " (restored)", isDirectory: true)
        guard !fm.fileExists(atPath: out.path) else { throw MigrationError(message: String(localized: "A restored copy is already there: \(out.lastPathComponent).")) }
        let tmp = fm.temporaryDirectory.appendingPathComponent("draft-restore-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: tmp) }
        try ditto(["-x", "-k", zip.path, tmp.path])
        guard let root = try fm.contentsOfDirectory(at: tmp, includingPropertiesForKeys: nil).first(where: { fm.fileExists(atPath: $0.appendingPathComponent("manifest.json").path) }),
              let m = try? JSONDecoder().decode(Manifest.self, from: Data(contentsOf: root.appendingPathComponent("manifest.json"))) else {
            throw MigrationError(message: String(localized: "This isn't a Draft backup archive (no manifest)."))
        }
        let v = root.appendingPathComponent("vault")
        for e in m.files {
            guard !e.path.contains(".."), fm.fileExists(atPath: v.appendingPathComponent(e.path).path), try sha(v.appendingPathComponent(e.path)) == e.sha256 else {
                throw MigrationError(message: String(localized: "The archive is damaged: \(e.path) is missing or changed. Nothing was restored."))
            }
        }
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        try fm.moveItem(at: v, to: out)
        return Restored(vault: out, manifest: m, check: VaultCheck.run(Vault(dir: out)))
    }

    static func ditto(_ args: [String]) throws {
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/ditto"); p.arguments = args
        p.standardError = Pipe(); p.standardOutput = Pipe()
        try p.run(); p.waitUntilExit()
        guard p.terminationStatus == 0 else { throw MigrationError(message: "ditto failed (\(p.terminationStatus))") }
    }
}
