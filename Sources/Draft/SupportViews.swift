import AppKit
import AVFoundation
import EventKit
import SwiftUI
import UserNotifications
import DraftCore

// MARK: - Privacy

/// Settings › Privacy: everything that can leave this Mac or needs a permission, its state, what it
/// does and how to turn it off.
struct PrivacyView: View {
    @Environment(AppModel.self) var model
    @Environment(\.tokens) var t
    @State private var notifications = "…"
    @State private var fileVault = "…"
    var body: some View {
        let s = model.library.settings
        let mic: String = { switch AVCaptureDevice.authorizationStatus(for: .audio) { case .authorized: return String(localized: "Allowed"); case .denied, .restricted: return String(localized: "Not allowed"); default: return String(localized: "Not asked") } }()
        let cal: String = { switch EKEventStore.authorizationStatus(for: .event) { case .fullAccess, .authorized: return String(localized: "Allowed"); case .denied, .restricted: return String(localized: "Not allowed"); default: return String(localized: "Not asked") } }()
        let agents = s.agentPermissions.count
        VStack(alignment: .leading, spacing: DS.s5) {
            SettingsSection(title: "Your data", footer: "Your notes are plain files in this folder on this Mac. Draft has no account and no server, and it doesn't collect usage data.") {
                item("internaldrive", "Vault", "\(model.vault.dir.lastPathComponent)", "Where every note, attachment, version and backup lives.", action: ("Show in Finder", { model.revealVault() }))
                item("chart.bar.xaxis", "Telemetry", String(localized: "None"), "Draft never sends usage data, crash reports or analytics. Report a Problem only saves a file you review.", action: nil)
                item("lock", "Encryption", fileVault, "Draft doesn't add its own encryption yet; FileVault encrypts the whole disk, including the vault.", action: ("Open FileVault Settings", { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?FileVault")!) }))
            }
            SettingsSection(title: "Network (each one off until you turn it on)", footer: "Nothing else in Draft uses the network.") {
                item("arrow.down.circle", "Update checks", s.updateChecks ? String(localized: "Automatic") : String(localized: "Only when you ask"), "Downloads the list of Draft versions over HTTPS. Sends nothing about you.", action: ("Update Settings", { model.showSettings("updates") }))
                item("photo.on.rectangle", "Online image search", s.onlineImageSearch ? String(localized: "On") : String(localized: "Off"), "Sends your search words to Openverse when you search for a backdrop image.", action: ("Advanced Settings", { model.showSettings("advanced") }))
                item("link", "Link previews", s.linkPreviews ? String(localized: "On") : String(localized: "Off"), "Loads the title and image of a pasted web address from that website.", action: ("Advanced Settings", { model.showSettings("advanced") }))
                item("sparkle", "Assistant", s.assistantProvider == .openai ? String(localized: "OpenAI API") : String(localized: "On this Mac"), "The local model never sends notes anywhere. The optional OpenAI mode sends only the context you review before each request.", action: ("Assistant Settings", { model.showSettings("assistant") }))
                item("key", "OpenAI API key", OpenAIKeyStore.load() == nil ? String(localized: "Not saved") : String(localized: "Saved in the Keychain"), "Used only for requests you confirm. Remove it in Assistant settings.", action: ("Assistant Settings", { model.showSettings("assistant") }))
                item("arrow.down.doc", "Assistant model", s.assistantModel == nil ? String(localized: "Not downloaded") : String(localized: "Downloaded"), "Downloaded once, only when you click Download; then the Assistant works offline.", action: ("Assistant Settings", { model.showSettings("assistant") }))
            }
            SettingsSection(title: "Agents and permissions", footer: "Agents talk to Draft on this Mac through scripts/draft-mcp.sh. Every change they want is a proposal you review.") {
                item("person.badge.key", "MCP agents", "\(agents)", "Codex, Claude Code and other agents: read notes and propose changes; destructive changes need your permission.", action: ("Agents Settings", { model.showSettings("agents") }))
                item("bell", "Notifications", notifications, "Task reminders, only when Remind me when tasks are due is on.", action: ("Daily Notes Settings", { model.showSettings("daily") }))
                item("calendar", "Calendar", cal, "Shows your events next to daily notes when you turn it on. Draft never changes events.", action: ("Daily Notes Settings", { model.showSettings("daily") }))
                item("mic", "Microphone", mic, "Assistant dictation, only while you hold the microphone button. Speech is recognized on this Mac.", action: ("System Settings", { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!) }))
            }
        }
        .task {
            let st = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
            notifications = st == .authorized ? String(localized: "Allowed") : st == .denied ? String(localized: "Not allowed") : String(localized: "Not asked")
            fileVault = await Task.detached { () -> String in
                let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/fdesetup"); p.arguments = ["isactive"]; let o = Pipe(); p.standardOutput = o; p.standardError = Pipe()
                guard (try? p.run()) != nil else { return String(localized: "Unknown") }
                p.waitUntilExit()
                return String(decoding: o.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self).contains("true") ? String(localized: "FileVault is on") : String(localized: "FileVault is off")
            }.value
        }
    }

    func item(_ symbol: String, _ title: LocalizedStringKey, _ state: String, _ what: LocalizedStringKey, action: (LocalizedStringKey, () -> Void)?) -> some View {
        HStack(alignment: .top, spacing: DS.s3) {
            Image(systemName: symbol).frame(width: 20).foregroundStyle(t.secondary).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                HStack { Text(title).font(.system(size: DS.body, weight: .medium)).foregroundStyle(t.text); Spacer(); Text(state).font(.system(size: DS.footnote, weight: .semibold)).foregroundStyle(t.secondary) }
                Text(what).font(.system(size: DS.footnote)).foregroundStyle(t.secondary).fixedSize(horizontal: false, vertical: true)
                if let action { Button(action.0, action: action.1).buttonStyle(.link).font(.system(size: DS.footnote)) }
            }
        }
        .padding(.horizontal, DS.s3 + 2).padding(.vertical, DS.s2 + 2)
        .accessibilityElement(children: .contain)
    }
}

// MARK: - Help

@MainActor
struct HelpTopic: Identifiable {
    let id: String
    let symbol: String
    let title: LocalizedStringKey
    let titleText: String
    let body: LocalizedStringKey
    let bodyText: String
    let action: (LocalizedStringKey, @MainActor (AppModel) -> Void)?
}

@MainActor
enum HelpTopics {
    static func t(_ id: String, _ symbol: String, _ title: String.LocalizationValue, _ body: String.LocalizationValue, _ action: (LocalizedStringKey, @MainActor (AppModel) -> Void)? = nil) -> HelpTopic {
        let ti = String(localized: title), bo = String(localized: body)
        return HelpTopic(id: id, symbol: symbol, title: LocalizedStringKey(ti), titleText: ti, body: LocalizedStringKey(bo), bodyText: bo, action: action)
    }
    static var all: [HelpTopic] { [
        t("shortcuts", "keyboard", "Keyboard shortcuts", "Every editor command has a shortcut; the Format, Insert and Table menus list them. ⌘O opens Quick Open for documents, blocks and commands.", ("Show Shortcuts", { $0.shortcutsSheet = true })),
        t("formatting", "textformat", "Formatting", "Select text to bring up the formatting bar. Type / for blocks, # for headings, [] for tasks and [[ to link a note. Effects and block decorations are in the Format panel.", ("Open the Format Panel", { $0.panel = .format })),
        t("agents", "person.badge.key", "Agents (Codex, Claude Code) and permissions", "Agents connect through scripts/draft-mcp.sh. They read notes and propose changes; nothing changes until you apply a proposal, and one Undo reverses it. Destructive changes need your permission per agent.", ("Agents Settings", { $0.showSettings("agents") })),
        t("assistant", "sparkle", "Assistant privacy", "The local model runs on this Mac and sends nothing. The optional OpenAI mode shows exactly what it will send before each request and uses your own API key.", ("Assistant Settings", { $0.showSettings("assistant") })),
        t("vault", "internaldrive", "Where your notes are", "Notes are plain files in your vault folder: library.json, docs/, assets/, history/ and backups/. You can copy the folder to keep or move your data.", ("Show the Vault in Finder", { $0.revealVault() })),
        t("backups", "archivebox", "Backups and backup archives", "Draft keeps versions of every note and copies files before any repair or migration. Create Backup Archive saves the whole vault in one file you can restore and check.", ("Data & Storage", { $0.showSettings("data") })),
        t("versions", "clock.arrow.circlepath", "Version history", "Draft saves a version every 10 minutes while you edit; Save Version Now (⌥⌘S) keeps one on purpose. Version History (⌥⌘Y) shows the differences and restores with one Undo.", ("Open Version History", { m in if let d = m.activeDocId { m.recovery.historyDoc = HistoryTarget(id: d) } })),
        t("import", "square.and.arrow.down", "Importing and exporting", "Import Markdown, text, OPML and Draft exports; you see a preview with duplicates before anything is added. Export Markdown with assets or a lossless JSON copy of everything.", ("Import…", { $0.chooseImport() })),
        t("updates", "arrow.down.circle", "Updates", "Check for Updates… in the Draft menu. Automatic checks are off until you turn them on. Every update is verified with Draft's release key before it is installed, and the previous version is kept until the new one starts.", ("Update Settings", { $0.showSettings("updates") })),
        t("troubleshooting", "wrench.and.screwdriver", "Troubleshooting", "If something looks wrong, check the vault (Settings › Recovery). Restarting in Safe Mode opens your notes read-only. Hold Option while opening Draft to do the same.", ("Check Vault", { m in m.showSettings("recovery"); Task { await m.checkVault() } })),
        t("damaged", "cross.case", "Recover from a damaged vault", "Recovery lists every problem with an exact repair preview. Repairs copy the files they touch to backups/ first and one Undo puts them back. If Draft can't open the vault, it offers recovery or read-only at launch.", ("Open Recovery", { $0.showSettings("recovery") })),
        t("report", "exclamationmark.bubble", "Report a problem", "Report a Problem writes a file with what you describe, versions and counts — no note text, titles or paths. You review it and save it; Draft sends nothing.", ("Report a Problem…", { $0.reportProblem = true })),
    ] }
}

struct HelpView: View {
    @Environment(AppModel.self) var model
    @Environment(\.tokens) var t
    @State private var query = ""
    var body: some View {
        let topics = HelpTopics.all.filter { query.isEmpty || $0.titleText.localizedCaseInsensitiveContains(query) || $0.bodyText.localizedCaseInsensitiveContains(query) }
        VStack(alignment: .leading, spacing: DS.s4) {
            TextField("Search help", text: $query).textFieldStyle(.roundedBorder).frame(maxWidth: 420).accessibilityLabel("Search help")
            if topics.isEmpty { Text("No help topic matches “\(query)”.").foregroundStyle(t.secondary) }
            ForEach(topics) { tp in
                SettingsSection(title: nil) {
                    HStack(alignment: .top, spacing: DS.s3) {
                        Image(systemName: tp.symbol).font(.system(size: DS.headline)).frame(width: 24).foregroundStyle(t.accent).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: DS.s1) {
                            Text(tp.title).font(.system(size: DS.body, weight: .semibold)).foregroundStyle(t.text).accessibilityAddTraits(.isHeader)
                            Text(tp.body).font(.system(size: DS.body)).foregroundStyle(t.secondary).fixedSize(horizontal: false, vertical: true)
                            if let a = tp.action { Button(a.0) { a.1(model) }.buttonStyle(DraftButtonStyle(compact: true)).padding(.top, DS.s1) }
                        }
                    }.padding(DS.s3 + 2)
                }
            }
        }
    }
}

// MARK: - Report a Problem

struct ReportProblemView: View {
    @Environment(AppModel.self) var model
    @Environment(\.tokens) var t
    @Environment(\.dismiss) var dismiss
    @State private var text = ""
    @State private var includeLog = true
    @State private var includeScreenshot = false
    @State private var screenshot: Data?
    var body: some View {
        let report = model.diagnosticReport(description: text, includeLog: includeLog)
        VStack(alignment: .leading, spacing: DS.s3) {
            Text("Report a Problem").font(.system(size: DS.title2, weight: .bold)).foregroundStyle(t.text).accessibilityAddTraits(.isHeader)
            Text("Describe what happened. Draft writes a report file you can read below and save; nothing is sent. Note text, titles, file names and the vault's location are never included.")
                .font(.system(size: DS.footnote)).foregroundStyle(t.secondary).fixedSize(horizontal: false, vertical: true)
            TextEditor(text: $text).font(.system(size: DS.body)).frame(height: 90).padding(4)
                .background(RoundedRectangle(cornerRadius: DS.rControl).strokeBorder(t.line)).accessibilityLabel("What happened")
            Toggle("Include the recent log (events and ids only)", isOn: $includeLog).toggleStyle(.checkbox)
            Toggle("Include a screenshot of the Draft window (it may show note text)", isOn: $includeScreenshot).toggleStyle(.checkbox)
                .onChange(of: includeScreenshot) { _, on in screenshot = on ? model.windowScreenshot() : nil }
            Text("Exactly what will be saved").font(.system(size: DS.footnote, weight: .semibold)).foregroundStyle(t.secondary)
            ScrollView { Text(report).font(.system(size: DS.caption, design: .monospaced)).foregroundStyle(t.text).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(DS.s2) }
                .frame(height: 220).background(RoundedRectangle(cornerRadius: DS.rControl).fill(t.hover))
            HStack {
                Button("Copy") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(report, forType: .string); model.toast("Report copied.") }.buttonStyle(DraftButtonStyle(compact: true))
                Spacer()
                Button("Cancel") { dismiss() }.buttonStyle(DraftButtonStyle(compact: true)).keyboardShortcut(.cancelAction)
                Button("Save Report…") { if model.saveReport(report, screenshot: includeScreenshot ? screenshot : nil) { dismiss() } }
                    .buttonStyle(DraftButtonStyle(role: .primary, compact: true)).keyboardShortcut(.defaultAction)
            }
        }
        .padding(DS.s5).frame(width: 600).background(t.canvas)
    }
}

extension AppModel {
    func diagnosticReport(description: String, includeLog: Bool) -> String {
        let info = Bundle.main.infoDictionary ?? [:]
        let os = ProcessInfo.processInfo.operatingSystemVersion
        var size = 0; var model = [CChar](repeating: 0, count: 64); size = 64; sysctlbyname("hw.model", &model, &size, nil, 0)
        let s = library.settings
        let input = Diagnostics.Input(
            description: description, appVersion: info["CFBundleShortVersionString"] as? String ?? "?", build: info["CFBundleVersion"] as? String ?? "?",
            channel: info["DraftChannel"] as? String ?? "?", commit: info["DraftCommit"] as? String ?? "?",
            system: "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)", machine: String(cString: model),
            displays: NSScreen.screens.map { "\(Int($0.frame.width))×\(Int($0.frame.height)) @\(Int($0.backingScaleFactor))x" },
            counts: ["notes": library.docs.values.filter { $0.deletedAt == nil }.count, "deleted notes": library.trashedDocs.count, "folders": library.folders.count,
                     "spaces": library.spaces.count, "attachments": (try? FileManager.default.contentsOfDirectory(atPath: vault.dir.appendingPathComponent("assets").path).count) ?? 0],
            switches: ["read-only": readOnly == nil ? "no" : "yes", "safe mode": recovery.safeMode ? "yes" : "no", "update checks": s.updateChecks ? "automatic" : "manual",
                       "update channel": s.updateChannel, "assistant": s.assistantProvider == .openai ? "OpenAI API" : "local", "image search": s.onlineImageSearch ? "on" : "off",
                       "link previews": s.linkPreviews ? "on" : "off", "reduce motion": s.reduceMotion ? "on" : "off", "telemetry": "none (Draft has none)",
                       "last save": lastSaveAt.map { ISO8601DateFormatter().string(from: $0) } ?? "none this session"],
            performance: ["link index \(String(format: "%.0f", lastIndexSeconds * 1000)) ms"],
            log: DraftLog.tail(120), includeLog: includeLog)
        return Diagnostics.report(input, titles: library.docs.values.map(\.title))
    }

    func windowScreenshot() -> Data? {
        guard let w = NSApp.windows.first(where: { $0.isVisible && $0.isMainWindow }) ?? NSApp.windows.first(where: { $0.isVisible }),
              let v = w.contentView, let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) else { return nil }
        v.cacheDisplay(in: v.bounds, to: rep)
        return rep.representation(using: .png, properties: [:])
    }

    /// Saves to a folder the person picks (default Desktop). Returns true when saved.
    func saveReport(_ text: String, screenshot: Data?) -> Bool {
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let folder: URL
        if let auto = ProcessInfo.processInfo.environment["DRAFT_REPORT_DIR"] { folder = URL(fileURLWithPath: auto) }
        else {
            let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.prompt = String(localized: "Save Here")
            panel.directoryURL = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
            guard panel.runModal() == .OK, let u = panel.url else { return false }
            folder = u
        }
        let dir = folder.appendingPathComponent("Draft Problem Report \(stamp)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try Data(text.utf8).write(to: dir.appendingPathComponent("report.md"))
            if let screenshot { try screenshot.write(to: dir.appendingPathComponent("screenshot.png")) }
            toast("Saved the report in “\(folder.lastPathComponent)”. Nothing was sent.", action: "Show") { NSWorkspace.shared.activateFileViewerSelecting([dir]) }
            DraftLog.write("problem report saved")
            return true
        } catch { toast("Couldn't save the report: \(error.localizedDescription)"); return false }
    }
}

// MARK: - Crash recovery

/// Shown once after Draft ended without quitting: what's known and the ways to continue.
struct CrashRecoveryCard: View {
    @Environment(AppModel.self) var model
    @Environment(\.tokens) var t
    let info: CrashInfo
    var body: some View {
        VStack(alignment: .leading, spacing: DS.s3) {
            Label("Draft quit unexpectedly last time", systemImage: "exclamationmark.triangle.fill").font(.system(size: DS.headline, weight: .semibold)).foregroundStyle(t.text)
            Text(info.lastSaveAt.map { "Your notes were last saved \($0.formatted(Date.FormatStyle(date: .abbreviated, time: .standard, locale: appLocale))). Draft saves half a second after you stop typing, so at most the last moment of typing can be missing. Versions and backups are untouched." }
                 ?? "Nothing was saved in that session. Versions and backups are untouched.")
                .font(.system(size: DS.footnote)).foregroundStyle(t.secondary).fixedSize(horizontal: false, vertical: true)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: DS.s2) { buttons }
                VStack(alignment: .leading, spacing: DS.s2) { buttons }
            }
        }
        .padding(DS.s4)
        .frame(maxWidth: 560, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: DS.rCard, style: .continuous).fill(t.card))
        .overlay(RoundedRectangle(cornerRadius: DS.rCard, style: .continuous).strokeBorder(t.line, lineWidth: 0.5))
        .shadow(color: .black.opacity(0.12), radius: 16, y: 6)
        .accessibilityElement(children: .contain)
    }
    @ViewBuilder var buttons: some View {
        Button("Check Vault") { model.recovery.crash = nil; model.showSettings("recovery"); Task { await model.checkVault() } }.buttonStyle(DraftButtonStyle(role: .primary, compact: true))
        Button("Restart in Safe Mode") { model.relaunchInSafeMode() }.buttonStyle(DraftButtonStyle(compact: true))
        Button("View Log") { NSWorkspace.shared.activateFileViewerSelecting([DraftLog.file]) }.buttonStyle(DraftButtonStyle(compact: true))
        Button("Report a Problem…") { model.recovery.crash = nil; model.reportProblem = true }.buttonStyle(DraftButtonStyle(compact: true))
        Button("Dismiss") { model.recovery.crash = nil }.buttonStyle(DraftButtonStyle(role: .quiet, compact: true)).keyboardShortcut(.cancelAction)
    }
}

// MARK: - Backup archive (Data & Storage)

struct BackupArchiveSection: View {
    @Environment(AppModel.self) var model
    @Environment(\.tokens) var t
    @State private var working = false
    @State private var last: String?
    var body: some View {
        SettingsSection(title: "Backup archive", footer: "One .zip with every note, attachment, version and backup, your settings, and a manifest with a checksum for each file. Restoring puts it in a new folder and checks it — it never writes over your vault.") {
            SettingsRow(title: "Create Backup Archive", detail: LocalizedStringKey(last ?? String(localized: "Saved to Documents › Draft Backups"))) {
                if working { ProgressView().controlSize(.small) } else {
                    Button("Create…") { create() }.buttonStyle(DraftButtonStyle(compact: true))
                }
            }
            SettingsRow(title: "Restore and Check an Archive", detail: "Extracts into a new folder next to the archive and runs Vault Check on it.") {
                Button("Choose…") { restore() }.buttonStyle(DraftButtonStyle(compact: true)).disabled(working)
            }
        }
    }
    func create() {
        working = true; model.flushAll()
        let v = model.vault, folder = model.defaultBackupFolder(), ver = model.updates.version
        Task {
            let r = await Task.detached { Result { try BackupArchive.create(vault: v, into: folder, appVersion: ver) } }.value
            working = false
            switch r {
            case .success(let url): last = url.lastPathComponent; model.toast("Backup archive saved.", action: "Show") { NSWorkspace.shared.activateFileViewerSelecting([url]) }; DraftLog.write("backup archive created")
            case .failure(let e): model.toast("Couldn't create the archive: \(e.localizedDescription)")
            }
        }
    }
    func restore() {
        let p = NSOpenPanel(); p.allowedContentTypes = [.zip]; p.directoryURL = model.defaultBackupFolder()
        guard p.runModal() == .OK, let zip = p.url else { return }
        working = true
        Task {
            let r = await Task.detached { Result { try BackupArchive.restore(zip, into: zip.deletingLastPathComponent()) } }.value
            working = false
            switch r {
            case .success(let x):
                let n = x.check.issues.filter { $0.severity > .info }.count
                model.toast(n == 0 ? "Restored and checked: \(x.manifest.files.count) files, no problems." : "Restored \(x.manifest.files.count) files; Vault Check found \(n) problems.", action: "Show") { NSWorkspace.shared.activateFileViewerSelecting([x.vault]) }
            case .failure(let e): model.toast("\(e.localizedDescription)")
            }
        }
    }
}
