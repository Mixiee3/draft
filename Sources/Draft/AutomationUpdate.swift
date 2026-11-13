import AppKit
import DraftCore

/// Updater test mode (scripts/update-test.sh), on a copy of the app and a throwaway vault:
/// - `update-e2e`: check → download → verify → install. DRAFT_UPDATE_MODE=restart installs and relaunches,
///   `quit` defers to Install on Quit, `later` only downloads (Remind Me Later: nothing changes).
/// - `update-disabled`: with automatic checks off, the launch check and an automatic check make no request.
/// - `update-after`: the relaunched app reports its version and quits.
extension Automation {
    static func updateE2E() async {
        let u = m.updates, mode = ProcessInfo.processInfo.environment["DRAFT_UPDATE_MODE"] ?? "restart"
        var r: [String: Any] = ["testMode": u.testMode, "from": "\(u.version) (\(u.build))"]
        defer {
            writeResult(r, "update-e2e.json")
            // Automation terminates next; AppKit ignores terminate while the update sheet is attached.
            u.sheet = false
            for w in NSApp.windows { if let s = w.attachedSheet { w.endSheet(s) } }
        }
        await u.check(manual: true, settings: m.library.settings)
        r["fetches"] = u.fetchCount
        guard case .available(let item) = u.phase else { r["phase"] = "\(u.phase)"; return }
        r["offered"] = "\(item.version) (\(item.build))"
        u.download(item)
        for _ in 0..<200 { if case .downloading = u.phase { await wait(0.1) } else { break } }
        r["phase"] = "\(u.phase)"
        guard case .ready = u.phase else { return }
        switch mode {
        case "quit": u.installOnQuit = item           // applicationWillTerminate installs without relaunch
        case "later": break
        default:
            do { try u.install(item, relaunch: true) } catch { r["installError"] = error.localizedDescription }
        }
        r["installing"] = mode
    }

    static func updateDisabled() async {
        let u = m.updates
        var r: [String: Any] = ["updateChecks": m.library.settings.updateChecks]
        defer { writeResult(r, "update-disabled.json") }
        u.launchCheck(settings: m.library.settings)
        await u.check(manual: false, settings: m.library.settings)
        await wait(0.5)
        r["fetches"] = u.fetchCount
        r["phase"] = "\(u.phase)"
    }

    static func updateAfter() async {
        writeResult(["version": m.updates.version, "build": m.updates.build], "update-after.json")
    }
}
