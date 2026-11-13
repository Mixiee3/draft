import AppKit
import DraftCore

public final class DraftTextView: NSTextView {
    weak var controller: EditorController?
    public var placeholder = "Start writing, or type / to insert a block"

    public override func insertNewline(_ sender: Any?) {
        if let c = controller, c.isBlockMode { c.exitBlockMode(caretAtEnd: true); return }
        if NSEvent.modifierFlags.contains(.shift) { insertText(Chars.lineBreak, replacementRange: selectedRange()); return }
        if controller?.handleNewline() != true { super.insertNewline(sender) }
    }
    public override func insertLineBreak(_ sender: Any?) { insertText(Chars.lineBreak, replacementRange: selectedRange()) }
    public override func insertNewlineIgnoringFieldEditor(_ sender: Any?) { insertText(Chars.lineBreak, replacementRange: selectedRange()) }

    public override func deleteBackward(_ sender: Any?) {
        if let c = controller, c.isBlockMode { c.deleteSelectedBlocks(); return }
        if controller?.handleDeleteBackward() != true { super.deleteBackward(sender) }
    }
    public override func deleteForward(_ sender: Any?) {
        if let c = controller, c.isBlockMode { c.deleteSelectedBlocks(); return }
        if controller?.handleDeleteForward() != true { super.deleteForward(sender) }
    }

    public override func insertTab(_ sender: Any?) {
        guard let c = controller else { return super.insertTab(sender) }
        if c.slash.isOpen { c.slash.choose(); return }
        if c.mention.isOpen { c.mention.choose(); return }
        if c.imageBar.isVisible, c.selectedImageIndex != nil { window?.makeFirstResponder(c.imageBar.size); return } // Esc returns
        if c.currentBlock.kind.isList { c.indent(); return }
        super.insertTab(sender)
    }
    public override func insertBacktab(_ sender: Any?) {
        guard let c = controller else { return super.insertBacktab(sender) }
        if c.currentBlock.kind.isList || c.currentBlock.decoration == "focus" { c.outdent(); return }
        super.insertBacktab(sender)
    }

    public override func doCommand(by selector: Selector) {
        if let c = controller, c.slash.isOpen {
            switch selector {
            case #selector(moveUp(_:)): c.slash.move(-1); return
            case #selector(moveDown(_:)): c.slash.move(1); return
            case #selector(cancelOperation(_:)): c.slash.close(); return
            default: break
            }
        }
        if let c = controller, c.mention.isOpen {
            switch selector {
            case #selector(moveUp(_:)): c.mention.move(-1); return
            case #selector(moveDown(_:)): c.mention.move(1); return
            case #selector(cancelOperation(_:)): c.mention.close(); return
            default: break
            }
        }
        super.doCommand(by: selector)
    }

    public override func cancelOperation(_ sender: Any?) {
        guard let c = controller else { return }
        if c.slash.isOpen { c.slash.close(); return }
        if c.mention.isOpen { c.mention.close(); return }
        if c.toolbar.isVisible { c.toolbar.dismissForCurrentSelection(); return }
        // Esc toggles between editing text and selecting whole blocks.
        if c.isBlockMode { c.exitBlockMode() } else { c.enterBlockMode() }
    }

    public override func moveUp(_ sender: Any?) { if let c = controller, c.isBlockMode { c.stepBlockSelection(-1, extend: false) } else { super.moveUp(sender) } }
    public override func moveDown(_ sender: Any?) { if let c = controller, c.isBlockMode { c.stepBlockSelection(1, extend: false) } else { super.moveDown(sender) } }
    public override func moveUpAndModifySelection(_ sender: Any?) { if let c = controller, c.isBlockMode { c.stepBlockSelection(-1, extend: true) } else { super.moveUpAndModifySelection(sender) } }
    public override func moveDownAndModifySelection(_ sender: Any?) { if let c = controller, c.isBlockMode { c.stepBlockSelection(1, extend: true) } else { super.moveDownAndModifySelection(sender) } }

    public override func insertText(_ string: Any, replacementRange: NSRange) {
        // Typing while blocks are selected returns to text editing at the end of the selection
        // instead of replacing whole blocks.
        if let c = controller, c.isBlockMode { c.exitBlockMode(caretAtEnd: true); super.insertText(string, replacementRange: selectedRange()); return }
        super.insertText(string, replacementRange: replacementRange)
    }

    public override func keyDown(with event: NSEvent) {
        // ⌥F10: move keyboard focus into the floating formatting bar.
        if event.keyCode == 109, event.modifierFlags.contains(.option), let c = controller, c.toolbar.isVisible {
            c.toolbar.focusForKeyboard(); return
        }
        super.keyDown(with: event)
    }

    public override func mouseDown(with event: NSEvent) {
        guard let c = controller else { return super.mouseDown(with: event) }
        if event.modifierFlags.contains(.control) { // Control-click opens the same context menu
            c.toolbar.suspended = true; c.toolbar.update()
            super.mouseDown(with: event)
            c.toolbar.suspended = false; c.toolbar.update()
            return
        }
        let p = convert(event.locationInWindow, from: nil)
        let cp = NSPoint(x: p.x - textContainerOrigin.x, y: p.y - textContainerOrigin.y)
        let idx = c.layout.characterIndex(for: cp, in: c.container, fractionOfDistanceBetweenInsertionPoints: nil)
        let pr = c.paragraphRange(at: idx)
        if let box = c.layout.checkboxRect(forParagraphAt: pr), box.insetBy(dx: -5, dy: -5).contains(cp) {
            c.toggleTask(at: pr); return
        }
        if let box = c.layout.toggleRect(forParagraphAt: pr), box.insetBy(dx: -5, dy: -5).contains(cp) {
            c.toggleOpen(at: pr); return
        }
        // A click below the last line of an empty trailing task still toggles it.
        if c.trailing.kind == .task, let box = c.layout.checkboxRect(forParagraphAt: NSRange(location: c.storage.length, length: 0)), box.insetBy(dx: -5, dy: -5).contains(cp) {
            c.toggleTask(at: NSRange(location: c.storage.length, length: 0)); return
        }
        if !event.modifierFlags.contains(.shift), c.openChip(at: idx, point: cp) { return }
        if event.modifierFlags.contains(.command), let (_, href) = c.linkRange(at: idx), let url = URL(string: href) {
            c.host?.open(url: url); return
        }
        super.mouseDown(with: event)
    }

    /// The text's context menu starts with the Block menu.
    /// The right-click menu is for the clipboard, look-up, block structure and system services;
    /// inline formatting lives in the formatting bar, which steps aside while the menu is open.
    /// AppKit's Font and Layout Orientation menus would bypass Draft's styles, so they are left out.
    public override func menu(for event: NSEvent) -> NSMenu? {
        let menu = super.menu(for: event) ?? NSMenu()
        guard let c = controller else { return menu }
        let dropped: Set<String> = ["orderFrontFontPanel:", "changeLayoutOrientation:"]
        for item in menu.items.reversed() {
            let actions = ([item] + (item.submenu?.items ?? [])).compactMap { $0.action.map(NSStringFromSelector) }
            if actions.contains(where: dropped.contains) || ["Font", "Layout Orientation", "AutoFill"].contains(item.title) { menu.removeItem(item) }
        }
        while let first = menu.items.first, first.isSeparatorItem { menu.removeItem(first) }
        for (k, item) in menu.items.enumerated().reversed() where k > 0 && item.isSeparatorItem && menu.items[k - 1].isSeparatorItem { menu.removeItem(item) }
        var i = 0
        if selectedRange().length > 0, !c.isBlockMode {
            let format = ClosureMenuItem(title: "Format Selection…") { [weak c] in
                guard let c else { return }
                c.toolbar.update(); c.toolbar.focusForKeyboard()
            }
            format.keyEquivalent = String(UnicodeScalar(NSF10FunctionKey)!); format.keyEquivalentModifierMask = [.option]
            format.image = NSImage(systemSymbolName: "textformat", accessibilityDescription: nil)
            menu.insertItem(format, at: i); i += 1
        }
        let block = NSMenuItem(title: loc("Block"), action: nil, keyEquivalent: "")
        block.image = NSImage(systemSymbolName: "square.stack", accessibilityDescription: nil)
        block.submenu = c.blockMenu()
        menu.insertItem(block, at: i); i += 1
        menu.insertItem(.separator(), at: i)
        return menu
    }

    /// The context menu runs modally inside these calls, so the formatting bar steps aside before it
    /// opens and comes back (for the same selection) when it closes.
    public override func rightMouseDown(with event: NSEvent) {
        controller?.toolbar.suspended = true; controller?.toolbar.update()
        super.rightMouseDown(with: event)
        controller?.toolbar.suspended = false; controller?.toolbar.update()
    }

    /// No Continuity Camera or sketch insertion: images come in through Draft's own image block.
    public override func validRequestor(forSendType sendType: NSPasteboard.PasteboardType?, returnType: NSPasteboard.PasteboardType?) -> Any? {
        if let r = returnType, [.png, .tiff, NSPasteboard.PasteboardType("public.image"), NSPasteboard.PasteboardType("public.jpeg")].contains(r) { return nil }
        return super.validRequestor(forSendType: sendType, returnType: returnType)
    }

    /// Printing / Save as PDF: start a new page at every page-break block.
    public override func adjustPageHeightNew(_ newBottom: UnsafeMutablePointer<CGFloat>, top oldTop: CGFloat, bottom proposedBottom: CGFloat, limit bottomLimit: CGFloat) {
        super.adjustPageHeightNew(newBottom, top: oldTop, bottom: proposedBottom, limit: bottomLimit)
        guard let c = controller else { return }
        c.storage.enumerateAttribute(.attachment, in: NSRange(location: 0, length: c.storage.length)) { v, r, stop in
            guard let a = v as? BlockAttachment, a.node.type == "pageBreak" else { return }
            let y = c.layout.boundingRect(forGlyphRange: c.layout.glyphRange(forCharacterRange: r, actualCharacterRange: nil), in: c.container).minY + textContainerOrigin.y
            if y > oldTop + 1, y < newBottom.pointee { newBottom.pointee = y; stop.pointee = true }
        }
    }

    // MARK: Cursor

    /// I-beam only over editable text; a pointing hand over things that act on click (checkboxes,
    /// toggles, link chips, tags); the arrow over cards, images, margins and empty space.
    public func cursor(at p: NSPoint) -> NSCursor {
        guard let c = controller, isEditable else { return .arrow }
        let cp = NSPoint(x: p.x - textContainerOrigin.x, y: p.y - textContainerOrigin.y)
        guard cp.x >= -2, cp.x <= c.container.size.width + 2 else { return .arrow }
        if c.storage.length == 0 { return cp.y < 40 && cp.y > -4 ? .iBeam : .arrow }
        let gi = c.layout.glyphIndex(for: cp, in: c.container, fractionOfDistanceThroughGlyph: nil)
        var line = c.layout.lineFragmentRect(forGlyphAt: gi, effectiveRange: nil)
        let extra = c.layout.extraLineFragmentRect
        if !extra.isEmpty, cp.y >= extra.minY { line = extra }
        guard cp.y >= line.minY - 1, cp.y <= line.maxY + 1 else { return .arrow }
        let idx = line == extra ? c.storage.length : c.layout.characterIndexForGlyph(at: gi)
        let pr = c.paragraphRange(at: idx)
        if let box = c.layout.checkboxRect(forParagraphAt: pr), box.insetBy(dx: -5, dy: -5).contains(cp) { return .pointingHand }
        if let box = c.layout.toggleRect(forParagraphAt: pr), box.insetBy(dx: -5, dy: -5).contains(cp) { return .pointingHand }
        if c.block(at: pr).kind.isAttachment { return .arrow }
        if idx < c.storage.length, c.chipRange(at: idx) != nil || c.tagRange(at: idx) != nil {
            let gr = c.layout.glyphRange(forCharacterRange: NSRange(location: idx, length: 1), actualCharacterRange: nil)
            if c.layout.boundingRect(forGlyphRange: gr, in: c.container).insetBy(dx: -1, dy: -2).contains(cp) { return .pointingHand }
        }
        return .iBeam
    }

    func updateCursor(_ event: NSEvent) {
        guard let w = window, w.isKeyWindow || w.isMainWindow else { return }
        cursor(at: convert(event.locationInWindow, from: nil)).set()
    }

    private var cursorArea: NSTrackingArea?
    public override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let a = cursorArea { removeTrackingArea(a) }
        let a = NSTrackingArea(rect: .zero, options: [.mouseMoved, .cursorUpdate, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(a)
        cursorArea = a
    }
    public override func resetCursorRects() {} // the cursor follows the content under the pointer instead
    public override func cursorUpdate(with event: NSEvent) { updateCursor(event) }
    public override func mouseMoved(with event: NSEvent) { super.mouseMoved(with: event); updateCursor(event) }
    public override func mouseExited(with event: NSEvent) { super.mouseExited(with: event); NSCursor.arrow.set() }
    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { NSCursor.arrow.set() } // leaving a tab never leaves an I-beam behind
    }

    // Placeholder for an empty document.
    public override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if string.isEmpty, let c = controller, c.trailing.kind == .paragraph {
            let f = c.theme.baseFont(.paragraph())
            (placeholder as NSString).draw(at: NSPoint(x: textContainerOrigin.x, y: textContainerOrigin.y + 2), withAttributes: [.font: f, .foregroundColor: c.theme.text.withAlphaComponent(0.32)])
        }
    }

    // MARK: Pasteboard

    public override var writablePasteboardTypes: [NSPasteboard.PasteboardType] { [EditorController.pasteboardType, .string] }

    public override func writeSelection(to pboard: NSPasteboard, type: NSPasteboard.PasteboardType) -> Bool {
        guard let c = controller else { return super.writeSelection(to: pboard, type: type) }
        let sel = selectedRange()
        if type == EditorController.pasteboardType, let d = c.fragmentData(sel) { return pboard.setData(d, forType: type) }
        if type == .string {
            let s = (string as NSString).substring(with: sel).replacingOccurrences(of: Chars.lineBreak, with: "\n").replacingOccurrences(of: Chars.attachment, with: "")
            return pboard.setString(s, forType: .string)
        }
        return super.writeSelection(to: pboard, type: type)
    }

    public override var readablePasteboardTypes: [NSPasteboard.PasteboardType] { [EditorController.pasteboardType, .fileURL, .rtf, .html, .png, .tiff, .string] }

    public override func readSelection(from pboard: NSPasteboard, type: NSPasteboard.PasteboardType) -> Bool {
        guard let c = controller else { return super.readSelection(from: pboard, type: type) }
        switch type {
        case EditorController.pasteboardType:
            if let d = pboard.data(forType: type) { return c.pasteFragment(d) }
        case .png:
            if let d = pboard.data(forType: .png) { return c.pasteImage(d, ext: "png") }
        case .tiff:
            if let d = pboard.data(forType: .tiff), let rep = NSBitmapImageRep(data: d), let png = rep.representation(using: .png, properties: [:]) { return c.pasteImage(png, ext: "png") }
        case .fileURL:
            if let urls = pboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty { return c.insertFiles(urls) }
        case .rtf, .html:
            if let d = pboard.data(forType: type),
               let s = try? NSAttributedString(data: d, options: [.documentType: type == .rtf ? NSAttributedString.DocumentType.rtf : .html, .characterEncoding: String.Encoding.utf8.rawValue], documentAttributes: nil) {
                c.pasteRich(s); return true
            }
        case .string:
            if let s = pboard.string(forType: .string) { c.pastePlain(s); return true }
        default: break
        }
        return super.readSelection(from: pboard, type: type)
    }

    public override func preferredPasteboardType(from availableTypes: [NSPasteboard.PasteboardType], restrictedToTypesFrom allowedTypes: [NSPasteboard.PasteboardType]?) -> NSPasteboard.PasteboardType? {
        for t in readablePasteboardTypes where availableTypes.contains(t) {
            // Prefer images only when there is no text alongside (e.g. a screenshot).
            if (t == .png || t == .tiff) && availableTypes.contains(.string) { continue }
            return t
        }
        return super.preferredPasteboardType(from: availableTypes, restrictedToTypesFrom: allowedTypes)
    }

    public override var acceptableDragTypes: [NSPasteboard.PasteboardType] { super.acceptableDragTypes + [.fileURL] }

    public override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        if let c = controller, let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty {
            let p = convert(sender.draggingLocation, from: nil)
            let idx = c.layout.characterIndex(for: NSPoint(x: p.x - textContainerOrigin.x, y: p.y - textContainerOrigin.y), in: c.container, fractionOfDistanceBetweenInsertionPoints: nil)
            setSelectedRange(NSRange(location: idx, length: 0))
            return c.insertFiles(urls)
        }
        return super.performDragOperation(sender)
    }

    public override func paste(_ sender: Any?) {
        let pb = NSPasteboard.general
        if let t = preferredPasteboardType(from: pb.types ?? [], restrictedToTypesFrom: nil), readSelection(from: pb, type: t) { return }
        super.paste(sender)
    }
}
