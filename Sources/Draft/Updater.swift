import AppKit
import SwiftUI
import DraftCore

/// Opt-in updates (docs/UPDATES.md). Nothing touches the network unless the person clicks
/// Check for Updates… or has turned automatic checks on. The feed and the download are verified
/// with Draft's Ed25519 release key; the new app's code signature, bundle id, build and channel
/// are checked before it replaces this one, and the old app is kept until the new one has launched.
@MainActor
@Observable
final class UpdateController {
    enum Phase: Equatable {
        case idle, checking, upToDate, available(UpdateItem), downloading(Double), ready(UpdateItem), installing, failed(String)
    }
    var phase: Phase = .idle
    var lastChecked: Date?
    /// Requests made to the update feed in this session (tests check it stays 0 when checks are off).
    private(set) var fetchCount = 0
    var installOnQuit: UpdateItem?
    var sheet = false
    @ObservationIgnored private var downloadTask: Task<Void, Never>?
    @ObservationIgnored private var stagedApp: URL?
    @ObservationIgnored weak var model: AppModel?

    let info = Bundle.main.infoDictionary ?? [:]
    var version: String { info["CFBundleShortVersionString"] as? String ?? "0" }
    var build: Int { Int(info["CFBundleVersion"] as? String ?? "0") ?? 0 }
    /// The channel this build was made for (development for local builds).
    var buildChannel: String { info["DraftChannel"] as? String ?? "development" }
    var env: [String: String] { ProcessInfo.processInfo.environment }
    /// Test mode: only in development builds, with a feed and key given in the environment.
    var testMode: Bool { buildChannel == "development" && env["DRAFT_UPDATE_TEST"] == "1" }
    var feedURL: URL? {
        if testMode, let f = env["DRAFT_UPDATE_FEED"] { return URL(string: f) }
        return (info["DraftUpdateFeedURL"] as? String).flatMap(URL.init(string:))
    }
    var publicKeyBase64: String? { testMode ? env["DRAFT_UPDATE_TEST_KEY"] : info["DraftUpdatePublicKey"] as? String }
    /// Where updates are staged and the previous app is kept (outside the vault).
    var workDir: URL {
        if testMode, let d = env["DRAFT_UPDATE_DIR"] { return URL(fileURLWithPath: d) }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Draft/Updates", isDirectory: true)
    }
    /// The app that gets replaced.
    var destination: URL { testMode && env["DRAFT_UPDATE_DEST"] != nil ? URL(fileURLWithPath: env["DRAFT_UPDATE_DEST"]!) : Bundle.main.bundleURL }

    var available: Bool { feedURL != nil && (try? Updates.publicKey(base64: publicKeyBase64)) != nil }

    /// Automatic check at launch, only when the person turned it on.
    func launchCheck(settings: DraftCore.Settings) {
        guard settings.updateChecks else { return }
        Task { await check(manual: false, settings: settings) }
    }

    func check(manual: Bool, settings: DraftCore.Settings) async {
        guard manual || settings.updateChecks else { return } // no request when automatic checks are off
        guard let url = feedURL else { if manual { phase = .failed(String(localized: "This build has no update address. Updates come with release builds.")); sheet = true }; return }
        guard Updates.allowed(url, testMode: testMode) else { phase = .failed(UpdateError.notHTTPS.localizedDescription); sheet = manual; return }
        if manual { sheet = true }
        phase = .checking
        fetchCount += 1
        do {
            let key = try Updates.publicKey(base64: publicKeyBase64)
            let data = try await fetch(url)
            let items = try Updates.items(fromFeed: data, key: key)
            lastChecked = Date()
            if let item = Updates.newest(in: items, channel: settings.updateChannel, currentBuild: build, skipped: manual ? nil : settings.skippedUpdate) {
                phase = .available(item); sheet = true
            } else { phase = .upToDate }
        } catch {
            // Offline or a bad feed: say so when asked, stay quiet for automatic checks.
            phase = .failed((error as? URLError).map { _ in String(localized: "Draft couldn't reach the update server. Check your connection and try again.") } ?? error.localizedDescription)
            if !manual { sheet = false }
        }
    }

    private func fetch(_ url: URL) async throws -> Data {
        if url.isFileURL { return try Data(contentsOf: url) }
        let cfg = URLSessionConfiguration.ephemeral // no cookies, no cache, no credentials
        cfg.timeoutIntervalForRequest = 20
        let (d, r) = try await URLSession(configuration: cfg).data(from: url)
        guard (r as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return d
    }

    func download(_ item: UpdateItem) {
        guard let url = URL(string: item.url), Updates.allowed(url, testMode: testMode) else { phase = .failed(UpdateError.notHTTPS.localizedDescription); return }
        phase = .downloading(0)
        downloadTask = Task {
            do {
                let data: Data
                if url.isFileURL { data = try Data(contentsOf: url); phase = .downloading(1) }
                else {
                    let (bytes, _) = try await URLSession(configuration: .ephemeral).bytes(from: url)
                    var buf = Data(); buf.reserveCapacity(Int(item.size))
                    for try await b in bytes {
                        buf.append(b)
                        if buf.count % 262_144 == 0 { phase = .downloading(Double(buf.count) / Double(max(1, item.size))) }
                        if Task.isCancelled { phase = .available(item); return }
                    }
                    data = buf
                }
                try Updates.verifyArchive(data, item: item, key: try Updates.publicKey(base64: publicKeyBase64))
                stagedApp = try stage(data, item: item)
                phase = .ready(item)
            } catch is CancellationError { phase = .available(item) }
            catch { phase = .failed(error.localizedDescription) }
        }
    }

    func cancelDownload() { downloadTask?.cancel() }

    /// Unzips into the work folder and checks the app inside before anything is replaced.
    func stage(_ data: Data, item: UpdateItem) throws -> URL {
        let fm = FileManager.default
        let dir = workDir.appendingPathComponent("staged-\(item.build)", isDirectory: true)
        try? fm.removeItem(at: dir)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let zip = dir.appendingPathComponent("update.zip")
        try data.write(to: zip)
        try run("/usr/bin/ditto", ["-x", "-k", zip.path, dir.path])
        guard let app = try fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil).first(where: { $0.pathExtension == "app" }),
              let plist = NSDictionary(contentsOf: app.appendingPathComponent("Contents/Info.plist")) as? [String: Any] else {
            throw MigrationError(message: String(localized: "The update doesn't contain Draft."))
        }
        guard plist["CFBundleIdentifier"] as? String == Bundle.main.bundleIdentifier else { throw MigrationError(message: String(localized: "The update is a different app.")) }
        guard Int(plist["CFBundleVersion"] as? String ?? "") == item.build else { throw MigrationError(message: String(localized: "The update's build number doesn't match the update list.")) }
        let channel = plist["DraftChannel"] as? String ?? "development"
        if channel == "development" && buildChannel != "development" {
            throw MigrationError(message: String(localized: "A development build never replaces a stable or beta Draft."))
        }
        try run("/usr/bin/codesign", ["--verify", "--deep", "--strict", app.path])
        if let team = teamID(Bundle.main.bundleURL), teamID(app) != team { throw MigrationError(message: String(localized: "The update is signed by someone else.")) }
        return app
    }

    func teamID(_ app: URL) -> String? {
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/codesign"); p.arguments = ["-dv", app.path]
        let pipe = Pipe(); p.standardError = pipe; p.standardOutput = Pipe()
        try? p.run(); p.waitUntilExit()
        let out = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        return out.split(separator: "\n").first { $0.hasPrefix("TeamIdentifier=") }.map { String($0.dropFirst(15)) }.flatMap { $0 == "not set" ? nil : $0 }
    }

    @discardableResult
    func run(_ tool: String, _ args: [String]) throws -> String {
        let p = Process(); p.executableURL = URL(fileURLWithPath: tool); p.arguments = args
        let out = Pipe(); p.standardOutput = out; p.standardError = out
        try p.run(); p.waitUntilExit()
        let s = String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        guard p.terminationStatus == 0 else { throw MigrationError(message: "\(URL(fileURLWithPath: tool).lastPathComponent) failed: \(s.prefix(300))") }
        return s
    }

    /// Hands the staged app to the installer script, which waits for this app to quit, keeps the old
    /// app, moves the new one into place and, when `relaunch`, puts the old one back if the new one
    /// doesn't report that it started.
    func install(_ item: UpdateItem, relaunch: Bool) throws {
        guard let staged = stagedApp else { throw MigrationError(message: String(localized: "The update isn't downloaded yet.")) }
        let fm = FileManager.default
        try fm.createDirectory(at: workDir, withIntermediateDirectories: true)
        let backup = workDir.appendingPathComponent("previous", isDirectory: true)
        let marker = workDir.appendingPathComponent("launched-\(item.build)")
        try? fm.removeItem(at: marker)
        let launch = testMode ? (env["DRAFT_UPDATE_LAUNCH"] ?? "true") : "/usr/bin/open \"$DEST\""
        let script = """
        #!/bin/bash
        # Draft updater: replace the app after it quits; roll back if the new one doesn't start.
        PID=\(ProcessInfo.processInfo.processIdentifier); NEW="\(staged.path)"; DEST="\(destination.path)"; BACKUP="\(backup.path)"; MARKER="\(marker.path)"; LOG="\(workDir.appendingPathComponent("install.log").path)"
        exec >>"$LOG" 2>&1; echo "$(date) install \(item.version) (\(item.build)) relaunch=\(relaunch ? 1 : 0)"
        for i in $(seq 1 600); do kill -0 $PID 2>/dev/null || break; sleep 0.1; done
        rm -rf "$BACKUP"; mkdir -p "$BACKUP"
        mv "$DEST" "$BACKUP/Draft.app" || { echo "could not move the old app"; exit 1; }
        if ! /usr/bin/ditto "$NEW" "$DEST" || ! /usr/bin/codesign --verify --deep --strict "$DEST"; then
          echo "install failed, rolling back"; rm -rf "$DEST"; mv "$BACKUP/Draft.app" "$DEST"; touch "\(workDir.appendingPathComponent("rolled-back").path)"; exit 1
        fi
        if [ \(relaunch ? 1 : 0) = 1 ]; then
          \(launch) &
          for i in $(seq 1 \(testMode ? 200 : 400)); do [ -f "$MARKER" ] && break; sleep 0.1; done
          if [ ! -f "$MARKER" ]; then
            echo "new app did not start, rolling back"; pkill -f "$DEST/Contents/MacOS/Draft"; rm -rf "$DEST"; mv "$BACKUP/Draft.app" "$DEST"
            touch "\(workDir.appendingPathComponent("rolled-back").path)"
            \(testMode ? "" : "/usr/bin/open \"$DEST\"")
            exit 1
          fi
        fi
        echo "installed"
        """
        let url = workDir.appendingPathComponent("install.sh")
        try script.write(to: url, atomically: true, encoding: .utf8)
        try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/bin/bash"); p.arguments = [url.path]
        p.environment = ProcessInfo.processInfo.environment.filter { !$0.key.hasPrefix("DRAFT_AUTOMATION") }
        try p.run() // detached: keeps running after Draft quits
        phase = .installing
    }

    /// Quits so the installer can swap the app. AppKit ignores terminate while a sheet is attached
    /// (the update sheet itself), so close sheets first.
    func quitForInstall() {
        sheet = false
        for w in NSApp.windows { if let s = w.attachedSheet { w.endSheet(s) } }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { NSApp.terminate(nil) }
    }

    /// At launch: say whether the last update rolled back, and confirm this app started.
    func launchedAfterUpdate() -> String? {
        let fm = FileManager.default
        try? fm.createDirectory(at: workDir, withIntermediateDirectories: true)
        fm.createFile(atPath: workDir.appendingPathComponent("launched-\(build)").path, contents: Data(version.utf8))
        let rb = workDir.appendingPathComponent("rolled-back")
        if fm.fileExists(atPath: rb.path) { try? fm.removeItem(at: rb); return String(localized: "The last update couldn't start, so Draft put the previous version back. Your notes weren't touched.") }
        return nil
    }
}
