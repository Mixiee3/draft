import AppKit
import SwiftUI
import QuartzCore
import DraftCore
import DraftEditor
import DraftAssistant

/// `audit-shots`, `audit-motion`, `audit-frames`: every screen in light/dark and normal/narrow,
/// frame sequences of transitions, and frame timing against the display's refresh rate.
extension Automation {
    // MARK: Capture

    /// Everything on screen over the window's area: the window plus its popovers, menus and sheets.
    static func shot(_ name: String, _ w: NSWindow, settle s: Double = 0.5, rect: NSRect? = nil) async {
        if s > 0 { await wait(s) }
        let f = rect ?? w.frame
        let screenH = NSScreen.screens[0].frame.height
        let r = CGRect(x: f.minX, y: screenH - f.maxY, width: f.width, height: f.height)
        guard let cg = CGWindowListCreateImage(r, .optionOnScreenOnly, kCGNullWindowID, [.bestResolution]) else { return }
        try? NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])?.write(to: out.appendingPathComponent(name + ".png"))
    }

    static func recordFrames(_ name: String, _ w: NSWindow, seconds: Double, rect: NSRect? = nil, during: @escaping () async -> Void) async {
        let dir = out.appendingPathComponent("motion-" + name, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let screenH = NSScreen.screens[0].frame.height
        let start = Date()
        var i = 0
        var stamps: [Double] = []
        let worker = Task { await during() }
        while Date().timeIntervalSince(start) < seconds {
            let f = rect ?? w.frame
            let r = CGRect(x: f.minX, y: screenH - f.maxY, width: f.width, height: f.height)
            if let cg = CGWindowListCreateImage(r, .optionOnScreenOnly, kCGNullWindowID, [.nominalResolution]) {
                try? NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])?.write(to: dir.appendingPathComponent(String(format: "%04d.png", i)))
                stamps.append(Date().timeIntervalSince(start)); i += 1
            }
            try? await Task.sleep(nanoseconds: 8_000_000)
        }
        _ = await worker.value
        let fps = stamps.count > 1 ? Double(stamps.count - 1) / (stamps.last! - stamps.first!) : 0
        try? "\(fps)".write(to: dir.appendingPathComponent("fps.txt"), atomically: true, encoding: .utf8)
    }

    /// Clicks a point the way a person would (through the app's event queue).
    static func click(_ p: NSPoint, _ w: NSWindow) async {
        mouse(.leftMouseDown, p, in: w); try? await Task.sleep(nanoseconds: 40_000_000); mouse(.leftMouseUp, p, in: w)
    }

    /// Opens a menu at `p`, captures it from another thread while AppKit tracks it, then closes it with Esc.
    static func shotMenu(_ name: String, at p: NSPoint, _ w: NSWindow) async {
        let screenH = NSScreen.screens[0].frame.height
        let f = w.frame.insetBy(dx: -40, dy: -40)
        let r = CGRect(x: f.minX, y: screenH - f.maxY, width: f.width, height: f.height)
        let url = out.appendingPathComponent(name + ".png")
        Thread.detachNewThread {
            Thread.sleep(forTimeInterval: 0.9)
            if let cg = CGWindowListCreateImage(r, .optionOnScreenOnly, kCGNullWindowID, [.bestResolution]) {
                try? NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])?.write(to: url)
            }
            let src = CGEventSource(stateID: .hidSystemState)
            for down in [true, false] { CGEvent(keyboardEventSource: src, virtualKey: 53, keyDown: down)?.postToPid(getpid()) }
        }
        await click(p, w)
        await wait(1.6)
    }

    static func point(of v: NSView, _ w: NSWindow) -> NSPoint { v.convert(NSPoint(x: v.bounds.midX, y: v.bounds.midY), to: nil) }

    /// SwiftUI menus are AppKit pop-up buttons underneath; returns them with their window rects.
    static func popups(_ v: NSView) -> [(NSView, NSRect)] {
        var out: [(NSView, NSRect)] = []
        func visit(_ x: NSView) {
            if x is NSPopUpButton || String(describing: Swift.type(of: x)).contains("Popup"), !x.isHiddenOrHasHiddenAncestor, x.bounds.width > 4 {
                out.append((x, x.convert(x.bounds, to: nil)))
            }
            x.subviews.forEach(visit)
        }
        visit(v)
        return out
    }

    /// Finds an AppKit-backed SwiftUI control by its accessibility label (menus, buttons).
    static func find(_ label: String, in v: NSView) -> NSView? {
        if v.accessibilityLabel() == label || (v as? NSButton)?.title == label { return v }
        for s in v.subviews { if let f = find(label, in: s) { return f } }
        return nil
    }

    // MARK: Content

    static func seedLibrary(_ n: Int) {
        let words = ["garden", "budget", "meeting", "travel", "reading", "design", "launch", "recipe", "workout", "draft", "letter", "plan"]
        for i in 0..<n {
            let id = newId("d_")
            var doc = DocFile.empty(id: id, title: "\(words[i % words.count].capitalized) notes \(i)")
            let paras = (0..<(4 + i % 30)).map { k in "Paragraph \(k) about \(words[(i + k) % words.count]) with a few more words to wrap a line or two in the preview." }
            doc.content = ensureBlockIds(Node("doc", content: MarkdownImport.blocks("## Overview\n\n" + paras.joined(separator: "\n\n") + "\n\n- [ ] follow up on \(words[i % words.count])")))
            try? m.vault.saveDoc(doc)
            var meta = DocMeta(id: id, title: doc.title); meta.applyDerived(from: doc); meta.spaceId = m.library.space.id
            meta.updatedAt = Double(Date().timeIntervalSince1970 * 1000) - Double(i) * 3_600_000
            m.library.docs[id] = meta
        }
    }

    static func bigDocId(_ blocks: Int, title: String) -> String {
        let id = newId("d_")
        var doc = DocFile.empty(id: id, title: title)
        doc.content = bigDoc(blocks)
        try? m.vault.saveDoc(doc)
        var meta = DocMeta(id: id, title: title); meta.applyDerived(from: doc); meta.spaceId = m.library.space.id
        m.library.docs[id] = meta
        return id
    }

    static func collectionDoc(_ items: Int) async -> (String, String)? {
        guard let host = m.createDoc(title: "Reading collection") else { return nil }
        await wait(0.4)
        let c = m.editor(for: host).controller
        c.insertAttachmentBlock(kind: .collection, node: CollectionData.starter(name: "Reading").node(id: "b_col"))
        m.flushAll()
        guard let block = c.document().content?.first(where: { $0.type == "collection" })?.id, var d = m.collectionData(host, block) else { return nil }
        let st = d.fields[0].id
        d.fields.append(CollectionField(id: "f_n", name: "Pages", type: "number"))
        for i in 0..<items {
            let id = newId("d_")
            var doc = DocFile.empty(id: id, title: "Book \(i)")
            doc.content = Node("doc", content: [Node("paragraph", attrs: ["id": .string(newId("b_"))])])
            try? m.vault.saveDoc(doc)
            var meta = DocMeta(id: id, title: "Book \(i)", parentDocId: host); meta.spaceId = m.library.space.id
            m.library.docs[id] = meta
            d.items.append(CollectionItem(docId: id, values: [st: .string(["To do", "Doing", "Done"][i % 3]), "f_n": .number(Double(100 + i % 400))]))
        }
        m.writeCollection(host, block, d)
        return (host, block)
    }

    // MARK: Screens

    static func auditShots() async {
        guard let w = NSApp.windows.first(where: { $0.isVisible }) else { return }
        let narrow = ProcessInfo.processInfo.environment["AUDIT_NARROW"] != nil
        let dark = ProcessInfo.processInfo.environment["AUDIT_DARK"] != nil
        let p = (narrow ? "narrow-" : "") + (dark ? "dark-" : "")
        w.setFrame(NSRect(x: 40, y: 40, width: narrow ? 760 : 1440, height: narrow ? 720 : 900), display: true)
        m.setSettings { $0.theme = dark ? "dark" : "light" }
        await shot(p + "01-first-launch", w, settle: 1.2)
        try? popups(w.contentView!).map { "\(Swift.type(of: $0.0)) \(Int($0.1.minX)),\(Int($0.1.minY)) \(Int($0.1.width))x\(Int($0.1.height))" }.joined(separator: "\n")
            .write(to: out.appendingPathComponent(p + "popups.txt"), atomically: true, encoding: .utf8)

        // New-note button, zoomed.
        let header = popups(w.contentView!).sorted { $0.1.minX < $1.1.minX }
        if let (plus, pr) = header.first {
            let r = NSRect(x: w.frame.minX + pr.midX - 40, y: w.frame.minY + pr.midY - 30, width: 80, height: 60)
            await shot(p + "02-new-note-button-zoom", w, settle: 0.2, rect: r)
            await shotMenu(p + "03-new-note-menu", at: point(of: plus, w), w)
        }
        seedLibrary(40)
        m.indexTick &+= 1
        for (layout, n) in [(LibraryLayout.gallery, "gallery"), (.grid, "grid"), (.list, "list")] {
            m.setSettings { $0.libraryView = layout }
            await shot(p + "04-library-\(n)", w)
        }
        m.librarySearchOpen = true; m.librarySearch = "budget"; await shot(p + "05-library-search", w)
        m.librarySearch = ""; m.librarySearchOpen = false

        // Note creation: what a new note looks like right after ⌘N.
        guard let id = m.createDoc() else { return }
        await shot(p + "06-new-note-empty", w, settle: 0.8)
        let c = m.editor(for: id).controller
        m.editor(for: id).focusBody(atStart: true)
        await type("Morning pages", into: c); c.textView.insertNewline(nil)
        c.pastePlainForAutomation("Three pages, first thing. **Bold idea** and a _soft one_.\n- [ ] water the plants\n- buy bread\n## Later\nA quote follows.\n> Keep it simple.")
        await shot(p + "07-editor-content", w)
        let ns = c.textView.string as NSString
        c.textView.setSelectedRange(ns.range(of: "Bold idea"))
        await shot(p + "08-selection-toolbar", w, settle: 0.7)
        c.textView.setSelectedRange(NSRange(location: ns.length, length: 0)); c.textView.insertNewline(nil)
        await type("/", into: c); await shot(p + "09-slash-menu", w, settle: 0.6)
        c.textView.doCommand(by: #selector(NSResponder.cancelOperation(_:))); c.textView.deleteBackward(nil)
        for panel in [Panel.format, .style, .info, .share] {
            withAnimation(Motion.panel(false)) { m.panel = panel }
            await shot(p + "10-panel-\(panel.rawValue)", w, settle: 0.7)
        }
        m.panel = nil
        m.styleGallery = true; await shot(p + "11-style-gallery", w, settle: 0.7); m.styleGallery = false
        m.quickOpen = true; await shot(p + "12-quick-open", w, settle: 0.5); m.quickOpen = false
        m.templatePicker = true; await shot(p + "13-template-picker", w, settle: 0.5); m.templatePicker = false

        for s in ["appearance", "editor", "space", "daily", "tags", "advanced", "stats", "data", "about", "templates", "assistant"] {
            m.openView(ViewRef(kind: "settings", section: s)); await shot(p + "14-settings-\(s)", w, settle: 0.5)
        }
        m.openView(ViewRef(kind: "calendar")); await shot(p + "15-calendar", w)
        m.openView(ViewRef(kind: "tasks")); await shot(p + "16-tasks", w)

        if let (host, block) = await collectionDoc(60) {
            m.openView(.doc(host)); await wait(0.5)
            let hc = m.editor(for: host).controller
            hc.textView.setSelectedRange(NSRange(location: 0, length: 0))
            hc.insertAttachmentBlock(kind: .table, node: Tables.parse(["| Book | Author | Pages |", "| --- | --- | --- |", "| Dune | Herbert | 412 |", "| Atlas | Mitchell | 120 |"])!)
            await shot(p + "17-doc-table-collection", w)
            if let tid = hc.document().content?.first(where: { $0.type == "table" })?.id { hc.tableEditor.begin(tableId: tid, row: 1, column: 0); await shot(p + "18-table-editing", w); hc.tableEditor.end() }
            m.openCollection(host, block)
            for v in m.collectionData(host, block)!.views {
                m.updateCollection(host, block, "View", undo: nil) { $0.activeView = v.id }
                await shot(p + "19-collection-\(v.type)", w)
            }
        }

        // Spaces menu, Assistant.
        if !narrow { await shotMenu(p + "20-space-menu", at: NSPoint(x: 100, y: w.frame.height - 104), w) }
        m.openView(.doc(id)); await wait(0.4)
        m.setSettings { $0.assistantPinned = true }
        m.toggleAssistant(); await shot(p + "21-assistant-ready", w, settle: 0.8)
        let a = m.assistant
        if a.store.isInstalled(a.model), ProcessInfo.processInfo.environment["AUDIT_NO_MODEL"] == nil {
            a.scope = .document; a.draft = "What should I do first?"; a.send()
            await wait(1.2); await shot(p + "22-assistant-thinking", w, settle: 0)
            await untilIdle(a)
            await shot(p + "23-assistant-answer", w)
            // Select answer text with a real drag, to see the selection colour.
            if let ans = find("Assistant answer", in: w.contentView!) ?? nil {
                let r = ans.convert(ans.bounds, to: nil)
                mouse(.leftMouseDown, NSPoint(x: r.minX + 4, y: r.maxY - 8), in: w)
                for k in 1...10 { mouse(.leftMouseDragged, NSPoint(x: r.minX + 4 + CGFloat(k) * 22, y: r.maxY - 8 - CGFloat(k) * 2), in: w); try? await Task.sleep(nanoseconds: 15_000_000) }
                mouse(.leftMouseUp, NSPoint(x: r.minX + 224, y: r.maxY - 28), in: w)
            }
            await shot(p + "24-assistant-text-selection", w)
            a.scope = .selection
            c.textView.setSelectedRange((c.textView.string as NSString).range(of: "Three pages, first thing. Bold idea and a soft one."))
            if c.selectedBlocksRange == nil { c.textView.setSelectedRange(NSRange(location: 0, length: 30)) }
            a.send(.rewrite); await untilIdle(a)
            if let msg = a.chat.messages.last { a.previewEdit(msg) }
            await wait(0.8)
            if let sheet = w.attachedSheet { await captureWindow(sheet, p + "25-assistant-edit-preview") }
            a.preview = nil
        }
        m.setAssistantPinned(false); await wait(0.8)
        if let fw = m.assistantWindow {
            try? "\(Int(fw.frame.width))x\(Int(fw.frame.height))".write(to: out.appendingPathComponent(p + "26-assistant-floating-size.txt"), atomically: true, encoding: .utf8)
            await shot(p + "26-assistant-floating", fw, settle: 0.3)
        }
        m.setAssistantPinned(true); m.toggleAssistant()

        // Import / export entry points.
        withAnimation { m.panel = .share }; await wait(0.3)
        m.infoTab = "info"
        await shot(p + "27-share-panel", w)
        m.panel = nil
        m.openView(.all); await wait(0.3)
        if let (more, _) = popups(w.contentView!).sorted(by: { $0.1.minX < $1.1.minX }).last { await shotMenu(p + "28-library-more-menu", at: point(of: more, w), w) }
        m.flushAll()
    }

    // MARK: Motion

    static func auditMotion() async {
        guard let w = NSApp.windows.first(where: { $0.isVisible }) else { return }
        w.setFrame(NSRect(x: 40, y: 40, width: 1280, height: 800), display: true)
        seedLibrary(24); m.indexTick &+= 1
        await wait(0.6)
        await recordFrames("new-note", w, seconds: 1.6) { try? await Task.sleep(nanoseconds: 300_000_000); _ = m.createDoc() }
        guard let doc = m.activeDocId else { return }
        let c = m.editor(for: doc).controller
        c.pastePlainForAutomation("A short note for motion.\nSelect these words to see the bar.\n- one\n- two\n- three")
        await recordFrames("panel-open-close", w, seconds: 2.4) {
            try? await Task.sleep(nanoseconds: 300_000_000); withAnimation(Motion.panel(false)) { m.panel = .format }
            try? await Task.sleep(nanoseconds: 900_000_000); withAnimation(Motion.panel(false)) { m.panel = nil }
        }
        await recordFrames("panel-switch", w, seconds: 2.0) {
            withAnimation(Motion.panel(false)) { m.panel = .format }
            try? await Task.sleep(nanoseconds: 600_000_000); withAnimation(Motion.panel(false)) { m.panel = .style }
            try? await Task.sleep(nanoseconds: 600_000_000); withAnimation(Motion.panel(false)) { m.panel = .info }
        }
        m.panel = nil
        await recordFrames("selection-toolbar", w, seconds: 2.0) {
            try? await Task.sleep(nanoseconds: 300_000_000)
            c.textView.setSelectedRange((c.textView.string as NSString).range(of: "these words"))
            try? await Task.sleep(nanoseconds: 900_000_000)
            c.textView.setSelectedRange(NSRange(location: 2, length: 0))
        }
        let tabIds = m.tabs.map(\.id)
        let other = m.createDoc(title: "Second tab") ?? doc
        _ = other
        await recordFrames("tab-switch", w, seconds: 2.0) {
            for k in 0..<4 { try? await Task.sleep(nanoseconds: 400_000_000); m.activateTab(m.tabs[(k % 2) + max(0, m.tabs.count - 2)].id) }
        }
        _ = tabIds
        m.openView(.all); await wait(0.4)
        await recordFrames("enter-editor-from-library", w, seconds: 1.4) { try? await Task.sleep(nanoseconds: 250_000_000); m.openView(.doc(doc)) }
        m.createSpace("Work"); await wait(0.4)
        let work = m.library.space.id
        let first = m.library.spaces.first { $0.id != work }!.id
        await recordFrames("space-switch", w, seconds: 2.4) {
            try? await Task.sleep(nanoseconds: 300_000_000); m.switchSpace(first)
            try? await Task.sleep(nanoseconds: 1_000_000_000); m.switchSpace(work)
        }
        m.switchSpace(first); await wait(0.4)
        m.openView(.doc(doc)); await wait(0.4)
        m.setSettings { $0.assistantPinned = true }
        let a = m.assistant
        await recordFrames("assistant-open-close", w, seconds: 2.0) {
            try? await Task.sleep(nanoseconds: 250_000_000); m.toggleAssistant()
            try? await Task.sleep(nanoseconds: 1_100_000_000); m.toggleAssistant()
        }
        if a.store.isInstalled(a.model) {
            m.toggleAssistant(); await wait(0.5)
            a.scope = .document; a.draft = "Summarize this note in one line."
            await recordFrames("assistant-states", w, seconds: 9, rect: NSRect(x: w.frame.maxX - 390, y: w.frame.minY, width: 390, height: w.frame.height)) { a.send() }
            await untilIdle(a)
            m.toggleAssistant()
        }
        // Block drag with real mouse events.
        await recordFrames("block-drag", w, seconds: 2.2) {
            guard let ed = m.editors[doc] else { return }
            let tv = c.textView
            guard let first = c.document().content?.first?.id, let pr = c.paragraph(withId: first), let line = c.layout.firstLineRect(pr)?.rect,
                  let last = c.document().content?.last?.id, let lr = c.paragraph(withId: last), let dRect = c.layout.paragraphRect(lr) else { return }
            ed.updateHandle(at: tv.convert(NSPoint(x: 20, y: line.midY + tv.textContainerOrigin.y), to: ed.paperView))
            let h = ed.handleView
            let start = h.convert(NSPoint(x: h.bounds.midX, y: h.bounds.midY), to: nil)
            let target = tv.convert(NSPoint(x: 40, y: dRect.maxY - 2 + tv.textContainerOrigin.y), to: nil)
            try? await Task.sleep(nanoseconds: 300_000_000)
            mouse(.leftMouseDown, start, in: w)
            for k in 1...30 { let t = CGFloat(k) / 30; mouse(.leftMouseDragged, NSPoint(x: start.x + (target.x - start.x) * t, y: start.y + (target.y - start.y) * t), in: w); try? await Task.sleep(nanoseconds: 25_000_000) }
            mouse(.leftMouseUp, target, in: w)
        }
        // Hover over library cards.
        m.openView(.all); await wait(0.5)
        await recordFrames("library-hover", w, seconds: 2.0) {
            for k in 0..<30 { mouse(.mouseMoved, NSPoint(x: 360 + CGFloat(k) * 22, y: w.frame.height - 260), in: w); try? await Task.sleep(nanoseconds: 50_000_000) }
        }
        m.flushAll()
    }

    // MARK: Frame timing

    final class FrameMeter: NSObject {
        var stamps: [CFTimeInterval] = []
        var period: CFTimeInterval = 1.0 / 60
        private var link: CADisplayLink?
        private var waiters: [CheckedContinuation<Void, Never>] = []
        func start(_ v: NSView) {
            stamps = []
            link = v.displayLink(target: self, selector: #selector(tick(_:)))
            link?.add(to: .main, forMode: .common)
        }
        @objc func tick(_ l: CADisplayLink) {
            stamps.append(l.timestamp)
            period = l.targetTimestamp - l.timestamp > 0 ? l.targetTimestamp - l.timestamp : period
            let w = waiters; waiters = []; w.forEach { $0.resume() }
        }
        func nextFrame() async { await withCheckedContinuation { waiters.append($0) } }
        func stop() { link?.invalidate(); link = nil; let w = waiters; waiters = []; w.forEach { $0.resume() } }
    }

    static func cpuSeconds() -> Double {
        var u = rusage(); getrusage(RUSAGE_SELF, &u)
        return Double(u.ru_utime.tv_sec + u.ru_stime.tv_sec) + Double(u.ru_utime.tv_usec + u.ru_stime.tv_usec) / 1e6
    }

    static func measure(_ name: String, _ w: NSWindow, _ meter: FrameMeter, into report: inout [String: Any], latencies: [Double]? = nil, body: () async -> [Double]) async {
        let cpu0 = cpuSeconds(), t0 = CACurrentMediaTime(), mem0 = SystemMemory.footprint
        meter.start(w.contentView!)
        await meter.nextFrame()
        let lat = await body()
        await meter.nextFrame()
        meter.stop()
        let wall = CACurrentMediaTime() - t0
        let iv = zip(meter.stamps.dropFirst(), meter.stamps).map { ($0 - $1) * 1000 }
        let periodMs = meter.period * 1000
        let budget = 16.7
        let within = iv.isEmpty ? 0 : Double(iv.filter { $0 <= budget + 0.5 }.count) / Double(iv.count)
        let withinRefresh = iv.isEmpty ? 0 : Double(iv.filter { $0 <= periodMs * 1.5 }.count) / Double(iv.count)
        let sorted = iv.sorted()
        func pct(_ p: Double) -> Double { sorted.isEmpty ? 0 : sorted[min(sorted.count - 1, Int(Double(sorted.count) * p))] }
        var r: [String: Any] = [
            "frames": iv.count, "refreshMs": (periodMs * 100).rounded() / 100,
            "within16_7": (within * 1000).rounded() / 10, "withinRefresh": (withinRefresh * 1000).rounded() / 10,
            "p50": (pct(0.5) * 10).rounded() / 10, "p95": (pct(0.95) * 10).rounded() / 10, "p99": (pct(0.99) * 10).rounded() / 10, "max": ((sorted.last ?? 0) * 10).rounded() / 10,
            "hitches": iv.filter { $0 > periodMs * 2.5 }.count, "longest": ((sorted.last ?? 0) * 10).rounded() / 10,
            "cpuPercent": ((cpuSeconds() - cpu0) / max(0.001, wall) * 1000).rounded() / 10,
            "memoryMB": Int(SystemMemory.footprint >> 20), "memoryDeltaMB": Int(Int64(SystemMemory.footprint) - Int64(mem0)) / (1 << 20),
            "seconds": (wall * 100).rounded() / 100,
        ]
        if !lat.isEmpty { let s = lat.sorted(); r["inputLatencyP50"] = (s[s.count / 2] * 10).rounded() / 10; r["inputLatencyP95"] = (s[min(s.count - 1, Int(Double(s.count) * 0.95))] * 10).rounded() / 10 }
        report[name] = r
        if let d = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) { try? d.write(to: out.appendingPathComponent("audit-frames.json")) }
    }

    static func auditFrames() async {
        guard let w = NSApp.windows.first(where: { $0.isVisible }) else { return }
        w.setFrame(NSRect(x: 40, y: 40, width: 1440, height: 900), display: true)
        var rep: [String: Any] = ["maxFPS": NSScreen.main?.maximumFramesPerSecond ?? 0]
        let only = ProcessInfo.processInfo.environment["AUDIT_ONLY"]
        func run(_ n: String) -> Bool { only == nil || only == n }
        let meter = FrameMeter()
        seedLibrary(300); m.indexTick &+= 1
        let big = bigDocId(10_000, title: "Ten thousand blocks")
        let mid = bigDocId(2_000, title: "Two thousand blocks")
        await wait(1)

        if run("idle") {
            m.openView(.doc(mid)); await wait(1)
            await measure("idle-doc-open", w, meter, into: &rep) { for _ in 0..<180 { await meter.nextFrame() }; return [] }
        }
        if run("typing") {
            m.openView(.doc(mid)); await wait(1)
            let c = m.editor(for: mid).controller
            w.makeFirstResponder(c.textView)
            let r = c.paragraphRange(at: (c.textView.string as NSString).length / 2)
            c.textView.setSelectedRange(NSRange(location: NSMaxRange(r) - 1, length: 0)); c.textView.scrollRangeToVisible(c.textView.selectedRange())
            await wait(0.5)
            await measure("typing-2k-doc", w, meter, into: &rep) {
                var lat: [Double] = []
                for ch in "Typing a sentence at a steady pace into a long note to measure latency." {
                    let t = CACurrentMediaTime()
                    c.textView.insertText(String(ch), replacementRange: c.textView.selectedRange())
                    await meter.nextFrame(); await meter.nextFrame()
                    lat.append((meter.stamps.last! - t) * 1000)
                    for _ in 0..<3 { await meter.nextFrame() }
                }
                return lat
            }
            await measure("return-2k-doc", w, meter, into: &rep) {
                var lat: [Double] = []
                for _ in 0..<15 {
                    let t = CACurrentMediaTime(); c.textView.insertNewline(nil)
                    await meter.nextFrame(); await meter.nextFrame(); lat.append((meter.stamps.last! - t) * 1000)
                    c.textView.insertText("x", replacementRange: c.textView.selectedRange())
                    for _ in 0..<4 { await meter.nextFrame() }
                }
                return lat
            }
        }
        if run("scroll") {
            for (id, n) in [(mid, "scroll-2k-doc"), (big, "scroll-10k-doc")] {
                m.openView(.doc(id)); await wait(1.2)
                guard let sv = m.editors[id]?.scrollView else { continue }
                await measure(n, w, meter, into: &rep) {
                    for k in 1...240 {
                        sv.contentView.scroll(to: NSPoint(x: 0, y: CGFloat(k) * 30)); sv.reflectScrolledClipView(sv.contentView)
                        await meter.nextFrame()
                    }
                    return []
                }
            }
        }
        if run("library") {
            for (layout, n) in [(LibraryLayout.gallery, "library-gallery-scroll"), (.grid, "library-grid-scroll"), (.list, "library-list-scroll")] {
                m.openView(.all); m.setSettings { $0.libraryView = layout }; await wait(1)
                guard let sv = deepestScrollView(w.contentView!) else { continue }
                await measure(n, w, meter, into: &rep) {
                    for k in 1...240 { sv.contentView.scroll(to: NSPoint(x: 0, y: CGFloat(k) * 30)); sv.reflectScrolledClipView(sv.contentView); await meter.nextFrame() }
                    return []
                }
            }
        }
        if run("collection"), let (host, block) = await collectionDoc(1000) {
            m.openView(.doc(host)); await wait(0.4)
            m.openCollection(host, block); await wait(1)
            for v in m.collectionData(host, block)!.views {
                m.updateCollection(host, block, "View", undo: nil) { $0.activeView = v.id }
                await wait(0.8)
                guard let sv = deepestScrollView(w.contentView!) else { continue }
                await measure("collection-1000-\(v.type)-scroll", w, meter, into: &rep) {
                    for k in 1...240 { sv.contentView.scroll(to: NSPoint(x: 0, y: CGFloat(k) * 30)); sv.reflectScrolledClipView(sv.contentView); await meter.nextFrame() }
                    return []
                }
            }
        }
        if run("create") {
            m.openView(.all); await wait(0.8)
            await measure("note-creation", w, meter, into: &rep) {
                var lat: [Double] = []
                for _ in 0..<8 {
                    m.openView(.all); for _ in 0..<12 { await meter.nextFrame() }
                    let t = CACurrentMediaTime(); _ = m.createDoc()
                    await meter.nextFrame(); await meter.nextFrame(); lat.append((meter.stamps.last! - t) * 1000)
                    for _ in 0..<24 { await meter.nextFrame() }
                }
                return lat
            }
        }
        if run("tabs") {
            for id in [mid, big] { m.openView(.doc(id), newTab: true); await wait(0.8) }
            m.openView(ViewRef(kind: "calendar"), newTab: true); await wait(0.5)
            let ids = m.tabs.map(\.id)
            await measure("tab-switching", w, meter, into: &rep) {
                var lat: [Double] = []
                for k in 0..<20 { let t = CACurrentMediaTime(); m.activateTab(ids[k % ids.count]); await meter.nextFrame(); await meter.nextFrame(); lat.append((meter.stamps.last! - t) * 1000); for _ in 0..<15 { await meter.nextFrame() } }
                return lat
            }
            m.createSpace("Work"); await wait(0.6)
            let a = m.library.space.id, b = m.library.spaces.first { $0.id != a }!.id
            await measure("space-switching", w, meter, into: &rep) {
                var lat: [Double] = []
                var sync: [Double] = []
                for k in 0..<8 { let t = CACurrentMediaTime(); m.switchSpace(k % 2 == 0 ? b : a); sync.append((CACurrentMediaTime() - t) * 1000); await meter.nextFrame(); await meter.nextFrame(); lat.append((meter.stamps.last! - t) * 1000); for _ in 0..<25 { await meter.nextFrame() } }
                try? sync.map { String(format: "%.1f", $0) }.joined(separator: " ").write(to: out.appendingPathComponent("space-sync.txt"), atomically: true, encoding: .utf8)
                return lat
            }
            m.switchSpace(b); await wait(0.6)
        }
        if run("panels") {
            m.openView(.doc(mid)); await wait(1)
            await measure("panels-open-close", w, meter, into: &rep) {
                var lat: [Double] = []
                for p in [Panel.format, .style, .info, .share, .format, .style] {
                    let t = CACurrentMediaTime(); withAnimation(Motion.panel(false)) { m.panel = p }
                    await meter.nextFrame(); await meter.nextFrame(); lat.append((meter.stamps.last! - t) * 1000)
                    for _ in 0..<30 { await meter.nextFrame() }
                    withAnimation(Motion.panel(false)) { m.panel = nil }
                    for _ in 0..<20 { await meter.nextFrame() }
                }
                return lat
            }
            let c = m.editor(for: mid).controller
            await measure("selection-toolbar", w, meter, into: &rep) {
                for k in 0..<10 {
                    let r = c.paragraphRange(at: min(c.storage.length - 1, 200 + k * 80))
                    c.textView.setSelectedRange(NSRange(location: r.location, length: min(12, r.length)))
                    for _ in 0..<15 { await meter.nextFrame() }
                    c.textView.setSelectedRange(NSRange(location: r.location, length: 0))
                    for _ in 0..<10 { await meter.nextFrame() }
                }
                return []
            }
        }
        if run("settings") {
            await measure("settings-sections", w, meter, into: &rep) {
                var lat: [Double] = []
                for s in ["appearance", "editor", "space", "daily", "tags", "advanced", "stats", "data", "about", "templates", "assistant", "appearance"] {
                    let t = CACurrentMediaTime(); m.openView(ViewRef(kind: "settings", section: s)); await meter.nextFrame(); await meter.nextFrame(); lat.append((meter.stamps.last! - t) * 1000)
                    for _ in 0..<15 { await meter.nextFrame() }
                }
                return lat
            }
        }
        if run("drag") {
            m.openView(.doc(mid)); await wait(1)
            let ed = m.editor(for: mid), c = ed.controller, tv = c.textView
            let paras = (c.document().content ?? []).filter { $0.type == "paragraph" || $0.type == "heading" }
            if paras.count > 12, let pr = c.paragraph(withId: paras[2].id ?? ""), let line = c.layout.firstLineRect(pr)?.rect, let tr = c.paragraph(withId: paras[12].id ?? ""), let dRect = c.layout.paragraphRect(tr) {
                await measure("block-drag", w, meter, into: &rep) {
                    ed.updateHandle(at: tv.convert(NSPoint(x: 20, y: line.midY + tv.textContainerOrigin.y), to: ed.paperView))
                    let h = ed.handleView
                    let start = h.convert(NSPoint(x: h.bounds.midX, y: h.bounds.midY), to: nil)
                    let target = tv.convert(NSPoint(x: 40, y: dRect.maxY - 2 + tv.textContainerOrigin.y), to: nil)
                    mouse(.leftMouseDown, start, in: w)
                    for k in 1...90 { let t = CGFloat(k) / 90; mouse(.leftMouseDragged, NSPoint(x: start.x + (target.x - start.x) * t, y: start.y + (target.y - start.y) * t), in: w); await meter.nextFrame() }
                    mouse(.leftMouseUp, target, in: w)
                    for _ in 0..<20 { await meter.nextFrame() }
                    return []
                }
            }
        }
        if run("assistant") {
            m.openView(.doc(mid)); await wait(0.6)
            m.setSettings { $0.assistantPinned = true }
            await measure("assistant-open-close", w, meter, into: &rep) {
                var lat: [Double] = []
                for _ in 0..<4 {
                    let t = CACurrentMediaTime(); m.toggleAssistant(); await meter.nextFrame(); await meter.nextFrame(); lat.append((meter.stamps.last! - t) * 1000)
                    for _ in 0..<40 { await meter.nextFrame() }
                }
                return lat
            }
            let a = m.assistant
            if a.store.isInstalled(a.model) {
                if !a.isOpen { m.toggleAssistant() }
                a.scope = .space; a.draft = "Which notes talk about the budget and what do they say?"
                let mem0 = SystemMemory.footprint
                await measure("assistant-streaming", w, meter, into: &rep) {
                    a.send()
                    var n = 0
                    while a.isRunning && n < 60 * 90 { await meter.nextFrame(); n += 1 }
                    return []
                }
                var r = rep["assistant-streaming"] as? [String: Any] ?? [:]
                r["residentMB"] = Int(SystemMemory.resident >> 20); r["footprintGrowthMB"] = Int((Int64(SystemMemory.footprint) - Int64(mem0)) >> 20)
                rep["assistant-streaming"] = r
                if let d = try? JSONSerialization.data(withJSONObject: rep, options: [.prettyPrinted, .sortedKeys]) { try? d.write(to: out.appendingPathComponent("audit-frames.json")) }
                m.toggleAssistant()
            }
        }
        if run("resize") {
            m.openView(.doc(mid)); await wait(0.8)
            await measure("window-resize", w, meter, into: &rep) {
                for k in 0..<90 { let x = 1440 - CGFloat(k) * 8; w.setFrame(NSRect(x: 40, y: 40, width: x, height: 900), display: true); await meter.nextFrame() }
                return []
            }
        }
        m.flushAll()
    }
}
