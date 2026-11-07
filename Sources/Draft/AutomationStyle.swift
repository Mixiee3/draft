import AppKit
import SwiftUI
import PDFKit
import DraftCore
import DraftEditor

/// `DRAFT_AUTOMATION=style-write | style-read`: Style studio and export, end to end.
extension Automation {
    static func pixel(_ img: NSImage?, _ fx: CGFloat, _ fy: CGFloat) -> String {
        guard let img, let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return "" }
        guard let c = rep.colorAt(x: Int(CGFloat(rep.pixelsWide) * fx), y: Int(CGFloat(rep.pixelsHigh) * fy))?.usingColorSpace(.sRGB) else { return "" }
        return ColorMath.hex(Double(c.redComponent), Double(c.greenComponent), Double(c.blueComponent))
    }
    static func near(_ a: String, _ b: String, _ tol: Double = 0.05) -> Bool {
        let (r1, g1, b1) = ColorMath.rgb(a), (r2, g2, b2) = ColorMath.rgb(b)
        return abs(r1 - r2) < tol && abs(g1 - g2) < tol && abs(b1 - b2) < tol
    }

    /// Real input arrives as events, and AppKit closes each event's undo group; scripted steps
    /// need the same boundary to stay separate undo steps.
    static func boundary() async {
        if let e = NSEvent.otherEvent(with: .applicationDefined, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, subtype: 0, data1: 0, data2: 0) { NSApp.postEvent(e, atStart: false) }
        await wait(0.05)
    }

    /// Color of the editor's page, sampled from the composited window (left margin of the paper).
    static func editorPagePixel(_ e: DocumentEditorView) -> String {
        guard let w = e.window, let cg = CGWindowListCreateImage(.null, .optionIncludingWindow, CGWindowID(w.windowNumber), [.boundsIgnoreFraming, .bestResolution]) else { return "" }
        let tv = e.controller.textView
        let p = tv.convert(NSPoint(x: tv.textContainerOrigin.x - 14, y: tv.visibleRect.minY + 120), to: nil)
        let scale = CGFloat(cg.width) / w.frame.width
        let x = Int(p.x * scale), y = Int((w.frame.height - p.y) * scale)
        let rep = NSBitmapImageRep(cgImage: cg)
        guard let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { return "" }
        return ColorMath.hex(Double(c.redComponent), Double(c.greenComponent), Double(c.blueComponent))
    }

    static func styleWrite() async {
        var r: [String: String] = [:]
        guard let a = m.createDoc(title: "Style source") else { return }
        await wait()
        let ea = m.editors[a]!, c = ea.controller
        ea.focusBody(atStart: true)
        await type("First paragraph in mono\nSecond paragraph", into: c)
        await boundary()
        c.textView.setSelectedRange(NSRange(location: 2, length: 0))
        c.setBlockFont("mono")
        await boundary()
        c.textView.setSelectedRange(NSRange(location: (c.textView.string as NSString).length, length: 0))
        c.insertDivider(); await boundary(); c.insertDivider(); await boundary()
        c.insertAttachmentBlock(kind: .divider, node: Node("pageBreak")); await boundary()
        m.updateAppearance(a) { $0.styleId = "citrus"; $0.overrides.backdrop = Backdrop(kind: "gradient", from: "#112233", to: "#ddeeff", angle: 40); $0.overrides.pageColor = "#fffef0" }
        await boundary()
        // Undo / redo of a style change (one step).
        m.updateAppearance(a) { $0.overrides.textColor = "#bbbbbb" }
        await boundary()
        let low = ColorMath.contrast("#bbbbbb", "#fffef0")
        let fix = ColorMath.readable("#bbbbbb", on: "#fffef0")
        r["contrastFix"] = low < 4.5 && fix.ratio >= 4.5 ? "yes" : "no"
        c.undo.undo()
        r["styleUndo"] = m.docs[a]?.appearance.overrides.textColor == nil ? "yes" : "no"
        c.undo.redo()
        r["styleRedo"] = m.docs[a]?.appearance.overrides.textColor == "#bbbbbb" ? "yes" : "no"
        c.undo.undo()
        await boundary()
        func text() -> String { docPlainText(c.document()) + "|" + (c.document().content ?? []).map { "\($0.type):\($0.attrs?["font"]?.string ?? "")" }.joined(separator: ",") }
        let before = text()
        // Save as a style, apply it to another document.
        let sid = m.saveStyle(from: a, name: "Studio") ?? ""
        r["styleId"] = sid
        guard let b = m.createDoc(title: "Style target") else { return }
        await wait()
        m.updateAppearance(b) { $0.styleId = sid; $0.overrides = StyleOverrides() }
        r["sameLook"] = Styles.resolve(m.docs[a]!.appearance) == Styles.resolve(m.docs[b]!.appearance) ? "yes" : "no"
        r["contentUntouched"] = before == text() ? "yes" : "no"
        // A second style to delete while in use.
        let tmp = m.duplicateStyle(sid)
        guard let t = m.createDoc(title: "Uses deleted style") else { return }
        await wait()
        m.updateAppearance(t) { $0.styleId = tmp }
        m.flushAll()
        let tBefore = m.docs[t].map { docPlainText($0.content) }
        m.deleteStyle(tmp)
        r["deleteFallback"] = m.docs[t]?.appearance.styleId == "citrus" && m.docs[t].map { docPlainText($0.content) } == tBefore ? "yes" : "no \(m.docs[t]?.appearance.styleId ?? "")"
        m.openView(.doc(a)); await wait(0.5)
        // Card with options.
        if let k = m.createDoc(open: false, title: "Card target") {
            c.textView.setSelectedRange(NSRange(location: (c.textView.string as NSString).length, length: 0))
            c.insertAttachmentBlock(kind: .page, node: Node("pageCard", attrs: ["docId": .string(k), "title": "Card target", "presentation": "card"]))
            await boundary()
            if let pr = (c.document().content ?? []).first(where: { $0.type == "pageCard" })?.id.flatMap({ c.paragraph(withId: $0) }) {
                c.textView.setSelectedRange(NSRange(location: pr.location, length: 0))
                c.setCardOption("size", "feature"); c.setCardOption("preview", "icon")
            }
        }
        await type("", into: c)
        m.flushAll()
        // Exports.
        let ex = out.appendingPathComponent("exports")
        try? FileManager.default.createDirectory(at: ex, withIntermediateDirectories: true)
        for kind in ["html", "pdf", "png"] {
            let url: URL? = await withCheckedContinuation { k in m.exportStyled(a, as: kind, useStyle: true, to: ex) { k.resume(returning: $0) } }
            r["export." + kind] = url?.path ?? ""
        }
        let plain: URL? = await withCheckedContinuation { k in m.exportStyled(a, as: "html", useStyle: false, to: ex.appendingPathComponent("plain")) { k.resume(returning: $0) } }
        r["export.plainHtml"] = plain?.path ?? ""
        let site: URL? = await withCheckedContinuation { k in m.exportSite(to: ex, useStyle: true) { k.resume(returning: $0) } }
        r["export.site"] = site?.path ?? ""
        // Same look in editor, HTML (PNG of it) and PDF: compare the page color.
        let page = Styles.resolve(m.docs[a]!.appearance).pageColor
        r["page"] = page
        r["editorPage"] = editorPagePixel(ea)
        r["pngPage"] = pixel(r["export.png"].flatMap { NSImage(contentsOfFile: $0) }, 0.12, 0.3)
        if let p = r["export.pdf"], let pdf = PDFDocument(url: URL(fileURLWithPath: p)), let pg = pdf.page(at: 0) {
            r["pdfPages"] = "\(pdf.pageCount)"
            r["pdfText"] = (pdf.string ?? "").contains("First paragraph in mono") ? "yes" : "no"
            r["pdfPage"] = pixel(pg.thumbnail(of: NSSize(width: 600, height: 800), for: .mediaBox), 0.07, 0.5)
        }
        r["consistent"] = near(r["editorPage"] ?? "", page) && near(r["pngPage"] ?? "", page) && near(r["pdfPage"] ?? "", page) ? "yes" : "no"
        // Online features are off by default: pasting a URL sends nothing.
        c.textView.setSelectedRange(NSRange(location: (c.textView.string as NSString).length, length: 0))
        c.textView.insertNewline(nil)
        c.pastePlainForAutomation("https://example.com/article")
        r["onlineDefaultsOff"] = !m.settings.onlineImageSearch && !m.settings.linkPreviews ? "yes" : "no"
        r["networkRequests"] = "\(m.online.requests)"
        let searched: String = await withCheckedContinuation { k in m.online.searchImages("lake", enabled: m.settings.onlineImageSearch) { k.resume(returning: (try? $0.get()) == nil ? "refused" : "ran") } }
        r["searchWhenOff"] = searched
        r["networkRequestsAfter"] = "\(m.online.requests)"
        r["a"] = a; r["b"] = b
        m.flushAll()
        save(r, "style-write.json")
    }

    static func styleRead() async {
        guard let d = try? Data(contentsOf: out.appendingPathComponent("style-write.json")),
              let w = try? JSONSerialization.jsonObject(with: d) as? [String: String], let a = w["a"], let b = w["b"] else { return }
        var r: [String: String] = [:]
        _ = m.ensureDoc(a); _ = m.ensureDoc(b)
        r["userStyles"] = m.library.userStyles.map(\.name).joined(separator: ",")
        r["sameLook"] = m.docs[a].map { Styles.resolve($0.appearance) } == m.docs[b].map { Styles.resolve($0.appearance) } && m.docs[b]?.appearance.styleId == w["styleId"] ? "yes" : "no"
        let content = m.docs[a]?.content
        r["blockFont"] = content?.content?.first?.attrs?["font"]?.string ?? ""
        let card = content.flatMap { c in (c.content ?? []).first { $0.type == "pageCard" } }
        r["card"] = "\(card?.attrs?["size"]?.string ?? ""),\(card?.attrs?["preview"]?.string ?? "")"
        let rules = (content?.content ?? []).filter { $0.type == "horizontalRule" }.map { $0.id ?? "" }
        r["tapeDiffers"] = rules.count == 2 && Variation.unit(rules[0], 2) != Variation.unit(rules[1], 2) ? "yes" : "no"
        r["gradient"] = m.docs[a].map { "\(Styles.resolve($0.appearance).backdrop.angle ?? -1)" } ?? ""
        save(r, "style-read.json")
    }
}

extension Automation {
    /// A popover's content shown in its own real window and captured (popovers are separate windows).
    static func renderComponent<V: View>(_ v: V, _ name: String, dark: Bool) async {
        let host = NSHostingView(rootView: v.environmentObject(m).environment(\.tokens, Tokens.make(dark: dark, accent: m.settings.accent, tint: nil))
            .padding(4).background(dark ? Color(hex: "#2a2a2b") : Color.white).environment(\.colorScheme, dark ? .dark : .light))
        let size = host.fittingSize
        let win = NSWindow(contentRect: NSRect(x: 200, y: 200, width: max(200, size.width), height: max(200, size.height)), styleMask: [.titled], backing: .buffered, defer: false)
        win.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        win.contentView = host
        win.orderFrontRegardless()
        await wait(0.6)
        if let cg = CGWindowListCreateImage(.null, .optionIncludingWindow, CGWindowID(win.windowNumber), [.boundsIgnoreFraming, .bestResolution]),
           let png = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) {
            try? png.write(to: out.appendingPathComponent(name + ".png"))
        }
        win.orderOut(nil)
    }

    static func screensV04() async {
        guard let w = NSApp.windows.first(where: { $0.isVisible }) else { return }
        var checks: [String: String] = [:]
        guard let a = m.createDoc(title: "Studio notes") else { return }
        await wait()
        let ea = m.editors[a]!, c = ea.controller
        ea.focusBody(atStart: true)
        await type("A calm page for long thoughts.\nThis block uses the mono font.", into: c)
        await boundary()
        c.textView.setSelectedRange(NSRange(location: (c.textView.string as NSString).length - 3, length: 0))
        c.setBlockFont("mono"); await boundary()
        c.textView.setSelectedRange(NSRange(location: (c.textView.string as NSString).length, length: 0))
        c.insertDivider(); await boundary(); c.insertDivider(); await boundary()
        for (size, preview) in [("compact", "standard"), ("medium", "icon"), ("feature", "gallery")] {
            guard let k = m.createDoc(open: false, title: "\(size.capitalized) card") else { continue }
            m.updateAppearance(k) { $0.styleId = size == "feature" ? "aurora" : "linen" }
            c.textView.setSelectedRange(NSRange(location: (c.textView.string as NSString).length, length: 0))
            c.insertAttachmentBlock(kind: .page, node: Node("pageCard", attrs: ["docId": .string(k), "title": .string("\(size.capitalized) card"), "presentation": "card", "size": .string(size), "preview": .string(preview)]))
            await boundary()
        }
        c.textView.setSelectedRange(NSRange(location: (c.textView.string as NSString).length, length: 0))
        c.insertAttachmentBlock(kind: .bookmark, node: Node("linkPreview", attrs: ["url": "https://example.org/essay", "title": "An essay on quiet tools", "summary": "Preview cards appear only when link previews are turned on.", "site": "example.org"]))
        await boundary()
        m.updateAppearance(a) { $0.styleId = "sorbet" }
        _ = m.saveStyle(from: a, name: "Studio")
        m.flushAll()
        for theme in ["light", "dark"] {
            m.setSettings { $0.theme = theme }
            for (width, height, tag) in [(1440.0, 900.0, ""), (720.0, 640.0, "narrow-")] {
                let p = tag + (theme == "dark" ? "dark-" : "")
                w.setFrame(NSRect(x: 60, y: 60, width: width, height: height), display: true)
                m.openView(.doc(a)); await wait(0.6)
                ea.scrollView.contentView.scroll(to: .zero)
                await capture(p + "v04-document")
                ea.scrollView.contentView.scroll(to: NSPoint(x: 0, y: 360)); ea.scrollView.reflectScrolledClipView(ea.scrollView.contentView)
                await capture(p + "v04-cards")
                m.panel = .style; await capture(p + "v04-style-panel")
                m.panel = nil
                m.styleGallery = true; await capture(p + "v04-style-gallery"); m.styleGallery = false
                if let pr = (c.document().content ?? []).first(where: { $0.type == "pageCard" })?.id.flatMap({ c.paragraph(withId: $0) }) {
                    c.textView.setSelectedRange(NSRange(location: pr.location, length: 0))
                }
                m.panel = .format; await capture(p + "v04-format-panel")
                m.panel = .share; await capture(p + "v04-export-panel")
                m.panel = nil
                if tag == "" { m.openView(ViewRef(kind: "settings", section: "advanced")); await capture(p + "v04-settings-advanced") }
            }
            await renderComponent(BackdropPicker(docId: a).frame(width: 300), (theme == "dark" ? "dark-" : "") + "v04-backdrop-picker", dark: theme == "dark")
            m.updateAppearance(a) { $0.overrides.backdrop = Backdrop(kind: "image", image: "aurora") }
            await renderComponent(BackdropPicker(docId: a).frame(width: 300), (theme == "dark" ? "dark-" : "") + "v04-backdrop-library", dark: theme == "dark")
            m.updateAppearance(a) { $0.overrides.backdrop = nil }
        }
        m.setSettings { $0.theme = "light" }
        // Low contrast warning with the hue-keeping fix.
        m.updateAppearance(a) { $0.overrides.textColor = "#c9a0b4" }
        w.setFrame(NSRect(x: 60, y: 60, width: 1440, height: 900), display: true)
        m.openView(.doc(a)); m.panel = .style; await capture("v04-contrast-adjust")
        m.panel = nil
        m.addTask("Send the draft", on: m.todayKey); m.flushAll()
        if let t = m.index.tasks(live: m.liveIds).first { await renderComponent(DuePicker(doc: t.doc, task: t.task), "v04-due-picker", dark: false) }
        checks["userStyles"] = m.library.userStyles.map(\.name).joined(separator: ",")
        save(checks, "v04-checks.json")
        m.flushAll()
    }
}
