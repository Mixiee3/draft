import AppKit
import DraftCore

/// Floating controls for the selected image: size, caption and alt text. Standard AppKit
/// controls, so Tab/Shift-Tab, Return and VoiceOver work without extra code.
public final class ImageBar: NSView, NSTextFieldDelegate {
    public override func resetCursorRects() { addCursorRect(bounds, cursor: .arrow) }
    public override func cursorUpdate(with event: NSEvent) { NSCursor.arrow.set() }
    unowned let controller: EditorController
    public let size = NSSegmentedControl(labels: ["S", "M", "L", "Full"], trackingMode: .selectOne, target: nil, action: nil)
    let caption = NSTextField()
    let alt = NSTextField()
    public private(set) var isVisible = false
    static let widths: [Double] = [0.33, 0.5, 0.75, 1]

    init(controller: EditorController) {
        self.controller = controller
        super.init(frame: NSRect(x: 0, y: 0, width: 520, height: 44))
        wantsLayer = true
        layer?.cornerRadius = 14
        layer?.borderWidth = 0.5
        layer?.shadowOpacity = 0.2
        layer?.shadowRadius = 12
        layer?.masksToBounds = false
        isHidden = true
        setAccessibilityRole(.toolbar)
        setAccessibilityLabel("Image options")
        size.target = self; size.action = #selector(sizeChanged)
        size.segmentStyle = .rounded
        size.setAccessibilityLabel("Image size")
        for (i, l) in ["Small", "Medium", "Large", "Full width"].enumerated() { size.setToolTip(l, forSegment: i) }
        for (f, ph, label) in [(caption, "Caption", "Image caption"), (alt, "Alt text for VoiceOver", "Image description for VoiceOver")] {
            f.placeholderString = ph
            f.setAccessibilityLabel(label)
            f.delegate = self
            f.bezelStyle = .roundedBezel
            f.font = .systemFont(ofSize: 12.5)
            f.target = self; f.action = #selector(commit(_:))
        }
        let stack = NSStackView(views: [size, caption, alt])
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 8, left: 10, bottom: 8, right: 10)
        stack.translatesAutoresizingMaskIntoConstraints = false
        caption.widthAnchor.constraint(greaterThanOrEqualToConstant: 150).isActive = true
        alt.widthAnchor.constraint(greaterThanOrEqualToConstant: 150).isActive = true
        addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: leadingAnchor), stack.trailingAnchor.constraint(equalTo: trailingAnchor),
                                     stack.topAnchor.constraint(equalTo: topAnchor), stack.bottomAnchor.constraint(equalTo: bottomAnchor)])
    }
    required init?(coder: NSCoder) { fatalError() }
    public override var isFlipped: Bool { true }

    public override func updateLayer() {
        let dark = controller.theme.isDarkPage
        layer?.backgroundColor = (dark ? NSColor(white: 0.16, alpha: 0.97) : NSColor(white: 0.995, alpha: 0.97)).cgColor
        layer?.borderColor = NSColor(white: dark ? 1 : 0, alpha: 0.1).cgColor
    }
    public override var wantsUpdateLayer: Bool { true }

    var attrs: [String: JSONValue]? {
        guard let i = controller.selectedImageIndex, let a = controller.storage.attribute(.attachment, at: i, effectiveRange: nil) as? BlockAttachment else { return nil }
        return a.node.attrs
    }

    public func update() {
        let editingHere = window?.firstResponder.flatMap { ($0 as? NSView)?.isDescendant(of: self) } ?? false
        guard let a = attrs, let host = controller.overlayHost, let i = controller.selectedImageIndex,
              let cell = (controller.storage.attribute(.attachment, at: i, effectiveRange: nil) as? NSTextAttachment)?.attachmentCell as? ImageCell else {
            if !editingHere { isHidden = true; isVisible = false }
            return
        }
        if superview !== host { host.addSubview(self) }
        let w = a["width"]?.double ?? 1
        size.selectedSegment = Self.widths.firstIndex { abs($0 - w) < 0.02 } ?? -1
        if !editingHere {
            caption.stringValue = a["caption"]?.string ?? ""
            alt.stringValue = a["alt"]?.string ?? ""
        }
        // Above the image, clamped to the visible area (below its top edge when there is no room).
        let tv = controller.textView
        let gr = controller.layout.glyphRange(forCharacterRange: NSRange(location: i, length: 1), actualCharacterRange: nil)
        var r = controller.layout.boundingRect(forGlyphRange: gr, in: controller.container)
        r = tv.convert(r.offsetBy(dx: tv.textContainerOrigin.x, dy: tv.textContainerOrigin.y), to: host)
        let img = cell.imageRect(in: r)
        let vis = host.visibleRect
        let barW = min(560, vis.width - 20)
        var y = img.minY - 44 - 8
        if y < vis.minY + 8 { y = img.minY + 8 }
        let x = min(max(img.midX - barW / 2, vis.minX + 10), vis.maxX - barW - 10)
        frame = NSRect(x: x, y: y, width: barW, height: 44)
        appearance = NSAppearance(named: controller.theme.isDarkPage ? .darkAqua : .aqua) // controls match the bar, not the app
        isHidden = false
        isVisible = true
        needsDisplay = true
    }

    @objc func sizeChanged() {
        guard size.selectedSegment >= 0 else { return }
        controller.setImageWidth(Self.widths[size.selectedSegment])
    }

    @objc func commit(_ sender: NSTextField) {
        if sender === caption { controller.setImageCaption(caption.stringValue) } else { controller.setImageAlt(alt.stringValue) }
    }

    public func controlTextDidEndEditing(_ obj: Notification) {
        guard let f = obj.object as? NSTextField else { return }
        commit(f)
    }

    public func control(_ control: NSControl, textView: NSTextView, doCommandBy sel: Selector) -> Bool {
        if sel == #selector(NSResponder.cancelOperation(_:)) {
            window?.makeFirstResponder(controller.textView)
            return true
        }
        return false
    }
}
