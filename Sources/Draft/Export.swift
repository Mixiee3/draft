import AppKit
import SwiftUI
import WebKit
import DraftCore

/// Styled HTML, PDF, PNG and offline-site export. PDF and PNG are made from the same HTML.
extension AppModel {
    func htmlOptions(useStyle: Bool, backdropFile: String?) -> HTMLExport.Options {
        HTMLExport.Options(useStyle: useStyle, assetPath: { "assets/" + $0 }, docPath: { _ in nil }, backdropImage: { _ in backdropFile },
                           tagColor: { self.tagColor($0) }, tagRules: settings.tagRules, today: todayKey,
                           linkTitle: { d, b in self.resolveLink(d, b)?.title })
    }

    /// A scenic backdrop as a picture (scenes are drawn in code, so HTML needs an image of them).
    func sceneImage(_ b: Backdrop) -> Data? {
        guard b.kind == "image" else { return nil }
        if let img = b.image, img.hasPrefix("asset:"), let url = try? vault.assetURL(String(img.dropFirst(6))) { return try? Data(contentsOf: url) }
        let r = ImageRenderer(content: BackdropView(backdrop: b).frame(width: 1600, height: 1000))
        r.scale = 1
        return r.nsImage.flatMap { $0.tiffRepresentation }.flatMap { NSBitmapImageRep(data: $0)?.representation(using: .png, properties: [:]) }
    }

    /// Write `<name>/<file>.html` + assets (+ backdrop.png); returns the folder and the HTML file.
    func writeHTML(_ docId: String, useStyle: Bool, parent: URL, name: String) throws -> (folder: URL, html: URL) {
        saveDirtyDocs()
        guard let d = ensureDoc(docId) else { throw CocoaError(.fileNoSuchFile) }
        let tok = Styles.resolve(d.appearance)
        let scene = useStyle ? sceneImage(tok.backdrop) : nil
        let r = HTMLExport.render(d, tokens: tok, htmlOptions(useStyle: useStyle, backdropFile: scene == nil ? nil : "backdrop.png"), dateChips: settings.dateStyle != "text")
        let file = Markdown.safeFileName(d.title.isEmpty ? "Untitled" : d.title) + ".html"
        let folder = try vault.writeExport(parent: parent, name: name, files: [(file, r.html)], assets: r.assets)
        if let scene { try scene.write(to: folder.appendingPathComponent("backdrop.png")) }
        return (folder, folder.appendingPathComponent(file))
    }

    func exportStyled(_ docId: String, as kind: String, useStyle: Bool, to parent: URL? = nil, done: ((URL?) -> Void)? = nil) {
        let title = Markdown.safeFileName(docTitle(docId))
        let go: (URL) -> Void = { parent in
            do {
                switch kind {
                case "html":
                    let (folder, _) = try self.writeHTML(docId, useStyle: useStyle, parent: parent, name: title)
                    self.finishExport(folder, done)
                default:
                    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("draft-render-\(UUID().uuidString)")
                    let (_, html) = try self.writeHTML(docId, useStyle: useStyle, parent: tmp, name: "doc")
                    let out = Self.uniqueURL(parent.appendingPathComponent(title + (kind == "pdf" ? ".pdf" : ".png")))
                    WebRenderer.shared.render(html, readAccess: tmp, to: out, pdf: kind == "pdf") { ok in
                        try? FileManager.default.removeItem(at: tmp)
                        if ok { self.finishExport(out, done) } else { self.toast("Export failed: the page could not be rendered."); done?(nil) }
                    }
                }
            } catch { self.toast("Export failed: \(error.localizedDescription)"); done?(nil) }
        }
        if let parent { go(parent); return }
        choosePlace("Export Here", "Draft writes the \(kind.uppercased()) here.") { go($0) }
    }

    /// Every top-level document (and its nested pages) as an offline website.
    func exportSite(to parent: URL? = nil, useStyle: Bool = true, done: ((URL?) -> Void)? = nil) {
        saveDirtyDocs()
        let go: (URL) -> Void = { parent in
            let roots = self.library.liveDocs.filter { $0.parentDocId == nil }.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }.map(\.id)
            var scenes: [String: Data] = [:]
            let site = SiteExport.build(rootIds: roots, metas: self.library.docs, folders: self.library.folders, load: { self.ensureDoc($0) },
                                        options: { id in
                                            let b = self.docs[id].map { Styles.resolve($0.appearance).backdrop }
                                            let name = b.flatMap { $0.kind == "image" ? "backdrops/\(Markdown.safeFileName($0.image ?? "scene")).png" : nil }
                                            if useStyle, let b, let name, scenes[name] == nil { scenes[name] = self.sceneImage(b) }
                                            return self.htmlOptions(useStyle: useStyle, backdropFile: useStyle ? name : nil)
                                        },
                                        tokens: { Styles.resolve($0.appearance) }, dateChips: self.settings.dateStyle != "text", siteTitle: self.library.space.name)
            do {
                let folder = try self.vault.writeExport(parent: parent, name: Markdown.safeFileName(self.library.space.name) + " site", files: site.files, assets: site.assets)
                for (p, d) in scenes { try FileManager.default.createDirectory(at: folder.appendingPathComponent("backdrops"), withIntermediateDirectories: true); try d.write(to: folder.appendingPathComponent(p)) }
                self.finishExport(folder, done)
            } catch { self.toast("Export failed: \(error.localizedDescription)"); done?(nil) }
        }
        if let parent { go(parent); return }
        choosePlace("Export Site Here", "Draft writes a folder with index.html, one page per document and their files. It works offline in any browser.") { go($0) }
    }

    func finishExport(_ url: URL, _ done: ((URL?) -> Void)?) {
        lastExportURL = url
        toast("Exported \(url.lastPathComponent)", action: "Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
        done?(url)
    }

    func choosePlace(_ prompt: String, _ message: String, _ go: @escaping (URL) -> Void) {
        let p = NSOpenPanel()
        p.canChooseDirectories = true; p.canChooseFiles = false; p.canCreateDirectories = true
        p.prompt = prompt; p.message = message
        p.begin { r in if r == .OK, let u = p.url { go(u) } }
    }

    static func uniqueURL(_ u: URL) -> URL {
        var out = u, i = 2
        while FileManager.default.fileExists(atPath: out.path) {
            out = u.deletingPathExtension().deletingLastPathComponent().appendingPathComponent("\(u.deletingPathExtension().lastPathComponent) \(i).\(u.pathExtension)"); i += 1
        }
        return out
    }
}

/// Loads a local HTML file in an off-screen web view and saves it as a paged PDF or a PNG.
@MainActor
final class WebRenderer: NSObject, WKNavigationDelegate {
    static let shared = WebRenderer()
    private var jobs: [(URL, URL, URL, Bool, (Bool) -> Void)] = []
    private var web: WKWebView?
    private var window: NSWindow?
    private var current: (out: URL, pdf: Bool, done: (Bool) -> Void)?

    func render(_ html: URL, readAccess: URL, to out: URL, pdf: Bool, done: @escaping (Bool) -> Void) {
        jobs.append((html, readAccess, out, pdf, done))
        if current == nil { next() }
    }

    private func next() {
        guard !jobs.isEmpty else { current = nil; return }
        let (html, access, out, pdf, done) = jobs.removeFirst()
        let cfg = WKWebViewConfiguration()
        cfg.websiteDataStore = .nonPersistent()
        let w = WKWebView(frame: NSRect(x: 0, y: 0, width: 900, height: 1200), configuration: cfg)
        w.navigationDelegate = self
        let win = NSWindow(contentRect: w.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        win.contentView = w
        win.setFrameOrigin(NSPoint(x: -20_000, y: -20_000))
        web = w; window = win
        current = (out, pdf, done)
        w.loadFileURL(html, allowingReadAccessTo: access)
    }

    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in self.finish(webView) }
    }
    nonisolated func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { Task { @MainActor in self.complete(false) } }
    nonisolated func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { Task { @MainActor in self.complete(false) } }

    private func finish(_ w: WKWebView) {
        guard let job = current else { return }
        w.evaluateJavaScript("document.fonts ? document.fonts.ready.then(()=>document.documentElement.scrollHeight) : document.documentElement.scrollHeight") { _, _ in
            w.evaluateJavaScript("document.documentElement.scrollHeight") { h, _ in
                let height = CGFloat((h as? NSNumber)?.doubleValue ?? 1200)
                if job.pdf {
                    let info = NSPrintInfo(dictionary: [.jobDisposition: NSPrintInfo.JobDisposition.save, .jobSavingURL: job.out])
                    info.topMargin = 24; info.bottomMargin = 24; info.leftMargin = 24; info.rightMargin = 24
                    info.horizontalPagination = .fit; info.verticalPagination = .automatic
                    info.isHorizontallyCentered = true
                    let op = w.printOperation(with: info)
                    op.showsPrintPanel = false; op.showsProgressPanel = false
                    op.view?.frame = w.bounds
                    op.runModal(for: self.window!, delegate: self, didRun: #selector(self.printed(_:success:contextInfo:)), contextInfo: nil)
                } else {
                    self.window?.setContentSize(NSSize(width: 900, height: min(height, 30_000)))
                    w.frame = NSRect(x: 0, y: 0, width: 900, height: min(height, 30_000))
                    let cfg = WKSnapshotConfiguration()
                    cfg.rect = w.bounds
                    w.takeSnapshot(with: cfg) { img, _ in
                        let png = img?.tiffRepresentation.flatMap { NSBitmapImageRep(data: $0)?.representation(using: .png, properties: [:]) }
                        let ok = (try? png?.write(to: job.out)) != nil
                        self.complete(ok)
                    }
                }
            }
        }
    }

    @objc private func printed(_ op: NSPrintOperation, success: Bool, contextInfo: UnsafeMutableRawPointer?) {
        complete(success && FileManager.default.fileExists(atPath: current?.out.path ?? ""))
    }

    private func complete(_ ok: Bool) {
        let done = current?.done
        window?.orderOut(nil)
        web = nil; window = nil; current = nil
        done?(ok)
        next()
    }
}
