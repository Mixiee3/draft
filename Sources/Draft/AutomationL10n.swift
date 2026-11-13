import AppKit
import SwiftUI
import Vision
import DraftCore

/// `l10n-shots`: run with `-AppleLanguages "(cs)"` (or de). Opens the main screens, captures each
/// one, and reads every text the accessibility tree exposes. A text is reported as English when it
/// is itself a catalog key that has a translation in this language (a code path that skipped
/// localization), or when it reads like English prose. Also records every control without a name
/// (the accessibility audit). AUDIT_NARROW / AUDIT_DARK as elsewhere.
extension Automation {
    static let englishWords: Set<String> = ["the", "and", "your", "with", "this", "that", "from", "into", "will", "isn't", "can't", "don't", "only", "every", "when", "are", "is", "to", "of", "it"]

    /// Every accessibility element under `e`: (role, text, has a name).
    static func axWalk(_ e: Any, depth: Int = 0, into out: inout [(role: String, text: String, named: Bool)]) {
        guard depth < 60, let o = e as? NSAccessibilityProtocol else { return }
        let role = o.accessibilityRole()?.rawValue ?? ""
        let label = o.accessibilityLabel() ?? ""
        let title = o.accessibilityTitle() ?? ""
        let value = o.accessibilityValue() as? String ?? ""
        let text = [label, title, value].first { !$0.isEmpty } ?? ""
        if !role.isEmpty && !o.isAccessibilityHidden() { out.append((role, text, !(label.isEmpty && title.isEmpty && value.isEmpty))) }
        for c in o.accessibilityChildren() ?? [] { axWalk(c, depth: depth + 1, into: &out) }
    }

    static func englishLooking(_ s: String) -> Bool {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.count > 2, t.rangeOfCharacter(from: .letters) != nil else { return false }
        // A catalog key with a different translation in this language: shown untranslated.
        let tr = Bundle.main.localizedString(forKey: t, value: "§§", table: nil)
        if tr != "§§" && tr != t { return true }
        let words = t.lowercased().split { !$0.isLetter && $0 != "'" }.map(String.init)
        return words.count >= 3 && words.filter { englishWords.contains($0) }.count >= 2
    }

    /// Text lines recognised on a captured screen (Vision, on this Mac).
    static func ocrLines(_ url: URL) -> [String] {
        guard let img = NSImage(contentsOf: url), let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return [] }
        let req = VNRecognizeTextRequest()
        req.recognitionLevel = .accurate
        req.recognitionLanguages = ["cs-CZ", "de-DE", "en-US"]
        req.usesLanguageCorrection = false
        try? VNImageRequestHandler(cgImage: cg).perform([req])
        return (req.results ?? []).compactMap { $0.topCandidates(1).first?.string }
    }

    static func l10nShots() async {
        guard let w = NSApp.windows.first(where: { $0.isVisible }) else { return }
        let env = ProcessInfo.processInfo.environment
        let narrow = env["AUDIT_NARROW"] != nil, dark = env["AUDIT_DARK"] != nil
        let lang = Bundle.main.preferredLocalizations.first ?? "en"
        let p = lang + "-" + (narrow ? "narrow-" : "") + (dark ? "dark-" : "")
        w.setFrame(NSRect(x: 40, y: 40, width: narrow ? 720 : 1280, height: narrow ? 700 : 900), display: true)
        m.setSettings { $0.theme = dark ? "dark" : "light" }
        var report: [String: Any] = ["language": lang]
        var english: [String: [String]] = [:], unnamed: [String: [String]] = [:], texts: [String: Int] = [:], axCounts: [String: Int] = [:]
        guard let doc = m.createDoc(title: "Plán cesty") else { return }
        let c = m.editor(for: doc).controller
        c.pastePlainForAutomation("## Plán\nLetíme v pondělí ráno #cesta\n- [ ] Rezervovat hotel\n| Den | Místo |\n| --- | --- |\n| 1 | Lisabon |")
        m.editorChanged(doc); m.flushAll()
        m.saveVersionNow(doc)
        let screens: [(String, () -> Void, () -> Void)] = [
            ("library", { m.openView(.all) }, {}),
            ("document", { m.openView(.doc(doc)) }, {}),
            ("format", { m.openView(.doc(doc)); m.panel = .format }, { m.panel = nil }),
            ("style", { m.panel = .style }, { m.panel = nil }),
            ("info", { m.panel = .info }, { m.panel = nil }),
            ("share", { m.panel = .share }, { m.panel = nil }),
            ("search", { m.openView(.all); m.librarySearchOpen = true; m.librarySearch = "hotel" }, { m.librarySearch = "" }),
            ("settings-appearance", { m.openView(ViewRef(kind: "settings", section: "appearance")) }, {}),
            ("settings-editor", { m.openView(ViewRef(kind: "settings", section: "editor")) }, {}),
            ("settings-daily", { m.openView(ViewRef(kind: "settings", section: "daily")) }, {}),
            ("settings-assistant", { m.openView(ViewRef(kind: "settings", section: "assistant")) }, {}),
            ("settings-agents", { m.openView(ViewRef(kind: "settings", section: "agents")) }, {}),
            ("settings-data", { m.openView(ViewRef(kind: "settings", section: "data")) }, {}),
            ("recovery-check", { m.openView(ViewRef(kind: "settings", section: "recovery")); m.recovery.tab = "check" }, {}),
            ("recovery-backups", { m.recovery.tab = "backups"; m.refreshBackups() }, {}),
            ("recovery-migration", { m.recovery.tab = "migration" }, { m.recovery.tab = "check" }),
            ("version-history", { m.openView(.doc(doc)); m.recovery.historyDoc = HistoryTarget(id: doc) }, { m.recovery.historyDoc = nil }),
            ("assistant", { m.openView(.doc(doc)); m.toggleAssistant() }, { m.toggleAssistant() }),
        ]
        for (name, open, close) in screens {
            open()
            if name == "recovery-check" { await m.checkVault() }
            await wait(1.0)
            await shot(p + name, w, settle: 0.2)
            var all: [(role: String, text: String, named: Bool)] = []
            // SwiftUI builds its accessibility tree on the first request; ask, let it build, then read.
            if let v = w.contentView { var warm: [(role: String, text: String, named: Bool)] = []; axWalk(v, into: &warm); await wait(0.6) }
            if let v = w.contentView { axWalk(v, into: &all) }
            if let s = w.attachedSheet?.contentView { axWalk(s, into: &all) }
            let lines = ocrLines(out.appendingPathComponent(p + name + ".png"))
            texts[name] = lines.count
            english[name] = Array(Set((all.map(\.text) + lines).filter(englishLooking))).sorted()
            let controls: Set<String> = ["AXButton", "AXCheckBox", "AXRadioButton", "AXPopUpButton", "AXMenuButton", "AXTextField", "AXSlider", "AXComboBox"]
            axCounts[name] = all.count
            unnamed[name] = all.filter { controls.contains($0.role) && !$0.named }.map(\.role)
            close()
            await wait(0.3)
        }
        report["textsRead"] = texts
        report["english"] = english
        report["englishCount"] = english.values.reduce(0) { $0 + $1.count }
        report["unnamedControls"] = unnamed.mapValues(\.count)
        report["axElements"] = axCounts
        m.flushAll()
        if let d = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) { try? d.write(to: out.appendingPathComponent(p + "l10n.json")) }
    }
}
