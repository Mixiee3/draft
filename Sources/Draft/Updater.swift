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
                else { data = try await fetchArchive(url) { p in self.phase = .downloading(p) } }
                if Task.isCancelled { phase = .available(item); return }
                try Updates.verifyArchive(data, item: item, key: try Updates.publicKey(base64: publicKeyBase64))
                stagedApp = try stage(data, item: item)
                phase = .ready(item)
            } catch is CancellationError { phase = .available(item) }
            catch let e as URLError where e.code == .cancelled { phase = .available(item) }
            catch { phase = .failed(error.localizedDescription) }
        }
    }

    /// One native download task with progress (a byte-by-byte loop was far too slow for a 14 MB archive).
    /// Ephemeral session: no cookies, cache or credentials. Cancelling the Task cancels the transfer.
    func fetchArchive(_ url: URL, progress: @escaping @MainActor (Double) -> Void) async throws -> Data {
        let session = URLSession(configuration: .ephemeral)
        defer { session.finishTasksAndInvalidate() }
        var task: URLSessionDownloadTask?
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Data, Error>) in
                var observation: NSKeyValueObservation?
                let t = session.downloadTask(with: url) { file, response, error in
                    withExtendedLifetime(observation) {} // keeps progress updates alive until the transfer ends
                    if let error { cont.resume(throwing: error); return }
                    guard (response as? HTTPURLResponse)?.statusCode == 200, let file else { cont.resume(throwing: URLError(.badServerResponse)); return }
                    do { cont.resume(returning: try Data(contentsOf: file)) } catch { cont.resume(throwing: error) }
                }
                observation = t.progress.observe(\.fractionCompleted) { p, _ in
                    let f = p.fractionCompleted
                    Task { @MainActor in progress(f) }
                }
                task = t
                t.resume()
            }
        } onCancel: {
            task?.cancel()
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
        let failedMarker = workDir.appendingPathComponent("install-failed")
        try? fm.removeItem(at: marker)
        try? fm.removeItem(at: failedMarker)
        let launch = testMode ? (env["DRAFT_UPDATE_LAUNCH"] ?? "true") : "open_app \"$DEST\""
        let team = teamID(destination) ?? ""
        let ownerUID = (try? fm.attributesOfItem(atPath: NSHomeDirectory())[.ownerAccountID] as? NSNumber)?.stringValue ?? ""
        let script = """
        #!/bin/bash
        # Draft updater: replace the app after it quits; roll back if the new one doesn't start.
        PID=\(ProcessInfo.processInfo.processIdentifier); NEW="\(staged.path)"; DEST="\(destination.path)"; BACKUP="\(backup.path)"; MARKER="\(marker.path)"; FAILED="\(failedMarker.path)"; LOG="\(workDir.appendingPathComponent("install.log").path)"; TEAM="\(team)"; OWNER_UID="\(ownerUID)"
        exec >>"$LOG" 2>&1; echo "$(date) install \(item.version) (\(item.build)) relaunch=\(relaunch ? 1 : 0)"
        open_app() {
          if [ "$(/usr/bin/id -u)" = "0" ]; then
            CONSOLE_UID=$(/usr/bin/stat -f '%u' /dev/console)
            /bin/launchctl asuser "$CONSOLE_UID" /usr/bin/open "$1"
          else /usr/bin/open "$1"; fi
        }
        fix_owner() { if [ -n "$OWNER_UID" ]; then /usr/sbin/chown "$OWNER_UID" "$LOG" "$FAILED" "\(workDir.appendingPathComponent("rolled-back").path)" 2>/dev/null || true; fi; }
        fail() { echo "INSTALL FAILED: $*"; touch "$FAILED"; fix_owner; if [ -d "$DEST" ]; then open_app "$DEST" >/dev/null 2>&1 || true; fi; exit 1; }
        for i in $(seq 1 600); do kill -0 "$PID" 2>/dev/null || break; sleep 0.1; done
        if kill -0 "$PID" 2>/dev/null; then fail "Draft did not quit within 60 seconds"; fi
        rm -rf "$BACKUP"; mkdir -p "$BACKUP" || fail "could not create backup folder: $BACKUP"
        mv "$DEST" "$BACKUP/Draft.app" || fail "could not move the old app (check folder permissions)"
        if ! /usr/bin/ditto "$NEW" "$DEST" || ! /usr/bin/codesign --verify --deep --strict "$DEST"; then
          echo "install failed, rolling back"; rm -rf "$DEST"; mv "$BACKUP/Draft.app" "$DEST" || fail "install failed and rollback could not restore the old app"; touch "\(workDir.appendingPathComponent("rolled-back").path)"; touch "$FAILED"; fix_owner; open_app "$DEST" >/dev/null 2>&1 || true; exit 1
        fi
        if [ -n "$TEAM" ]; then NEW_TEAM=$(/usr/bin/codesign -dv "$DEST" 2>&1 | /usr/bin/sed -n 's/^TeamIdentifier=//p'); [ "$NEW_TEAM" = "$TEAM" ] || { rm -rf "$DEST"; mv "$BACKUP/Draft.app" "$DEST" || fail "signing check failed and rollback could not restore the old app"; fail "the installed app's signing team changed"; }; fi
        # The archive and app have both passed Draft's cryptographic and code-signature checks.
        # Remove download quarantine from this verified copy so Gatekeeper does not block an
        # otherwise valid, explicitly user-approved in-app update on a non-notarized build.
        /usr/bin/xattr -dr com.apple.quarantine "$DEST" 2>/dev/null || true
        if [ \(relaunch ? 1 : 0) = 1 ]; then
          \(launch) &
          for i in $(seq 1 \(testMode ? 200 : 400)); do [ -f "$MARKER" ] && break; sleep 0.1; done
          if [ ! -f "$MARKER" ]; then
            echo "new app did not start, rolling back"; pkill -f "$DEST/Contents/MacOS/Draft"; rm -rf "$DEST"; mv "$BACKUP/Draft.app" "$DEST" || fail "new app did not start and rollback could not restore the old app"
            touch "\(workDir.appendingPathComponent("rolled-back").path)"
            touch "$FAILED"
            fix_owner
            \(testMode ? "" : "open_app \"$DEST\"")
            exit 1
          fi
        fi
        echo "installed"
        fix_owner
        """
        let url = workDir.appendingPathComponent("install.sh")
        try script.write(to: url, atomically: true, encoding: .utf8)
        try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
        let parent = destination.deletingLastPathComponent().path
        let needsAuthorization = !fm.isWritableFile(atPath: parent) && !testMode
        var commandURL = url
        if needsAuthorization {
            // A small unprivileged supervisor keeps the old version available if the user cancels
            // the macOS authorization prompt. The privileged script re-verifies the code signature.
            let appleScriptPath = url.path.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
            let supervisor = """
            #!/bin/bash
            PID=\(ProcessInfo.processInfo.processIdentifier)
            /usr/bin/osascript <<'APPLESCRIPT'
            do shell script "/bin/bash " & quoted form of "\(appleScriptPath)" with administrator privileges
            APPLESCRIPT
            STATUS=$?
            if [ "$STATUS" -ne 0 ]; then
              for i in $(seq 1 600); do kill -0 "$PID" 2>/dev/null || break; sleep 0.1; done
              echo "$(date) authorization cancelled or privileged install failed (status $STATUS)" >> "\(workDir.appendingPathComponent("install.log").path)"
              touch "\(failedMarker.path)"
              /usr/bin/open "\(destination.path)" >/dev/null 2>&1 || true
            fi
            """
            let supervisorURL = workDir.appendingPathComponent("install-supervisor.sh")
            try supervisor.write(to: supervisorURL, atomically: true, encoding: .utf8)
            try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: supervisorURL.path)
            commandURL = supervisorURL
        }
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/bin/bash"); p.arguments = [commandURL.path]
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
        let failed = workDir.appendingPathComponent("install-failed")
        if fm.fileExists(atPath: failed.path) {
            try? fm.removeItem(at: failed)
            return String(localized: "The last update could not be installed. Draft kept your previous version and your notes are unchanged. Open Settings › Updates to try again. Details are in ~/Library/Application Support/Draft/Updates/install.log.")
        }
        return nil
    }
}
