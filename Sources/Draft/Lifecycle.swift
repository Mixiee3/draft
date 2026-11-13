import AppKit
import SwiftUI
import DraftCore

/// A small local log for troubleshooting: lifecycle events and errors with ids and counts only —
/// never note text, titles or file paths. ~/Library/Logs/Draft/draft.log, at most 1 MB (one rotation).
enum DraftLog {
    static var dir: URL {
        if let d = ProcessInfo.processInfo.environment["DRAFT_DATA_DIR"], !d.isEmpty { return URL(fileURLWithPath: d).deletingLastPathComponent().appendingPathComponent("logs") }
        return FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0].appendingPathComponent("Logs/Draft")
    }
    static var file: URL { dir.appendingPathComponent("draft.log") }
    static let queue = DispatchQueue(label: "draft.log")

    static func write(_ event: String) {
        let line = ISO8601DateFormatter().string(from: Date()) + " " + event + "\n"
        queue.async {
            let fm = FileManager.default
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
            if let size = (try? fm.attributesOfItem(atPath: file.path)[.size] as? Int), size > 1_000_000 {
                let old = dir.appendingPathComponent("draft.1.log"); try? fm.removeItem(at: old); try? fm.moveItem(at: file, to: old)
            }
            if let h = try? FileHandle(forWritingTo: file) { h.seekToEndOfFile(); h.write(Data(line.utf8)); try? h.close() }
            else { try? Data(line.utf8).write(to: file) }
        }
    }

    static func tail(_ lines: Int = 200) -> [String] {
        queue.sync {}
        return Array(((try? String(contentsOf: file, encoding: .utf8)) ?? "").split(separator: "\n").suffix(lines).map(String.init))
    }
}

/// What a crash left behind, shown once at the next launch.
struct CrashInfo: Codable, Equatable {
    var startedAt: Date
    var lastSaveAt: Date?
    var version: String
}

/// Notes for What's New, newest first. Each version shows its own once after an update.
enum ReleaseNotes {
    static let all: [(version: String, title: LocalizedStringKey, points: [LocalizedStringKey])] = [
        ("0.10.0", "Updates you control, help and privacy in one place", [
            "Check for Updates… in the Draft menu. Automatic checks stay off until you turn them on.",
            "Help: search how-tos for writing, backups, version history, agents and recovery.",
            "Report a Problem: write a local report you review before saving. Nothing is sent.",
            "Privacy: every permission and network feature, what it does and how to turn it off.",
            "Backup Archive: one file with your whole vault, which you can restore and check.",
        ]),
    ]
}

extension AppModel {
    /// Outside the vault so Safe Mode (which writes nothing to the vault) still has it.
    var sessionFile: URL {
        if let d = ProcessInfo.processInfo.environment["DRAFT_DATA_DIR"], !d.isEmpty { return URL(fileURLWithPath: d).deletingLastPathComponent().appendingPathComponent("draft-session.json") }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Draft/session.json")
    }

    /// Reads what an unclean exit left, then marks this session as running.
    func beginSession() {
        if let d = try? Data(contentsOf: sessionFile), let info = try? JSONDecoder().decode(CrashInfo.self, from: d) {
            recovery.crash = info
            DraftLog.write("previous session ended unexpectedly (started \(info.startedAt), last save \(info.lastSaveAt.map { "\($0)" } ?? "none"))")
        }
        writeSession(lastSave: nil)
        DraftLog.write("launch \(updates.version) (\(updates.build)) channel \(updates.buildChannel)\(recovery.safeMode ? " safe-mode" : "")")
    }

    func writeSession(lastSave: Date?) {
        let info = CrashInfo(startedAt: sessionStart, lastSaveAt: lastSave, version: updates.version)
        try? FileManager.default.createDirectory(at: sessionFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(info).write(to: sessionFile, options: .atomic)
    }

    func cleanExit() {
        try? FileManager.default.removeItem(at: sessionFile)
        DraftLog.write("quit normally")
    }

    func showWhatsNewIfNeeded() {
        let v = updates.version
        guard let seen = library.settings.lastSeenVersion else { setSettings { $0.lastSeenVersion = v }; return } // first launch: onboarding instead
        if seen != v, ReleaseNotes.all.contains(where: { $0.version == v }), onboarding == nil { whatsNew = true }
    }

    func closeWhatsNew() {
        whatsNew = false
        setSettings { $0.lastSeenVersion = updates.version }
    }

    /// Relaunches this app in Safe Mode (read-only).
    func relaunchInSafeMode() {
        flushAll()
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        p.arguments = ["-n", Bundle.main.bundlePath, "--args", "-DraftSafeMode", "YES"]
        try? p.run()
        NSApp.terminate(nil)
    }
}
