import Foundation

/// Space-wide search over the library index: every term must match the title or text.
/// One result per document with a match count and a snippet around the first body match.
public struct SearchHit: Identifiable {
    public var id: String { meta.id }
    public let meta: DocMeta
    public let count: Int
    public let titleMatch: Bool
    /// Snippet and the range of the match inside it (for highlighting).
    public let snippet: String
    public let snippetMatch: Range<String.Index>?
}

public enum Search {
    static let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]

    public static func terms(_ query: String) -> [String] {
        query.split(whereSeparator: { $0.isWhitespace }).map(String.init)
    }

    /// Length of the index text kept per document in library.json.
    public static let indexLimit = 50_000

    /// `fullText` supplies the complete text of documents whose index text was cut at `indexLimit`.
    public static func hits(_ query: String, in docs: [DocMeta], fullText: ((DocMeta) -> String?)? = nil) -> [SearchHit] {
        let ts = terms(query)
        guard !ts.isEmpty else { return [] }
        var out: [SearchHit] = []
        for var m in docs {
            if m.searchText.count >= indexLimit, let full = fullText?(m) { m.searchText = m.title + "\n" + full }
            guard ts.allSatisfy({ m.searchText.range(of: $0, options: options) != nil || m.title.range(of: $0, options: options) != nil }) else { continue }
            let body = bodyText(m)
            let count = ts.reduce(0) { $0 + occurrences(of: $1, in: body) }
            let titleMatch = ts.contains { m.title.range(of: $0, options: options) != nil }
            let (snip, r) = snippet(body, term: ts.first { body.range(of: $0, options: options) != nil })
            out.append(SearchHit(meta: m, count: count, titleMatch: titleMatch, snippet: snip, snippetMatch: r))
        }
        return out.sorted { a, b in
            if a.titleMatch != b.titleMatch { return a.titleMatch }
            if a.count != b.count { return a.count > b.count }
            return a.meta.updatedAt > b.meta.updatedAt
        }
    }

    /// The body part of the index text (the title is its first line).
    static func bodyText(_ m: DocMeta) -> String {
        guard let nl = m.searchText.firstIndex(of: "\n") else { return "" }
        return String(m.searchText[m.searchText.index(after: nl)...])
    }

    static func occurrences(of term: String, in text: String) -> Int {
        var n = 0
        var r = text.startIndex..<text.endIndex
        while let f = text.range(of: term, options: options, range: r) { n += 1; r = f.upperBound..<text.endIndex }
        return n
    }

    static func snippet(_ text: String, term: String?, radius: Int = 60) -> (String, Range<String.Index>?) {
        let flat = text.replacingOccurrences(of: "\n", with: " ")
        guard let term, let r = flat.range(of: term, options: options) else { return (String(flat.prefix(radius * 2)), nil) }
        let start = flat.index(r.lowerBound, offsetBy: -radius, limitedBy: flat.startIndex) ?? flat.startIndex
        let end = flat.index(r.upperBound, offsetBy: radius, limitedBy: flat.endIndex) ?? flat.endIndex
        let prefix = start > flat.startIndex ? "…" : ""
        let s = prefix + String(flat[start..<end]) + (end < flat.endIndex ? "…" : "")
        let lo = s.index(s.startIndex, offsetBy: prefix.count + flat.distance(from: start, to: r.lowerBound))
        let hi = s.index(lo, offsetBy: flat.distance(from: r.lowerBound, to: r.upperBound))
        return (s, lo..<hi)
    }
}
