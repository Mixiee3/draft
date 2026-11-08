import Foundation
import CryptoKit

/// A downloadable open-weight model. Weights are fetched from the publisher at a pinned revision
/// and checked against `sha256` before Draft will load them.
public struct LocalModel: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let file: String
    public let url: URL
    public let sha256: String
    public let bytes: Int64
    public let parameters: String
    public let license: String
    public let licenseURL: URL
    public let source: URL
    /// Physical memory below which loading is refused.
    public let minimumMemory: UInt64

    public init(id: String, name: String, file: String, url: URL, sha256: String, bytes: Int64, parameters: String, license: String, licenseURL: URL, source: URL, minimumMemory: UInt64) {
        self.id = id; self.name = name; self.file = file; self.url = url; self.sha256 = sha256; self.bytes = bytes
        self.parameters = parameters; self.license = license; self.licenseURL = licenseURL; self.source = source; self.minimumMemory = minimumMemory
    }

    public static let lfm2_6 = LocalModel(
        id: "lfm2.5-2.6b-q4km", name: "LFM2.5 2.6B", file: "LFM2.5-2.6B-Q4_K_M.gguf",
        url: URL(string: "https://huggingface.co/LiquidAI/LFM2.5-2.6B-GGUF/resolve/e7caca5d835a3901a8e0d63e94009429bafafdfc/LFM2.5-2.6B-Q4_K_M.gguf")!,
        sha256: "02a8b7e17487d326e46d68ce0ba24211e1b80a14c4cd0597fa73c1cd697f52ed", bytes: 1_674_455_040,
        parameters: "2.6B, 4-bit (Q4_K_M)", license: "LFM Open License v1.0",
        licenseURL: URL(string: "https://huggingface.co/LiquidAI/LFM2.5-2.6B-GGUF/blob/e7caca5d835a3901a8e0d63e94009429bafafdfc/LICENSE")!,
        source: URL(string: "https://huggingface.co/LiquidAI/LFM2.5-2.6B-GGUF")!, minimumMemory: 8 << 30)

    public static let lfm1_2 = LocalModel(
        id: "lfm2.5-1.2b-q4km", name: "LFM2.5 1.2B Instruct", file: "LFM2.5-1.2B-Instruct-Q4_K_M.gguf",
        url: URL(string: "https://huggingface.co/LiquidAI/LFM2.5-1.2B-Instruct-GGUF/resolve/8ed288026e23958ad9dfa92d53ed773a8eee7125/LFM2.5-1.2B-Instruct-Q4_K_M.gguf")!,
        sha256: "b1b3de114215d9507409a662a501a631095a479a419584e8a2ded6304b19b4f5", bytes: 730_895_168,
        parameters: "1.2B, 4-bit (Q4_K_M)", license: "LFM Open License v1.0",
        licenseURL: URL(string: "https://huggingface.co/LiquidAI/LFM2.5-1.2B-Instruct-GGUF/blob/8ed288026e23958ad9dfa92d53ed773a8eee7125/LICENSE")!,
        source: URL(string: "https://huggingface.co/LiquidAI/LFM2.5-1.2B-Instruct-GGUF")!, minimumMemory: 4 << 30)

    public static let all = [lfm2_6, lfm1_2]
}

public enum ModelStoreError: LocalizedError, Equatable {
    case checksumMismatch(expected: String, actual: String)
    case wrongSize(expected: Int64, actual: Int64)
    case notEnoughDisk(needed: Int64, available: Int64)
    case http(Int)

    public var errorDescription: String? {
        switch self {
        case .checksumMismatch: return "The downloaded file did not match the published checksum, so it was deleted. Try again."
        case .wrongSize(let e, let a): return "The download was incomplete (\(ByteCountFormatter.string(fromByteCount: a, countStyle: .file)) of \(ByteCountFormatter.string(fromByteCount: e, countStyle: .file))). Try again."
        case .notEnoughDisk(let n, let a): return "Not enough free disk space: the model needs \(ByteCountFormatter.string(fromByteCount: n, countStyle: .file)), \(ByteCountFormatter.string(fromByteCount: a, countStyle: .file)) is free."
        case .http(let c): return "The model host answered with HTTP \(c). Try again later."
        }
    }
}

/// Where models live: `~/Library/Application Support/Draft/Models` (never in a vault or the repository).
public final class ModelStore: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    public let directory: URL
    private var session: URLSession!
    private var progress: ((Double) -> Void)?
    private var finish: ((Result<URL, Error>) -> Void)?
    private var task: URLSessionDownloadTask?
    private var model: LocalModel?

    public init(directory: URL? = nil, configuration: URLSessionConfiguration = .ephemeral) {
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Draft/Models", isDirectory: true)
        super.init()
        configuration.httpAdditionalHeaders = ["User-Agent": "Draft"]
        session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }

    public func path(for m: LocalModel) -> URL { directory.appendingPathComponent(m.file) }
    public func isInstalled(_ m: LocalModel) -> Bool {
        ((try? FileManager.default.attributesOfItem(atPath: path(for: m).path)[.size]) as? Int64) == m.bytes
    }

    public func remove(_ m: LocalModel) throws {
        if FileManager.default.fileExists(atPath: path(for: m).path) { try FileManager.default.removeItem(at: path(for: m)) }
    }

    /// Streams the file through SHA-256 so multi-gigabyte files never sit in memory.
    public static func verify(_ file: URL, sha256: String, bytes: Int64) throws {
        let size = ((try FileManager.default.attributesOfItem(atPath: file.path)[.size]) as? Int64) ?? -1
        guard size == bytes else { throw ModelStoreError.wrongSize(expected: bytes, actual: size) }
        let h = try FileHandle(forReadingFrom: file)
        defer { try? h.close() }
        var hasher = SHA256()
        while let chunk = try h.read(upToCount: 8 << 20), !chunk.isEmpty { hasher.update(data: chunk) }
        let actual = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        guard actual == sha256.lowercased() else { throw ModelStoreError.checksumMismatch(expected: sha256, actual: actual) }
    }

    /// Downloads, verifies, then moves the file into place. The request carries no note data:
    /// it is a plain GET of the pinned URL.
    public func download(_ m: LocalModel, from url: URL? = nil, progress: @escaping (Double) -> Void, completion: @escaping (Result<URL, Error>) -> Void) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let free = (try? directory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage) ?? Int64.max
        if free < m.bytes + (256 << 20) { completion(.failure(ModelStoreError.notEnoughDisk(needed: m.bytes, available: free))); return }
        model = m; self.progress = progress; finish = completion
        task = session.downloadTask(with: URLRequest(url: url ?? m.url))
        task?.resume()
    }

    public func cancel() { task?.cancel(); task = nil }

    public func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData _: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        let total = totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : (model?.bytes ?? 1)
        progress?(min(1, Double(totalBytesWritten) / Double(total)))
    }

    public func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let m = model else { return }
        let result: Result<URL, Error>
        do {
            if let r = downloadTask.response as? HTTPURLResponse, !(200..<300).contains(r.statusCode) { throw ModelStoreError.http(r.statusCode) }
            let partial = directory.appendingPathComponent(m.file + ".partial")
            try? FileManager.default.removeItem(at: partial)
            try FileManager.default.moveItem(at: location, to: partial)
            do { try Self.verify(partial, sha256: m.sha256, bytes: m.bytes) } catch { try? FileManager.default.removeItem(at: partial); throw error }
            try? FileManager.default.removeItem(at: path(for: m))
            try FileManager.default.moveItem(at: partial, to: path(for: m))
            result = .success(path(for: m))
        } catch { result = .failure(error) }
        let f = finish; finish = nil; f?(result)
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error, let f = finish else { return }
        finish = nil
        f(.failure(error))
    }
}

public enum SystemMemory {
    public static var physical: UInt64 { ProcessInfo.processInfo.physicalMemory }

    /// Free plus reclaimable (inactive, purgeable) memory right now.
    public static var available: UInt64 {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let r = withUnsafeMutablePointer(to: &stats) { $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count) } }
        guard r == KERN_SUCCESS else { return physical / 2 }
        let page = UInt64(vm_kernel_page_size)
        return UInt64(stats.free_count + stats.inactive_count + stats.purgeable_count + stats.speculative_count) * page
    }

    /// This process's memory footprint, the figure Activity Monitor shows.
    public static var footprint: UInt64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let r = withUnsafeMutablePointer(to: &info) { $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count) } }
        return r == KERN_SUCCESS ? info.phys_footprint : 0
    }
}
