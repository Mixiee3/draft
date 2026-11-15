import AppKit
import UniformTypeIdentifiers
import DraftCore

/// Services the editor needs from the app (asset storage, page lookups, navigation).
public protocol EditorHost: AnyObject {
    func image(forAsset id: String) -> NSImage?
    func pageInfo(docId: String) -> (title: String, excerpt: String, tint: NSColor)?
    func openPage(docId: String)
    func createChildPage() -> (docId: String, title: String)?
    func pickImage(_ completion: @escaping (String?) -> Void)
    func storeImage(data: Data, ext: String) -> String?
    func storeFile(data: Data, name: String, ext: String) -> (assetId: String, name: String, size: Int)?
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
    /// Documents offered by "Move to" (most recent first, this one excluded).
    func moveTargets() -> [(id: String, title: String)]
    /// Append top-level blocks to another document; false if it is not available.
    func appendBlocks(_ content: Node, toDocument target: String) -> Bool
    /// Undo of a move: take the blocks back out of the other document.
    func removeBlocks(_ ids: [String], fromDocument target: String)
    /// Let the user pick a file; it is copied into the vault.
    func pickFile(_ completion: @escaping ((assetId: String, name: String, size: Int)?) -> Void)
    /// Store a file from disk in the vault (drag and drop, pasted Finder files).
    func storeFile(at url: URL) -> (assetId: String, name: String, size: Int)?
    /// Open a stored file with its original name in the default app.
    func openAttachment(assetId: String, name: String)
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
    var variant: String? { node.attrs?["variant"]?.string }
    override func height(forWidth w: CGFloat) -> CGFloat { node.type == "pageBreak" ? 30 : (variant == nil && theme.separator == "tape" ? 30 : 22) }
    override func draw(withFrame f: NSRect, in controlView: NSView?) {
        let midY = f.midY
        let c = theme.text
        if node.type == "pageBreak" {
            let p = NSBezierPath(); p.move(to: NSPoint(x: f.minX, y: midY)); p.line(to: NSPoint(x: f.maxX, y: midY))
            p.setLineDash([6, 5], count: 2, phase: 0); p.lineWidth = 1
            c.withAlphaComponent(0.3).setStroke(); p.stroke()
            let label = "Page break" as NSString
            let a: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 11, weight: .medium), .foregroundColor: theme.secondary]
            let sz = label.size(withAttributes: a)
            let pill = NSRect(x: f.midX - sz.width / 2 - 8, y: midY - sz.height / 2 - 2, width: sz.width + 16, height: sz.height + 4)
            NSColor(hex: theme.pageColor).setFill(); NSBezierPath(roundedRect: pill, xRadius: pill.height / 2, yRadius: pill.height / 2).fill()
            label.draw(at: NSPoint(x: pill.minX + 8, y: pill.minY + 2), withAttributes: a)
            return
        }
        switch variant ?? theme.separator {
        case "strong":
            c.withAlphaComponent(0.55).setFill()
            NSBezierPath(roundedRect: NSRect(x: f.minX, y: midY - 1.25, width: f.width, height: 2.5), xRadius: 1.25, yRadius: 1.25).fill()
        case "dots":
            c.withAlphaComponent(0.45).setFill()
            for i in -1...1 { NSBezierPath(ovalIn: NSRect(x: f.midX + CGFloat(i) * 16 - 2.5, y: midY - 2.5, width: 5, height: 5)).fill() }
        case "dotted":
            c.withAlphaComponent(0.35).setFill()
            var x = f.minX + 4
            while x < f.maxX - 4 { NSBezierPath(ovalIn: NSRect(x: x, y: midY - 1.5, width: 3, height: 3)).fill(); x += 10 }
        case "wave":
            let id = node.id ?? ""
            let period = 13 + 8 * Variation.unit(id, 1), amp = 3.5 + 3 * Variation.unit(id, 2)
            let p = NSBezierPath()
            p.move(to: NSPoint(x: f.minX, y: midY))
            var x = f.minX
            while x < f.maxX { p.curve(to: NSPoint(x: x + period, y: midY), controlPoint1: NSPoint(x: x + period * 0.31, y: midY - amp), controlPoint2: NSPoint(x: x + period * 0.69, y: midY + amp)); x += period }
            p.lineWidth = 1.6; p.lineCapStyle = .round
            theme.accentColor.withAlphaComponent(0.55).setStroke(); p.stroke()
        case "tape":
            // Original "paper tape": a slightly rotated translucent strip with torn ends.
            // Each strip of tape is cut and stuck a little differently (stable per block).
            let id = node.id ?? ""
            let w = min(260, f.width * (0.38 + 0.24 * Variation.unit(id, 1)))
            let shift = (Variation.unit(id, 3) - 0.5) * f.width * 0.2
            let r = NSRect(x: f.midX - w / 2 + shift, y: midY - 9, width: w, height: 18)
            NSGraphicsContext.saveGraphicsState()
            let t = NSAffineTransform(); t.translateX(by: r.midX, yBy: r.midY); t.rotate(byDegrees: -3 + 6 * Variation.unit(id, 2)); t.translateX(by: -r.midX, yBy: -r.midY); t.concat()
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
    /// Width fraction while the user drags the resize edge.
    var liveWidth: CGFloat?
    static let captionHeight: CGFloat = 28

    func image() -> NSImage? {
        if cached == nil, let id = node.attrs?["assetId"]?.string { cached = controller?.host?.image(forAsset: id) }
        return cached
    }
    var widthFraction: CGFloat { liveWidth ?? CGFloat(node.attrs?["width"]?.double ?? 1) }
    var caption: String { node.attrs?["caption"]?.string ?? "" }

    /// Drawn image size inside a line of width `w`.
    func imageSize(forWidth w: CGFloat) -> NSSize {
        guard let img = image(), img.size.width > 0 else { return NSSize(width: w, height: 120) }
        let target = min(img.size.width, w * min(1, max(0.15, widthFraction)))
        let h = img.size.height * target / img.size.width
        let capped = min(h, 640)
        return NSSize(width: target * capped / h, height: capped)
    }
    func imageRect(in f: NSRect) -> NSRect {
        let s = imageSize(forWidth: f.width)
        return NSRect(x: f.minX + (f.width - s.width) / 2, y: f.minY, width: s.width, height: s.height)
    }
    override func height(forWidth w: CGFloat) -> CGFloat { imageSize(forWidth: w).height + (caption.isEmpty ? 0 : Self.captionHeight) }

    override func draw(withFrame f: NSRect, in controlView: NSView?) {
        guard let img = image() else {
            theme.text.withAlphaComponent(0.06).setFill()
            NSBezierPath(roundedRect: f, xRadius: 12, yRadius: 12).fill()
            ("Image not found in vault" as NSString).draw(at: NSPoint(x: f.minX + 16, y: f.midY - 8), withAttributes: [.foregroundColor: theme.secondary, .font: NSFont.systemFont(ofSize: 13)])
            return
        }
        let r = imageRect(in: f)
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(roundedRect: r, xRadius: 10, yRadius: 10).addClip()
        img.draw(in: r, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        NSGraphicsContext.restoreGraphicsState()
        if liveWidth != nil || controller?.isImageSelected(self) == true {
            let ring = NSBezierPath(roundedRect: r.insetBy(dx: -3, dy: -3), xRadius: 12, yRadius: 12)
            ring.lineWidth = 2.5
            theme.accentColor.setStroke(); ring.stroke()
            theme.accentColor.setFill()
            NSBezierPath(roundedRect: NSRect(x: r.maxX - 5, y: r.midY - 18, width: 4, height: 36), xRadius: 2, yRadius: 2).fill()
        }
        if !caption.isEmpty {
            let ps = NSMutableParagraphStyle(); ps.alignment = .center; ps.lineBreakMode = .byTruncatingTail
            (caption as NSString).draw(in: NSRect(x: f.minX, y: r.maxY + 7, width: f.width, height: Self.captionHeight - 7),
                                       withAttributes: [.font: theme.font(size: 13, weight: .regular), .foregroundColor: theme.secondary, .paragraphStyle: ps])
        }
    }

    override func wantsToTrackMouse(for event: NSEvent, in cellFrame: NSRect, of controlView: NSView?, atCharacterIndex charIndex: Int) -> Bool {
        guard let v = controlView else { return false }
        let p = v.convert(event.locationInWindow, from: nil)
        let r = imageRect(in: cellFrame)
        return abs(p.x - r.maxX) < 9 && p.y > r.minY && p.y < r.maxY
    }

    /// Drag the right edge to resize; the width is stored as a fraction of the text width.
    override func trackMouse(with event: NSEvent, in cellFrame: NSRect, of controlView: NSView?, atCharacterIndex charIndex: Int, untilMouseUp flag: Bool) -> Bool {
        guard let v = controlView, let w = v.window, let c = controller else { return false }
        let center = cellFrame.midX
        var e: NSEvent? = event
        while let ev = e {
            if ev.type == .leftMouseUp { break }
            let x = v.convert(ev.locationInWindow, from: nil).x
            liveWidth = min(1, max(0.15, (x - center) * 2 / cellFrame.width))
            c.layout.invalidateLayout(forCharacterRange: NSRange(location: charIndex, length: 1), actualCharacterRange: nil)
            v.needsDisplay = true
            e = w.nextEvent(matching: [.leftMouseDragged, .leftMouseUp])
        }
        if let final = liveWidth {
            liveWidth = nil
            c.updateAttachment(at: charIndex) { $0[attr: "width"] = .number((Double(final) * 100).rounded() / 100) }
        }
        return true
    }
}

/// A stored file: icon, name and size; click opens it in its default app.
final class FileCell: BlockCell {
    var name: String { node.attrs?["name"]?.string ?? "File" }
    override func height(forWidth w: CGFloat) -> CGFloat { 58 }
    override func wantsToTrackMouse() -> Bool { true }
    override func trackMouse(with event: NSEvent, in cellFrame: NSRect, of controlView: NSView?, untilMouseUp flag: Bool) -> Bool {
        if event.type == .leftMouseDown, event.clickCount >= 1, let a = node.attrs?["assetId"]?.string {
            let n = name
            DispatchQueue.main.async { [weak controller] in controller?.host?.openAttachment(assetId: a, name: n) }
        }
        return true
    }
    override func draw(withFrame f: NSRect, in controlView: NSView?) {
        let r = f.insetBy(dx: 0, dy: 3)
        let box = NSBezierPath(roundedRect: r, xRadius: 12, yRadius: 12)
        theme.text.withAlphaComponent(theme.isDarkPage ? 0.08 : 0.035).setFill(); box.fill()
        theme.text.withAlphaComponent(0.12).setStroke(); box.lineWidth = 1; box.stroke()
        let ext = (name as NSString).pathExtension
        let icon = NSWorkspace.shared.icon(for: UTType(filenameExtension: ext) ?? .data)
        icon.draw(in: NSRect(x: r.minX + 12, y: r.midY - 17, width: 34, height: 34), from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        let ps = NSMutableParagraphStyle(); ps.lineBreakMode = .byTruncatingMiddle
        (name as NSString).draw(in: NSRect(x: r.minX + 56, y: r.minY + 9, width: r.width - 140, height: 20),
                                withAttributes: [.font: theme.font(size: 15, weight: .medium, design: .default), .foregroundColor: theme.text, .paragraphStyle: ps])
        let size = ByteCountFormatter.string(fromByteCount: Int64(node.attrs?["size"]?.int ?? 0), countStyle: .file)
        ("\(ext.uppercased().isEmpty ? "File" : ext.uppercased()) · \(size)" as NSString).draw(at: NSPoint(x: r.minX + 56, y: r.minY + 29),
                                withAttributes: [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: theme.secondary])
        ("Open" as NSString).draw(at: NSPoint(x: r.maxX - 52, y: r.midY - 8), withAttributes: [.font: NSFont.systemFont(ofSize: 12.5, weight: .medium), .foregroundColor: theme.accentColor])
    }
}

/// A nested page shown as a card (or a compact page row). Same model either way.
final class PageCardCell: BlockCell {
    var isCard: Bool { node.attrs?["presentation"]?.string != "page" }
    var size: String { node.attrs?["size"]?.string ?? "medium" }
    var preview: String { node.attrs?["preview"]?.string ?? "standard" }
    override func height(forWidth w: CGFloat) -> CGFloat {
        guard isCard else { return 36 }
        switch size {
        case "compact": return 52
        case "feature": return min(260, max(180, w * 0.36))
        default: return 84
        }
    }
    override func wantsToTrackMouse() -> Bool { true }
    override func trackMouse(with event: NSEvent, in cellFrame: NSRect, of controlView: NSView?, untilMouseUp flag: Bool) -> Bool {
        if event.type == .leftMouseDown, let id = node.attrs?["docId"]?.string {
            DispatchQueue.main.async { [weak controller] in controller?.host?.openPage(docId: id) }
        }
        return true
    }

    /// Picture area of a card: gallery = cover image, icon = monogram tile, standard = tinted page.
    func drawThumb(_ rect: NSRect, title: String, tint: NSColor, cover: NSImage?) {
        let clip = NSBezierPath(roundedRect: rect, xRadius: 9, yRadius: 9)
        NSGraphicsContext.saveGraphicsState(); clip.addClip()
        tint.withAlphaComponent(0.85).setFill(); rect.fill()
        if preview == "gallery", let cover {
            let s = cover.size, scale = max(rect.width / max(1, s.width), rect.height / max(1, s.height))
            let d = NSRect(x: rect.midX - s.width * scale / 2, y: rect.midY - s.height * scale / 2, width: s.width * scale, height: s.height * scale)
            cover.draw(in: d, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        } else if preview == "icon" || preview == "gallery" {
            let letter = String(title.trimmingCharacters(in: .whitespaces).prefix(1)).uppercased()
            let f = theme.font(size: min(rect.height, rect.width) * 0.48, weight: .bold)
            let a: [NSAttributedString.Key: Any] = [.font: f, .foregroundColor: NSColor(hex: theme.pageColor)]
            let sz = (letter as NSString).size(withAttributes: a)
            (letter as NSString).draw(at: NSPoint(x: rect.midX - sz.width / 2, y: rect.midY - sz.height / 2), withAttributes: a)
        } else {
            NSColor(hex: theme.pageColor).withAlphaComponent(0.92).setFill()
            NSBezierPath(roundedRect: rect.insetBy(dx: rect.width * 0.18, dy: rect.height * 0.2), xRadius: 2, yRadius: 2).fill()
        }
        NSGraphicsContext.restoreGraphicsState()
    }

    override func draw(withFrame f: NSRect, in controlView: NSView?) {
        let docId = node.attrs?["docId"]?.string ?? ""
        let info = controller?.host?.pageInfo(docId: docId)
        let title = info?.title.isEmpty == false ? info!.title : (node.attrs?["title"]?.string.flatMap { $0.isEmpty ? nil : $0 } ?? "Untitled page")
        let missing = info == nil
        let r = f.insetBy(dx: 0, dy: 2)
        let tint = info?.tint ?? theme.accentColor
        let sub = missing ? "This page was deleted" : (info!.excerpt.isEmpty ? "Empty page" : info!.excerpt)
        let ps = NSMutableParagraphStyle(); ps.lineBreakMode = .byTruncatingTail
        if isCard {
            let path = NSBezierPath(roundedRect: r, xRadius: 14, yRadius: 14)
            theme.text.withAlphaComponent(theme.isDarkPage ? 0.08 : 0.035).setFill(); path.fill()
            theme.text.withAlphaComponent(0.12).setStroke(); path.lineWidth = 1; path.stroke()
            let cover = preview == "gallery" ? (controller?.linkHost?.pageCover(docId: docId)) : nil
            switch size {
            case "feature":
                let band = NSRect(x: r.minX + 10, y: r.minY + 10, width: r.width - 20, height: r.height - 74)
                drawThumb(band, title: title, tint: tint, cover: cover)
                (title as NSString).draw(in: NSRect(x: r.minX + 18, y: band.maxY + 10, width: r.width - 60, height: 24), withAttributes: [.font: theme.font(size: 18, weight: .semibold), .foregroundColor: missing ? theme.secondary : theme.text, .paragraphStyle: ps])
                (sub as NSString).draw(in: NSRect(x: r.minX + 18, y: band.maxY + 34, width: r.width - 60, height: 20), withAttributes: [.font: theme.font(size: 13, weight: .regular), .foregroundColor: theme.secondary, .paragraphStyle: ps])
            case "compact":
                let thumb = NSRect(x: r.minX + 10, y: r.minY + 9, width: 30, height: r.height - 18)
                drawThumb(thumb, title: title, tint: tint, cover: cover)
                (title as NSString).draw(in: NSRect(x: thumb.maxX + 12, y: r.midY - 11, width: r.width - 90, height: 22), withAttributes: [.font: theme.font(size: 15, weight: .semibold), .foregroundColor: missing ? theme.secondary : theme.text, .paragraphStyle: ps])
            default:
                let thumb = NSRect(x: r.minX + 14, y: r.minY + 14, width: preview == "standard" ? 40 : 56, height: r.height - 28)
                drawThumb(thumb, title: title, tint: tint, cover: cover)
                (title as NSString).draw(in: NSRect(x: thumb.maxX + 14, y: r.minY + 16, width: r.width - thumb.width - 70, height: 22), withAttributes: [.font: theme.font(size: 16, weight: .semibold), .foregroundColor: missing ? theme.secondary : theme.text, .paragraphStyle: ps])
                (sub as NSString).draw(in: NSRect(x: thumb.maxX + 14, y: r.minY + 42, width: r.width - thumb.width - 90, height: 20), withAttributes: [.font: theme.font(size: 13, weight: .regular), .foregroundColor: theme.secondary, .paragraphStyle: ps])
            }
        } else {
            let icon = NSImage(systemSymbolName: "doc.text", accessibilityDescription: nil)
            let iconRect = NSRect(x: r.minX + 2, y: r.minY + 8, width: 16, height: 18)
            icon?.withSymbolConfiguration(.init(paletteColors: [theme.secondary]))?.draw(in: iconRect)
            let ul: [NSAttributedString.Key: Any] = [.font: theme.font(size: 17, weight: .medium), .foregroundColor: theme.text, .underlineStyle: NSUnderlineStyle.single.rawValue, .underlineColor: theme.text.withAlphaComponent(0.25)]
            (title as NSString).draw(at: NSPoint(x: iconRect.maxX + 10, y: r.minY + 6), withAttributes: ul)
        }
        let chev = NSImage(systemSymbolName: "chevron.right", accessibilityDescription: nil)
        chev?.withSymbolConfiguration(.init(paletteColors: [theme.secondary]))?.draw(in: NSRect(x: r.maxX - 24, y: r.midY - 7, width: 8, height: 14))
    }
}

/// A web link shown as a card (title, summary, site). Opens in the browser.
final class BookmarkCell: BlockCell {
    override func height(forWidth w: CGFloat) -> CGFloat { node.attrs?["summary"]?.string?.isEmpty == false ? 86 : 62 }
    override func wantsToTrackMouse() -> Bool { true }
    override func trackMouse(with event: NSEvent, in cellFrame: NSRect, of controlView: NSView?, untilMouseUp flag: Bool) -> Bool {
        if event.type == .leftMouseDown, let s = node.attrs?["url"]?.string, let u = URL(string: s) {
            DispatchQueue.main.async { [weak controller] in controller?.host?.open(url: u) }
        }
        return true
    }
    override func draw(withFrame f: NSRect, in controlView: NSView?) {
        let r = f.insetBy(dx: 0, dy: 3)
        let path = NSBezierPath(roundedRect: r, xRadius: 12, yRadius: 12)
        theme.text.withAlphaComponent(theme.isDarkPage ? 0.08 : 0.035).setFill(); path.fill()
        theme.text.withAlphaComponent(0.12).setStroke(); path.lineWidth = 1; path.stroke()
        let icon = NSRect(x: r.minX + 14, y: r.minY + 14, width: 30, height: 30)
        theme.accentColor.withAlphaComponent(0.14).setFill(); NSBezierPath(roundedRect: icon, xRadius: 8, yRadius: 8).fill()
        NSImage(systemSymbolName: "link", accessibilityDescription: nil)?.withSymbolConfiguration(.init(paletteColors: [theme.accentColor]))?.draw(in: icon.insetBy(dx: 7, dy: 7))
        let ps = NSMutableParagraphStyle(); ps.lineBreakMode = .byTruncatingTail
        let x = icon.maxX + 12, w = r.width - (x - r.minX) - 16
        let title = node.attrs?["title"]?.string ?? ""
        (title as NSString).draw(in: NSRect(x: x, y: r.minY + 11, width: w, height: 20), withAttributes: [.font: theme.font(size: 15, weight: .semibold), .foregroundColor: theme.text, .paragraphStyle: ps])
        var y = r.minY + 32
        if let sum = node.attrs?["summary"]?.string, !sum.isEmpty {
            (sum as NSString).draw(in: NSRect(x: x, y: y, width: w, height: 20), withAttributes: [.font: theme.font(size: 13, weight: .regular), .foregroundColor: theme.secondary, .paragraphStyle: ps])
            y += 22
        }
        ((node.attrs?["url"]?.string ?? "") as NSString).draw(in: NSRect(x: x, y: y, width: w, height: 18), withAttributes: [.font: NSFont.systemFont(ofSize: 11.5), .foregroundColor: theme.secondary.withAlphaComponent(0.8), .paragraphStyle: ps])
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
