import AppKit
import DraftCore

/// Services the editor needs from the app (asset storage, page lookups, navigation).
public protocol EditorHost: AnyObject {
    func image(forAsset id: String) -> NSImage?
    func pageInfo(docId: String) -> (title: String, excerpt: String, tint: NSColor)?
    func openPage(docId: String)
    func createChildPage() -> (docId: String, title: String)?
    func pickImage(_ completion: @escaping (String?) -> Void)
    func storeImage(data: Data, ext: String) -> String?
    func open(url: URL)
    func editorDidChange()
    func editorStateDidChange()
    /// Create a nested page of this document that holds `content` (block ids kept); returns its id.
    func createGroupedPage(title: String, content: Node) -> String?
    /// Undo/redo of grouping: `false` sends the page to Recently Deleted and hands its nested
    /// pages back to this document; `true` brings it back.
    func setGroupedPage(_ docId: String, active: Bool)
    /// Current title and content of a nested page (for ungroup).
    func pageDocument(docId: String) -> (title: String, content: Node)?
    /// Stable link to a block of this document (`draft://open?doc=…&block=…`).
    func link(toBlock blockId: String) -> URL?
}

/// Base cell: block attachments span the full text width.
class BlockCell: NSTextAttachmentCell {
    weak var controller: EditorController?
    var node: Node { (attachment as? BlockAttachment)?.node ?? Node("paragraph") }
    var theme: EditorTheme { controller?.theme ?? EditorTheme() }
    func height(forWidth w: CGFloat) -> CGFloat { 24 }

    override func cellFrame(for textContainer: NSTextContainer, proposedLineFragment lineFrag: NSRect, glyphPosition position: NSPoint, characterIndex charIndex: Int) -> NSRect {
        let w = max(40, lineFrag.width - 2)
        return NSRect(x: 0, y: 0, width: w, height: height(forWidth: w))
    }
    override func cellSize() -> NSSize { NSSize(width: 600, height: height(forWidth: 600)) }
    override func cellBaselineOffset() -> NSPoint { NSPoint(x: 0, y: -4) }
    override func wantsToTrackMouse() -> Bool { false }
}

/// Separator: semantic `horizontalRule`; its look comes from the document style.
final class DividerCell: BlockCell {
    override func height(forWidth w: CGFloat) -> CGFloat { theme.separator == "tape" ? 30 : 22 }
    override func draw(withFrame f: NSRect, in controlView: NSView?) {
        let midY = f.midY
        let c = theme.text
        switch theme.separator {
        case "dotted":
            c.withAlphaComponent(0.35).setFill()
            var x = f.minX + 4
            while x < f.maxX - 4 { NSBezierPath(ovalIn: NSRect(x: x, y: midY - 1.5, width: 3, height: 3)).fill(); x += 10 }
        case "wave":
            let p = NSBezierPath()
            p.move(to: NSPoint(x: f.minX, y: midY))
            var x = f.minX
            while x < f.maxX { p.curve(to: NSPoint(x: x + 16, y: midY), controlPoint1: NSPoint(x: x + 5, y: midY - 5), controlPoint2: NSPoint(x: x + 11, y: midY + 5)); x += 16 }
            p.lineWidth = 1.6; p.lineCapStyle = .round
            theme.accentColor.withAlphaComponent(0.55).setStroke(); p.stroke()
        case "tape":
            // Original "paper tape": a slightly rotated translucent strip with torn ends.
            let w = min(220, f.width * 0.5)
            let r = NSRect(x: f.midX - w / 2, y: midY - 9, width: w, height: 18)
            NSGraphicsContext.saveGraphicsState()
            let t = NSAffineTransform(); t.translateX(by: r.midX, yBy: r.midY); t.rotate(byDegrees: -1.6); t.translateX(by: -r.midX, yBy: -r.midY); t.concat()
            let p = NSBezierPath()
            p.move(to: NSPoint(x: r.minX, y: r.minY))
            var y = r.minY
            while y < r.maxY { p.line(to: NSPoint(x: r.minX + ((Int(y) / 3) % 2 == 0 ? 3 : 0), y: y + 3)); y += 3 }
            p.line(to: NSPoint(x: r.maxX, y: r.maxY))
            y = r.maxY
            while y > r.minY { p.line(to: NSPoint(x: r.maxX - ((Int(y) / 3) % 2 == 0 ? 3 : 0), y: y - 3)); y -= 3 }
            p.close()
            theme.accentColor.withAlphaComponent(0.32).setFill(); p.fill()
            theme.accentColor.withAlphaComponent(0.18).setFill()
            var sx = r.minX + 8
            while sx < r.maxX - 8 { NSBezierPath(rect: NSRect(x: sx, y: r.minY + 2, width: 4, height: r.height - 4)).fill(); sx += 12 }
            NSGraphicsContext.restoreGraphicsState()
        default:
            c.withAlphaComponent(0.18).setFill()
            NSBezierPath(rect: NSRect(x: f.minX, y: midY - 0.5, width: f.width, height: 1)).fill()
        }
    }
}

final class ImageCell: BlockCell {
    var cached: NSImage?
    func image() -> NSImage? {
        if cached == nil, let id = node.attrs?["assetId"]?.string { cached = controller?.host?.image(forAsset: id) }
        return cached
    }
    override func height(forWidth w: CGFloat) -> CGFloat {
        guard let img = image(), img.size.width > 0 else { return 120 }
        let scale = min(1, w / img.size.width)
        return min(560, img.size.height * scale)
    }
    override func draw(withFrame f: NSRect, in controlView: NSView?) {
        guard let img = image() else {
            theme.text.withAlphaComponent(0.06).setFill()
            NSBezierPath(roundedRect: f, xRadius: 12, yRadius: 12).fill()
            ("Image not found in vault" as NSString).draw(at: NSPoint(x: f.minX + 16, y: f.midY - 8), withAttributes: [.foregroundColor: theme.secondary, .font: NSFont.systemFont(ofSize: 13)])
            return
        }
        let scale = min(f.width / img.size.width, f.height / img.size.height)
        let size = NSSize(width: img.size.width * scale, height: img.size.height * scale)
        let r = NSRect(x: f.minX, y: f.minY, width: size.width, height: size.height)
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(roundedRect: r, xRadius: 10, yRadius: 10).addClip()
        img.draw(in: r, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        NSGraphicsContext.restoreGraphicsState()
    }
}

/// A nested page shown as a card (or a compact page row). Same model either way.
final class PageCardCell: BlockCell {
    var isCard: Bool { node.attrs?["presentation"]?.string != "page" }
    override func height(forWidth w: CGFloat) -> CGFloat { isCard ? 84 : 36 }
    override func wantsToTrackMouse() -> Bool { true }
    override func trackMouse(with event: NSEvent, in cellFrame: NSRect, of controlView: NSView?, untilMouseUp flag: Bool) -> Bool {
        if event.type == .leftMouseDown, let id = node.attrs?["docId"]?.string {
            DispatchQueue.main.async { [weak controller] in controller?.host?.openPage(docId: id) }
        }
        return true
    }
    override func draw(withFrame f: NSRect, in controlView: NSView?) {
        let docId = node.attrs?["docId"]?.string ?? ""
        let info = controller?.host?.pageInfo(docId: docId)
        let title = info?.title.isEmpty == false ? info!.title : (node.attrs?["title"]?.string.flatMap { $0.isEmpty ? nil : $0 } ?? "Untitled page")
        let missing = info == nil
        let r = f.insetBy(dx: 0, dy: 2)
        let iconRect: NSRect
        if isCard {
            let path = NSBezierPath(roundedRect: r, xRadius: 14, yRadius: 14)
            theme.text.withAlphaComponent(theme.isDarkPage ? 0.08 : 0.035).setFill(); path.fill()
            theme.text.withAlphaComponent(0.12).setStroke(); path.lineWidth = 1; path.stroke()
            let tintBar = NSRect(x: r.minX + 14, y: r.minY + 14, width: 40, height: r.height - 28)
            (info?.tint ?? theme.accentColor).withAlphaComponent(0.85).setFill()
            NSBezierPath(roundedRect: tintBar, xRadius: 8, yRadius: 8).fill()
            NSColor(hex: theme.pageColor).withAlphaComponent(0.92).setFill()
            NSBezierPath(roundedRect: tintBar.insetBy(dx: 7, dy: 8), xRadius: 2, yRadius: 2).fill()
            iconRect = tintBar
            let titleFont = theme.font(size: 16, weight: .semibold)
            (title as NSString).draw(in: NSRect(x: iconRect.maxX + 14, y: r.minY + 16, width: r.width - 90, height: 22), withAttributes: [.font: titleFont, .foregroundColor: missing ? theme.secondary : theme.text])
            let sub = missing ? "This page was deleted" : (info!.excerpt.isEmpty ? "Empty page" : info!.excerpt)
            let ps = NSMutableParagraphStyle(); ps.lineBreakMode = .byTruncatingTail
            (sub as NSString).draw(in: NSRect(x: iconRect.maxX + 14, y: r.minY + 42, width: r.width - 110, height: 20), withAttributes: [.font: theme.font(size: 13, weight: .regular), .foregroundColor: theme.secondary, .paragraphStyle: ps])
        } else {
            let icon = NSImage(systemSymbolName: "doc.text", accessibilityDescription: nil)
            iconRect = NSRect(x: r.minX + 2, y: r.minY + 8, width: 16, height: 18)
            icon?.withSymbolConfiguration(.init(paletteColors: [theme.secondary]))?.draw(in: iconRect)
            let ul: [NSAttributedString.Key: Any] = [.font: theme.font(size: 17, weight: .medium), .foregroundColor: theme.text, .underlineStyle: NSUnderlineStyle.single.rawValue, .underlineColor: theme.text.withAlphaComponent(0.25)]
            (title as NSString).draw(at: NSPoint(x: iconRect.maxX + 10, y: r.minY + 6), withAttributes: ul)
        }
        // chevron
        let chev = NSImage(systemSymbolName: "chevron.right", accessibilityDescription: nil)
        chev?.withSymbolConfiguration(.init(paletteColors: [theme.secondary]))?.draw(in: NSRect(x: r.maxX - 24, y: r.midY - 7, width: 8, height: 14))
    }
}

/// A block written by a newer Draft or another app. Shown honestly and preserved verbatim.
final class OpaqueCell: BlockCell {
    override func height(forWidth w: CGFloat) -> CGFloat { 40 }
    override func draw(withFrame f: NSRect, in controlView: NSView?) {
        let r = f.insetBy(dx: 0, dy: 3)
        theme.text.withAlphaComponent(0.05).setFill()
        let p = NSBezierPath(roundedRect: r, xRadius: 9, yRadius: 9); p.fill()
        theme.text.withAlphaComponent(0.15).setStroke(); p.setLineDash([4, 3], count: 2, phase: 0); p.stroke()
        ("“\(node.type)” block — not editable in this version, kept unchanged" as NSString).draw(at: NSPoint(x: r.minX + 12, y: r.midY - 8), withAttributes: [.font: NSFont.systemFont(ofSize: 12.5), .foregroundColor: theme.secondary])
    }
}
