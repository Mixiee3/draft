import Foundation

public enum AssistantProvider: String, Codable, CaseIterable, Sendable {
    case local, openai
    public var title: String { self == .local ? "On This Mac" : "OpenAI API" }
}

public struct ChatTurn: Hashable, Sendable {
    public var role: String
    public var text: String
    public init(_ role: String, _ text: String) { self.role = role; self.text = text }
}

public enum AssistantAction: String, Codable, CaseIterable, Sendable {
    case ask, summarize, explain, rewrite, shorten, expand, outline

    public var title: String {
        switch self {
        case .ask: return "Ask"
        case .summarize: return "Summarize"
        case .explain: return "Explain"
        case .rewrite: return "Rewrite"
        case .shorten: return "Shorten"
        case .expand: return "Expand"
        case .outline: return "Draft an Outline"
        }
    }

    /// Results meant to go back into the note (shown as a preview first).
    public var producesText: Bool { [.rewrite, .shorten, .expand, .outline, .summarize].contains(self) }

    var instruction: String {
        switch self {
        case .ask: return ""
        case .summarize: return "Summarize the text below in a few short bullet points. Keep names, numbers and decisions exact."
        case .explain: return "Explain the text below in plain language for someone new to the topic. Keep it short."
        case .rewrite: return "Rewrite the text below so it reads clearly and naturally. Keep its meaning, facts, Markdown structure (headings, lists, tasks, links) and language. Return only the rewritten text."
        case .shorten: return "Make the text below about half as long. Keep its meaning, key facts, Markdown structure and language. Return only the shortened text."
        case .expand: return "Expand the text below with more detail and smoother transitions, without inventing facts, names or numbers. Keep its Markdown structure and language. Return only the expanded text."
        case .outline: return "Draft a Markdown outline (headings and bullet points) for a document about the text below. Return only the outline."
        }
    }
}

public enum AssistantScope: String, Codable, CaseIterable, Sendable {
    case selection, document, space

    public var title: String {
        switch self {
        case .selection: return "Selected Text"
        case .document: return "This Document"
        case .space: return "This Space"
        }
    }
}

/// One numbered piece of context the model saw: a block of a document.
public struct AssistantSource: Codable, Hashable, Identifiable, Sendable {
    public var n: Int
    public var docId: String
    public var blockId: String?
    public var title: String
    public var text: String
    public var id: Int { n }
    public init(n: Int, docId: String, blockId: String?, title: String, text: String) {
        self.n = n; self.docId = docId; self.blockId = blockId; self.title = title; self.text = text
    }
}

public struct AssistantRequest: Sendable {
    public var action: AssistantAction
    public var scope: AssistantScope
    public var question: String
    /// Markdown of the selection or the whole document (for `.selection` / `.document`).
    public var text: String
    public var docId: String?
    public var docTitle: String
    /// Retrieved blocks for `.space`, best first.
    public var retrieved: [AssistantSource]
    public init(action: AssistantAction, scope: AssistantScope, question: String = "", text: String = "", docId: String? = nil, docTitle: String = "", retrieved: [AssistantSource] = []) {
        self.action = action; self.scope = scope; self.question = question; self.text = text; self.docId = docId; self.docTitle = docTitle; self.retrieved = retrieved
    }
}

public struct PreparedPrompt: Sendable {
    public var turns: [ChatTurn]
    public var sources: [AssistantSource]
    /// Share of the document or selection the model could read (1 = all of it).
    public var includedFraction: Double
}

public enum AssistantPrompt {
    /// About 3.5 characters per token for English prose; the engine counts exactly before running.
    public static let charsPerToken = 3.5

    static let system = """
    You are the writing assistant inside Draft, a notes app. You run on this Mac and only see the notes given to you below.
    Use only those notes for facts. When notes are numbered like [1], cite the ones you used with their numbers in square brackets.
    If the notes do not contain the answer, say you could not find it in these notes instead of guessing.
    Write in the same language as the notes. Be concise.
    """

    /// Builds the conversation for the model within `budgetTokens` of context (sources, history and question).
    public static func prepare(_ r: AssistantRequest, history: [ChatTurn] = [], budgetTokens: Int = 5000) -> PreparedPrompt {
        let budget = Int(Double(budgetTokens) * charsPerToken)
        var sources: [AssistantSource] = []
        var body: String
        var fraction = 1.0
        let question = r.question.trimmingCharacters(in: .whitespacesAndNewlines)

        switch r.scope {
        case .space:
            var used = 0
            var parts: [String] = []
            for s in r.retrieved {
                let entry = "[\(sources.count + 1)] \(s.title.isEmpty ? "Untitled" : s.title): \(s.text)"
                if used + entry.count > budget { break }
                used += entry.count
                var s = s; s.n = sources.count + 1
                sources.append(s); parts.append(entry)
            }
            body = parts.isEmpty ? "(No matching notes were found in this Space.)" : "Notes from this Space:\n" + parts.joined(separator: "\n\n")
        case .selection, .document:
            var text = r.text
            if text.count > budget {
                fraction = Double(budget) / Double(text.count)
                text = String(text.prefix(budget))
                if let cut = text.range(of: "\n", options: .backwards), text.distance(from: text.startIndex, to: cut.lowerBound) > budget / 2 { text = String(text[..<cut.lowerBound]) }
            }
            let label = r.scope == .selection ? "Selected text" : "Document"
            if let d = r.docId { sources = [AssistantSource(n: 1, docId: d, blockId: nil, title: r.docTitle, text: String(text.prefix(280)))] }
            let name = "“\(r.docTitle.isEmpty ? "Untitled" : r.docTitle)”\(fraction < 1 ? " (only the first part fits)" : "")"
            body = r.action.producesText
                ? "\(label) from \(name), between the markers:\n<<<\n\(text)\n>>>"
                : "[1] \(label) \(name):\n\(text)"
        }

        var task: String
        switch r.action {
        case .ask: task = question.isEmpty ? "What are the main points?" : question
        default: task = r.action.instruction + (question.isEmpty ? "" : "\nAlso: \(question)")
        }
        let historyBudget = max(0, budget / 4)
        var kept: [ChatTurn] = []
        var used = 0
        for t in history.reversed() {
            let c = min(t.text.count, 1200)
            if used + c > historyBudget { break }
            used += c
            kept.insert(ChatTurn(t.role, String(t.text.prefix(1200))), at: 0)
        }
        let turns = [ChatTurn("system", system)] + kept + [ChatTurn("user", body + "\n\n" + task)]
        return PreparedPrompt(turns: turns, sources: sources, includedFraction: fraction)
    }
}

/// Finds the blocks of a Space that best match a question, from the vault index (BM25 over block
/// text, with the document title counted as part of every block).
public enum Retrieval {
    public struct Hit: Hashable, Sendable { public var docId: String; public var blockId: String; public var score: Double; public var text: String }

    static let stop: Set<String> = ["the", "a", "an", "and", "or", "of", "to", "in", "on", "for", "is", "are", "was", "were", "be", "it", "this", "that", "with", "as", "at", "by", "from", "what", "which", "who", "how", "when", "where", "why", "do", "does", "did", "my", "i", "me", "we", "our", "you", "your", "about", "can", "should", "there", "have", "has", "had", "not", "no", "any", "all", "der", "die", "das", "und"]

    public static func terms(_ s: String) -> [String] {
        s.lowercased().folding(options: .diacriticInsensitive, locale: nil)
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
            .filter { $0.count > 1 && !stop.contains($0) }
            .map { $0.count > 4 && $0.hasSuffix("s") ? String($0.dropLast()) : $0 }
    }

    public static func rank(_ query: String, entries: [String: DocIndexEntry], titles: [String: String], limit: Int = 8, perDoc: Int = 3) -> [Hit] {
        let q = Set(terms(query))
        guard !q.isEmpty else { return [] }
        struct B { let doc: String; let id: String; let text: String; let tf: [String: Int]; let len: Int }
        var blocks: [B] = []
        for (doc, e) in entries {
            let title = terms(titles[doc] ?? "")
            for b in e.blocks where !b.id.isEmpty {
                let t = terms(b.text) + title
                var tf: [String: Int] = [:]
                for w in t where q.contains(w) { tf[w, default: 0] += 1 }
                blocks.append(B(doc: doc, id: b.id, text: b.text, tf: tf, len: t.count))
            }
        }
        guard !blocks.isEmpty else { return [] }
        let n = Double(blocks.count)
        let avg = Double(blocks.reduce(0) { $0 + $1.len }) / n
        var df: [String: Double] = [:]
        for b in blocks { for w in b.tf.keys { df[w, default: 0] += 1 } }
        let k1 = 1.2, bb = 0.75
        var hits: [Hit] = []
        for b in blocks where !b.tf.isEmpty {
            var s = 0.0
            for (w, f) in b.tf {
                let idf = log(1 + (n - df[w]! + 0.5) / (df[w]! + 0.5))
                let tf = Double(f)
                s += idf * tf * (k1 + 1) / (tf + k1 * (1 - bb + bb * Double(b.len) / max(1, avg)))
            }
            s *= 1 + Double(b.tf.count - 1) * 0.25
            hits.append(Hit(docId: b.doc, blockId: b.id, score: s, text: b.text))
        }
        hits.sort { $0.score != $1.score ? $0.score > $1.score : ($0.docId, $0.blockId) < ($1.docId, $1.blockId) }
        var perDocCount: [String: Int] = [:]
        return Array(hits.filter { h in perDocCount[h.docId, default: 0] += 1; return perDocCount[h.docId]! <= perDoc }.prefix(limit))
    }
}

public enum Citations {
    /// Source numbers cited as `[2]`, `[1, 3]` or `[1][2]`, in order of first use, limited to real sources.
    public static func cited(in answer: String, sourceCount: Int) -> [Int] {
        guard sourceCount > 0, let re = try? NSRegularExpression(pattern: #"\[(\d+(?:\s*[,;]\s*\d+)*)\]"#) else { return [] }
        var out: [Int] = []
        for m in re.matches(in: answer, range: NSRange(answer.startIndex..., in: answer)) {
            guard let r = Range(m.range(at: 1), in: answer) else { continue }
            for p in answer[r].split(whereSeparator: { $0 == "," || $0 == ";" }) {
                if let n = Int(p.trimmingCharacters(in: .whitespaces)), (1...sourceCount).contains(n), !out.contains(n) { out.append(n) }
            }
        }
        return out
    }
}

public struct AssistantMessage: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var role: String
    public var text: String
    public var action: AssistantAction?
    public var scope: AssistantScope?
    public var sources: [AssistantSource]?
    public var createdAt: Double
    public var failed: Bool?
    public init(id: String = newId("m_"), role: String, text: String, action: AssistantAction? = nil, scope: AssistantScope? = nil, sources: [AssistantSource]? = nil, createdAt: Double = nowMs(), failed: Bool? = nil) {
        self.id = id; self.role = role; self.text = text; self.action = action; self.scope = scope; self.sources = sources; self.createdAt = createdAt; self.failed = failed
    }
}

/// A Space's Assistant conversation, stored separately per provider inside the vault.
public struct AssistantChat: Codable, Hashable, Sendable {
    public var schemaVersion = 1
    public var spaceId: String
    public var provider: AssistantProvider = .local
    public var messages: [AssistantMessage] = []
    public init(spaceId: String, provider: AssistantProvider = .local) { self.spaceId = spaceId; self.provider = provider }

    enum CodingKeys: String, CodingKey { case schemaVersion, spaceId, provider, messages }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        spaceId = try c.decode(String.self, forKey: .spaceId)
        provider = try c.decodeIfPresent(AssistantProvider.self, forKey: .provider) ?? .local
        messages = try c.decodeIfPresent([AssistantMessage].self, forKey: .messages) ?? []
    }

    static func url(_ vault: Vault, _ spaceId: String, provider: AssistantProvider = .local) -> URL {
        let name = spaceId.filter { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" }
        return vault.dir.appendingPathComponent("assistant/\(name)\(provider == .local ? "" : "-openai").json")
    }

    public static func load(_ vault: Vault, spaceId: String, provider: AssistantProvider = .local) -> AssistantChat {
        guard let d = try? Data(contentsOf: url(vault, spaceId, provider: provider)), let c = try? JSONDecoder().decode(AssistantChat.self, from: d), c.spaceId == spaceId, c.provider == provider else { return AssistantChat(spaceId: spaceId, provider: provider) }
        return c
    }

    public func save(_ vault: Vault) throws {
        guard !vault.isReadOnly else { return }
        let e = JSONEncoder(); e.outputFormatting = [.prettyPrinted, .sortedKeys]
        try Vault.writeAtomic(try e.encode(self), to: Self.url(vault, spaceId, provider: provider))
    }

    public static func delete(_ vault: Vault, spaceId: String, provider: AssistantProvider = .local) { try? FileManager.default.removeItem(at: url(vault, spaceId, provider: provider)) }

    /// The last turns, oldest first, as the model sees them.
    public var turns: [ChatTurn] { messages.filter { $0.failed != true }.suffix(6).map { ChatTurn($0.role, $0.text) } }
}

/// Word-level differences for previews before an Insert or Replace.
public enum WordDiff {
    public enum Op: String, Sendable { case same, removed, added }
    public struct Part: Hashable, Sendable { public var op: Op; public var text: String }

    static func tokens(_ s: String) -> [String] {
        var out: [String] = []
        var cur = ""
        var curIsSpace: Bool?
        for ch in s {
            let sp = ch.isWhitespace
            if curIsSpace != nil, sp != curIsSpace { out.append(cur); cur = "" }
            cur.append(ch); curIsSpace = sp
        }
        if !cur.isEmpty { out.append(cur) }
        return out
    }

    public static func diff(_ a: String, _ b: String) -> [Part] {
        let x = tokens(a), y = tokens(b)
        guard x.count * y.count <= 4_000_000 else { return [Part(op: .removed, text: a), Part(op: .added, text: b)].filter { !$0.text.isEmpty } }
        var lcs = [[Int32]](repeating: [Int32](repeating: 0, count: y.count + 1), count: x.count + 1)
        for i in stride(from: x.count - 1, through: 0, by: -1) {
            for j in stride(from: y.count - 1, through: 0, by: -1) {
                lcs[i][j] = x[i] == y[j] ? lcs[i + 1][j + 1] + 1 : max(lcs[i + 1][j], lcs[i][j + 1])
            }
        }
        var parts: [Part] = []
        func add(_ op: Op, _ t: String) { if let last = parts.last, last.op == op { parts[parts.count - 1].text += t } else { parts.append(Part(op: op, text: t)) } }
        var i = 0, j = 0
        while i < x.count || j < y.count {
            if i < x.count, j < y.count, x[i] == y[j] { add(.same, x[i]); i += 1; j += 1 }
            else if j < y.count, i == x.count || lcs[i][j + 1] >= lcs[i + 1][j] { add(.added, y[j]); j += 1 }
            else { add(.removed, x[i]); i += 1 }
        }
        return parts
    }
}

/// Separates a reasoning model's `<think>…</think>` from its answer while text streams in, even
/// when a tag arrives split across pieces.
public struct ThinkSplitter: Sendable {
    public private(set) var thinking = ""
    public private(set) var answer = ""
    public private(set) var inThought = false
    private var buffer = ""
    private var started = false
    public init() {}

    public mutating func feed(_ piece: String) {
        buffer += piece
        while !buffer.isEmpty {
            if !started {
                let trimmed = buffer.drop { $0.isWhitespace }
                if "<think>".hasPrefix(trimmed) && trimmed.count < 7 { return }
                started = true
                if trimmed.hasPrefix("<think>") { inThought = true; buffer = String(trimmed.dropFirst(7)); continue }
            }
            let tag = inThought ? "</think>" : "<think>"
            if let r = buffer.range(of: tag) {
                append(String(buffer[..<r.lowerBound]))
                buffer = String(buffer[r.upperBound...])
                inThought.toggle()
                continue
            }
            var keep = 0
            for k in stride(from: min(tag.count - 1, buffer.count), to: 0, by: -1) where tag.hasPrefix(buffer.suffix(k)) { keep = k; break }
            append(String(buffer.dropLast(keep)))
            buffer = String(buffer.suffix(keep))
            return
        }
    }

    /// Call when generation ends: a held partial tag is plain text after all.
    public mutating func finish() { append(buffer); buffer = "" }

    private mutating func append(_ s: String) {
        if inThought { thinking += s } else { answer += answer.isEmpty ? String(s.drop { $0.isWhitespace }) : s }
    }
}
