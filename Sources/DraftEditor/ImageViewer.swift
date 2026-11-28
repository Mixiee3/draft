import AppKit
import Quartz
import DraftCore

/// Quick Look for the note's images: Space on a selected image (or the image bar's eye) opens it;
/// the arrow keys step through every image in the note; Esc closes. Images are handed to Quick Look
/// as files in a private temporary folder that is emptied each time the viewer opens.
final class ImageViewer: NSObject, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    private final class Item: NSObject, QLPreviewItem {
        let url: URL; let title: String
        init(url: URL, title: String) { self.url = url; self.title = title }
        var previewItemURL: URL? { url }
        var previewItemTitle: String? { title }
    }
    private var items: [Item] = []
    private weak var controller: EditorController?
    static var folder: URL { FileManager.default.temporaryDirectory.appendingPathComponent("DraftQuickLook", isDirectory: true) }

    func show(controller c: EditorController, startingAt charIndex: Int) {
        controller = c
        let fm = FileManager.default
        try? fm.removeItem(at: Self.folder)
        try? fm.createDirectory(at: Self.folder, withIntermediateDirectories: true)
        items = []
        var start = 0
        c.storage.enumerateAttribute(.attachment, in: NSRange(location: 0, length: c.storage.length)) { v, r, _ in
            guard let a = v as? BlockAttachment, a.kind == .image, let id = a.node.attrs?["assetId"]?.string,
                  let img = c.host?.image(forAsset: id) else { return }
            let name = (a.node.attrs?["caption"]?.string).flatMap { $0.isEmpty ? nil : $0 } ?? (a.node.attrs?["alt"]?.string).flatMap { $0.isEmpty ? nil : $0 } ?? loc("Image")
            // Sketches are previewed as drawn (vectors over the page colour), not the bare export picture.
            let picture: NSImage
            if let s = Sketch(a.node.attrs?["sketch"]) {
                picture = NSImage(size: NSSize(width: s.width * 2, height: s.height * 2), flipped: true) { rect in
                    NSColor(hex: c.theme.pageColor).setFill(); rect.fill()
                    SketchRenderer.draw(s, in: rect, ink: c.theme.text); return true
                }
            } else { picture = img }
            guard let tiff = picture.tiffRepresentation, let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { return }
            let url = Self.folder.appendingPathComponent("\(items.count + 1) \(name.prefix(60).replacingOccurrences(of: "/", with: "-")).png")
            guard (try? png.write(to: url)) != nil else { return }
            if r.location <= charIndex { start = items.count }
            items.append(Item(url: url, title: name))
        }
        guard !items.isEmpty, let panel = QLPreviewPanel.shared() else { return }
        panel.dataSource = self
        panel.delegate = self
        panel.reloadData()
        panel.currentPreviewItemIndex = start
        panel.makeKeyAndOrderFront(nil)
    }

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int { items.count }
    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! { items[index] }
    func previewPanel(_ panel: QLPreviewPanel!, handle event: NSEvent!) -> Bool {
        // Space closes, as it opened.
        if event.type == .keyDown, event.charactersIgnoringModifiers == " " { panel.close(); return true }
        return false
    }
}

extension EditorController {
    /// Quick Look on the selected image, with every image of the note one arrow key away.
    public func quickLookSelectedImage() {
        guard let i = selectedImageIndex else { return }
        let viewer = (imageViewer as? ImageViewer) ?? ImageViewer()
        imageViewer = viewer
        viewer.show(controller: self, startingAt: i)
    }
}
