import AppKit
import DraftCore

/// `vault-check`: Settings › Data & Storage on a clean throwaway vault, then with one problem of each
/// kind, the move confirmation, the Undo toast, and a check that Undo restores the same bytes. AUDIT_DARK for dark.
extension Automation {
    static func vaultCheckShots() async {
        guard let w = NSApp.windows.first(where: { $0.isVisible }) else { return }
        let dark = ProcessInfo.processInfo.environment["AUDIT_DARK"] != nil
        let p = dark ? "dark-" : ""
        var r: [String: Any] = [:]
        defer { if let d = try? JSONSerialization.data(withJSONObject: r, options: [.prettyPrinted, .sortedKeys]) { try? d.write(to: out.appendingPathComponent(p + "vault-check.json")) } }
        w.setFrame(NSRect(x: 40, y: 40, width: 1280, height: 900), display: true)
        m.setSettings { $0.theme = dark ? "dark" : "light" }
        m.openView(ViewRef(kind: "settings", section: "data"))
        await m.checkVault()
        r["clean.problems"] = m.vaultReport?.problemCount ?? -1
        r["clean.unused"] = m.vaultReport?.unusedAssets.count ?? -1
        await shot(p + "vault-clean", w)
        // One problem of each kind, made on the throwaway vault's files.
        let v = m.vault
        let unused = (try? v.putAsset(Data("unused picture \(dark)".utf8), ext: "png")) ?? ""
        try? Vault.writeAtomic(Data("{}".utf8), to: v.dir.appendingPathComponent("docs/d_brokenfile.json"))
        if let id = m.createDoc(title: "Missing image") {
            m.editor(for: id).controller.load(Node("doc", content: [Node("image", attrs: ["id": "b_missing", "assetId": "0123456789abcdef0123456789abcdef.png"])]))
            m.editorChanged(id)
        }
        m.openView(ViewRef(kind: "settings", section: "data"))
        await m.checkVault()
        r["problems.stray"] = m.vaultReport?.strayDocFiles ?? []
        r["problems.missingAssets"] = m.vaultReport?.missingAssets ?? []
        r["problems.unusedWhileUnreadable"] = m.vaultReport?.unusedAssets.count ?? -1
        await shot(p + "vault-problems", w)
        // Remove the unreadable note so unused files can be listed, then confirm and move.
        try? FileManager.default.removeItem(at: v.dir.appendingPathComponent("docs/d_brokenfile.json"))
        await m.checkVault()
        r["unused.listed"] = m.vaultReport?.unusedAssets.contains(unused) ?? false
        m.vaultConfirmMove = true
        await shot(p + "vault-confirm", w)
        let before = (try? Data(contentsOf: v.assetURL(unused))) ?? Data()
        await m.moveUnusedFiles()
        r["moved.gone"] = !FileManager.default.fileExists(atPath: (try? v.assetURL(unused).path) ?? "")
        r["moved.toast"] = m.toasts.first?.message ?? ""
        await shot(p + "vault-moved", w)
        m.toasts.first?.action?()
        await wait(0.5)
        r["undo.sameBytes"] = ((try? Data(contentsOf: v.assetURL(unused))) ?? Data()) == before && !before.isEmpty
        r["undo.listedAgain"] = m.vaultReport?.unusedAssets.contains(unused) ?? false
        m.flushAll()
    }
}
