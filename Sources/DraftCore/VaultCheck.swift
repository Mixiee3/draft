import Foundation

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
        public var problemCount: Int { (libraryReadable ? 0 : 1) + missingDocFiles.count + strayDocFiles.count + unreadableDocs.count + missingAssets.count }
        public var isClean: Bool { problemCount == 0 && unusedAssets.isEmpty }
    }

    /// Asset ids a note refers to: image and file blocks, covers and uploaded backdrops.
    public static func assetIds(in doc: DocFile) -> Set<String> {
        var ids = Set<String>()
        walk(doc.content) { n in if let a = n.attrs?["assetId"]?.string { ids.insert(a) } }
        if let c = doc.appearance.cover?.assetId { ids.insert(c) }
        if let img = doc.appearance.overrides.backdrop?.image, img.hasPrefix("asset:") { ids.insert(String(img.dropFirst(6))) }
        return ids
    }

    public static func run(_ vault: Vault) -> Report {
        var r = Report()
        let fm = FileManager.default
        let lib: Library?
        do { lib = try vault.loadLibrary() } catch { r.libraryReadable = false; lib = nil }
        let docsDir = vault.dir.appendingPathComponent("docs")
        let files = Set(((try? fm.contentsOfDirectory(atPath: docsDir.path)) ?? []).filter { $0.hasSuffix(".json") }.map { String($0.dropLast(5)) })
        let listed = Set(lib?.docs.keys.map { $0 } ?? [])
        r.missingDocFiles = listed.subtracting(files).sorted()
        if lib != nil { r.strayDocFiles = files.subtracting(listed).sorted() }
        var used = Set<String>()
        for id in files.sorted() {
            r.docsChecked += 1
            guard let d = (try? vault.loadDoc(id)) ?? nil else { r.unreadableDocs.append(id); continue }
            used.formUnion(assetIds(in: d))
        }
        let assetsDir = vault.dir.appendingPathComponent("assets")
        let assets = Set((try? fm.contentsOfDirectory(atPath: assetsDir.path)) ?? []).filter { !$0.hasPrefix(".") }
        r.assetsChecked = assets.count
        r.missingAssets = used.subtracting(assets).sorted()
        // Unused only when every note was readable: a note that can't be read might use any file.
        if r.unreadableDocs.isEmpty && r.libraryReadable {
            r.unusedAssets = assets.subtracting(used).sorted()
            r.unusedBytes = r.unusedAssets.reduce(0) { $0 + ((try? fm.attributesOfItem(atPath: assetsDir.appendingPathComponent($1).path)[.size] as? Int64) ?? 0) }
        }
        return r
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
