import AppKit
import SwiftUI
import DraftCore
import DraftEditor

/// Scripted runs used for the persistence smoke test and for capturing screenshots.
/// Enabled only through environment variables; never active in normal use.
///   DRAFT_AUTOMATION=smoke-write | smoke-read | screenshots
///   DRAFT_OUT=<directory for results/screenshots>
@MainActor
enum Automation {
    static var out: URL { URL(fileURLWithPath: ProcessInfo.processInfo.environment["DRAFT_OUT"] ?? NSTemporaryDirectory()) }

    static func startIfRequested() {
        guard let mode = ProcessInfo.processInfo.environment["DRAFT_AUTOMATION"] else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.2))
            switch mode {
            case "smoke-write": await smokeWrite()
            case "smoke-read": smokeRead()
            case "screenshots": await screenshots()
            default: break
            }
            NSApp.terminate(nil)
        }
    }

    static var m: AppModel { AppModel.shared }

    static func wait(_ s: Double = 0.6) async { try? await Task.sleep(for: .seconds(s)) }

    static func type(_ s: String, into c: EditorController) async {
        for ch in s {
            if ch == "\n" { c.textView.insertNewline(nil); try? await Task.sleep(for: .milliseconds(8)); continue }
            c.textView.insertText(String(ch), replacementRange: c.textView.selectedRange())
            try? await Task.sleep(for: .milliseconds(8))
        }
    }

    static func smokeWrite() async {
        guard let id = m.createDoc(title: "") else { return }
        await wait()
        guard let ed = m.editors[id] else { return }
        ed.titleView.insertText("Smoke test document", replacementRange: NSRange(location: 0, length: 0))
        ed.focusBody(atStart: true)
        await type("## Persisted heading\n", into: ed.controller)
        await type("Typed **bold** text survives a restart.\n", into: ed.controller)
        await type("[] a task\n", into: ed.controller)
        // Styling is stored separately from content.
        m.updateAppearance(id) { $0.styleId = "ember" }
        if let t = m.createDoc(open: false, title: "Trash me") { m.flushAll(); m.requestDelete(t) }
        await wait(1.0)
        try? Data(id.utf8).write(to: out.appendingPathComponent("smoke-doc-id.txt"))
        // Quit immediately: the quit path itself must flush pending saves.
    }

    static func smokeRead() {
        let id = (try? String(contentsOf: out.appendingPathComponent("smoke-doc-id.txt"), encoding: .utf8)) ?? ""
        var result: [String: String] = ["docId": id]
        if let meta = m.library.docs[id], let doc = m.ensureDoc(id) {
            result["title"] = meta.title
            result["style"] = doc.appearance.styleId
            result["text"] = docPlainText(doc.content)
            result["blocks"] = (doc.content.content ?? []).map(\.type).joined(separator: ",")
            let boldOK = (doc.content.content ?? []).contains { n in (n.content ?? []).contains { $0.text == "bold" && $0.marks == [Mark("bold")] } }
            result["bold"] = boldOK ? "yes" : "no"
            result["tabOpen"] = m.library.tabs.contains { $0.view.docId == id } ? "yes" : "no"
            result["backups"] = "\(m.snapshots(id).count)"
            result["trashed"] = m.library.trashedDocs.map(\.title).joined(separator: ",")
            result["listed"] = m.docsFor(.all).map(\.title).sorted().joined(separator: ",")
        } else { result["error"] = "document not found after restart" }
        if let d = try? JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]) {
            try? d.write(to: out.appendingPathComponent("smoke-result.json"))
        }
    }

    static func capture(_ name: String) async {
        await wait(0.7)
        guard let w = NSApp.windows.first(where: { $0.isVisible && $0.contentView != nil }), let v = w.contentView else { return }
        // Capture the composited window (includes AppKit and SwiftUI layers).
        if let cg = CGWindowListCreateImage(.null, .optionIncludingWindow, CGWindowID(w.windowNumber), [.boundsIgnoreFraming, .bestResolution]) {
            let rep = NSBitmapImageRep(cgImage: cg)
            if let png = rep.representation(using: .png, properties: [:]) { try? png.write(to: out.appendingPathComponent(name + ".png")); return }
        }
        guard let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) else { return }
        v.cacheDisplay(in: v.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: out.appendingPathComponent(name + ".png"))
    }

    static func screenshots() async {
        guard let w = NSApp.windows.first(where: { $0.isVisible }) else { return }
        w.setFrame(NSRect(x: 60, y: 60, width: 1440, height: 900), display: true)
        m.setSettings { $0.theme = ProcessInfo.processInfo.environment["DRAFT_THEME"] ?? "light" }
        await wait(1)
        for (layout, name) in [(LibraryLayout.gallery, "library-gallery"), (.grid, "library-grid"), (.list, "library-list")] {
            m.setSettings { $0.libraryView = layout }
            await capture(name)
        }
        m.librarySearchOpen = true
        m.librarySearch = "shortcut"
        await capture("library-search")
        m.librarySearch = ""; m.librarySearchOpen = false

        guard let welcome = m.library.docs.values.first(where: { $0.title == "Welcome to Draft" }) else { return }
        m.openView(.doc(welcome.id))
        await wait(1)
        await capture("document")
        guard let ed = m.editors[welcome.id] else { return }
        let c = ed.controller
        w.makeFirstResponder(c.textView)
        let s = c.textView.string as NSString
        let r = s.range(of: "Style never changes your content")
        c.textView.setSelectedRange(r)
        c.toolbar.update()
        await capture("selection-toolbar")
        c.toolbar.setMode(.palette)
        await capture("color-palette")
        c.toolbar.setMode(.main)
        c.textView.setSelectedRange(NSRange(location: s.range(of: "Start writing").location, length: 0))
        m.panel = .format
        await capture("format-panel")
        m.panel = .style
        await capture("style-panel")
        m.styleGallery = true
        await capture("style-gallery")
        m.styleGallery = false
        m.updateAppearance(welcome.id) { $0.styleId = "ember" }
        m.panel = nil
        await capture("document-ember")
        m.docRailTab = .tasks
        await capture("document-tasks-rail")
        m.docRailTab = .find
        m.findQuery = "style"
        await capture("document-find")
        m.findQuery = ""
        m.docRailTab = .outline
        m.panel = .share
        await capture("share-export-panel")
        m.panel = .info
        await capture("info-panel")
        m.panel = nil
        // Slash menu
        c.textView.setSelectedRange(NSRange(location: (c.textView.string as NSString).length, length: 0))
        w.makeFirstResponder(c.textView)
        c.textView.insertNewline(nil)
        await type("/", into: c)
        await capture("slash-menu")
        c.slash.close()
        c.textView.undoManager?.undo(); c.textView.undoManager?.undo()
        // Nested page
        if let kid = m.library.docs.values.first(where: { $0.title == "Keyboard shortcuts" }) { m.openView(.doc(kid.id), inPlace: true); await capture("nested-page") }
        // Dark app theme
        m.setSettings { $0.theme = "dark" }
        m.activateTab(m.library.tabs[0].id)
        m.setSettings { $0.libraryView = .gallery }
        await capture("library-gallery-dark")
        m.openView(ViewRef(kind: "settings", section: "appearance"))
        await capture("settings-appearance-dark")
        m.setSettings { $0.theme = "light" }
        // Narrow window
        m.openView(.doc(welcome.id))
        w.setFrame(NSRect(x: 60, y: 60, width: 720, height: 860), display: true)
        await capture("narrow-document")
        // Export
        m.export(docIds: [welcome.id], name: "Welcome export", groupByFolder: false, to: URL(fileURLWithPath: NSTemporaryDirectory()))
        await wait(0.3)
        try? (m.lastExportURL?.path ?? "").write(to: out.appendingPathComponent("last-export-path.txt"), atomically: true, encoding: .utf8)
        await wait(0.5)
        m.flushAll()
    }
}
