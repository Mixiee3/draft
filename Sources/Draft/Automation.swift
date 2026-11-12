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
            case "smoke-read": await smokeRead()
            case "screenshots": await screenshots()
            case "drag-write": await dragWrite()
            case "drag-read": dragRead()
            case "showcase": await showcase()
            case "perf": await perf()
            case "a11y": await a11yAudit()
            case "links-write": await linksWrite()
            case "links-read": await linksRead()
            case "screens-v03": await screensV03()
            case "permissions": await permissions()
            case "style-write": await styleWrite()
            case "style-read": await styleRead()
            case "screens-v04": await screensV04()
            case "polish": await polish()
            case "structure-write": await structureWrite()
            case "structure-read": await structureRead()
            case "workflow-write": await workflowWrite()
            case "workflow-read": await workflowRead()
            case "online-live": await onlineLive()
            case "screens-v05": await screensV05()
            case "assistant-bench": await assistantBench()
            case "assistant-quality": await assistantQuality()
            case "assistant-write": await assistantWrite()
            case "assistant-read": await assistantRead()
            case "motion-frames": await motionFrames()
            case "audit-shots": await auditShots()
            case "nav-test": await navTest()
            case "chrome-test": await chromeTest()
            case "selection-test": await selectionTest()
            case "editor-audit": await editorAudit()
            case "text-audit": await textAudit()
            case "presets-shots": await presetsShots()
            case "trust-shots": await trustShots()
            case "trust-read": await trustRead()
            case "safe-mode-check": await safeModeCheck()
            case "effects-live": await effectsLive(read: false)
            case "effects-read": await effectsLive(read: true)
            case "spectrum-test": await spectrumTest(read: false)
            case "spectrum-read": await spectrumTest(read: true)
            case "backgrounds-shots": await backgroundShots()
            case "styling-shots": await stylingShots()
            case "audit-motion": await auditMotion()
            case "audit-frames": await auditFrames()
            case "ux-perf": await uxPerf()
            case "idle": await idle()
            case "agent-edit": await agentEdit()
            case "agent-integrity": await agentIntegrity()
            case "agent-review": await agentReview()
            case "agent-seed": await agentSeed()
            case "agent-external-accept": await agentExternalAccept()
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
        // Long enough to scroll: remember a scroll position and caret for this tab.
        let tv = ed.controller.textView
        tv.setSelectedRange(NSRange(location: (tv.string as NSString).length, length: 0))
        ed.controller.pastePlainForAutomation(String(repeating: "Scroll filler line.\n", count: 70) + "Caret lands here.")
        await wait(0.3)
        // ⌘G: group the heading and the bold paragraph into a nested page.
        let blocks = ed.controller.document().content ?? []
        ed.controller.selectBlocks(ids: [blocks[0].id!, blocks[1].id!])
        EditorCommands.command("block.group")!.run(ed.controller)
        // Move the checklist into "Morning pages".
        if let task = (ed.controller.document().content ?? []).first(where: { $0.type == "taskList" })?.content?.first?.id,
           let morning = m.library.liveDocs.first(where: { $0.title == "Morning pages" }) {
            ed.controller.selectBlocks(ids: [task])
            ed.controller.moveSelectedBlocks(toDocument: morning.id)
        }
        let caretLoc = ((tv.string as NSString).range(of: "Caret lands here.")).location + 5
        tv.setSelectedRange(NSRange(location: caretLoc, length: 3))
        ed.scrollView.contentView.scroll(to: NSPoint(x: 0, y: 900)); ed.scrollView.reflectScrolledClipView(ed.scrollView.contentView)
        try? "\(caretLoc),\(Int(ed.scrollView.contentView.bounds.origin.y))".write(to: out.appendingPathComponent("smoke-tabstate.txt"), atomically: true, encoding: .utf8)
        await wait(1.0)
        try? Data(id.utf8).write(to: out.appendingPathComponent("smoke-doc-id.txt"))
        // Quit immediately: the quit path itself must flush pending saves.
    }

    static func smokeRead() async {
        let id = (try? String(contentsOf: out.appendingPathComponent("smoke-doc-id.txt"), encoding: .utf8)) ?? ""
        var result: [String: String] = ["docId": id]
        await wait(0.8) // let the reopened tab restore itself
        if let ed = m.editors[id], let expected = try? String(contentsOf: out.appendingPathComponent("smoke-tabstate.txt"), encoding: .utf8) {
            let sel = ed.controller.textView.selectedRange()
            result["tabState"] = "\(sel.location),\(Int(ed.scrollView.contentView.bounds.origin.y))"
            result["tabStateExpected"] = expected + " len3=\(sel.length == 3)"
        }
        if let meta = m.library.docs[id], let doc = m.ensureDoc(id) {
            result["title"] = meta.title
            result["style"] = doc.appearance.styleId
            result["text"] = docPlainText(doc.content)
            result["blocks"] = (doc.content.content ?? []).map(\.type).joined(separator: ",")
            // The grouped page: child of this doc, titled by the first block, holding the rest.
            let pageId = m.cardDocIds(doc.content).first ?? ""
            let page = m.ensureDoc(pageId)
            result["pageParentOK"] = m.library.docs[pageId]?.parentDocId == id ? "yes" : "no"
            result["pageTitle"] = page?.title ?? ""
            result["pageText"] = page.map { docPlainText($0.content) } ?? ""
            let boldOK = (page?.content.content ?? []).contains { n in (n.content ?? []).contains { $0.text == "bold" && $0.marks == [Mark("bold")] } }
            result["bold"] = boldOK ? "yes" : "no"
            result["text"] = docPlainText(doc.content)
            result["tabOpen"] = m.tabs.contains { $0.view.docId == id } ? "yes" : "no"
            result["backups"] = "\(m.snapshots(id).count)"
            result["trashed"] = m.library.trashedDocs.map(\.title).joined(separator: ",")
            result["listed"] = m.docsFor(.all).map(\.title).sorted().joined(separator: ",")
            // Search across documents and jump: long body so the match must be scrolled to.
            if let ed = m.editors[id] ?? Optional(m.editor(for: id)) {
                ed.controller.textView.setSelectedRange(NSRange(location: 0, length: 0))
                ed.controller.pastePlainForAutomation(String(repeating: "Filler paragraph.\n", count: 60) + "The zeppelin keyword lives far down.")
            }
            m.flushAll()
            m.activateTab(m.tabs[0].id)
            m.librarySearch = "ZEPPELIN"
            result["searchHits"] = m.searchHits.map(\.meta.title).joined(separator: ",")
            m.openSearchResult(id)
            await wait(1.0)
            if let c = m.editors[id]?.controller, let r = c.findMatches.first {
                let rect = c.layout.boundingRect(forGlyphRange: c.layout.glyphRange(forCharacterRange: r, actualCharacterRange: nil), in: c.container)
                result["jumpVisible"] = c.textView.visibleRect.intersects(rect.offsetBy(dx: c.textView.textContainerOrigin.x, dy: c.textView.textContainerOrigin.y)) ? "yes" : "no"
                result["jumpMatches"] = "\(c.findMatches.count)"
            }
            // Block link opens the document; then ⇧⌘G ungroups the page in place.
            if let morning = m.library.liveDocs.first(where: { $0.title == "Morning pages" }), let md = m.ensureDoc(morning.id) {
                result["movedTo"] = docPlainText(md.content).contains("a task") ? "yes" : "no"
                result["movedFrom"] = docPlainText(doc.content).contains("a task") ? "still here" : "gone"
            }
            if let taskId = (m.ensureDoc(id)?.content.content ?? []).first(where: { $0.type == "pageCard" })?.id,
               let url = AppModel.blockLink(doc: id, block: taskId) {
                m.activateTab(m.tabs[0].id)
                m.openLink(url)
                await wait(0.5)
                result["linkOpened"] = m.activeDocId == id ? "yes" : "no"
            }
            if let c = m.editors[id]?.controller, let card = c.document().content?.first(where: { $0.type == "pageCard" }) {
                let pageId = card.attrs?["docId"]?.string ?? ""
                c.selectBlocks(ids: [card.id!])
                EditorCommands.command("block.ungroup")!.run(c)
                await wait(0.3)
                result["afterUngroup"] = (c.document().content ?? []).map(\.type).filter { $0 != "paragraph" || true }.suffix(4).joined(separator: ",")
                result["ungroupedGone"] = m.library.docs[pageId] == nil && !m.library.trashedDocs.contains { $0.id == pageId } ? "yes" : "no"
                result["ungroupedText"] = docPlainText(c.document())
            }
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
        m.activateTab(m.tabs[0].id)
        m.setSettings { $0.libraryView = .gallery }
        await capture("library-gallery-dark")
        m.openView(ViewRef(kind: "settings", section: "appearance"))
        await capture("settings-appearance-dark")
        m.setSettings { $0.theme = "light" }
        var checks: [String: String] = [:]
        // Scrolled: text must start below the top controls.
        m.setSettings { $0.libraryView = .gallery }
        m.openView(.doc(welcome.id))
        await wait(0.8)
        if let ed = m.editors[welcome.id] {
            ed.scrollView.contentView.scroll(to: NSPoint(x: 0, y: 260)); ed.scrollView.reflectScrolledClipView(ed.scrollView.contentView)
            await capture("document-scrolled")
            checks["normal.scrollTopBelowControls"] = "\(ed.bounds.height - ed.scrollView.frame.maxY)"
            // Block selection + handle
            let c = ed.controller
            ed.scrollView.contentView.scroll(to: .zero)
            w.makeFirstResponder(c.textView)
            if let pr = c.paragraph(withId: (c.document().content ?? [])[1].id ?? "") {
                c.textView.setSelectedRange(NSRange(location: pr.location, length: 0))
                c.enterBlockMode(); c.stepBlockSelection(1, extend: true)
                let r = c.layout.firstLineRect(pr)!.rect
                ed.updateHandle(at: c.textView.convert(NSPoint(x: 10, y: r.midY + c.textView.textContainerOrigin.y), to: ed.paperView))
                await capture("block-selection")
                EditorCommands.command("block.group")!.run(c) // ⌘G on the two selected blocks
                await capture("grouped-page")
                await wait(0.2)
                c.textView.undoManager?.undo()
                c.exitBlockMode()
            }
            // Backups list
            m.flushAll()
            m.infoTab = "backups"; m.panel = .info
            await capture("backups-panel")
            m.panel = nil; m.infoTab = "info"
        }
        // Search results
        m.activateTab(m.tabs[0].id)
        m.librarySearchOpen = true; m.librarySearch = "markdown"
        await capture("search-results")
        m.librarySearch = ""; m.librarySearchOpen = false
        // Recently Deleted
        if let morning = m.library.docs.values.first(where: { $0.title == "Morning pages" }) {
            m.requestDelete(morning.id)
            m.openView(ViewRef(kind: "trash"))
            await capture("recently-deleted")
            m.restore(morning.id)
            m.activateTab(m.tabs[0].id)
        }
        // Narrow window: scrolled text and the slash menu at the bottom edge.
        m.openView(.doc(welcome.id))
        w.setFrame(NSRect(x: 60, y: 60, width: 720, height: 640), display: true)
        await wait(0.6)
        await capture("narrow-document")
        if let ed = m.editors[welcome.id] {
            let c = ed.controller
            checks["narrow.scrollTopBelowControls"] = "\(ed.bounds.height - ed.scrollView.frame.maxY)"
            w.makeFirstResponder(c.textView)
            c.textView.setSelectedRange(NSRange(location: (c.textView.string as NSString).length, length: 0))
            c.textView.insertNewline(nil)
            await type("/", into: c)
            c.textView.scrollRangeToVisible(c.textView.selectedRange()); c.slash.position()
            await capture("narrow-slash-menu")
            checks["narrow.slashInside"] = ed.paperView.visibleRect.insetBy(dx: -1, dy: -1).contains(c.slash.frame) ? "yes" : "no \(c.slash.frame) \(ed.paperView.visibleRect)"
            c.slash.close()
            c.textView.undoManager?.undo(); c.textView.undoManager?.undo()
            w.setFrame(NSRect(x: 60, y: 60, width: 1440, height: 900), display: true)
            await wait(0.6)
            c.textView.setSelectedRange(NSRange(location: (c.textView.string as NSString).length, length: 0))
            c.textView.insertNewline(nil)
            await type("/", into: c)
            c.textView.scrollRangeToVisible(c.textView.selectedRange()); c.slash.position()
            checks["normal.slashInside"] = ed.paperView.visibleRect.insetBy(dx: -1, dy: -1).contains(c.slash.frame) ? "yes" : "no"
            await capture("slash-menu")
            c.slash.close()
        }
        if let d = try? JSONSerialization.data(withJSONObject: checks, options: [.prettyPrinted, .sortedKeys]) { try? d.write(to: out.appendingPathComponent("layout-checks.json")) }
        // Export
        m.export(docIds: [welcome.id], name: "Welcome export", groupByFolder: false, to: URL(fileURLWithPath: NSTemporaryDirectory()))
        await wait(0.3)
        try? (m.lastExportURL?.path ?? "").write(to: out.appendingPathComponent("last-export-path.txt"), atomically: true, encoding: .utf8)
        await wait(0.5)
        m.flushAll()
    }

    // MARK: Drag test through the window's real mouse-event path

    static func json(_ n: Node) -> String { String(decoding: (try? DraftJSON.encode(n)) ?? Data(), as: UTF8.self) }

    static func mouse(_ type: NSEvent.EventType, _ p: NSPoint, in w: NSWindow) {
        guard let e = NSEvent.mouseEvent(with: type, location: p, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                         windowNumber: w.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: type == .leftMouseUp ? 0 : 1) else { return }
        NSApp.postEvent(e, atStart: false) // through the app queue, like real input (event monitors, tracking loops)
    }

    static func dragWrite() async {
        guard let w = NSApp.windows.first(where: { $0.isVisible }), let id = m.createDoc(title: "Drag test") else { return }
        await wait(0.6)
        guard let ed = m.editors[id] else { return }
        let c = ed.controller
        w.makeFirstResponder(c.textView)
        c.pastePlainForAutomation("Alpha plain\n**Bravo** bold\n- [x] Charlie done\n## Delta heading\nEcho last")
        await wait(0.4)
        var r: [String: String] = ["docId": id, "before": json(c.document())]
        // Hover Alpha → handle appears; press it, drag below "Delta heading", release.
        let alpha = c.paragraph(withId: (c.document().content ?? [])[0].id ?? "")!
        let line = c.layout.firstLineRect(alpha)!.rect
        let tv = c.textView
        ed.updateHandle(at: tv.convert(NSPoint(x: 20, y: line.midY + tv.textContainerOrigin.y), to: ed.paperView))
        let h = ed.handleView
        let start = h.convert(NSPoint(x: h.bounds.midX, y: h.bounds.midY), to: nil)
        let delta = c.paragraph(withId: (c.document().content ?? [])[3].id ?? "")!
        let dRect = c.layout.paragraphRect(delta)!
        let target = tv.convert(NSPoint(x: 40, y: dRect.maxY - 2 + tv.textContainerOrigin.y), to: nil)
        mouse(.leftMouseDown, start, in: w)
        for k in 1...12 {
            let t = CGFloat(k) / 12
            mouse(.leftMouseDragged, NSPoint(x: start.x + (target.x - start.x) * t, y: start.y + (target.y - start.y) * t), in: w)
            try? await Task.sleep(for: .milliseconds(15))
        }
        mouse(.leftMouseUp, target, in: w)
        await wait(0.3)
        r["afterDrag"] = json(c.document())
        r["order"] = (c.document().content ?? []).map { n in n.type == "taskList" ? "Charlie" : nodeText(n).components(separatedBy: " ").first ?? "" }.joined(separator: ",")
        tv.undoManager?.undo()
        r["afterUndo"] = json(c.document())
        tv.undoManager?.redo()
        r["afterRedo"] = json(c.document())
        m.flushAll()
        if let d = try? JSONSerialization.data(withJSONObject: r, options: [.sortedKeys]) { try? d.write(to: out.appendingPathComponent("drag-write.json")) }
    }

    static func dragRead() {
        guard let d = try? Data(contentsOf: out.appendingPathComponent("drag-write.json")),
              let r = try? JSONSerialization.jsonObject(with: d) as? [String: String], let id = r["docId"] else { return }
        let reloaded = m.ensureDoc(id).map { json($0.content) } ?? "missing"
        func ids(_ s: String?) -> [String] {
            guard let s, let n = try? JSONDecoder().decode(Node.self, from: Data(s.utf8)) else { return [] }
            var out: [String] = []; walk(n) { if let i = $0.id { out.append(i) } }; return out.sorted()
        }
        let res = ["idsPreserved": ids(r["before"]) == ids(r["afterDrag"]) && !ids(r["before"]).isEmpty ? "yes" : "no", "relaunchMatchesDrag": reloaded == r["afterDrag"] ? "yes" : "no", "undoRestored": r["afterUndo"] == r["before"] ? "yes" : "no",
                   "redoMatchesDrag": r["afterRedo"] == r["afterDrag"] ? "yes" : "no", "order": r["order"] ?? "", "afterDrag": r["afterDrag"] ?? ""]
        if let o = try? JSONSerialization.data(withJSONObject: res, options: [.prettyPrinted, .sortedKeys]) { try? o.write(to: out.appendingPathComponent("drag-result.json")) }
    }

    // MARK: Visual check of block types (normal + narrow)

    static func showcaseDoc() -> Node {
        func p(_ t: String) -> Node { Node("paragraph", content: [.text(t)]) }
        return ensureBlockIds(Node("doc", content: [
            p("Block types in Draft v0.2.1."),
            Node("callout", attrs: ["icon": "💡"], content: [p("Callouts hold a tip or a warning."), p("They can span several paragraphs.")]),
            Node("toggleList", content: [
                Node("toggleItem", attrs: ["open": true], content: [p("An open toggle"), Node("bulletList", content: [Node("listItem", content: [p("Its child is visible")])])]),
                Node("toggleItem", attrs: ["open": false], content: [p("A collapsed toggle"), Node("bulletList", content: [Node("listItem", content: [p("Hidden child")])])]),
            ]),
            Node("taskList", content: [Node("taskItem", attrs: ["checked": false], content: [p("Typed with “x ”")])]),
            p("Regular separator"), Node("horizontalRule"),
            p("Strong"), Node("horizontalRule", attrs: ["variant": "strong"]),
            p("Dotted"), Node("horizontalRule", attrs: ["variant": "dotted"]),
            p("Three dots"), Node("horizontalRule", attrs: ["variant": "dots"]),
            p("Next comes a page break"), Node("pageBreak"),
            p("End."),
        ]))
    }

    static func showcase() async {
        guard let w = NSApp.windows.first(where: { $0.isVisible }), let id = m.createDoc(title: "Block showcase") else { return }
        m.updateAppearance(id) { $0.styleId = ProcessInfo.processInfo.environment["DRAFT_STYLE"] ?? "paper" }
        w.setFrame(NSRect(x: 60, y: 60, width: 1440, height: 900), display: true)
        await wait(0.6)
        m.editors[id]?.controller.load(showcaseDoc())
        await capture("showcase-normal")
        w.setFrame(NSRect(x: 60, y: 60, width: 720, height: 900), display: true)
        await capture("showcase-narrow")
        // Image bar and file block.
        guard let c = m.editors[id]?.controller else { return }
        let art = NSImage(size: NSSize(width: 1200, height: 600), flipped: false) { r in
            NSGradient(colors: [NSColor(hex: "#8fd3e6"), NSColor(hex: "#1f6475")])!.draw(in: r, angle: -90); return true
        }
        let rep = NSBitmapImageRep(data: art.tiffRepresentation!)!
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("Field notes.txt")
        try? "Draft attachment".write(to: tmp, atomically: true, encoding: .utf8)
        c.textView.setSelectedRange(NSRange(location: 0, length: 0))
        _ = c.insertFiles([tmp])
        if let aid = m.storeImage(data: rep.representation(using: .png, properties: [:])!, ext: "png") {
            c.textView.setSelectedRange(NSRange(location: 0, length: 0))
            c.insertImage(assetId: aid, alt: "Gradient study")
            if let i = c.document().content?.first(where: { $0.type == "image" })?.id, let pr = c.paragraph(withId: i) {
                c.textView.setSelectedRange(NSRange(location: pr.location, length: 1))
                c.setImageCaption("A calm gradient, resized to medium")
                c.setImageWidth(0.5)
                w.makeFirstResponder(c.textView)
                c.textView.scrollRangeToVisible(pr)
            }
        }
        m.docRailTab = .attachments
        await capture("media-narrow")
        // Cover: generated scene, cropped to 2:1 around the upper third.
        let sceneArt = NSImage(size: NSSize(width: 1600, height: 1000), flipped: true) { r in
            NSGradient(colors: [NSColor(hex: "#f06a4a"), NSColor(hex: "#f9c79a")])!.draw(in: r, angle: 90)
            NSColor(hex: "#fff1c9").setFill(); NSBezierPath(ovalIn: NSRect(x: 1050, y: 180, width: 220, height: 220)).fill()
            NSColor(hex: "#8e3a42").setFill(); NSBezierPath(rect: NSRect(x: 0, y: 700, width: 1600, height: 300)).fill()
            return true
        }
        if let png = NSBitmapImageRep(data: sceneArt.tiffRepresentation!)?.representation(using: .png, properties: [:]), let cid = m.storeImage(data: png, ext: "png") {
            m.updateAppearance(id) { $0.cover = Cover(assetId: cid, crop: CoverCrop.fitted(ratio: 2, imageAspect: 1.6, cy: 0.3), ratio: "2:1") }
            m.editors[id]?.scrollView.contentView.scroll(to: .zero)
            await capture("cover-narrow")
            m.coverEditorDoc = id
            await capture("cover-crop-sheet-narrow")
            m.coverEditorDoc = nil
        }
        w.setFrame(NSRect(x: 60, y: 60, width: 1440, height: 900), display: true)
        await capture("media-normal")
        m.editors[id]?.scrollView.contentView.scroll(to: .zero)
        await capture("cover-normal")
        m.coverEditorDoc = id
        await capture("cover-crop-sheet")
        m.coverEditorDoc = nil
    }

    // MARK: Performance (10,000 blocks)

    static func bigDoc(_ n: Int) -> Node {
        var blocks: [Node] = []
        func p(_ t: String, _ marks: [Mark]? = nil) -> Node { Node("paragraph", content: [.text(t, marks: marks)]) }
        var i = 0
        while blocks.count < n {
            switch i % 10 {
            case 0: blocks.append(Node("heading", attrs: ["level": 2], content: [.text("Section \(i / 10)")]))
            case 1, 2, 3: blocks.append(p("Paragraph \(i): a sentence of ordinary length to make lines wrap like real notes do in a long document."))
            case 4: blocks.append(Node("bulletList", content: (0..<3).map { k in Node("listItem", content: [p("Bullet \(i).\(k) with some text")]) }))
            case 5: blocks.append(Node("taskList", content: [Node("taskItem", attrs: ["checked": .bool(i % 20 == 5)], content: [p("Task \(i)")])]))
            case 6: blocks.append(p("Bold and highlighted ", [Mark("bold")]))
            case 7: blocks.append(Node("orderedList", attrs: ["start": 1], content: (0..<2).map { k in Node("listItem", content: [p("Step \(k)")]) }))
            case 8: blocks.append(Node("toggleList", content: [Node("toggleItem", attrs: ["open": .bool(i % 40 != 8)], content: [p("Toggle \(i)"), Node("bulletList", content: [Node("listItem", content: [p("inside")])])])]))
            default: blocks.append(Node("blockquote", content: [p("A quote \(i)")]))
            }
            i += 1
        }
        return ensureBlockIds(Node("doc", content: blocks))
    }

    static func ms(_ t0: CFAbsoluteTime) -> Double { ((CFAbsoluteTimeGetCurrent() - t0) * 1000 * 10).rounded() / 10 }
    static func settle() async { await Task.yield(); await MainActor.run { RunLoop.main.run(mode: .default, before: Date()) }; await Task.yield() }
    static func stats(_ xs: [Double]) -> [String: Double] {
        let s = xs.sorted()
        return ["p50": s[s.count / 2], "p95": s[min(s.count - 1, Int(Double(s.count) * 0.95))], "max": s.last ?? 0]
    }

    static func perf() async {
        guard let w = NSApp.windows.first(where: { $0.isVisible }) else { return }
        w.setFrame(NSRect(x: 60, y: 60, width: 1440, height: 900), display: true)
        var r: [String: Any] = [:]
        let content = bigDoc(10_000)
        let id = newId("d_")
        var doc = DocFile.empty(id: id, title: "Ten thousand blocks")
        doc.content = content
        if let style = ProcessInfo.processInfo.environment["DRAFT_PERF_STYLE"] { doc.appearance.styleId = style; r["style"] = style }
        try? m.vault.saveDoc(doc)
        var meta = DocMeta(id: id); meta.applyDerived(from: doc)
        m.library.docs[id] = meta
        r["blocks"] = docStats(content).blocks
        if ProcessInfo.processInfo.environment["DRAFT_PERF_FOCUS"] != nil { m.focusMode = true; r["focusMode"] = true }
        var t0 = CFAbsoluteTimeGetCurrent()
        m.openView(.doc(id))
        await settle()
        guard let ed = m.editors[id] else { return }
        ed.layoutSubtreeIfNeeded()
        r["openMs"] = ms(t0)
        let c = ed.controller, tv = c.textView
        w.makeFirstResponder(tv)
        let mid = c.paragraphRange(at: (tv.string as NSString).length / 2)
        tv.setSelectedRange(NSRange(location: NSMaxRange(mid) - 1, length: 0))
        tv.scrollRangeToVisible(tv.selectedRange())
        await settle()
        var keys: [Double] = []
        for ch in "quick typing in the middle of a long document" {
            t0 = CFAbsoluteTimeGetCurrent()
            tv.insertText(String(ch), replacementRange: tv.selectedRange())
            await settle()
            keys.append(ms(t0))
        }
        r["keystrokeMs"] = stats(keys)
        var enters: [Double] = []
        for _ in 0..<10 {
            t0 = CFAbsoluteTimeGetCurrent(); tv.insertNewline(nil); await settle(); enters.append(ms(t0))
            tv.insertText("x", replacementRange: tv.selectedRange()); await settle()
        }
        r["returnMs"] = stats(enters)
        var moves: [Double] = []
        for _ in 0..<5 { t0 = CFAbsoluteTimeGetCurrent(); c.moveSelectedBlocks(by: 1); await settle(); moves.append(ms(t0)) }
        r["moveMs"] = stats(moves)
        if let tp = (0..<(tv.string as NSString).length).lazy.map({ c.paragraphRange(at: $0) }).first(where: { c.block(at: $0).kind == .toggle }) {
            t0 = CFAbsoluteTimeGetCurrent(); c.toggleOpen(at: tp); await settle(); r["toggleMs"] = ms(t0)
        }
        t0 = CFAbsoluteTimeGetCurrent(); m.flushAll(); r["saveMs"] = ms(t0)
        m.activateTab(m.tabs[0].id)
        m.librarySearch = "Paragraph 7771:"
        t0 = CFAbsoluteTimeGetCurrent(); let hits = m.searchHits; r["searchMs"] = ms(t0); r["searchHits"] = hits.count
        // Index rebuilt from disk (index/ deleted), the whole vault including the 10k-block document.
        m.flushAll(); try? FileManager.default.removeItem(at: m.vault.dir.appendingPathComponent("index"))
        t0 = CFAbsoluteTimeGetCurrent(); m.index = VaultIndex(); m.refreshIndex(); r["indexRebuildMs"] = ms(t0)
        m.librarySearch = ""
        if let d = try? JSONSerialization.data(withJSONObject: r, options: [.prettyPrinted, .sortedKeys]) { try? d.write(to: out.appendingPathComponent("perf.json")) }
    }

    // MARK: Accessibility audit: every control in the window's accessibility tree has a name

    static func unlabeled(_ v: NSView, into out: inout [String]) {
        if let c = v as? NSControl, !v.isHiddenOrHasHiddenAncestor, !(v is NSTextView) {
            let field = v as? NSTextField
            let isInput = field.map { $0.isEditable } ?? true
            let names = [c.accessibilityLabel(), c.accessibilityTitle(), (c as? NSButton)?.title, field?.placeholderString, c.toolTip]
            if isInput && names.allSatisfy({ ($0 ?? "").isEmpty }) { out.append("\(Swift.type(of: c)) at \(Int(c.frame.minX)),\(Int(c.frame.minY))") }
        }
        for sub in v.subviews { unlabeled(sub, into: &out) }
    }

    static func a11yAudit() async {
        guard let w = NSApp.windows.first(where: { $0.isVisible }), let id = m.createDoc(title: "A11y") else { return }
        w.setFrame(NSRect(x: 60, y: 60, width: 1440, height: 900), display: true)
        await wait(0.5)
        guard let c = m.editors[id]?.controller else { return }
        c.load(showcaseDoc())
        let art = NSImage(size: NSSize(width: 600, height: 300), flipped: false) { r in NSColor.systemTeal.setFill(); r.fill(); return true }
        if let png = NSBitmapImageRep(data: art.tiffRepresentation!)?.representation(using: .png, properties: [:]), let aid = m.storeImage(data: png, ext: "png") {
            c.textView.setSelectedRange(NSRange(location: 0, length: 0))
            c.insertImage(assetId: aid)
            m.updateAppearance(id) { $0.cover = Cover(assetId: aid) }
            if let i = c.selectedImageIndex ?? c.document().content?.first(where: { $0.type == "image" }).flatMap({ c.paragraph(withId: $0.id!)?.location }) {
                c.textView.setSelectedRange(NSRange(location: i, length: 1))
            }
        }
        var report: [String: [String]] = [:]
        for (name, setup) in [("document+imageBar", { m.panel = nil }), ("format", { m.panel = .format }), ("style", { m.panel = .style }),
                              ("info", { m.panel = .info }), ("share", { m.panel = .share }), ("cropSheet", { m.panel = nil; m.coverEditorDoc = id })] as [(String, () -> Void)] {
            setup()
            await wait(0.6)
            var out: [String] = []
            if let root = w.contentView { unlabeled(root, into: &out) }
            report[name] = out
        }
        m.coverEditorDoc = nil
        c.textView.setSelectedRange(NSRange(location: (c.textView.string as NSString).length, length: 0))
        EditorCommands.command("insert.table")!.run(c); await boundary()
        EditorCommands.command("insert.collection")!.run(c); await boundary()
        m.flushAll()
        if let tid = c.document().content?.first(where: { $0.type == "table" })?.id {
            c.tableEditor.begin(tableId: tid, row: 0, column: 0); await wait(0.3)
            var out: [String] = []; if let root = w.contentView { unlabeled(root, into: &out) }; report["tableEditor"] = out
            c.tableEditor.end()
        }
        if let block = c.document().content?.first(where: { $0.type == "collection" })?.id {
            m.addCollectionItem(id, block, title: "One", values: [:], undo: nil)
            m.openCollection(id, block)
            for v in m.collectionData(id, block)?.views ?? [] {
                m.updateCollection(id, block, "View", undo: nil) { $0.activeView = v.id }
                await wait(0.5)
                var out: [String] = []; if let root = w.contentView { unlabeled(root, into: &out) }; report["collection-" + v.type] = out
            }
        }
        for (name, setup, done) in [("templatePicker", { m.templatePicker = true }, { m.templatePicker = false }),
                                    ("settingsSpaces", { m.openView(ViewRef(kind: "settings", section: "space")) }, {}),
                                    ("assistant", { m.openView(.doc(id)); m.setSettings { $0.assistantPinned = true }; m.toggleAssistant() }, { m.toggleAssistant() }),
                                    ("settingsAssistant", { m.openView(ViewRef(kind: "settings", section: "assistant")) }, {})] as [(String, () -> Void, () -> Void)] {
            setup(); await wait(0.5)
            var out: [String] = []; if let root = w.contentView { unlabeled(root, into: &out) }; report[name] = out
            done()
        }
        m.openView(.doc(id)); await wait(0.4)
        // Keyboard: Tab on a selected image moves into the image bar.
        w.makeFirstResponder(c.textView)
        if let i = c.document().content?.first(where: { $0.type == "image" }).flatMap({ c.paragraph(withId: $0.id!)?.location }) { c.textView.setSelectedRange(NSRange(location: i, length: 1)) }
        c.textView.insertTab(nil)
        report["tabIntoImageBar"] = [w.firstResponder === c.imageBar.size ? "yes" : "no: \(String(describing: w.firstResponder))"]
        if let d = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) { try? d.write(to: out.appendingPathComponent("a11y.json")) }
    }
}
