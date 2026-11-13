import AppKit
import DraftCore

/// One row of the `[[` / `@` / `#` picker.
public struct MentionItem: Equatable {
    public enum Kind: Equatable { case doc, block, date, tag, create }
    public var kind: Kind
    public var title: String
    public var subtitle: String?
    public var symbol: String
    public var docId: String?
    public var blockId: String?
    /// Date key for `.date`, tag name for `.tag`.
    public var value: String?
    public init(kind: Kind, title: String, subtitle: String? = nil, symbol: String, docId: String? = nil, blockId: String? = nil, value: String? = nil) {
        self.kind = kind; self.title = title; self.subtitle = subtitle; self.symbol = symbol; self.docId = docId; self.blockId = blockId; self.value = value
    }
}

/// Linking services; the defaults keep hosts that don't link (tests, previews) working.
public protocol LinkHost: AnyObject {
    /// Picker rows for a trigger (`[[`, `@`, `#`) and the text typed after it.
    func mentionItems(trigger: String, query: String) -> [MentionItem]
    /// New top-level document for "Create …" in the picker.
    func createLinkedDocument(title: String) -> String?
    func openDocLink(docId: String, blockId: String?)
    func openDay(_ day: String)
    func openTag(_ tag: String)
    /// Where a link points now (blocks can move to other documents) and its live title;
    /// nil when the target no longer exists.
    func resolveLink(docId: String, blockId: String?) -> (docId: String, title: String)?
    func todayKey() -> String
    /// New top-level document holding `content` (Move to New Document).
    func createDocument(title: String, content: Node) -> String?
    /// Today's daily note, created on demand.
    func dailyNoteId(create: Bool) -> String?
    /// The linked document's cover (or a picture of its backdrop) for gallery cards.
    func pageCover(docId: String) -> NSImage?
    /// Settings → Online → Link previews (off by default).
    func wantsLinkPreviews() -> Bool
    /// Open a collection block of this document in its own view.
    func openCollection(blockId: String)
    /// A new collection: its starter data (the app creates nothing until items are added).
    func newCollectionName() -> String
    func fetchLinkPreview(_ url: URL, _ done: @escaping (LinkPreview?) -> Void)
}

public extension LinkHost {
    func mentionItems(trigger: String, query: String) -> [MentionItem] { [] }
    func createLinkedDocument(title: String) -> String? { nil }
    func openDocLink(docId: String, blockId: String?) {}
    func openDay(_ day: String) {}
    func openTag(_ tag: String) {}
    func resolveLink(docId: String, blockId: String?) -> (docId: String, title: String)? { (docId, "") }
    func todayKey() -> String { Day.today() }
    func createDocument(title: String, content: Node) -> String? { nil }
    func dailyNoteId(create: Bool) -> String? { nil }
    func pageCover(docId: String) -> NSImage? { nil }
    func wantsLinkPreviews() -> Bool { false }
    func openCollection(blockId: String) {}
    func newCollectionName() -> String { "Collection" }
    func fetchLinkPreview(_ url: URL, _ done: @escaping (LinkPreview?) -> Void) { done(nil) }
}

extension EditorController {
    var linkHost: LinkHost? { host as? LinkHost }

    func chipAttrs(_ key: NSAttributedString.Key, _ value: String, block b: BlockInfo) -> [NSAttributedString.Key: Any] {
        attrs(for: b, marks: currentMarks().merging([key: value]) { _, n in n })
    }

    /// Replace `range` with a chip and a following space, as one undo step.
    func insertChip(_ key: NSAttributedString.Key, value: String, text: String, replacing range: NSRange) {
        let b = currentBlock
        let s = NSMutableAttributedString(string: text.isEmpty ? "Untitled" : text, attributes: chipAttrs(key, value, block: b))
        s.append(NSAttributedString(string: " ", attributes: attrs(for: b, marks: currentMarks())))
        undoGroup { replace(range, with: s, select: NSRange(location: range.location + s.length, length: 0)) }
        updateTypingAttributes()
    }

    public func insertDocLink(docId: String, blockId: String? = nil, title: String, replacing range: NSRange? = nil) {
        insertChip(.draftDocLink, value: docId + (blockId.map { "#" + $0 } ?? ""), text: title, replacing: range ?? textView.selectedRange())
    }

    public func insertDate(_ day: String, replacing range: NSRange? = nil) {
        insertChip(.draftDate, value: day, text: Day.chipLabel(day, today: linkHost?.todayKey() ?? Day.today()), replacing: range ?? textView.selectedRange())
    }

    /// The chip (link or date) covering `loc`.
    public func chipRange(at loc: Int) -> (NSRange, NSAttributedString.Key, String)? {
        guard loc >= 0, loc < storage.length else { return nil }
        for k in [NSAttributedString.Key.draftDocLink, .draftDate] {
            var r = NSRange()
            if let v = storage.attribute(k, at: loc, longestEffectiveRange: &r, in: paragraphRange(at: loc)) as? String { return (r, k, v) }
        }
        return nil
    }

    func tagRange(at loc: Int) -> (NSRange, String)? {
        let pr = paragraphRange(at: loc)
        guard block(at: pr).kind != .code else { return nil }
        return Tags.find(in: ns.substring(with: pr), rules: theme.tagRules)
            .map { (NSRange(location: pr.location + $0.range.location, length: $0.range.length), $0.name) }
            .first { NSLocationInRange(loc, $0.0) }
    }

    /// A click on a chip or tag opens it. `point` is in text-container coordinates.
    func openChip(at idx: Int, point: NSPoint) -> Bool {
        guard idx < storage.length else { return false }
        let gr = layout.glyphRange(forCharacterRange: NSRange(location: idx, length: 1), actualCharacterRange: nil)
        guard layout.boundingRect(forGlyphRange: gr, in: container).insetBy(dx: -1, dy: -2).contains(point) else { return false }
        if let (_, key, v) = chipRange(at: idx) {
            if key == .draftDate { linkHost?.openDay(String(v.prefix(10))); return true }
            let p = v.split(separator: "#", maxSplits: 1).map(String.init)
            linkHost?.openDocLink(docId: p[0], blockId: p.count > 1 ? p[1] : nil)
            return true
        }
        if let (_, t) = tagRange(at: idx) { linkHost?.openTag(t); return true }
        return false
    }

    /// Bring link titles, block-reference locations and date labels up to date.
    @discardableResult
    public func refreshLinks(afterLoad: Bool = false) -> Bool {
        guard let h = linkHost, storage.length > 0 else { return false }
        let today = h.todayKey()
        var edits: [(NSRange, NSAttributedString.Key, String, String?, Bool)] = [] // range, key, value, newText, missing
        let all = NSRange(location: 0, length: storage.length)
        storage.enumerateAttribute(.draftDocLink, in: all) { v, r, _ in
            guard let v = v as? String else { return }
            let p = v.split(separator: "#", maxSplits: 1).map(String.init)
            if let t = h.resolveLink(docId: p[0], blockId: p.count > 1 ? p[1] : nil) {
                let nv = t.docId + (p.count > 1 ? "#" + p[1] : "")
                let title = t.title.isEmpty ? nil : String(t.title.replacingOccurrences(of: "\n", with: " ").prefix(80))
                edits.append((r, .draftDocLink, nv, title, false))
            } else { edits.append((r, .draftDocLink, v, nil, true)) }
        }
        storage.enumerateAttribute(.draftDate, in: all) { v, r, _ in
            guard let v = v as? String else { return }
            edits.append((r, .draftDate, v, Day.chipLabel(v, today: today), false))
        }
        var textChanged = false, any = false
        let sorted = edits.sorted(by: { $0.0.location > $1.0.location })
        isProgrammaticEdit = true
        storage.beginEditing()
        for (r, key, value, _, missing) in sorted {
            let had = storage.attribute(.draftLinkMissing, at: r.location, effectiveRange: nil) != nil
            if had != missing { any = true; if missing { storage.addAttribute(.draftLinkMissing, value: true, range: r) } else { storage.removeAttribute(.draftLinkMissing, range: r) } }
            if (storage.attribute(key, at: r.location, effectiveRange: nil) as? String) != value { any = true; storage.addAttribute(key, value: value, range: r) }
        }
        storage.endEditing()
        isProgrammaticEdit = false
        let textEdits = sorted.filter { $0.3 != nil && ns.substring(with: $0.0) != $0.3 }
        if !textEdits.isEmpty {
            textChanged = true
            // In the document being looked at, new titles are a visible, undoable step. Anywhere else
            // they are applied quietly; that document's own history is reset because its steps
            // refer to text positions the new titles shift (other documents keep theirs).
            let quiet = afterLoad || isLoading
            let apply = {
                for (r, _, _, text, _) in textEdits {
                    let a = self.storage.attributes(at: r.location, effectiveRange: nil)
                    if quiet { self.storage.replaceCharacters(in: r, with: NSAttributedString(string: text!, attributes: a)) }
                    else { self.replace(r, with: NSAttributedString(string: text!, attributes: a)) }
                }
            }
            if quiet {
                isProgrammaticEdit = true; storage.beginEditing(); apply(); storage.endEditing(); isProgrammaticEdit = false
            } else {
                // Recorded so earlier steps keep valid positions, but never a step of its own.
                undoGroup(apply)
                undo.setActionName(DocumentUndoManager.silentAction)
            }
        }
        return textChanged || any
    }

    /// A pasted web address becomes a preview card; the title and summary arrive later and fill
    /// it in place (no extra undo step). Without them it is still a working link.
    func insertLinkPreview(_ u: URL) {
        let site = (u.host ?? "").replacingOccurrences(of: "www.", with: "")
        insertAttachmentBlock(kind: .bookmark, node: Node("linkPreview", attrs: ["url": .string(u.absoluteString), "title": .string(site), "site": .string(site)]))
        guard let id = paragraphIdOfLastBookmark(url: u.absoluteString) else { return }
        linkHost?.fetchLinkPreview(u) { [weak self] p in
            guard let self, let p else { return }
            self.fillLinkPreview(blockId: id, p)
        }
    }

    func paragraphIdOfLastBookmark(url: String) -> String? {
        var found: String?
        storage.enumerateAttribute(.attachment, in: NSRange(location: 0, length: storage.length)) { v, r, _ in
            if let a = v as? BlockAttachment, a.kind == .bookmark, a.node.attrs?["url"]?.string == url, r.location <= textView.selectedRange().location { found = a.node.id }
        }
        return found
    }

    public func fillLinkPreview(blockId: String, _ p: LinkPreview) {
        guard let pr = paragraph(withId: blockId), pr.length > 0, let a = storage.attribute(.attachment, at: pr.location, effectiveRange: nil) as? BlockAttachment, a.kind == .bookmark else { return }
        a.node[attr: "title"] = .string(p.title)
        a.node[attr: "site"] = .string(p.site)
        if let s = p.summary { a.node[attr: "summary"] = .string(s) }
        storage.addAttribute(.draftBlock, value: block(at: pr).with(raw: .some(a.node)), range: pr)
        layout.invalidateLayout(forCharacterRange: pr, actualCharacterRange: nil)
        textView.needsDisplay = true
        host?.editorDidChange()
    }

    /// Set or clear a task's due date (one undo step in this document).
    @discardableResult
    public func setTaskDue(blockId: String, due: String?) -> Bool {
        let today = linkHost?.todayKey() ?? Day.today()
        var flat = flatBlocks()
        guard let i = flat.firstIndex(where: { $0.info.id == blockId && $0.info.kind == .task }),
              let n = Converter.tree(from: [flat[i]]).content?.first?.content?.first, let id = n.id,
              let changed = Node("doc", content: [n]).settingTaskDue(id, due: due, label: Day.chipLabel(due ?? "", today: today)) else { return false }
        flat[i].inline = changed.content?.first?.content?.first?.content ?? []
        rebuild(flat, select: [], blockMode: false)
        undo.setActionName(due == nil ? "Clear Due Date" : "Set Due Date")
        return true
    }

    /// Check or uncheck a task from outside the editor (Tasks view). The caller owns undo.
    @discardableResult
    public func setTaskChecked(blockId: String, checked: Bool) -> Bool {
        guard let pr = paragraph(withId: blockId) else { return false }
        let b = block(at: pr)
        guard b.kind == .task else { return false }
        if b.checked == checked { return true }
        if pr.length == 0 { trailing = b.with(checked: checked) } else {
            storage.beginEditing()
            storage.addAttribute(.draftBlock, value: b.with(checked: checked), range: pr)
            storage.endEditing()
        }
        textView.needsDisplay = true
        host?.editorDidChange()
        return true
    }

    /// Backspace right after a chip removes the whole chip.
    func deleteChipBackward() -> Bool {
        let sel = textView.selectedRange()
        guard sel.length == 0, sel.location > 0, let (r, _, _) = chipRange(at: sel.location - 1), NSMaxRange(r) == sel.location else { return false }
        undoGroup { replace(r, with: NSAttributedString(), select: NSRange(location: r.location, length: 0)) }
        return true
    }
}

/// The `[[` (documents, pages, blocks), `@` (dates and documents) and `#` (tags) picker.
/// Typing filters, ↑/↓ move, Return/Tab choose, Esc dismisses and keeps the typed text.
public final class MentionMenu: NSView {
    public override func resetCursorRects() { addCursorRect(bounds, cursor: .arrow) }
    public override func cursorUpdate(with event: NSEvent) { NSCursor.arrow.set() }
    unowned let controller: EditorController
    public private(set) var isOpen = false
    public private(set) var trigger = ""
    var anchor = 0
    public private(set) var query = ""
    public private(set) var results: [MentionItem] = []
    var index = 0
    var scrollOffset: CGFloat = 0
    let rowH: CGFloat = 40

    init(controller: EditorController) {
        self.controller = controller
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 14
        layer?.borderWidth = 0.5
        layer?.shadowOpacity = 0.2
        layer?.shadowRadius = 16
        layer?.masksToBounds = false
        setAccessibilityRole(.menu)
        setAccessibilityLabel(loc("Link to"))
    }
    required init?(coder: NSCoder) { fatalError() }
    public override var isFlipped: Bool { true }

    func textChanged(typed: String?, at loc: Int) {
        let c = controller
        if !isOpen, let typed, ["@", "#", "["].contains(typed), !c.slash.isOpen {
            let pr = c.paragraphRange(at: loc)
            let b = c.block(at: pr)
            guard b.kind != .code, !b.kind.isAttachment, c.storage.attribute(.draftCode, at: loc, effectiveRange: nil) == nil else { return }
            let before = loc > pr.location ? c.ns.character(at: loc - 1) : 32
            if typed == "[" {
                guard loc > pr.location, before == 91 else { return }
                trigger = "[["; anchor = loc - 1
            } else {
                guard loc == pr.location || before == 32 || before == 40 else { return }
                trigger = typed; anchor = loc
            }
            open()
        }
        guard isOpen else { return }
        let caret = c.textView.selectedRange().location
        let tl = (trigger as NSString).length
        guard caret >= anchor + tl, caret <= c.storage.length, NSMaxRange(NSRange(location: anchor, length: tl)) <= c.storage.length,
              c.ns.substring(with: NSRange(location: anchor, length: tl)) == trigger else { close(); return }
        query = c.ns.substring(with: NSRange(location: anchor + tl, length: caret - anchor - tl))
        if query.contains("\n") || query.contains(Chars.lineBreak) || query.count > 48 || query.hasPrefix(" ")
            || (trigger == "#" && query.contains(" ")) || (trigger == "[[" && query.contains("]]")) || query.hasSuffix("  ") { close(); return }
        refresh()
    }

    func selectionChanged() {
        guard isOpen else { return }
        let caret = controller.textView.selectedRange()
        if caret.length > 0 || caret.location <= anchor || controller.paragraphRange(at: caret.location).location != controller.paragraphRange(at: anchor).location { close() }
    }

    func open() {
        isOpen = true
        query = ""
        index = 0
        scrollOffset = 0
        controller.overlayHost?.addSubview(self)
        refresh()
    }

    public func close() {
        isOpen = false
        removeFromSuperview()
    }

    func refresh() {
        results = controller.linkHost?.mentionItems(trigger: trigger, query: query) ?? []
        if results.isEmpty && (query.count > 2 || trigger == "#") { close(); return }
        if results.isEmpty { removeFromSuperview(); return }
        if superview == nil { controller.overlayHost?.addSubview(self) }
        index = min(index, results.count - 1)
        position()
        needsDisplay = true
        NSAccessibility.post(element: self, notification: .valueChanged)
    }

    public func position() {
        guard let host = controller.overlayHost else { return }
        let tv = controller.textView
        let gr = controller.layout.glyphRange(forCharacterRange: NSRange(location: anchor, length: 1), actualCharacterRange: nil)
        var r = controller.layout.boundingRect(forGlyphRange: gr, in: controller.container)
        r = tv.convert(r.offsetBy(dx: tv.textContainerOrigin.x, dy: tv.textContainerOrigin.y), to: host)
        let vis = host.visibleRect
        let w: CGFloat = 320
        let want = min(CGFloat(results.count) * rowH + 12, 340)
        let below = vis.maxY - 8 - (r.maxY + 6)
        let above = (r.minY - 6) - (vis.minY + 8)
        let useBelow = below >= want || below >= above
        let h = max(min(want, useBelow ? below : above), min(want, rowH * 2 + 12))
        var y = useBelow ? r.maxY + 6 : r.minY - 6 - h
        y = min(max(y, vis.minY + 8), max(vis.minY + 8, vis.maxY - 8 - h))
        frame = NSRect(x: min(max(r.minX - 8, vis.minX + 8), vis.maxX - w - 8), y: y, width: w, height: h)
    }

    func move(_ d: Int) {
        guard !results.isEmpty else { return }
        index = (index + d + results.count) % results.count
        let top = CGFloat(index) * rowH + 6
        if top + rowH > bounds.height + scrollOffset { scrollOffset = top + rowH - bounds.height + 6 }
        if top < scrollOffset { scrollOffset = max(0, top - 6) }
        needsDisplay = true
    }

    public func choose(_ i: Int? = nil) {
        let i = i ?? index
        guard results.indices.contains(i) else { close(); return }
        let item = results[i]
        let c = controller
        let range = NSRange(location: anchor, length: c.textView.selectedRange().location - anchor)
        close()
        switch item.kind {
        case .doc, .block:
            guard let d = item.docId else { return }
            c.insertDocLink(docId: d, blockId: item.blockId, title: item.title, replacing: range)
        case .create:
            guard let d = c.linkHost?.createLinkedDocument(title: item.value ?? query) else { NSSound.beep(); return }
            c.insertDocLink(docId: d, title: item.value ?? query, replacing: range)
        case .date:
            guard let v = item.value else { return }
            c.insertDate(v, replacing: range)
        case .tag:
            let s = NSAttributedString(string: "#" + (item.value ?? query) + " ", attributes: c.attrs(for: c.currentBlock, marks: c.currentMarks()))
            c.undoGroup { c.replace(range, with: s, select: NSRange(location: range.location + s.length, length: 0)) }
        }
    }

    public override func scrollWheel(with event: NSEvent) {
        scrollOffset = min(max(0, scrollOffset - event.scrollingDeltaY), max(0, CGFloat(results.count) * rowH + 12 - bounds.height))
        needsDisplay = true
    }

    public override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        let i = Int((p.y + scrollOffset - 6) / rowH)
        if results.indices.contains(i) { choose(i) }
    }

    public override func accessibilityChildren() -> [Any]? {
        results.enumerated().map { i, r in
            let e = NSAccessibilityElement()
            e.setAccessibilityRole(.menuItem)
            e.setAccessibilityLabel([r.title, r.subtitle].compactMap { $0 }.joined(separator: ", "))
            e.setAccessibilitySelected(i == index)
            e.setAccessibilityParent(self)
            e.setAccessibilityFrameInParentSpace(NSRect(x: 6, y: 6 + CGFloat(i) * rowH - scrollOffset, width: bounds.width - 12, height: rowH))
            return e
        }
    }

    public override func draw(_ dirtyRect: NSRect) {
        let dark = controller.theme.isDarkPage
        layer?.backgroundColor = (dark ? NSColor(white: 0.16, alpha: 0.97) : NSColor(white: 0.995, alpha: 0.97)).cgColor
        layer?.borderColor = NSColor(white: dark ? 1 : 0, alpha: 0.1).cgColor
        layer?.shadowPath = CGPath(roundedRect: bounds, cornerWidth: 14, cornerHeight: 14, transform: nil)
        let fg = dark ? NSColor(white: 0.94, alpha: 1) : NSColor(white: 0.13, alpha: 1)
        let accent = NSColor(hex: controller.theme.accent)
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: bounds).addClip()
        for (i, item) in results.enumerated() {
            let r = NSRect(x: 6, y: 6 + CGFloat(i) * rowH - scrollOffset, width: bounds.width - 12, height: rowH)
            guard r.maxY > 0, r.minY < bounds.height else { continue }
            if i == index {
                accent.withAlphaComponent(dark ? 0.4 : 0.14).setFill()
                NSBezierPath(roundedRect: r, xRadius: 8, yRadius: 8).fill()
            }
            let tint = item.kind == .tag ? NSColor(hex: controller.theme.tagColors[(item.value ?? "").lowercased()] ?? Tags.defaultColor(item.value ?? "")) : fg
            if let img = NSImage(systemSymbolName: item.symbol, accessibilityDescription: nil)?.withSymbolConfiguration(.init(pointSize: 13, weight: .regular).applying(.init(paletteColors: [tint]))) {
                img.draw(in: NSRect(x: r.minX + 8 + (18 - img.size.width) / 2, y: r.midY - img.size.height / 2, width: img.size.width, height: img.size.height), from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
            }
            let para = NSMutableParagraphStyle(); para.lineBreakMode = .byTruncatingTail
            let tr = NSRect(x: r.minX + 36, y: r.minY + (item.subtitle == nil ? 11 : 4), width: r.width - 44, height: 18)
            (item.title as NSString).draw(with: tr, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], attributes: [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: fg, .paragraphStyle: para])
            if let sub = item.subtitle {
                (sub as NSString).draw(with: NSRect(x: tr.minX, y: r.minY + 21, width: tr.width, height: 15), options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
                                       attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: fg.withAlphaComponent(0.5), .paragraphStyle: para])
            }
        }
        NSGraphicsContext.restoreGraphicsState()
    }
}

/// A document's undo history. Link-title updates made by Draft are recorded (so earlier steps
/// stay valid) but ride along with the user's steps: ⌘Z and ⇧⌘Z always undo or redo a real edit.
public final class DocumentUndoManager: UndoManager {
    public static let silentAction = "Update Link Titles"

    public override func undo() {
        let silentOnTop = undoActionName == Self.silentAction
        super.undo()
        if silentOnTop, canUndo, !isUndoing { super.undo() }
        while canUndo, undoActionName == Self.silentAction, !isUndoing { super.undo() }
    }

    public override func redo() {
        super.redo()
        while canRedo, redoActionName == Self.silentAction, !isRedoing { super.redo() }
    }

    public override var undoMenuItemTitle: String { undoActionName == Self.silentAction ? "Undo" : super.undoMenuItemTitle }
    public override var redoMenuItemTitle: String { redoActionName == Self.silentAction ? "Redo" : super.redoMenuItemTitle }
}
