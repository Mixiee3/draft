import AppKit
import DraftCore

/// Plain-text title field that behaves like the first line of the page.
final class TitleTextView: NSTextView {
    var onEnter: (() -> Void)?
    var onDown: (() -> Void)?
    var placeholder = "Untitled"
    var placeholderColor = NSColor.tertiaryLabelColor

    override func insertNewline(_ sender: Any?) { onEnter?() }
    override func insertTab(_ sender: Any?) { onEnter?() }
    override func moveDown(_ sender: Any?) {
        let atLastLine = selectedRange().location >= (string as NSString).length
        if atLastLine { onDown?() } else { super.moveDown(sender) }
    }
    override func paste(_ sender: Any?) { pasteAsPlainText(sender) }
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if string.isEmpty, let f = font {
            (placeholder as NSString).draw(at: NSPoint(x: textContainerOrigin.x, y: textContainerOrigin.y), withAttributes: [.font: f, .foregroundColor: placeholderColor])
        }
    }
}

/// The scrollable page: optional cover, title, body. Background is transparent so the
/// document backdrop (drawn behind by the app) shows around the paper.
final class PaperView: NSView {
    weak var owner: DocumentEditorView?
    var paperRect: NSRect = .zero { didSet { if paperRect != oldValue { window?.invalidateCursorRects(for: self) } } }
    override var isFlipped: Bool { true }
    // I-beam on the page (a click there edits); the backdrop around it keeps the arrow.
    override func resetCursorRects() { addCursorRect(paperRect, cursor: .iBeam) }
    override func mouseDown(with event: NSEvent) {
        // Clicking empty paper below the text puts the caret at the end; the backdrop ends editing.
        let p = convert(event.locationInWindow, from: nil)
        guard let o = owner, paperRect.contains(p) else { window?.makeFirstResponder(nil); return }
        let tv = o.controller.textView
        window?.makeFirstResponder(tv)
        if p.y > tv.frame.maxY - 4 { tv.setSelectedRange(NSRange(location: (tv.string as NSString).length, length: 0)) }
    }
}

/// Non-scrolling, flipped layer over the page for floating controls; its empty areas pass clicks through.
final class FloatingLayer: NSView {
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? {
        let hit = super.hitTest(point)
        return hit === self ? nil : hit
    }
}

public final class DocumentEditorView: NSView, NSTextViewDelegate {
    public let controller = EditorController()
    public let scrollView = NSScrollView()
    let paper = PaperView()
    public var paperView: NSView { paper }
    let paperBackground = NSView()
    let coverView = NSImageView()
    public let titleView: NSTextView
    var title_: TitleTextView { titleView as! TitleTextView }
    let ruleView = NSView()
    public var onTitleChange: ((String) -> Void)?
    let handle = BlockHandleView(frame: .zero)
    let blockActions = BlockActionBar(frame: .zero)
    let floating = FloatingLayer()
    private let fade: CAGradientLayer = {
        let l = CAGradientLayer()
        l.colors = [NSColor.clear.cgColor, NSColor.black.cgColor, NSColor.black.cgColor] // the scroll view's layer is flipped: 0 is the top edge
        return l
    }()
    public var blockActionsView: NSView { blockActions }
    public var handleView: NSView { handle }
    public var onLayout: (() -> Void)?
    public var onEditCover: (() -> Void)?
    public var onRemoveCover: (() -> Void)?
    let coverControls = NSStackView()
    /// Height reserved at the top for the host's floating controls.
    public var topInset: CGFloat = 0 { didSet { needsLayout = true } }
    /// Room kept free on the right for an open panel; the page moves aside rather than under it.
    public var trailingInset: CGFloat = 0 { didSet { if oldValue != trailingInset { needsLayout = true } } }
    private var lastTitleLayoutWidth: CGFloat = -1
    private var lastTitleLayoutText = ""

    /// Slides the page aside for a side panel instead of jumping; the text reflows once, at the end width.
    public func setTrailingInset(_ inset: CGFloat, animated: Bool) {
        guard inset != trailingInset else { return }
        guard animated, window != nil else { trailingInset = inset; return }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.26
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.25, 1)
            ctx.allowsImplicitAnimation = true
            trailingInset = inset
            relayout()
        }
    }

    public var pageColor = NSColor(hex: "#fffdf8") { didSet { paperBackground.layer?.backgroundColor = pageColor.cgColor } }
    public var coverImage: NSImage? { didSet { coverView.image = coverImage; coverView.isHidden = coverImage == nil; needsLayout = true; relayout() } }
    public var narrow: Bool { bounds.width < 640 }

    public override init(frame: NSRect) {
        let ts = NSTextStorage()
        let lm = NSLayoutManager()
        ts.addLayoutManager(lm)
        let tc = NSTextContainer(size: NSSize(width: 600, height: CGFloat.greatestFiniteMagnitude))
        tc.widthTracksTextView = true
        tc.lineFragmentPadding = 0
        lm.addTextContainer(tc)
        titleView = TitleTextView(frame: .zero, textContainer: tc) as NSTextView
        super.init(frame: frame)

        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.borderType = .noBorder
        scrollView.contentView.drawsBackground = false
        scrollView.documentView = paper
        scrollView.translatesAutoresizingMaskIntoConstraints = true
        scrollView.autoresizingMask = []
        addSubview(scrollView)
        paper.owner = self
        // Floating glass lives in this non-scrolling layer above the page, inside the editor, so it
        // samples the page behind it and is clipped to the editor rather than the whole window.
        addSubview(floating)
        controller.floatingHost = floating
        blockActions.owner = self
        floating.addSubview(blockActions)
        // Text fades as it scrolls under the top controls. Masking only the scroll view (not the whole
        // editor, as a SwiftUI mask would) keeps the floating glass out of an offscreen pass.
        scrollView.wantsLayer = true
        scrollView.layer?.mask = fade
        controller.onSelectionChange = { [weak self] in self?.blockActions.update() }

        paperBackground.wantsLayer = true
        paperBackground.layer?.cornerRadius = 22
        paperBackground.layer?.shadowOpacity = 0.12
        paperBackground.layer?.shadowRadius = 24
        paperBackground.layer?.shadowOffset = CGSize(width: 0, height: -6)
        paperBackground.layer?.backgroundColor = pageColor.cgColor
        paper.addSubview(paperBackground)

        coverView.imageScaling = .scaleAxesIndependently
        coverView.wantsLayer = true
        coverView.layer?.cornerRadius = 22
        coverView.layer?.maskedCorners = [.layerMinXMaxYCorner, .layerMaxXMaxYCorner]
        coverView.layer?.masksToBounds = true
        coverView.layer?.contentsGravity = .resizeAspectFill
        coverView.isHidden = true
        coverView.setAccessibilityLabel(loc("Cover image"))
        paper.addSubview(coverView)
        // Hover controls on the cover: edit (crop) and remove.
        for (symbol, label, sel) in [("pencil", "Edit cover", #selector(editCover)), ("xmark", "Remove cover", #selector(removeCover))] {
            let b = NSButton(image: NSImage(systemSymbolName: symbol, accessibilityDescription: label)!, target: self, action: sel)
            b.bezelStyle = .circular
            b.setAccessibilityLabel(label)
            b.toolTip = label
            coverControls.addArrangedSubview(b)
        }
        coverControls.spacing = 6
        coverControls.isHidden = true
        paper.addSubview(coverControls)

        titleView.isRichText = false
        titleView.drawsBackground = false
        titleView.allowsUndo = true
        titleView.isVerticallyResizable = true
        titleView.textContainerInset = .zero
        titleView.delegate = self
        titleView.setAccessibilityLabel(loc("Document title"))
        title_.onEnter = { [weak self] in self?.focusBody(atStart: true) }
        title_.onDown = { [weak self] in self?.focusBody(atStart: true) }
        paper.addSubview(titleView)

        ruleView.wantsLayer = true
        paper.addSubview(ruleView)

        let tv = controller.textView
        tv.autoresizingMask = []
        tv.minSize = NSSize(width: 0, height: 120)
        tv.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        paper.addSubview(tv)
        controller.overlayHost = paper
        handle.owner = self
        paper.addSubview(handle)
        paper.addSubview(handle.indicator)
        paper.addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self))

        tv.postsFrameChangedNotifications = true
        NotificationCenter.default.addObserver(self, selector: #selector(relayoutNote), name: NSView.frameDidChangeNotification, object: tv)
        scrollView.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(self, selector: #selector(scrolled), name: NSView.boundsDidChangeNotification, object: scrollView.contentView)
        applyTheme()
    }
    required init?(coder: NSCoder) { fatalError() }

    public var theme: EditorTheme {
        get { controller.theme }
        set { controller.theme = newValue; applyTheme() }
    }

    func applyTheme() {
        let t = controller.theme
        titleView.font = t.font(size: narrow ? 28 : 34, weight: .bold)
        titleView.textColor = t.text
        titleView.insertionPointColor = t.text
        title_.placeholderColor = t.text.withAlphaComponent(0.28)
        controller.textView.insertionPointColor = t.text
        controller.refreshSelectionStyle()
        titleView.selectedTextAttributes = [.backgroundColor: t.accentColor.withAlphaComponent(t.isDarkPage ? 0.45 : 0.22)]
        ruleView.layer?.backgroundColor = t.text.withAlphaComponent(0.1).cgColor
        pageColor = NSColor(hex: t.pageColor)
        relayout()
        titleView.needsDisplay = true
        if controller.toolbar.isVisible { controller.toolbar.update() }
        blockActions.update()
    }

    public var title: String {
        get { titleView.string }
        set { if titleView.string != newValue { titleView.string = newValue; relayout() } }
    }

    public func textDidChange(_ notification: Notification) {
        guard (notification.object as? NSTextView) === titleView else { return }
        let clean = titleView.string.replacingOccurrences(of: "\n", with: " ")
        onTitleChange?(clean)
        relayout()
    }

    public func focusTitle() {
        window?.makeFirstResponder(titleView)
        titleView.setSelectedRange(NSRange(location: (titleView.string as NSString).length, length: 0))
    }

    public func focusBody(atStart: Bool) {
        window?.makeFirstResponder(controller.textView)
        if atStart { controller.textView.setSelectedRange(NSRange(location: 0, length: 0)) }
    }

    @objc func relayoutNote() { relayout() }

    public override func mouseMoved(with event: NSEvent) {
        let p = paper.convert(event.locationInWindow, from: nil)
        updateHandle(at: p)
        blockActions.update()
        coverControls.isHidden = coverImage == nil || !coverView.frame.contains(p)
    }
    @objc func editCover() { onEditCover?() }
    @objc func removeCover() { onRemoveCover?() }
    public override func mouseExited(with event: NSEvent) { if !handle.isDragging { handle.isHidden = true } }
    @objc func scrolled() {
        if controller.toolbar.isVisible { controller.toolbar.position() }
        if controller.slash.isOpen { controller.slash.position() }
        if controller.tableEditor.tableId != nil { controller.tableEditor.reposition() }
    }

    public override func layout() {
        super.layout()
        // Text scrolls only below the host's top controls, never underneath them.
        scrollView.frame = NSRect(x: 0, y: 0, width: bounds.width, height: max(0, bounds.height - topInset))
        if floating.frame != scrollView.frame { floating.frame = scrollView.frame }
        let h = scrollView.frame.height
        if fade.frame != scrollView.bounds || fade.locations?.count != 3 {
            CATransaction.begin(); CATransaction.setDisableActions(true)
            fade.frame = scrollView.bounds
            fade.locations = [0, NSNumber(value: Double(min(1, 14 / max(h, 1)))), 1] // 14 pt fade at the top edge
            CATransaction.commit()
        }
        placeBlockActions()
        relayout()
        blockActions.update()
    }

    func placeBlockActions() {
        let size = blockActions.fittingSize
        let r = NSRect(x: ((floating.bounds.width - size.width) / 2).rounded(), y: floating.bounds.height - size.height - 18, width: size.width, height: size.height)
        if blockActions.frame != r { blockActions.frame = r }
    }

    /// Scrolling runs layout; re-assigning unchanged frames there dirtied the window's regions every frame.
    private func place(_ v: NSView, _ r: NSRect) { if v.frame != r { v.frame = r } }

    private var inLayout = false
    func relayout() {
        guard !inLayout else { return }
        inLayout = true
        defer { inLayout = false }
        if !handle.isDragging { handle.isHidden = true } // the next mouse move places it again
        let width = scrollView.contentSize.width
        guard width > 0 else { return }
        let margin: CGFloat = width < 640 ? 10 : 28
        var paperW = min(840, width - margin * 2)
        var paperX = ((width - paperW) / 2).rounded()
        if trailingInset > 0 {
            // A side panel slides the page left when there is room, but never narrows it: a narrower
            // page re-wraps every paragraph and the text under the reader jumps. What doesn't fit
            // sits under the floating panel.
            let avail = width - trailingInset - margin
            if paperX + paperW > avail { paperX = max(margin, avail - paperW) }
        }
        let top: CGFloat = topInset > 0 ? 14 : 70
        let pad: CGFloat = paperW < 560 ? 22 : (paperW < 700 ? 44 : 68)
        var y = top
        if let img = coverImage, img.size.width > 0 {
            let h = min(460, max(90, (paperW * img.size.height / img.size.width).rounded()))
            place(coverView, NSRect(x: paperX, y: top, width: paperW, height: h))
            place(coverControls, NSRect(x: paperX + paperW - 92, y: top + 12, width: 80, height: 32))
            y += h + 36
        } else { y += 52 }
        let innerW = paperW - pad * 2
        let titleNeedsLayout = titleView.frame.width != innerW || lastTitleLayoutWidth != innerW || lastTitleLayoutText != titleView.string
        if titleView.frame.width != innerW { titleView.frame.size.width = innerW }
        if titleNeedsLayout {
            titleView.layoutManager?.ensureLayout(for: titleView.textContainer!)
            lastTitleLayoutWidth = innerW
            lastTitleLayoutText = titleView.string
        }
        let titleH = max((titleView.layoutManager?.usedRect(for: titleView.textContainer!).height ?? 40), (titleView.font?.pointSize ?? 34) * 1.25)
        place(titleView, NSRect(x: paperX + pad, y: y, width: innerW, height: titleH))
        y += titleH + 16
        place(ruleView, NSRect(x: paperX + pad, y: y, width: innerW, height: 1))
        y += 22
        let tv = controller.textView
        if abs(tv.frame.width - innerW) > 0.5 || tv.frame.minX != paperX + pad || tv.frame.minY != y {
            tv.frame = NSRect(x: paperX + pad, y: y, width: innerW, height: tv.frame.height)
        }
        // The text view sizes itself; forcing a full layout here cost ~90 ms per height change in a 10k-block document.
        if tv.frame.height < 160 { tv.setFrameSize(NSSize(width: innerW, height: 160)) }
        // A short note still gets a whole page, down to just above the window edge.
        let fill = scrollView.contentSize.height - 84
        let paperBottom = max(tv.frame.maxY + 90, fill)
        paper.paperRect = NSRect(x: paperX, y: top, width: paperW, height: paperBottom - top)
        if paperBackground.frame != paper.paperRect {
            paperBackground.frame = paper.paperRect
            paperBackground.layer?.shadowPath = CGPath(roundedRect: paperBackground.bounds, cornerWidth: 22, cornerHeight: 22, transform: nil)
        }
        let docH = paperBottom == fill ? scrollView.contentSize.height : max(paperBottom + 84, scrollView.contentSize.height)
        if paper.frame.size != NSSize(width: width, height: docH) { paper.frame = NSRect(x: 0, y: 0, width: width, height: docH) }
        if controller.imageBar.isVisible { controller.imageBar.update() }
        if controller.toolbar.isVisible { controller.toolbar.position() }
        onLayout?()
    }
}
