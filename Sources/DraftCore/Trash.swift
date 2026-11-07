import Foundation

/// Recently Deleted. Deleting moves a document *and its nested pages* to the trash by stamping
/// `deletedAt`; files stay on disk until purged, so restore is lossless.
public extension Library {
    static let trashRetentionDays: Double = 30

    func descendants(of id: String) -> [String] {
        var out: [String] = []
        func visit(_ p: String) { for m in docs.values where m.parentDocId == p { out.append(m.id); visit(m.id) } }
        visit(id)
        return out
    }

    var liveDocs: [DocMeta] { docs.values.filter { $0.deletedAt == nil } }
    var trashedDocs: [DocMeta] { docs.values.filter { $0.deletedAt != nil } }

    /// Trash a document and its live descendants; closes their tabs. Returns trashed ids.
    @discardableResult
    mutating func trash(_ id: String, at now: Double = nowMs()) -> [String] {
        guard docs[id]?.deletedAt == nil else { return [] }
        let ids = [id] + descendants(of: id).filter { docs[$0]?.deletedAt == nil }
        for i in ids { docs[i]?.deletedAt = now }
        tabs.removeAll { $0.view.kind == "doc" && ids.contains($0.view.docId ?? "") }
        if tabs.isEmpty || tabs[0].view.kind != "all" { tabs.insert(Tab(view: .all), at: 0) }
        if !tabs.contains(where: { $0.id == activeTabId }) { activeTabId = tabs[0].id }
        return ids
    }

    /// Restore a document and the descendants that were trashed with it. A page whose parent is
    /// still in the trash comes back as a top-level document so it stays reachable.
    @discardableResult
    mutating func restore(_ id: String) -> [String] {
        guard let stamp = docs[id]?.deletedAt else { return [] }
        let ids = [id] + descendants(of: id).filter { docs[$0]?.deletedAt == stamp }
        for i in ids { docs[i]?.deletedAt = nil }
        if let p = docs[id]?.parentDocId, docs[p] == nil || docs[p]?.deletedAt != nil { docs[id]?.parentDocId = nil }
        return ids
    }

    /// Trashed documents older than the retention period (with their trashed descendants).
    func expiredTrash(now: Double = nowMs()) -> [String] {
        let cutoff = now - Library.trashRetentionDays * 86_400_000
        return trashedDocs.filter { ($0.deletedAt ?? now) < cutoff }.map(\.id)
    }
}

public struct Snapshot: Hashable, Identifiable {
    public var id: String { url.lastPathComponent }
    public let url: URL
    public let savedAt: Double
}

/// Automatic local backups: `history/<docId>/<ms>.json`, at most one per interval while a
/// document is being edited, keeping the newest `keep`.
public extension Vault {
    static let snapshotInterval: Double = 10 * 60_000
    static let snapshotsKept = 30

    func historyDir(_ id: String) throws -> URL {
        _ = try docURL(id) // validates the id
        return dir.appendingPathComponent("history/\(id)", isDirectory: true)
    }

    func snapshots(_ id: String) -> [Snapshot] {
        guard let d = try? historyDir(id), let names = try? FileManager.default.contentsOfDirectory(atPath: d.path) else { return [] }
        return names.compactMap { n in Double(n.replacingOccurrences(of: ".json", with: "")).map { Snapshot(url: d.appendingPathComponent(n), savedAt: $0) } }
            .sorted { $0.savedAt > $1.savedAt }
    }

    /// Writes a snapshot when the newest one is older than the interval (or `force`) and the
    /// content differs. Returns true when one was written.
    @discardableResult
    func snapshotIfDue(_ doc: DocFile, now: Double = nowMs(), force: Bool = false) throws -> Bool {
        if isReadOnly { return false }
        let existing = snapshots(doc.id)
        if !force, let last = existing.first, now - last.savedAt < Vault.snapshotInterval { return false }
        let data = try DraftJSON.encode(doc)
        if let last = existing.first, let old = try? Data(contentsOf: last.url), old == data { return false }
        try Vault.writeAtomic(data, to: try historyDir(doc.id).appendingPathComponent("\(Int64(now)).json"))
        for s in snapshots(doc.id).dropFirst(Vault.snapshotsKept) { try? FileManager.default.removeItem(at: s.url) }
        return true
    }

    func loadSnapshot(_ s: Snapshot) throws -> DocFile { try Migrations.migrateDoc(Data(contentsOf: s.url)).doc }

    /// Permanently remove a document file and its backups.
    func purgeDoc(_ id: String) throws {
        try deleteDoc(id)
        if let h = try? historyDir(id), FileManager.default.fileExists(atPath: h.path) { try FileManager.default.removeItem(at: h) }
    }
}
