import AppKit
import DraftCore

/// v0.10 (v1.0 groundwork) screens, shared by the localization check and `screens-v10`:
/// update available with notes, Settings › Updates / Privacy / Help, What's New, Report a Problem,
/// crash recovery card, backup archive (Data & Storage), import preview, Safe Mode banner.
extension Automation {
    static func v10Screens() -> [(String, () -> Void, () -> Void)] {
        let item = UpdateItem(version: "0.11.0", build: 999, channel: "stable", date: "2026-12-01",
                              notes: ["Faster search in large vaults", "Tables can be sorted by any column", "Fixes for dictation"],
                              url: "https://example.invalid/Draft-0.11.0.zip", size: 48_300_000, sha256: "", signature: "",
                              minimumSystem: "14.0", librarySchema: librarySchemaVersion, docSchema: docSchemaVersion)
        let u = m.updates
        return [
            ("onboarding-welcome", { m.openView(.all); m.showWelcome() }, { m.onboarding = nil }),
            ("onboarding-tour", { m.startTour() }, { m.onboarding = nil }),
            ("update-available", { u.phase = .available(item); u.sheet = true }, { u.sheet = false; u.phase = .idle }),
            ("update-ready", { u.phase = .ready(item); u.sheet = true }, { u.sheet = false; u.phase = .idle }),
            ("settings-updates", { m.openView(ViewRef(kind: "settings", section: "updates")) }, {}),
            ("settings-privacy", { m.openView(ViewRef(kind: "settings", section: "privacy")) }, {}),
            ("settings-help", { m.openView(ViewRef(kind: "settings", section: "help")) }, {}),
            ("settings-backup-archive", { m.openView(ViewRef(kind: "settings", section: "data")) }, {}),
            ("whats-new", { m.whatsNew = true }, { m.whatsNew = false }),
            ("report-problem", { m.reportProblem = true }, { m.reportProblem = false }),
            ("crash-recovery", { m.openView(.all); m.recovery.crash = CrashInfo(startedAt: Date().addingTimeInterval(-3600), lastSaveAt: Date().addingTimeInterval(-90), version: u.version) }, { m.recovery.crash = nil }),
            ("import-preview", {
                m.importPreview = ImportPreview(urls: [], titles: ["Reading list", "Trip plan", "Meeting notes", "Recipes", "Garden"],
                                                duplicates: ["Trip plan"], notes: 5, folders: 1, warnings: [], failed: [])
            }, { m.importPreview = nil }),
        ]
    }

    /// Light, dark (AUDIT_DARK) and narrow (AUDIT_NARROW) screenshots of the v0.10 screens.
    static func screensV10() async {
        guard let (w, p) = trustSetup() else { return }
        for (name, open, close) in v10Screens() {
            open(); await wait(1.0)
            await shot(p + name, w, settle: 0.2)
            close(); await wait(0.4)
        }
    }
}
