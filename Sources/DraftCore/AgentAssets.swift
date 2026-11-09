import Foundation
import CryptoKit

/// What an agent may ask Draft to copy into a note. The file is only read here; nothing enters the
/// vault until the user applies the proposal.
public enum AgentAsset {
    public static let imageTypes: Set<String> = ["png", "jpg", "jpeg", "gif", "heic", "webp", "tiff", "tif"]
    public static let fileTypes: Set<String> = ["pdf", "txt", "md", "csv", "rtf", "json", "docx", "xlsx", "pptx", "pages", "numbers", "key", "zip", "mp3", "m4a", "mp4", "mov"]
    public static let imageLimit = 25 * 1024 * 1024
    public static let fileLimit = 100 * 1024 * 1024

    public struct Info: Equatable, Sendable {
        public var url: URL
        public var name: String
        public var ext: String
        public var isImage: Bool
        public var size: Int
        public var sha256: String
    }

    public static func check(path: String, as action: String) throws -> Info {
        guard path.hasPrefix("/") else { throw AgentEditError.invalid("Give the file's full path (starting with /).") }
        let url = URL(fileURLWithPath: path).standardizedFileURL
        let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey, .isPackageKey])
        guard FileManager.default.fileExists(atPath: url.path), let v = values else { throw AgentEditError.invalid("There's no file at \(path).") }
        guard v.isSymbolicLink != true, v.isRegularFile == true, v.isPackage != true else { throw AgentEditError.invalid("\(url.lastPathComponent) isn't a plain file (links, folders and app bundles aren't copied).") }
        let ext = url.pathExtension.lowercased()
        let image = imageTypes.contains(ext)
        if action == "insert_image" {
            guard image else { throw AgentEditError.invalid("“\(url.lastPathComponent)” isn't an image Draft accepts (\(imageTypes.sorted().joined(separator: ", "))).") }
        } else {
            guard image || fileTypes.contains(ext) else { throw AgentEditError.invalid("Draft doesn't attach .\(ext.isEmpty ? "(none)" : ext) files from agents. Allowed: \(fileTypes.union(imageTypes).sorted().joined(separator: ", ")).") }
        }
        let size = v.fileSize ?? 0
        let limit = action == "insert_image" ? imageLimit : fileLimit
        guard size <= limit else { throw AgentEditError.invalid("“\(url.lastPathComponent)” is \(size / 1_048_576) MB; the limit is \(limit / 1_048_576) MB.") }
        guard size > 0, let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { throw AgentEditError.invalid("“\(url.lastPathComponent)” is empty or can't be read.") }
        let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        return Info(url: url, name: url.lastPathComponent, ext: ext, isImage: image, size: size, sha256: hash)
    }
}
