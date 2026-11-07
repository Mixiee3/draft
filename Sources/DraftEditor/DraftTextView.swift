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
        super.doCommand(by: selector)
    }

    public override func cancelOperation(_ sender: Any?) {
        guard let c = controller else { return }
        if c.slash.isOpen { c.slash.close(); return }
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
        let p = convert(event.locationInWindow, from: nil)
        let cp = NSPoint(x: p.x - textContainerOrigin.x, y: p.y - textContainerOrigin.y)
        let idx = c.layout.characterIndex(for: cp, in: c.container, fractionOfDistanceBetweenInsertionPoints: nil)
        let pr = c.paragraphRange(at: idx)
        if let box = c.layout.checkboxRect(forParagraphAt: pr), box.insetBy(dx: -5, dy: -5).contains(cp) {
            c.toggleTask(at: pr); return
        }
        // A click below the last line of an empty trailing task still toggles it.
        if c.trailing.kind == .task, let box = c.layout.checkboxRect(forParagraphAt: NSRange(location: c.storage.length, length: 0)), box.insetBy(dx: -5, dy: -5).contains(cp) {
            c.toggleTask(at: NSRange(location: c.storage.length, length: 0)); return
        }
        if event.modifierFlags.contains(.command), let (_, href) = c.linkRange(at: idx), let url = URL(string: href) {
            c.host?.open(url: url); return
        }
        super.mouseDown(with: event)
    }

    /// The text's context menu starts with the Block menu.
    public override func menu(for event: NSEvent) -> NSMenu? {
        let menu = super.menu(for: event) ?? NSMenu()
        guard let c = controller else { return menu }
        let block = NSMenuItem(title: "Block", action: nil, keyEquivalent: "")
        block.submenu = c.blockMenu()
        menu.insertItem(block, at: 0)
        menu.insertItem(.separator(), at: 1)
        return menu
    }

    public override func resetCursorRects() {
        super.resetCursorRects()
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

    public override var readablePasteboardTypes: [NSPasteboard.PasteboardType] { [EditorController.pasteboardType, .rtf, .html, .png, .tiff, .string] }

    public override func readSelection(from pboard: NSPasteboard, type: NSPasteboard.PasteboardType) -> Bool {
        guard let c = controller else { return super.readSelection(from: pboard, type: type) }
        switch type {
        case EditorController.pasteboardType:
            if let d = pboard.data(forType: type) { return c.pasteFragment(d) }
        case .png:
            if let d = pboard.data(forType: .png) { return c.pasteImage(d, ext: "png") }
        case .tiff:
            if let d = pboard.data(forType: .tiff), let rep = NSBitmapImageRep(data: d), let png = rep.representation(using: .png, properties: [:]) { return c.pasteImage(png, ext: "png") }
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

    public override func paste(_ sender: Any?) {
        let pb = NSPasteboard.general
        if let t = preferredPasteboardType(from: pb.types ?? [], restrictedToTypesFrom: nil), readSelection(from: pb, type: t) { return }
        super.paste(sender)
    }
}
