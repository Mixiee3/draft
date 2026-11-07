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

    /// A parsed query: words and `"exact phrases"` must all appear, `-words` must not; in regex
    /// mode the whole query is one regular expression.
    public struct Query {
        public var include: [String] = []
        public var exclude: [String] = []
        public var regex: NSRegularExpression?
        public var isEmpty: Bool { include.isEmpty && regex == nil }
    }

    public struct QueryError: Error, Equatable { public let message: String; public init(message: String) { self.message = message } }

    public static func parse(_ q: String, regex: Bool = false) throws -> Query {
        var out = Query()
        if regex {
            guard !q.isEmpty else { return out }
            do { out.regex = try NSRegularExpression(pattern: q, options: [.caseInsensitive]) }
            catch { throw QueryError(message: "Invalid regular expression") }
            return out
        }
        var i = q.startIndex
        while i < q.endIndex {
            if q[i].isWhitespace { i = q.index(after: i); continue }
            var negate = false
            if q[i] == "-", q.index(after: i) < q.endIndex, !q[q.index(after: i)].isWhitespace { negate = true; i = q.index(after: i) }
            var word: String
            if q[i] == "\"", let close = q[q.index(after: i)...].firstIndex(of: "\"") {
                word = String(q[q.index(after: i)..<close]); i = q.index(after: close)
            } else {
                let end = q[i...].firstIndex(where: \.isWhitespace) ?? q.endIndex
                word = String(q[i..<end]); i = end
                if word.hasPrefix("\"") { word.removeFirst() } // unclosed quote: treat as a word
            }
            guard !word.isEmpty else { continue }
            if negate { out.exclude.append(word) } else { out.include.append(word) }
        }
        return out
    }

    /// Length of the index text kept per document in library.json.
    public static let indexLimit = 50_000

    /// `fullText` supplies the complete text of documents whose index text was cut at `indexLimit`.
    public static func hits(_ query: String, in docs: [DocMeta], fullText: ((DocMeta) -> String?)? = nil) -> [SearchHit] {
        (try? parse(query)).map { hits($0, in: docs, fullText: fullText) } ?? []
    }

    public static func hits(_ q: Query, in docs: [DocMeta], fullText: ((DocMeta) -> String?)? = nil) -> [SearchHit] {
        guard !q.isEmpty else { return [] }
        var out: [SearchHit] = []
        for var m in docs {
            if m.searchText.count >= indexLimit, let full = fullText?(m) { m.searchText = m.title + "\n" + full }
            let all = m.searchText.isEmpty ? m.title : m.searchText
            guard q.include.allSatisfy({ all.range(of: $0, options: options) != nil || m.title.range(of: $0, options: options) != nil }),
                  !q.exclude.contains(where: { all.range(of: $0, options: options) != nil || m.title.range(of: $0, options: options) != nil }) else { continue }
            let body = bodyText(m)
            if let re = q.regex {
                let ns = body as NSString
                let ms = re.matches(in: body, range: NSRange(location: 0, length: ns.length))
                let titleMatch = re.firstMatch(in: m.title, range: NSRange(location: 0, length: (m.title as NSString).length)) != nil
                guard !ms.isEmpty || titleMatch else { continue }
                let first = ms.first.flatMap { Range($0.range, in: body) }.map { String(body[$0]) }
                let (snip, r) = snippet(body, term: first)
                out.append(SearchHit(meta: m, count: ms.count, titleMatch: titleMatch, snippet: snip, snippetMatch: r))
                continue
            }
            let count = q.include.reduce(0) { $0 + occurrences(of: $1, in: body) }
            let titleMatch = q.include.contains { m.title.range(of: $0, options: options) != nil }
            let (snip, r) = snippet(body, term: q.include.first { body.range(of: $0, options: options) != nil })
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
