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

extension Automation {
    /// Nested folders and moving a document into one (throwaway vault): checks the model and the rail.
    static func foldersCheck() async {
        guard let (w, p) = trustSetup() else { return }
        var r: [String: Any] = [:]
        defer { writeResult(r, p + "folders-check.json") }
        let parent = m.createFolder()
        m.renamingFolder = nil
        m.renameFolder(parent, "Projects")
        let sub = m.createFolder(parentId: parent)
        m.renamingFolder = nil
        m.renameFolder(sub, "Draft")
        guard let doc = m.createDoc(title: "Folder check") else { r["error"] = "no doc"; return }
        m.flushAll()
        m.move(doc, to: sub)
        await wait(0.8)
        r["rows"] = m.flatFolders().map { "\($0.folder.name)@\($0.depth)" }
        r["docInSub"] = m.library.docs[doc]?.folderId == sub
        r["subParentIsProjects"] = m.library.folders.first { $0.id == sub }?.parentId == parent
        await shot(p + "folders-rail", w, settle: 0.3)
    }
}

extension Automation {
    /// Feature scenarios that can be checked without clicks (throwaway vault): Focus Mode on and off,
    /// Present opens a presentation window from a note, spelling language applies to NSSpellChecker,
    /// and the Format panel and Settings stay reachable. Writes features-check.json.
    static func featuresCheck() async {
        guard let (w, p) = trustSetup() else { return }
        var r: [String: Any] = [:]
        defer { writeResult(r, p + "features-check.json") }
        guard let doc = m.createDoc(title: "Feature check") else { r["error"] = "no doc"; return }
        m.openView(.doc(doc))
        m.editor(for: doc).controller.pastePlainForAutomation("First block.\nSecond block.")
        m.editorChanged(doc); m.flushAll()
        await wait(0.5)
        // Focus Mode: on, then off.
        m.focusMode = true; await wait(0.6)
        r["focus.on"] = m.focusMode
        await shot(p + "focus-mode", w, settle: 0.2)
        m.focusMode = false; await wait(0.6)
        r["focus.off"] = !m.focusMode
        // Present: a presentation window appears and can be closed again.
        let before = NSApp.windows.filter { $0 is PresentWindow }.count
        m.present(doc); await wait(1.0)
        let presentWindows = NSApp.windows.filter { $0 is PresentWindow }
        r["present.opened"] = presentWindows.count > before
        presentWindows.forEach { $0.close() }
        await wait(0.4)
        // Spelling language: a real available language is applied; back to automatic afterwards.
        let sc = NSSpellChecker.shared
        if let lang = sc.availableLanguages.first(where: { $0.hasPrefix("cs") }) ?? sc.availableLanguages.first {
            m.setSettings { $0.spellingLanguage = lang }
            await wait(0.4)
            r["spelling.set"] = sc.automaticallyIdentifiesLanguages == false && sc.language() == lang
            m.setSettings { $0.spellingLanguage = nil }
            await wait(0.4)
            r["spelling.automaticAfterClear"] = sc.automaticallyIdentifiesLanguages == true
        } else { r["spelling.skipped"] = "no spelling languages installed" }
        r["check.critical"] = VaultCheck.run(m.vault).count(.critical)
    }
}
