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
    var paperRect: NSRect = .zero
    override var isFlipped: Bool { true }
    override func mouseDown(with event: NSEvent) {
        // Clicking empty paper below the text puts the caret at the end.
        let p = convert(event.locationInWindow, from: nil)
        guard let o = owner, paperRect.contains(p) else { return super.mouseDown(with: event) }
        let tv = o.controller.textView
        window?.makeFirstResponder(tv)
        if p.y > tv.frame.maxY - 4 { tv.setSelectedRange(NSRange(location: (tv.string as NSString).length, length: 0)) }
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
    public var handleView: NSView { handle }
    public var onLayout: (() -> Void)?
    /// Height reserved at the top for the host's floating controls.
    public var topInset: CGFloat = 0 { didSet { needsLayout = true } }

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
        coverView.setAccessibilityLabel("Cover image")
        paper.addSubview(coverView)

        titleView.isRichText = false
        titleView.drawsBackground = false
        titleView.allowsUndo = true
        titleView.isVerticallyResizable = true
        titleView.textContainerInset = .zero
        titleView.delegate = self
        titleView.setAccessibilityLabel("Document title")
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
        controller.textView.selectedTextAttributes = [.backgroundColor: t.accentColor.withAlphaComponent(t.isDarkPage ? 0.45 : 0.22)]
        titleView.selectedTextAttributes = controller.textView.selectedTextAttributes
        ruleView.layer?.backgroundColor = t.text.withAlphaComponent(0.1).cgColor
        pageColor = NSColor(hex: t.pageColor)
        relayout()
        titleView.needsDisplay = true
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

    public override func mouseMoved(with event: NSEvent) { updateHandle(at: paper.convert(event.locationInWindow, from: nil)) }
    public override func mouseExited(with event: NSEvent) { if !handle.isDragging { handle.isHidden = true } }
    @objc func scrolled() {
        if controller.toolbar.isVisible { controller.toolbar.position() }
        if controller.slash.isOpen { controller.slash.position() }
    }

    public override func layout() {
        super.layout()
        // Text scrolls only below the host's top controls, never underneath them.
        scrollView.frame = NSRect(x: 0, y: 0, width: bounds.width, height: max(0, bounds.height - topInset))
        relayout()
    }

    private var inLayout = false
    func relayout() {
        guard !inLayout else { return }
        inLayout = true
        defer { inLayout = false }
        if !handle.isDragging { handle.isHidden = true } // the next mouse move places it again
        let width = scrollView.contentSize.width
        guard width > 0 else { return }
        let margin: CGFloat = width < 640 ? 10 : 28
        let paperW = min(840, width - margin * 2)
        let paperX = ((width - paperW) / 2).rounded()
        let top: CGFloat = topInset > 0 ? 14 : 70
        let pad: CGFloat = paperW < 560 ? 22 : (paperW < 700 ? 44 : 68)
        var y = top
        if coverImage != nil {
            let h = min(240, paperW * 0.32)
            coverView.frame = NSRect(x: paperX, y: top, width: paperW, height: h)
            y += h + 36
        } else { y += 52 }
        let innerW = paperW - pad * 2
        titleView.frame.size.width = innerW
        titleView.layoutManager?.ensureLayout(for: titleView.textContainer!)
        let titleH = max((titleView.layoutManager?.usedRect(for: titleView.textContainer!).height ?? 40), (titleView.font?.pointSize ?? 34) * 1.25)
        titleView.frame = NSRect(x: paperX + pad, y: y, width: innerW, height: titleH)
        y += titleH + 16
        ruleView.frame = NSRect(x: paperX + pad, y: y, width: innerW, height: 1)
        y += 22
        let tv = controller.textView
        if abs(tv.frame.width - innerW) > 0.5 || tv.frame.minX != paperX + pad || tv.frame.minY != y {
            tv.frame = NSRect(x: paperX + pad, y: y, width: innerW, height: tv.frame.height)
        }
        controller.layout.ensureLayout(for: controller.container)
        let used = controller.layout.usedRect(for: controller.container).height + controller.layout.extraLineFragmentRect.height
        let bodyH = max(used + 8, 160)
        if abs(tv.frame.height - bodyH) > 0.5 { tv.setFrameSize(NSSize(width: innerW, height: bodyH)) }
        let paperBottom = tv.frame.maxY + 90
        paper.paperRect = NSRect(x: paperX, y: top, width: paperW, height: paperBottom - top)
        paperBackground.frame = paper.paperRect
        paperBackground.layer?.shadowPath = CGPath(roundedRect: paperBackground.bounds, cornerWidth: 22, cornerHeight: 22, transform: nil)
        let docH = max(paperBottom + 60, scrollView.contentSize.height)
        if paper.frame.size != NSSize(width: width, height: docH) { paper.frame = NSRect(x: 0, y: 0, width: width, height: docH) }
        onLayout?()
    }
}
