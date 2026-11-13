import Foundation

/// Report a Problem: the text the person reviews before saving it. Built from counts, versions and
/// settings switches — never note text or titles — and every line is redacted again before it is
/// shown: home folders become ~, and any note title that slipped into a log line becomes ‹title›.
public enum Diagnostics {
    public struct Input: Sendable {
        public var description: String
        public var appVersion: String, build: String, channel: String, commit: String
        public var system: String, machine: String, displays: [String]
        public var counts: [String: Int]
        public var switches: [String: String]
        public var performance: [String]
        public var log: [String]
        public var includeLog: Bool
        public init(description: String, appVersion: String, build: String, channel: String, commit: String, system: String, machine: String, displays: [String],
                    counts: [String: Int], switches: [String: String], performance: [String], log: [String], includeLog: Bool) {
            self.description = description; self.appVersion = appVersion; self.build = build; self.channel = channel; self.commit = commit
            self.system = system; self.machine = machine; self.displays = displays; self.counts = counts; self.switches = switches
            self.performance = performance; self.log = log; self.includeLog = includeLog
        }
    }

    /// Removes personal paths and known titles from a line.
    public static func redact(_ s: String, titles: [String], home: String = NSHomeDirectory()) -> String {
        var out = s.replacingOccurrences(of: home, with: "~")
        out = out.replacingOccurrences(of: #"/Users/[^/\s"']+"#, with: "~", options: .regularExpression)
        for t in titles where t.count >= 3 { out = out.replacingOccurrences(of: t, with: "‹title›") }
        return out
    }

    public static func report(_ i: Input, titles: [String]) -> String {
        var lines = ["# Draft problem report", "", "## What happened", i.description.isEmpty ? "(no description)" : i.description, "",
                     "## Draft", "Version \(i.appVersion) (\(i.build)), channel \(i.channel), commit \(i.commit)", "",
                     "## Mac", "\(i.machine), macOS \(i.system)"] + i.displays.map { "Display: \($0)" } + ["", "## Vault (counts only)"]
        lines += i.counts.sorted { $0.key < $1.key }.map { "\($0.key): \($0.value)" }
        lines += ["", "## Settings"] + i.switches.sorted { $0.key < $1.key }.map { "\($0.key): \($0.value)" }
        if !i.performance.isEmpty { lines += ["", "## Performance"] + i.performance }
        if i.includeLog { lines += ["", "## Log (last \(i.log.count) lines; events and ids only)"] + i.log }
        lines += ["", "Not included: note text, note titles, file names, the vault's location, attachments."]
        // The description is the person's own words and stays as written.
        let head = lines.prefix(4)
        return (Array(head) + lines.dropFirst(4).map { redact($0, titles: titles) }).joined(separator: "\n")
    }
}
