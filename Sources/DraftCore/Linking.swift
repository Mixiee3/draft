import Foundation

// MARK: - Days

/// Calendar days as `yyyy-MM-dd` keys in the user's calendar. A day can start after midnight
/// (Settings → Advanced → Start of day): before that hour, "today" is still the previous day.
public enum Day {
    static let lock = NSLock()
    nonisolated(unsafe) static var formatters: [String: DateFormatter] = [:]

    /// Localized formatters by template, cached like `formatter`.
    static func localized(_ template: String, _ cal: Calendar) -> DateFormatter {
        let k = "\(template)|\(cal.identifier)|\(cal.timeZone.identifier)|\(Locale.current.identifier)"
        lock.lock(); defer { lock.unlock() }
        if let f = formatters[k] { return f }
        let f = DateFormatter(); f.calendar = cal; f.timeZone = cal.timeZone
        f.setLocalizedDateFormatFromTemplate(template)
        formatters[k] = f
        return f
    }

    /// One formatter per calendar and time zone: making a DateFormatter costs more than using it.
    static func formatter(_ cal: Calendar) -> DateFormatter {
        let k = "\(cal.identifier)|\(cal.timeZone.identifier)"
        lock.lock(); defer { lock.unlock() }
        if let f = formatters[k] { return f }
        let f = DateFormatter()
        f.calendar = cal; f.timeZone = cal.timeZone; f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        formatters[k] = f
        return f
    }

    public static func key(_ d: Date, cal: Calendar = .current) -> String { formatter(cal).string(from: d) }
    public static func date(_ key: String, cal: Calendar = .current) -> Date? { formatter(cal).date(from: String(key.prefix(10))) }

    public static func today(now: Date = Date(), startHour: Int = 0, cal: Calendar = .current) -> String {
        key(now.addingTimeInterval(-Double(max(0, min(23, startHour))) * 3600), cal: cal)
    }

    public static func add(_ key: String, days: Int, cal: Calendar = .current) -> String {
        guard let d = date(key, cal: cal), let n = cal.date(byAdding: .day, value: days, to: d) else { return key }
        return Day.key(n, cal: cal)
    }

    public static func distance(from a: String, to b: String, cal: Calendar = .current) -> Int {
        guard let x = date(a, cal: cal), let y = date(b, cal: cal) else { return 0 }
        return cal.dateComponents([.day], from: x, to: y).day ?? 0
    }

    /// 1 = Sunday … 7 = Saturday.
    public static func weekday(_ key: String, cal: Calendar = .current) -> Int { date(key, cal: cal).map { cal.component(.weekday, from: $0) } ?? 1 }

    /// First day of the week containing `key`; `weekStart` 1 = Sunday, 2 = Monday (0 = the calendar's).
    public static func startOfWeek(_ key: String, weekStart: Int, cal: Calendar = .current) -> String {
        let ws = weekStart == 0 ? cal.firstWeekday : weekStart
        return add(key, days: -((weekday(key, cal: cal) - ws + 7) % 7), cal: cal)
    }

    public static func title(_ key: String, cal: Calendar = .current) -> String {
        guard let d = date(key, cal: cal) else { return key }
        return localized("EEEEMMMMdyyyy", cal).string(from: d)
    }

    /// Short chip label: Today, Tomorrow, Yesterday, a weekday within a week, else "Nov 12".
    public static func label(_ key: String, today: String, cal: Calendar = .current) -> String {
        let n = distance(from: today, to: key, cal: cal)
        switch n {
        case 0: return "Today"
        case 1: return "Tomorrow"
        case -1: return "Yesterday"
        default:
            guard let d = date(key, cal: cal) else { return key }
            return localized(n > 1 && n < 7 ? "EEEE" : (key.prefix(4) == today.prefix(4) ? "MMMd" : "MMMdyyyy"), cal).string(from: d)
        }
    }
}

public extension Day {
    /// Label stored in a date chip. Absolute, so it never needs rewriting when the day changes:
    /// "Mon 9 Nov", "Mon 9 Nov 2027", "Mon 9 Nov 14:30".
    static func chipLabel(_ value: String, today: String, cal: Calendar = .current) -> String {
        let key = String(value.prefix(10))
        guard let d = date(key, cal: cal) else { return value }
        return localized(key.prefix(4) == today.prefix(4) ? "EEEdMMM" : "EEEdMMMyyyy", cal).string(from: d) + (value.count > 10 ? " " + String(value.suffix(5)) : "")
    }
}

/// Natural-language dates typed after `@`: today, tomorrow, yesterday, (this|next) monday,
/// monday, next week, next month, in 3 days, in 2 weeks, 2026-11-12, nov 12, 12 november.
public enum DateParse {
    static let weekdays = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"]
    static let months = ["january", "february", "march", "april", "may", "june", "july", "august", "september", "october", "november", "december"]

    static func weekdayIndex(_ w: String) -> Int? {
        guard w.count >= 2 else { return nil }
        return weekdays.firstIndex { $0.hasPrefix(w) }.map { $0 + 1 }
    }
    static func monthIndex(_ w: String) -> Int? {
        guard w.count >= 3 else { return nil }
        return months.firstIndex { $0.hasPrefix(w) }.map { $0 + 1 }
    }

    static let timePattern = try! NSRegularExpression(pattern: #"(?:^|\s+)(?:at\s+)?(\d{1,2})(?::(\d{2}))?\s*(am|pm)?$"#)

    /// A date with an optional time: "tomorrow 3pm", "fri at 14:30", "nov 12 9:00" → `yyyy-MM-ddTHH:mm`.
    public static func parse(_ raw: String, today: String, weekStart: Int = 0, cal: Calendar = .current) -> String? {
        let low = raw.lowercased().trimmingCharacters(in: .whitespaces)
        let ns = low as NSString
        if let m = timePattern.firstMatch(in: low, range: NSRange(location: 0, length: ns.length)),
           m.range(at: 2).location != NSNotFound || m.range(at: 3).location != NSNotFound {
            var h = Int(ns.substring(with: m.range(at: 1))) ?? -1
            let min = m.range(at: 2).location != NSNotFound ? Int(ns.substring(with: m.range(at: 2))) ?? -1 : 0
            if m.range(at: 3).location != NSNotFound {
                guard (1...12).contains(h) else { return nil }
                let pm = ns.substring(with: m.range(at: 3)) == "pm"
                h = h % 12 + (pm ? 12 : 0)
            }
            guard (0...23).contains(h), (0...59).contains(min) else { return nil }
            let rest = ns.substring(to: m.range.location).trimmingCharacters(in: .whitespaces)
            guard let day = rest.isEmpty ? today : parseDay(rest, today: today, weekStart: weekStart, cal: cal) else { return nil }
            return day + String(format: "T%02d:%02d", h, min)
        }
        return parseDay(raw, today: today, weekStart: weekStart, cal: cal)
    }

    static func parseDay(_ raw: String, today: String, weekStart: Int = 0, cal: Calendar = .current) -> String? {
        let s = raw.lowercased().trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: " ")
        let w = s.split(separator: " ").map(String.init)
        guard !w.isEmpty else { return nil }
        // Partly typed words count once they are unambiguous (3+ letters): "tom" → tomorrow.
        if s.count >= 3 || s == "tmr" {
            if "today".hasPrefix(s) || s == "now" { return today }
            if "tomorrow".hasPrefix(s) || s == "tmr" { return Day.add(today, days: 1, cal: cal) }
            if "yesterday".hasPrefix(s) { return Day.add(today, days: -1, cal: cal) }
        }
        switch s {
        case "next week": return Day.add(Day.startOfWeek(today, weekStart: weekStart, cal: cal), days: 7, cal: cal)
        case "next month":
            guard let d = Day.date(today, cal: cal), let n = cal.date(byAdding: .month, value: 1, to: d) else { return nil }
            var c = cal.dateComponents([.year, .month], from: n); c.day = 1
            return cal.date(from: c).map { Day.key($0, cal: cal) }
        default: break
        }
        if s.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil { return Day.date(s, cal: cal) != nil ? s : nil }
        if w.count == 3, w[0] == "in", let n = Int(w[1]), n >= 0, n < 3650 {
            if w[2].hasPrefix("day") { return Day.add(today, days: n, cal: cal) }
            if w[2].hasPrefix("week") { return Day.add(today, days: 7 * n, cal: cal) }
            if w[2].hasPrefix("month"), let d = Day.date(today, cal: cal), let m = cal.date(byAdding: .month, value: n, to: d) { return Day.key(m, cal: cal) }
            return nil
        }
        if w.count <= 2, let wd = weekdayIndex(w.last!) , w.count == 1 || ["this", "next"].contains(w[0]) {
            if w.count == 1 { // the next one after today
                let delta = (wd - Day.weekday(today, cal: cal) + 7) % 7
                return Day.add(today, days: delta == 0 ? 7 : delta, cal: cal)
            }
            let start = Day.startOfWeek(today, weekStart: weekStart, cal: cal)
            let ws = weekStart == 0 ? cal.firstWeekday : weekStart
            let inWeek = Day.add(start, days: (wd - ws + 7) % 7, cal: cal)
            return w[0] == "next" ? Day.add(inWeek, days: 7, cal: cal) : inWeek
        }
        if w.count == 2 || w.count == 3 {
            var month: Int?, day: Int?, year: Int?
            for t in w {
                if let n = Int(t) { if n > 31 { year = n } else if day == nil { day = n } else { return nil } }
                else if let m = monthIndex(t) { month = m } else { return nil }
            }
            guard let m = month, let d = day, let t = Day.date(today, cal: cal) else { return nil }
            let y = year ?? cal.component(.year, from: t)
            guard let date = cal.date(from: DateComponents(year: y, month: m, day: d)), cal.component(.day, from: date) == d else { return nil }
            var key = Day.key(date, cal: cal)
            if year == nil, key < today, let next = cal.date(byAdding: .year, value: 1, to: date) { key = Day.key(next, cal: cal) }
            return key
        }
        return nil
    }

    /// What the `@` menu offers for a typed query (parsed date first, then common choices).
    public static func suggestions(_ q: String, today: String, weekStart: Int = 0, cal: Calendar = .current) -> [String] {
        let ql = q.lowercased().trimmingCharacters(in: .whitespaces)
        var out: [String] = []
        if let d = parse(q, today: today, weekStart: weekStart, cal: cal) { out.append(d) }
        if ql.isEmpty {
            out += [today, Day.add(today, days: 1, cal: cal), parse("next monday", today: today, weekStart: weekStart, cal: cal)!]
        } else {
            // Words still being typed: "nex" offers next week, next month, next monday…
            let words = ["today", "tomorrow", "yesterday", "next week", "next month"] + weekdays + weekdays.map { "next " + $0 }
            for w in words where w.hasPrefix(ql) && out.count < 6 { if let d = parse(w, today: today, weekStart: weekStart, cal: cal) { out.append(d) } }
        }
        var seen = Set<String>()
        return out.filter { seen.insert($0).inserted }
    }
}

// MARK: - Tags

/// Which `#words` count as tags. Hex colors (#fff, #a1b2c3) and numbers (#12) are ignored by
/// default, plus any custom words.
public struct TagRules: Codable, Hashable, Sendable {
    public var ignoreHex = true
    public var ignoreNumeric = true
    public var custom: [String] = []
    public init(ignoreHex: Bool = true, ignoreNumeric: Bool = true, custom: [String] = []) { self.ignoreHex = ignoreHex; self.ignoreNumeric = ignoreNumeric; self.custom = custom }

    public var key: String { "\(ignoreHex)|\(ignoreNumeric)|\(custom.map { $0.lowercased() }.sorted().joined(separator: ","))" }

    public func allows(_ tag: String) -> Bool {
        let t = tag.lowercased()
        if ignoreNumeric && t.allSatisfy(\.isNumber) { return false }
        if ignoreHex && [3, 4, 6, 8].contains(t.count) && t.allSatisfy(\.isHexDigit) { return false }
        return !custom.contains { $0.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "# ")) == t }
    }
}

public enum Tags {
    public static let pattern = try! NSRegularExpression(pattern: #"(?<![\p{L}\p{N}_#&/\\])#([\p{L}\p{N}_](?:[\p{L}\p{N}_/-]*[\p{L}\p{N}_])?)"#)

    /// Tag ranges (including `#`) and names in plain text.
    public static func find(in text: String, rules: TagRules) -> [(range: NSRange, name: String)] {
        let ns = text as NSString
        return pattern.matches(in: text, range: NSRange(location: 0, length: ns.length)).compactMap { m in
            let name = ns.substring(with: m.range(at: 1))
            return rules.allows(name) ? (m.range, name) : nil
        }
    }

    /// Default color for a tag without a chosen one (stable per name).
    public static let palette = ["#5b6cf0", "#e0679a", "#2fa37a", "#d9822b", "#8a5cd6", "#2b9bd9", "#c9a227", "#d14d4d"]
    public static func defaultColor(_ tag: String) -> String {
        let h = tag.lowercased().unicodeScalars.reduce(UInt32(5381)) { ($0 &* 33) ^ $1.value }
        return palette[Int(h % UInt32(palette.count))]
    }
}

// MARK: - Index

public struct IndexedLink: Codable, Hashable, Sendable {
    /// Block containing the link, and the linked document / block.
    public var block: String
    public var doc: String
    public var target: String?
    public var text: String
}

public struct IndexedTag: Codable, Hashable, Sendable {
    public var tag: String // as written; compare lowercased
    public var block: String
    public var text: String
}

public struct IndexedTask: Codable, Hashable, Sendable {
    public var block: String
    public var text: String
    public var checked: Bool
    /// `yyyy-MM-dd` or `yyyy-MM-ddTHH:mm`.
    public var due: String?
}

public struct IndexedBlock: Codable, Hashable, Sendable {
    public var id: String
    public var text: String
    public var heading: Bool?
}

public struct DocIndexEntry: Codable, Hashable, Sendable {
    public var updatedAt: Double
    public var daily: String?
    public var links: [IndexedLink] = []
    public var tags: [IndexedTag] = []
    public var tasks: [IndexedTask] = []
    public var blocks: [IndexedBlock] = []
}

/// Links, tags, tasks and block locations derived from the documents. Stored in
/// `index/index.json`; deleting it is always safe — it is rebuilt from the document files, and
/// building it never writes a document.
public struct VaultIndex: Codable, Hashable, Sendable {
    public static let version = 1
    public var version = VaultIndex.version
    public var rules = ""
    public var entries: [String: DocIndexEntry] = [:]
    public init() {}

    static let blockTextLimit = 200

    /// Index one document. Tasks without their own date are due on their daily note's day.
    public static func entry(for doc: DocFile, daily: String?, rules: TagRules) -> DocIndexEntry {
        var e = DocIndexEntry(updatedAt: doc.updatedAt, daily: daily)
        func visit(_ n: Node, item: Node?) {
            switch n.type {
            case "paragraph", "heading", "codeBlock":
                let id = item?.id ?? n.id ?? ""
                let text = nodeText(n)
                if !text.isEmpty { e.blocks.append(IndexedBlock(id: id, text: String(text.prefix(blockTextLimit)), heading: n.type == "heading" ? true : nil)) }
                guard n.type != "codeBlock" else { return }
                var plain = ""
                var firstDate: String?
                for t in n.content ?? [] {
                    let marks = t.marks ?? []
                    if let l = marks.first(where: { $0.type == "docLink" }), let d = l.attrs?["docId"]?.string {
                        e.links.append(IndexedLink(block: id, doc: d, target: l.attrs?["blockId"]?.string, text: String(text.prefix(160))))
                    } else if let l = marks.first(where: { $0.type == "link" }), let h = l.attrs?["href"]?.string, let (d, b) = parseDraftURL(h) {
                        e.links.append(IndexedLink(block: id, doc: d, target: b, text: String(text.prefix(160))))
                    }
                    if firstDate == nil, let dm = marks.first(where: { $0.type == "date" }) { firstDate = dm.attrs?["date"]?.string }
                    let s = t.type == "text" ? (t.text ?? "") : " "
                    // Tags never come from code, links or chips.
                    plain += marks.contains { ["code", "link", "docLink", "date"].contains($0.type) } ? String(repeating: " ", count: s.count) : s
                }
                for t in Tags.find(in: plain, rules: rules) { e.tags.append(IndexedTag(tag: t.name, block: id, text: String(text.prefix(160)))) }
                if let item, item.type == "taskItem", item.content?.first == n {
                    e.tasks.append(IndexedTask(block: id, text: text, checked: item.attrs?["checked"]?.bool ?? false, due: item.attrs?["due"]?.string ?? firstDate ?? daily))
                }
            case "listItem", "taskItem", "toggleItem":
                for (i, c) in (n.content ?? []).enumerated() { visit(c, item: i == 0 && c.type == "paragraph" ? n : nil) }
            default:
                if n.type == "pageCard", let id = n.id { e.blocks.append(IndexedBlock(id: id, text: n.attrs?["title"]?.string ?? "")) }
                if let id = n.id, n.type == "image" || n.type == "file" || n.type == "horizontalRule" || n.type == "pageBreak" { e.blocks.append(IndexedBlock(id: id, text: "")) }
                for c in n.content ?? [] { visit(c, item: nil) }
            }
        }
        visit(doc.content, item: nil)
        return e
    }

    /// Bring the index up to date with the library: re-index changed documents only, drop
    /// deleted ones. Returns how many documents were (re)indexed.
    @discardableResult
    public mutating func refresh(docs: [String: DocMeta], rules r: TagRules, load: (String) -> DocFile?) -> Int {
        if version != VaultIndex.version || rules != r.key { entries = [:]; version = VaultIndex.version; rules = r.key }
        for id in entries.keys where docs[id] == nil { entries[id] = nil }
        var n = 0
        for (id, m) in docs {
            if let e = entries[id], e.updatedAt == m.updatedAt, e.daily == m.dailyDate { continue }
            guard let d = load(id) else { entries[id] = nil; continue }
            entries[id] = VaultIndex.entry(for: d, daily: m.dailyDate, rules: r)
            entries[id]!.updatedAt = m.updatedAt
            n += 1
        }
        return n
    }

    /// Block id → document id, for following block references after blocks move.
    public func blockLocations() -> [String: String] {
        var out: [String: String] = [:]
        out.reserveCapacity(entries.values.reduce(0) { $0 + $1.blocks.count })
        for (doc, e) in entries { for b in e.blocks { out[b.id] = doc } }
        return out
    }

    public struct Backlink: Hashable, Identifiable {
        public var id: String { source + "/" + link.block + "/" + (link.target ?? "") }
        public var source: String
        public var link: IndexedLink
    }

    /// Links from other documents to `docId` or to any of its blocks.
    public func backlinks(to docId: String, live: Set<String>) -> [Backlink] {
        let mine = Set(entries[docId]?.blocks.map(\.id) ?? [])
        var out: [Backlink] = []
        for (src, e) in entries where src != docId && live.contains(src) {
            for l in e.links where l.doc == docId || (l.target.map(mine.contains) ?? false) { out.append(Backlink(source: src, link: l)) }
        }
        return out
    }

    /// All tags with their number of uses (live documents only), by lowercased name.
    public func tagCounts(live: Set<String>) -> [(tag: String, count: Int)] {
        var counts: [String: (String, Int)] = [:]
        for (doc, e) in entries where live.contains(doc) {
            for t in e.tags { let k = t.tag.lowercased(); counts[k] = (counts[k]?.0 ?? t.tag, (counts[k]?.1 ?? 0) + 1) }
        }
        return counts.values.map { ($0.0, $0.1) }.sorted { $0.tag.lowercased() < $1.tag.lowercased() }
    }

    public func tagged(_ tag: String, live: Set<String>) -> [(doc: String, tag: IndexedTag)] {
        let k = tag.lowercased()
        return entries.filter { live.contains($0.key) }.flatMap { d, e in e.tags.filter { $0.tag.lowercased() == k }.map { (d, $0) } }
    }

    public func tasks(live: Set<String>) -> [(doc: String, task: IndexedTask)] {
        entries.filter { live.contains($0.key) }.flatMap { d, e in e.tasks.map { (d, $0) } }
    }

    /// Blocks whose text contains every term (Quick Open).
    public func blockHits(_ query: String, live: Set<String>, limit: Int = 20) -> [(doc: String, block: IndexedBlock)] {
        let ts = Search.terms(query)
        guard !ts.isEmpty else { return [] }
        var out: [(String, IndexedBlock)] = []
        for (d, e) in entries where live.contains(d) {
            for b in e.blocks where !b.text.isEmpty && ts.allSatisfy({ b.text.range(of: $0, options: [.caseInsensitive, .diacriticInsensitive]) != nil }) {
                out.append((d, b))
                if out.count >= limit * 4 { break }
            }
        }
        return Array(out.sorted { ($0.1.heading ?? false) && !($1.1.heading ?? false) }.prefix(limit))
    }
}

/// `draft://open?doc=…&block=…` → (doc, block).
public func parseDraftURL(_ s: String) -> (String, String?)? {
    guard s.hasPrefix("draft://"), let q = URLComponents(string: s)?.queryItems, let d = q.first(where: { $0.name == "doc" })?.value else { return nil }
    return (d, q.first { $0.name == "block" }?.value)
}

// MARK: - Tasks

public enum TaskBucket: String, CaseIterable, Sendable { case inbox, today, upcoming, overdue, completed
    public var title: String { rawValue.capitalized }
}

public extension IndexedTask {
    var dueDay: String? { due.map { String($0.prefix(10)) } }
    func bucket(today: String) -> TaskBucket {
        if checked { return .completed }
        guard let d = dueDay else { return .inbox }
        return d < today ? .overdue : d == today ? .today : .upcoming
    }
}

// MARK: - Reminders

public struct ReminderPlan: Hashable, Sendable {
    public var id: String
    public var fire: Date
    public var title: String
}

public enum Reminders {
    /// One reminder per open task with a future due time; date-only tasks remind at `hour`.
    /// The system keeps at most 64 pending notifications, so only the soonest are scheduled.
    public static func plan(_ tasks: [IndexedTask], now: Date = Date(), hour: Int = 9, limit: Int = 60, cal: Calendar = .current) -> [ReminderPlan] {
        let f = DateFormatter(); f.calendar = cal; f.timeZone = cal.timeZone; f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd'T'HH:mm"
        var out: [ReminderPlan] = []
        for t in tasks where !t.checked {
            guard let due = t.due else { continue }
            let fire: Date?
            if due.count > 10 { fire = f.date(from: String(due.prefix(16))) }
            else { fire = Day.date(due, cal: cal).flatMap { cal.date(bySettingHour: max(0, min(23, hour)), minute: 0, second: 0, of: $0) } }
            guard let fire, fire > now else { continue }
            out.append(ReminderPlan(id: "task-" + t.block, fire: fire, title: t.text.isEmpty ? "Task" : t.text))
        }
        return Array(out.sorted { $0.fire < $1.fire }.prefix(limit))
    }
}

public extension Node {
    /// The tree with task item `id` checked or unchecked; nil when there is no such task.
    /// The tree with task `id` due at `due` (a date chip in its first paragraph, replacing any
    /// existing one); `due == nil` removes the date. Nil when there is no such task.
    func settingTaskDue(_ id: String, due: String?, label: String) -> Node? {
        var found = false
        func visit(_ n: Node) -> Node {
            var out = n
            if n.type == "taskItem", n.id == id, var items = n.content, let pi = items.firstIndex(where: { $0.type == "paragraph" }) {
                var inline = (items[pi].content ?? []).filter { !($0.marks ?? []).contains { $0.type == "date" } }
                while let last = inline.last, last.type == "text", let t = last.text, t.hasSuffix(" ") {
                    let trimmed = String(t.dropLast()); inline.removeLast()
                    if !trimmed.isEmpty { var l = last; l.text = trimmed; inline.append(l); break }
                }
                if let due {
                    if !inline.isEmpty { inline.append(.text(" ")) }
                    inline.append(.text(label, marks: [Mark("date", attrs: ["date": .string(due)])]))
                }
                items[pi].content = inline.isEmpty ? nil : inline
                out.content = items
                out.attrs?["due"] = nil
                found = true
                return out
            }
            out.content = n.content?.map(visit)
            return out
        }
        let r = visit(self)
        return found ? r : nil
    }

    func settingTask(_ id: String, checked: Bool) -> Node? {
        var found = false
        func visit(_ n: Node) -> Node {
            var out = n
            if n.type == "taskItem", n.id == id { out[attr: "checked"] = .bool(checked); found = true }
            out.content = n.content?.map(visit)
            return out
        }
        let r = visit(self)
        return found ? r : nil
    }
}
