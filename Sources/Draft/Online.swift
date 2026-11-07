import AppKit
import DraftCore

/// The only place Draft talks to the network, and only for features the user turned on.
@MainActor
final class OnlineServices {
    /// Requests sent this session (shown in Settings; used by checks).
    private(set) var requests = 0

    func linkPreview(_ url: URL, enabled: Bool, _ done: @escaping (LinkPreview?) -> Void) {
        guard enabled else { done(nil); return }
        requests += 1
        var r = URLRequest(url: url, timeoutInterval: 10)
        r.setValue("Draft (local-first notes app)", forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: r) { data, resp, _ in
            let html = data.flatMap { String(data: $0.prefix(400_000), encoding: .utf8) ?? String(data: $0.prefix(400_000), encoding: .isoLatin1) }
            let ok = (resp as? HTTPURLResponse).map { (200..<300).contains($0.statusCode) } ?? false
            let p = ok ? html.map { LinkPreviews.parse(html: $0, url: url) } : nil
            DispatchQueue.main.async { done(p) }
        }.resume()
    }

    func searchImages(_ q: String, enabled: Bool, _ done: @escaping (Result<[WebImage], Error>) -> Void) {
        struct Off: LocalizedError { var errorDescription: String? { "Online image search is off (Settings → Advanced)." } }
        guard enabled, let r = OnlineImageSearch.request(q) else { done(.failure(Off())); return }
        requests += 1
        URLSession.shared.dataTask(with: r) { data, _, err in
            let res: Result<[WebImage], Error> = data.map { d in Result { try OnlineImageSearch.parse(d) } } ?? .failure(err ?? Off())
            DispatchQueue.main.async { done(res) }
        }.resume()
    }

    func download(_ s: String, enabled: Bool, _ done: @escaping (Data?) -> Void) {
        guard enabled, let u = URL(string: s), u.scheme == "https" else { done(nil); return }
        requests += 1
        URLSession.shared.dataTask(with: u) { data, _, _ in DispatchQueue.main.async { done(data) } }.resume()
    }
}
