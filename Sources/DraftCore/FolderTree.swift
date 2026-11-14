import Foundation

/// Display order for folders: each folder follows its parent, children appear only when the parent is
/// expanded, and a folder whose parent is missing is shown at the top so nothing disappears.
public enum FolderTree {
    public static func rows(_ folders: [Folder], expanded: Set<String>) -> [(folder: Folder, depth: Int)] {
        let all = folders.sorted { $0.order < $1.order }
        let ids = Set(all.map(\.id))
        var out: [(folder: Folder, depth: Int)] = []
        func add(_ parent: String?, _ depth: Int) {
            for f in all {
                let isRoot = f.parentId == nil || !ids.contains(f.parentId ?? "")
                guard parent == nil ? isRoot : f.parentId == parent else { continue }
                out.append((f, depth))
                if expanded.contains(f.id) { add(f.id, depth + 1) }
            }
        }
        add(nil, 0)
        return out
    }
}
