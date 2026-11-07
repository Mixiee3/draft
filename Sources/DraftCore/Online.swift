import Foundation

/// Opt-in online helpers. Nothing here performs a request: these build requests and read
/// responses, and the app sends them only when the user has turned the feature on.

public struct WebImage: Decodable, Hashable, Identifiable, Sendable {
    public var id: String
    public var title: String?
    public var url: String
    public var thumbnail: String?
    public var creator: String?
    public var license: String?
}

/// Openverse (openly licensed images, no account or key).
public enum OnlineImageSearch {
    public static let host = "api.openverse.org"

    public static func request(_ query: String) -> URLRequest? {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty, var c = URLComponents(string: "https://\(host)/v1/images/") else { return nil }
        c.queryItems = [URLQueryItem(name: "q", value: q), URLQueryItem(name: "page_size", value: "18"), URLQueryItem(name: "mature", value: "false")]
        guard let u = c.url else { return nil }
        var r = URLRequest(url: u, timeoutInterval: 15)
        r.setValue("Draft (local-first notes app)", forHTTPHeaderField: "User-Agent")
        return r
    }

    public static func parse(_ data: Data) throws -> [WebImage] {
        struct Page: Decodable { var results: [WebImage] }
        return try JSONDecoder().decode(Page.self, from: data).results.filter { $0.url.hasPrefix("https://") }
    }
}

public struct LinkPreview: Codable, Hashable, Sendable {
    public var url: String
    public var title: String
    public var summary: String?
    public var site: String
    public init(url: String, title: String, summary: String?, site: String) { self.url = url; self.title = title; self.summary = summary; self.site = site }
}

public enum LinkPreviews {
    /// A single web address on its own (what gets a preview card when pasted).
    public static func soleURL(_ text: String) -> URL? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.contains(where: \.isWhitespace), let u = URL(string: t), ["http", "https"].contains(u.scheme?.lowercased() ?? ""), u.host != nil else { return nil }
        return u
    }

    /// Title and description from Open Graph tags or `<title>` / meta description.
    public static func parse(html: String, url: URL) -> LinkPreview {
        func meta(_ names: [String]) -> String? {
            for n in names {
                for pattern in [#"<meta[^>]+(?:property|name)=["']\#(n)["'][^>]*content=["']([^"']*)["']"#, #"<meta[^>]+content=["']([^"']*)["'][^>]*(?:property|name)=["']\#(n)["']"#] {
                    if let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
                       let m = re.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)), let r = Range(m.range(at: 1), in: html) {
                        let v = decode(String(html[r]))
                        if !v.isEmpty { return v }
                    }
                }
            }
            return nil
        }
        var title = meta(["og:title", "twitter:title"])
        if title == nil, let re = try? NSRegularExpression(pattern: "<title[^>]*>(.*?)</title>", options: [.caseInsensitive, .dotMatchesLineSeparators]),
           let m = re.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)), let r = Range(m.range(at: 1), in: html) {
            title = decode(String(html[r]).trimmingCharacters(in: .whitespacesAndNewlines))
        }
        let site = meta(["og:site_name"]) ?? (url.host ?? "").replacingOccurrences(of: "www.", with: "")
        return LinkPreview(url: url.absoluteString, title: String((title?.isEmpty == false ? title! : site).prefix(200)), summary: meta(["og:description", "description"]).map { String($0.prefix(300)) }, site: site)
    }

    static func decode(_ s: String) -> String {
        s.replacingOccurrences(of: "&amp;", with: "&").replacingOccurrences(of: "&quot;", with: "\"").replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<").replacingOccurrences(of: "&gt;", with: ">")
    }
}
