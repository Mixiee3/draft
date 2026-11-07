import AppKit
import DraftCore

/// Owns the TextKit 1 stack for one document and implements every editing command.
/// Toolbar, Format panel, slash menu, insert menu, menu bar and keyboard shortcuts all call
/// these methods (via `EditorCommands`), so behavior and undo are identical everywhere.
public final class EditorController: NSObject, NSTextStorageDelegate, NSTextViewDelegate {
    public let storage = NSTextStorage()
    public let layout = DraftLayoutManager()
    public let container = NSTextContainer(size: NSSize(width: 640, height: CGFloat.greatestFiniteMagnitude))
    public let textView: DraftTextView
    public weak var host: EditorHost?
    /// View that hosts floating overlays (selection toolbar, slash menu). Set by the paper view.
    public weak var overlayHost: NSView?

    public var theme = EditorTheme() {
        didSet { if theme != oldValue { layout.theme = theme; restyleAll() } }
    }
    var trailing: BlockInfo = .paragraph() { didSet { layout.trailingBlock = trailing } }
    public private(set) var lastColor: (kind: String, hex: String)? = nil
    var isLoading = false
    var isProgrammaticEdit = false
    var hiddenChars = IndexSet()
    var pendingTrigger: (location: Int, text: String)?
    /// Ids of blocks selected as whole units (block mode); empty when editing text.
    public internal(set) var blockSelectionIds: [String] = []
    var expectedBlockSelection: NSRange?

    public lazy var toolbar = SelectionToolbar(controller: self)
    public lazy var slash = SlashMenu(controller: self)
    public lazy var imageBar = ImageBar(controller: self)

    public override init() {
        storage.addLayoutManager(layout)
        container.widthTracksTextView = true
        container.lineFragmentPadding = 0
        layout.addTextContainer(container)
        textView = DraftTextView(frame: NSRect(x: 0, y: 0, width: 640, height: 400), textContainer: container)
        super.init()
        textView.controller = self
        layout.delegate = self
        layout.selectedBlockIds = { [weak self] in self?.blockSelectionIds ?? [] }
        layout.isHidden = { [weak self] in self?.hiddenChars.contains($0) ?? false }
        layout.selectionIsOutlined = { [weak self] in
            guard let self else { return false }
            return self.isBlockMode || (self.selectedImageIndex != nil && self.textView.selectedRange().length == 1)
        }
        textView.delegate = self
        storage.delegate = self
        textView.isRichText = true
        textView.allowsUndo = true
        textView.importsGraphics = false
        textView.drawsBackground = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isContinuousSpellCheckingEnabled = true
        textView.usesFindBar = false
        textView.textContainerInset = .zero
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.setAccessibilityLabel("Document body")
        layout.theme = theme
    }

    // MARK: - Load / serialize

    public func load(_ doc: Node) {
        isLoading = true
        let (s, trailing) = Converter.attributed(from: doc)
        storage.beginEditing()
        storage.setAttributedString(s)
        storage.endEditing()
        self.trailing = trailing
        assignCells(in: NSRange(location: 0, length: storage.length))
        restyleAll()
        hiddenChars = IndexSet()
        refreshHidden()
        textView.undoManager?.removeAllActions()
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        updateTypingAttributes()
        isLoading = false
    }

    public func document() -> Node { Converter.document(from: storage, trailing: trailing) }

    public func restyleAll() {
        guard storage.length > 0 else { updateTypingAttributes(); textView.needsDisplay = true; return }
        storage.beginEditing()
        Styler.restyle(storage, range: NSRange(location: 0, length: storage.length), theme: theme)
        storage.endEditing()
        layout.invalidateNumbers()
        for case let cell as BlockCell in attachmentCells() { cell.controller = self }
        layout.invalidateLayout(forCharacterRange: NSRange(location: 0, length: storage.length), actualCharacterRange: nil)
        updateTypingAttributes()
        textView.needsDisplay = true
    }

    func attachmentCells() -> [NSTextAttachmentCellProtocol] {
        var cells: [NSTextAttachmentCellProtocol] = []
        storage.enumerateAttribute(.attachment, in: NSRange(location: 0, length: storage.length)) { v, _, _ in
            if let a = v as? NSTextAttachment, let c = a.attachmentCell { cells.append(c) }
        }
        return cells
    }

    func assignCells(in range: NSRange) {
        guard range.length > 0 else { return }
        storage.enumerateAttribute(.attachment, in: range) { v, _, _ in
            guard let a = v as? BlockAttachment else { return }
            if (a.attachmentCell as? BlockCell)?.controller === self { return }
            let cell: BlockCell
            switch a.kind {
            case .divider: cell = DividerCell()
            case .image: cell = ImageCell()
            case .page: cell = PageCardCell()
            case .file: cell = FileCell()
            default: cell = OpaqueCell()
            }
            switch a.kind {
            case .image: cell.setAccessibilityLabel((a.node.attrs?["alt"]?.string).flatMap { $0.isEmpty ? nil : "Image: \($0)" } ?? "Image without description")
            case .file: cell.setAccessibilityLabel("File: \(a.node.attrs?["name"]?.string ?? "attachment")")
            case .page: cell.setAccessibilityLabel("Page: \(a.node.attrs?["title"]?.string ?? "Untitled")")
            default: cell.setAccessibilityLabel(a.kind == .divider ? "Separator" : "Preserved block")
            }
            cell.controller = self
            a.attachmentCell = cell
        }
    }

    // MARK: - Paragraph helpers

    var ns: NSString { storage.string as NSString }

    public func paragraphRange(at loc: Int) -> NSRange {
        if loc >= storage.length {
            if storage.length == 0 || ns.character(at: storage.length - 1) == 10 { return NSRange(location: storage.length, length: 0) }
            return ns.paragraphRange(for: NSRange(location: storage.length - 1, length: 0))
        }
        return ns.paragraphRange(for: NSRange(location: loc, length: 0))
    }

    func contentRange(_ pr: NSRange) -> NSRange {
        var r = pr
        if r.length > 0, ns.character(at: NSMaxRange(r) - 1) == 10 { r.length -= 1 }
        return r
    }

    public func block(at pr: NSRange) -> BlockInfo {
        if pr.location >= storage.length { return trailing }
        return (storage.attribute(.draftBlock, at: pr.location, effectiveRange: nil) as? BlockInfo) ?? .paragraph()
    }

    public var currentBlock: BlockInfo { block(at: paragraphRange(at: textView.selectedRange().location)) }

    /// Paragraph ranges touched by the selection.
    public func selectedParagraphs() -> [NSRange] {
        let sel = textView.selectedRange()
        var out: [NSRange] = []
        var loc = sel.location
        repeat {
            let pr = paragraphRange(at: loc)
            out.append(pr)
            if pr.length == 0 { break }
            loc = NSMaxRange(pr)
        } while loc < NSMaxRange(sel)
        return out
    }

    // MARK: - Undoable primitives

    func replace(_ range: NSRange, with s: NSAttributedString, select: NSRange? = nil) {
        isProgrammaticEdit = true
        defer { isProgrammaticEdit = false }
        guard textView.shouldChangeText(in: range, replacementString: s.string) else { return }
        storage.beginEditing()
        storage.replaceCharacters(in: range, with: s)
        storage.endEditing()
        textView.didChangeText()
        if let select { textView.setSelectedRange(select) }
    }

    /// Change a paragraph's block (attribute-only, undoable).
    public func setBlock(_ pr: NSRange, _ b: BlockInfo) {
        if pr.length == 0 && pr.location >= storage.length {
            let old = trailing
            textView.undoManager?.registerUndo(withTarget: self) { $0.setBlock(pr, old) }
            trailing = b
            updateTypingAttributes()
            textView.needsDisplay = true
            host?.editorDidChange()
            return
        }
        guard textView.shouldChangeText(in: pr, replacementString: nil) else { return }
        storage.beginEditing()
        storage.addAttribute(.draftBlock, value: b, range: pr)
        storage.endEditing()
        textView.didChangeText()
        updateTypingAttributes()
    }

    func attrs(for b: BlockInfo, marks: [NSAttributedString.Key: Any] = [:]) -> [NSAttributedString.Key: Any] {
        Styler.typingAttributes(block: b, marks: marks, theme: theme)
    }

    // MARK: - Normalization (runs after every edit)

    public func textStorage(_ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorageEditActions, range editedRange: NSRange, changeInLength delta: Int) {
        guard editedMask.contains(.editedCharacters) || editedMask.contains(.editedAttributes) else { return }
        let len = textStorage.length
        guard len > 0 else { return }
        let start = min(editedRange.location, len - 1)
        let endLoc = min(max(NSMaxRange(editedRange), start), len)
        let first = ns.paragraphRange(for: NSRange(location: start, length: 0))
        let last = ns.paragraphRange(for: NSRange(location: max(start, endLoc - (endLoc > start ? 1 : 0)), length: 0))
        let range = NSUnionRange(first, last)
        if editedMask.contains(.editedCharacters) {
            normalizeBlocks(in: range, fullDedupe: range != first)
            assignCells(in: range)
        }
        Styler.restyle(textStorage, range: range, theme: theme)
        layout.invalidateNumbers()
        if hasToggles || !hiddenChars.isEmpty { DispatchQueue.main.async { [weak self] in self?.refreshHidden() } }
    }

    func normalizeBlocks(in range: NSRange, fullDedupe: Bool) {
        var loc = range.location
        var prevId: String? = nil
        if loc > 0 { prevId = block(at: paragraphRange(at: loc - 1)).id }
        while loc < NSMaxRange(range) && loc < storage.length {
            let pr = ns.paragraphRange(for: NSRange(location: loc, length: 0))
            let content = contentRange(pr)
            var b: BlockInfo
            if NSMaxRange(pr) > content.location + content.length { // has newline: the newline owns the block
                b = (storage.attribute(.draftBlock, at: NSMaxRange(pr) - 1, effectiveRange: nil) as? BlockInfo) ?? .paragraph()
            } else {
                b = (storage.attribute(.draftBlock, at: pr.location, effectiveRange: nil) as? BlockInfo) ?? .paragraph()
            }
            let hasAttachment = content.length > 0 && (storage.attribute(.attachment, at: content.location, effectiveRange: nil) != nil)
            if b.kind.isAttachment && !hasAttachment { b = b.with(kind: .paragraph, raw: .some(nil)) }
            if !b.kind.isAttachment && hasAttachment, let a = storage.attribute(.attachment, at: content.location, effectiveRange: nil) as? BlockAttachment {
                b = b.with(kind: a.kind, raw: .some(a.node))
            }
            if b.id == prevId { b = b.with(id: newId("b_")) }
            var uniform = true
            storage.enumerateAttribute(.draftBlock, in: pr) { v, _, stop in if !((v as? BlockInfo)?.isEqual(b) ?? false) { uniform = false; stop.pointee = true } }
            if !uniform { storage.addAttribute(.draftBlock, value: b, range: pr) }
            prevId = b.id
            loc = NSMaxRange(pr)
        }
        if fullDedupe { dedupeAll() }
    }

    func dedupeAll() {
        var seen = Set<String>()
        var loc = 0
        while loc < storage.length {
            let pr = ns.paragraphRange(for: NSRange(location: loc, length: 0))
            let b = block(at: pr)
            if seen.contains(b.id) { storage.addAttribute(.draftBlock, value: b.with(id: newId("b_")), range: pr) }
            else { seen.insert(b.id) }
            loc = NSMaxRange(pr)
        }
        if seen.contains(trailing.id), storage.length > 0, ns.character(at: storage.length - 1) == 10 { trailing = trailing.with(id: newId("b_")) }
    }

    // MARK: - Typing attributes

    func currentMarks() -> [NSAttributedString.Key: Any] {
        let sel = textView.selectedRange()
        let pr = paragraphRange(at: sel.location)
        var m: [NSAttributedString.Key: Any] = [:]
        let probe = sel.length > 0 ? sel.location : sel.location - 1
        if probe >= pr.location, probe >= 0, probe < storage.length, ns.character(at: probe) != 10 {
            let a = storage.attributes(at: probe, effectiveRange: nil)
            for k in semanticKeys where k != .draftLink { if let v = a[k] { m[k] = v } }
        }
        return m
    }

    public func updateTypingAttributes() {
        let b = currentBlock
        textView.typingAttributes = attrs(for: b.kind.isAttachment ? .paragraph() : b, marks: currentMarks())
    }

    // MARK: - NSTextViewDelegate

    /// Keep the caret out of collapsed toggles.
    public func textView(_ textView: NSTextView, willChangeSelectionFromCharacterRange old: NSRange, toCharacterRange new: NSRange) -> NSRange {
        guard new.length == 0, hiddenChars.contains(new.location) else { return new }
        if new.location > old.location, let after = (new.location..<storage.length).first(where: { !hiddenChars.contains($0) }) { return NSRange(location: after, length: 0) }
        var i = new.location
        while i > 0, hiddenChars.contains(i) { i -= 1 }
        return NSRange(location: contentRange(paragraphRange(at: i)).upperBound, length: 0)
    }

    public func textViewDidChangeSelection(_ notification: Notification) {
        guard !isLoading else { return }
        selectionChangedForBlockMode()
        refreshSelectionStyle()
        updateTypingAttributes()
        toolbar.update()
        imageBar.update()
        slash.selectionChanged()
        host?.editorStateDidChange()
    }

    public func textView(_ textView: NSTextView, shouldChangeTextIn range: NSRange, replacementString s: String?) -> Bool {
        guard let s else { return true }
        // Typing into an attachment block (image/divider/card) goes to a new paragraph instead.
        let pr = paragraphRange(at: range.location)
        let b = block(at: pr)
        let um = textView.undoManager
        let userTyping = !isProgrammaticEdit && !(um?.isUndoing ?? false) && !(um?.isRedoing ?? false)
        if userTyping && b.kind.isAttachment && !s.isEmpty && s != "\n" && range.length == 0 && pr.length > 0 {
            DispatchQueue.main.async { [weak self] in self?.insertParagraphAfter(pr, text: s) }
            return false
        }
        pendingTrigger = (s.count == 1 && range.length == 0) ? (range.location, s) : nil
        return true
    }

    public func textDidChange(_ notification: Notification) {
        if !isLoading, let t = pendingTrigger {
            pendingTrigger = nil
            slash.textChanged(typed: t.text, at: t.location)
            // Run the Markdown conversion as its own event so Undo restores the literal text.
            DispatchQueue.main.async { [weak self] in self?.applyMarkdownTrigger(typed: t.text, at: t.location) }
        } else {
            slash.textChanged(typed: nil, at: textView.selectedRange().location)
        }
        toolbar.update()
        host?.editorDidChange()
    }

    // MARK: - Enter / Backspace / Tab

    func insertParagraphAfter(_ pr: NSRange, text: String = "", block nb: BlockInfo = .paragraph()) {
        let end = NSMaxRange(pr)
        let hasNewline = end > 0 && end <= storage.length && ns.character(at: end - 1) == 10
        if hasNewline {
            let s = NSAttributedString(string: text + "\n", attributes: attrs(for: nb))
            replace(NSRange(location: end, length: 0), with: s, select: NSRange(location: end + (text as NSString).length, length: 0))
        } else {
            let prev = block(at: pr)
            let m = NSMutableAttributedString(string: "\n", attributes: attrs(for: prev))
            m.append(NSAttributedString(string: text, attributes: attrs(for: nb)))
            if text.isEmpty { trailing = nb }
            replace(NSRange(location: end, length: 0), with: m, select: NSRange(location: end + 1 + (text as NSString).length, length: 0))
        }
        updateTypingAttributes()
    }

    /// Returns true when handled.
    func handleNewline() -> Bool {
        if slash.isOpen { slash.choose(); return true }
        var sel = textView.selectedRange()
        if sel.length > 0 { replace(sel, with: NSAttributedString(), select: NSRange(location: sel.location, length: 0)); sel = textView.selectedRange() }
        let loc = sel.location
        let pr = paragraphRange(at: loc)
        let b = block(at: pr)
        let content = contentRange(pr)
        let text = ns.substring(with: content)

        if b.kind.isAttachment { insertParagraphAfter(pr); return true }
        if b.kind == .code {
            if loc == NSMaxRange(content), text.hasSuffix(Chars.lineBreak) {
                // Enter on an empty last line leaves the code block.
                replace(NSRange(location: loc - 1, length: 1), with: NSAttributedString(), select: NSRange(location: loc - 1, length: 0))
                insertParagraphAfter(paragraphRange(at: loc - 1))
            } else {
                textView.insertText(Chars.lineBreak, replacementRange: sel)
            }
            return true
        }
        if text.isEmpty && (b.kind.isList || b.kind == .quote || b.kind == .callout) {
            if b.kind.isList && b.indent > 0 { setBlock(pr, b.with(indent: b.indent - 1, continuation: false)) }
            else { setBlock(pr, b.with(kind: .paragraph, indent: 0, checked: false, start: .some(nil), continuation: false, innerId: .some(nil), containerId: .some(nil))) }
            return true
        }
        let next: BlockInfo
        switch b.kind {
        case .bullet, .ordered, .task, .toggle:
            next = BlockInfo(kind: b.kind, indent: b.indent, checked: b.kind == .toggle, containerId: b.containerId)
        case .quote:
            next = BlockInfo(kind: .quote, containerId: b.containerId)
        case .callout:
            next = BlockInfo(kind: .callout, icon: b.icon, containerId: b.containerId)
        default:
            next = .paragraph()
        }
        if b.kind == .heading && loc == content.location && !text.isEmpty {
            // Enter at the start of a heading inserts an empty paragraph above it.
            let s = NSAttributedString(string: "\n", attributes: attrs(for: .paragraph()))
            replace(NSRange(location: pr.location, length: 0), with: s, select: NSRange(location: pr.location + 1, length: 0))
            return true
        }
        let rest = NSRange(location: loc, length: NSMaxRange(pr) - loc)
        let restText = storage.attributedSubstring(from: rest).mutableCopy() as! NSMutableAttributedString
        restText.addAttribute(.draftBlock, value: next, range: NSRange(location: 0, length: restText.length))
        let m = NSMutableAttributedString(string: "\n", attributes: attrs(for: b))
        m.append(restText)
        if restText.length == 0 { trailing = next }
        replace(rest, with: m, select: NSRange(location: loc + 1, length: 0))
        textView.typingAttributes = attrs(for: next, marks: b.kind == .heading ? [:] : currentMarks())
        textView.scrollRangeToVisible(textView.selectedRange())
        return true
    }

    func handleDeleteBackward() -> Bool {
        let sel = textView.selectedRange()
        guard sel.length == 0 else { return false }
        let pr = paragraphRange(at: sel.location)
        guard sel.location == pr.location else { return false }
        let b = block(at: pr)
        if b.kind.isList && !b.continuation {
            if b.indent > 0 { setBlock(pr, b.with(indent: b.indent - 1)) }
            else { setBlock(pr, b.with(kind: .paragraph, checked: false, start: .some(nil), innerId: .some(nil), containerId: .some(nil))) }
            return true
        }
        if [.quote, .callout, .heading, .code].contains(b.kind) || b.variant != nil || b.decoration != nil || b.blockColor != nil {
            setBlock(pr, b.with(kind: .paragraph, indent: 0, variant: .some(nil), blockColor: .some(nil), decoration: .some(nil), containerId: .some(nil)))
            return true
        }
        guard pr.location > 0 else { return true }
        let prev = paragraphRange(at: pr.location - 1)
        let pb = block(at: prev)
        if pb.kind.isAttachment {
            // Remove the attachment block above (undoable) instead of merging into it.
            replace(prev, with: NSAttributedString(), select: NSRange(location: prev.location, length: 0))
            return true
        }
        if b.kind.isAttachment {
            if contentRange(prev).length == 0 { replace(prev, with: NSAttributedString(), select: NSRange(location: prev.location, length: 0)) }
            else { textView.setSelectedRange(NSRange(location: NSMaxRange(contentRange(prev)), length: 0)) }
            return true
        }
        // Merge into the previous paragraph, which keeps its identity and type.
        undoGroup {
            replace(NSRange(location: pr.location - 1, length: 1), with: NSAttributedString(), select: NSRange(location: pr.location - 1, length: 0))
            let merged = paragraphRange(at: pr.location - 1 == storage.length ? max(0, pr.location - 2) : pr.location - 1)
            if merged.length > 0 { setBlock(merged, pb) } else { trailing = pb }
            textView.setSelectedRange(NSRange(location: pr.location - 1, length: 0))
        }
        return true
    }

    func handleDeleteForward() -> Bool {
        let sel = textView.selectedRange()
        guard sel.length == 0, sel.location < storage.length, ns.character(at: sel.location) == 10 else { return false }
        let pr = paragraphRange(at: sel.location)
        let b = block(at: pr)
        let next = paragraphRange(at: sel.location + 1)
        if block(at: next).kind.isAttachment || b.kind.isAttachment { return false }
        undoGroup {
            replace(NSRange(location: sel.location, length: 1), with: NSAttributedString(), select: sel)
            let merged = paragraphRange(at: sel.location)
            if merged.length > 0 { setBlock(merged, b) }
            textView.setSelectedRange(sel)
        }
        return true
    }

    func undoGroup(_ fn: () -> Void) {
        textView.breakUndoCoalescing()
        textView.undoManager?.beginUndoGrouping()
        fn()
        textView.undoManager?.endUndoGrouping()
    }

    public func indent() {
        undoGroup {
            for pr in selectedParagraphs() {
                let b = block(at: pr)
                guard b.kind.isList else { continue }
                let prevIndent = pr.location > 0 ? block(at: paragraphRange(at: pr.location - 1)) : nil
                let maxIndent = (prevIndent?.kind.isList ?? false) ? prevIndent!.indent + 1 : 0
                if b.indent < min(maxIndent, 6) { setBlock(pr, b.with(indent: b.indent + 1, start: .some(nil))) }
            }
        }
    }

    public func outdent() {
        undoGroup {
            for pr in selectedParagraphs() {
                let b = block(at: pr)
                if b.kind.isList && b.indent > 0 { setBlock(pr, b.with(indent: b.indent - 1)) }
                else if b.decoration == "focus" { setBlock(pr, b.with(decoration: .some(nil))) }
            }
        }
    }

    public var canIndent: Bool { selectedParagraphs().contains { block(at: $0).kind.isList } }
    public var canOutdent: Bool { selectedParagraphs().contains { let b = block(at: $0); return b.kind.isList && b.indent > 0 } }

    // MARK: - Markdown triggers (undo restores the literal text)

    static let blockTriggers: [(String, (BlockInfo) -> BlockInfo)] = [
        ("####", { $0.with(kind: .heading, level: 4) }),
        ("###", { $0.with(kind: .heading, level: 3) }),
        ("##", { $0.with(kind: .heading, level: 2) }),
        ("#", { $0.with(kind: .heading, level: 1) }),
        ("-", { $0.with(kind: .bullet, indent: $0.kind.isList ? $0.indent : 0) }),
        ("*", { $0.with(kind: .bullet, indent: $0.kind.isList ? $0.indent : 0) }),
        ("[]", { $0.with(kind: .task, indent: $0.kind.isList ? $0.indent : 0, checked: false) }),
        ("[ ]", { $0.with(kind: .task, indent: $0.kind.isList ? $0.indent : 0, checked: false) }),
        ("[x]", { $0.with(kind: .task, indent: $0.kind.isList ? $0.indent : 0, checked: true) }),
        ("x", { $0.with(kind: .task, indent: $0.kind.isList ? $0.indent : 0, checked: false) }),
        ("+", { $0.with(kind: .toggle, indent: $0.kind.isList ? $0.indent : 0, checked: true) }),
        (">", { $0.with(kind: .quote, containerId: .some(newId("b_"))) }),
        ("|", { $0.with(kind: .quote, containerId: .some(newId("b_"))) }),
    ]

    func applyMarkdownTrigger(typed: String, at loc: Int) {
        // Only convert if the caret is still right after the typed character.
        guard loc + (typed as NSString).length <= storage.length, textView.selectedRange() == NSRange(location: loc + (typed as NSString).length, length: 0),
              ns.substring(with: NSRange(location: loc, length: (typed as NSString).length)) == typed, !slash.isOpen else { return }
        let pr = paragraphRange(at: loc)
        let b = block(at: pr)
        guard b.kind != .code, !b.kind.isAttachment else { return }
        let caret = loc + (typed as NSString).length
        let prefix = ns.substring(with: NSRange(location: pr.location, length: max(0, caret - pr.location)))

        if typed == " " && caret - pr.location <= 5 {
            let pattern = String(prefix.dropLast())
            var newBlock: BlockInfo? = nil
            if let rule = Self.blockTriggers.first(where: { $0.0 == pattern }) { newBlock = rule.1(b) }
            else if pattern.range(of: "^[0-9]{1,3}\\.$", options: .regularExpression) != nil {
                let n = Int(pattern.dropLast()) ?? 1
                newBlock = b.with(kind: .ordered, indent: b.kind.isList ? b.indent : 0, start: .some(n))
            }
            guard var nb = newBlock else { return }
            if nb.kind.isList && b.kind != nb.kind { nb = nb.with(containerId: .some(newId("b_"))) }
            undoGroup {
                replace(NSRange(location: pr.location, length: caret - pr.location), with: NSAttributedString(), select: NSRange(location: pr.location, length: 0))
                setBlock(paragraphRange(at: pr.location), nb)
            }
            return
        }
        let text = ns.substring(with: contentRange(pr))
        if typed == "`" && text == "```" {
            undoGroup {
                replace(contentRange(pr), with: NSAttributedString(), select: NSRange(location: pr.location, length: 0))
                setBlock(paragraphRange(at: pr.location), BlockInfo(id: b.id, kind: .code))
            }
            return
        }
        let separators: [String: Node] = ["---": Node("horizontalRule"), "=--": Node("horizontalRule", attrs: ["variant": "strong"]),
                                          ".--": Node("horizontalRule", attrs: ["variant": "dotted"]), "..-": Node("horizontalRule", attrs: ["variant": "dots"]),
                                          "===": Node("pageBreak")]
        if typed == "-" || typed == "=", let div = separators[text] {
            undoGroup {
                let att = NSMutableAttributedString(attachment: BlockAttachment(kind: .divider, node: div))
                att.addAttribute(.draftBlock, value: BlockInfo(id: b.id, kind: .divider, raw: div), range: NSRange(location: 0, length: att.length))
                replace(contentRange(pr), with: att)
                insertParagraphAfter(paragraphRange(at: pr.location))
            }
            return
        }
        // Inline marks: **bold**, *italic*, ~~strike~~, ==highlight==, `code`
        let inline: [(String, NSAttributedString.Key, Any, Int)] = [
            ("\\*\\*([^*\\s](?:[^*]*[^*\\s])?)\\*\\*$", .draftBold, true, 2),
            ("(?<![*\\w])\\*([^*\\s](?:[^*]*[^*\\s])?)\\*$", .draftItalic, true, 1),
            ("~~([^~\\s](?:[^~]*[^~\\s])?)~~$", .draftStrike, true, 2),
            ("==([^=\\s](?:[^=]*[^=\\s])?)==$", .draftHighlight, "#fff3a3", 2),
            ("`([^`]+)`$", .draftCode, true, 1),
        ]
        guard ["*", "~", "=", "`"].contains(typed) else { return }
        for (pattern, key, value, delim) in inline {
            guard let re = try? NSRegularExpression(pattern: pattern),
                  let m = re.firstMatch(in: prefix, range: NSRange(location: 0, length: (prefix as NSString).length)) else { continue }
            let whole = NSRange(location: pr.location + m.range.location, length: m.range.length)
            let inner = (prefix as NSString).substring(with: m.range(at: 1))
            undoGroup {
                let base = storage.attributedSubstring(from: NSRange(location: whole.location + delim, length: (inner as NSString).length)).mutableCopy() as! NSMutableAttributedString
                base.addAttribute(key, value: value, range: NSRange(location: 0, length: base.length))
                replace(whole, with: base, select: NSRange(location: whole.location + base.length, length: 0))
            }
            var t = textView.typingAttributes
            t[key] = nil
            textView.typingAttributes = attrs(for: block(at: pr), marks: t.filter { semanticKeys.contains($0.key) })
            return
        }
    }

    // MARK: - Block commands

    public func setBlockKind(_ kind: BlockKind, level: Int = 1, variant: String? = nil) {
        let groupContainer = newId("b_") // selected paragraphs become one quote/callout
        undoGroup {
            for pr in selectedParagraphs() {
                let b = block(at: pr)
                guard !b.kind.isAttachment else { continue }
                var nb = b.with(kind: kind, level: level, variant: .some(variant), continuation: false)
                if !kind.isList {
                    let keepContainer = kind == b.kind && (kind == .quote || kind == .callout)
                    nb = BlockInfo(id: b.id, kind: kind, level: level, variant: variant, blockColor: b.blockColor, decoration: b.decoration, align: b.align,
                                   icon: kind == .callout ? (b.icon ?? "💡") : nil,
                                   containerId: kind == .quote || kind == .callout ? (keepContainer ? b.containerId : groupContainer) : nil)
                }
                if kind == .code {
                    // Code keeps only plain text.
                    let cr = contentRange(pr)
                    if cr.length > 0 {
                        guard textView.shouldChangeText(in: cr, replacementString: nil) else { continue }
                        for k in semanticKeys { storage.removeAttribute(k, range: cr) }
                        textView.didChangeText()
                    }
                }
                setBlock(paragraphRange(at: pr.location), nb)
            }
        }
        host?.editorStateDidChange()
    }

    public func isBlockKind(_ kind: BlockKind, level: Int? = nil, variant: String? = nil) -> Bool {
        let b = currentBlock
        return b.kind == kind && (level == nil || b.level == level) && b.variant == variant
    }

    public func toggleList(_ kind: BlockKind) {
        let all = selectedParagraphs().allSatisfy { block(at: $0).kind == kind }
        if all { setBlockKind(.paragraph) }
        else {
            let cid = newId("b_")
            undoGroup {
                for pr in selectedParagraphs() {
                    let b = block(at: pr)
                    guard !b.kind.isAttachment else { continue }
                    setBlock(pr, b.with(kind: kind, indent: b.kind.isList ? b.indent : 0, checked: kind == .toggle, variant: .some(nil), containerId: .some(b.kind.isList ? b.containerId : cid)))
                }
            }
        }
        host?.editorStateDidChange()
    }

    public func setAlign(_ a: String?) { mapBlocks { $0.with(align: .some(a == "left" ? nil : a)) } }
    public func setDecoration(_ d: String?) { mapBlocks { $0.with(decoration: .some($0.decoration == d ? nil : d)) } }
    public func setBlockColor(_ c: String?) { mapBlocks { $0.with(blockColor: .some(c), decoration: .some($0.decoration ?? (c == nil ? nil : "block"))) } }

    func mapBlocks(_ f: (BlockInfo) -> BlockInfo) {
        undoGroup { for pr in selectedParagraphs() { let b = block(at: pr); if !b.kind.isAttachment || b.kind == .page { setBlock(pr, f(b)) } } }
        host?.editorStateDidChange()
    }

    public func toggleTask(at pr: NSRange) {
        let b = block(at: pr)
        guard b.kind == .task else { return }
        setBlock(pr, b.with(checked: !b.checked))
        textView.needsDisplay = true
        host?.editorDidChange()
    }

    /// Expand or collapse a toggle (undoable). Its children are hidden from layout, not removed.
    public func toggleOpen(at pr: NSRange) {
        let b = block(at: pr)
        guard b.kind == .toggle else { return }
        setBlock(pr, b.with(checked: !b.checked))
        refreshHidden()
    }

    public func toggleCurrentOpen() {
        let pr = paragraphRange(at: textView.selectedRange().location)
        if block(at: pr).kind == .toggle { toggleOpen(at: pr) } else { NSSound.beep() }
    }

    /// Characters inside collapsed toggles.
    func computeHidden() -> IndexSet {
        var hidden = IndexSet()
        var collapsedIndent: Int? = nil
        var loc = 0
        let len = storage.length
        while loc < len {
            let pr = ns.paragraphRange(for: NSRange(location: loc, length: 0))
            let b = block(at: pr)
            if let ci = collapsedIndent, b.kind.isList, b.indent > ci || (b.continuation && b.indent == ci) {
                hidden.insert(integersIn: pr.location..<NSMaxRange(pr))
            } else {
                collapsedIndent = (b.kind == .toggle && !b.continuation && !b.checked) ? b.indent : nil
            }
            loc = NSMaxRange(pr)
        }
        return hidden
    }

    /// Recompute hidden text and relayout what changed.
    func refreshHidden() {
        let new = computeHidden()
        guard new != hiddenChars else { return }
        let changed = new.symmetricDifference(hiddenChars)
        hiddenChars = new
        if let lo = changed.first, let hi = changed.last {
            let r = NSRange(location: lo, length: min(storage.length, hi + 1) - lo)
            layout.invalidateGlyphs(forCharacterRange: r, changeInLength: 0, actualCharacterRange: nil)
            layout.invalidateLayout(forCharacterRange: r, actualCharacterRange: nil)
        }
        textView.needsDisplay = true
    }

    public func toggleTask(blockId: String) {
        if let pr = paragraph(withId: blockId) { toggleTask(at: pr) }
    }

    public func paragraph(withId id: String) -> NSRange? {
        var loc = 0
        while loc < storage.length {
            let pr = ns.paragraphRange(for: NSRange(location: loc, length: 0))
            if block(at: pr).id == id { return pr }
            loc = NSMaxRange(pr)
        }
        return trailing.id == id ? NSRange(location: storage.length, length: 0) : nil
    }

    // MARK: - Inline marks

    public func isMarkActive(_ m: InlineMark) -> Bool {
        let sel = textView.selectedRange()
        if sel.length == 0 { return textView.typingAttributes[m.key] != nil }
        var all = true
        storage.enumerateAttribute(m.key, in: sel) { v, r, stop in
            if v == nil && ns.substring(with: r).trimmingCharacters(in: .newlines).count > 0 { all = false; stop.pointee = true }
        }
        return all
    }

    public func value(of key: NSAttributedString.Key) -> String? {
        let sel = textView.selectedRange()
        if sel.length == 0 { return textView.typingAttributes[key] as? String }
        return storage.attribute(key, at: sel.location, effectiveRange: nil) as? String
    }

    public func toggleMark(_ m: InlineMark) {
        let sel = textView.selectedRange()
        let on = !isMarkActive(m)
        if sel.length == 0 {
            var t = textView.typingAttributes
            t[m.key] = on ? true : nil
            textView.typingAttributes = attrs(for: currentBlock, marks: t.filter { semanticKeys.contains($0.key) })
        } else {
            setInline(m.key, on ? true : nil, range: sel)
        }
        toolbar.update()
        host?.editorStateDidChange()
    }

    func setInline(_ key: NSAttributedString.Key, _ value: Any?, range: NSRange) {
        guard range.length > 0, textView.shouldChangeText(in: range, replacementString: nil) else { return }
        storage.beginEditing()
        if let value { storage.addAttribute(key, value: value, range: range) } else { storage.removeAttribute(key, range: range) }
        storage.endEditing()
        textView.didChangeText()
    }

    public func setHighlight(_ hex: String?) {
        applyColor(.draftHighlight, hex)
        if let hex { lastColor = ("highlight", hex) }
    }

    public func setTextColor(_ hex: String?) {
        applyColor(.draftTextColor, hex)
        if let hex { lastColor = ("text", hex) }
    }

    func applyColor(_ key: NSAttributedString.Key, _ hex: String?) {
        let sel = textView.selectedRange()
        if sel.length == 0 {
            var t = textView.typingAttributes
            t[key] = hex
            textView.typingAttributes = attrs(for: currentBlock, marks: t.filter { semanticKeys.contains($0.key) })
        } else { setInline(key, hex, range: sel) }
        toolbar.update()
        host?.editorStateDidChange()
    }

    public func reapplyLastColor() {
        guard let c = lastColor else { NSSound.beep(); return }
        if c.kind == "highlight" { setHighlight(c.hex) } else { setTextColor(c.hex) }
    }

    public func clearFormatting() {
        let sel = textView.selectedRange()
        guard sel.length > 0, textView.shouldChangeText(in: sel, replacementString: nil) else { return }
        storage.beginEditing()
        for k in semanticKeys { storage.removeAttribute(k, range: sel) }
        storage.endEditing()
        textView.didChangeText()
    }

    public func setLink(_ href: String?, range: NSRange) {
        var h = href?.trimmingCharacters(in: .whitespaces)
        if let x = h, !x.isEmpty, !x.contains(":") { h = "https://" + x }
        setInline(.draftLink, (h?.isEmpty ?? true) ? nil : h, range: range)
        textView.setSelectedRange(range)
    }

    public func linkRange(at loc: Int) -> (NSRange, String)? {
        guard loc < storage.length else { return nil }
        var r = NSRange()
        if let h = storage.attribute(.draftLink, at: loc, longestEffectiveRange: &r, in: NSRange(location: 0, length: storage.length)) as? String { return (r, h) }
        return nil
    }

    // MARK: - Insertion

    /// Insert an attachment block after the current paragraph (or replace it when empty).
    public func insertAttachmentBlock(kind: BlockKind, node: Node) {
        let pr = paragraphRange(at: textView.selectedRange().location)
        let b = block(at: pr)
        let id = newId("b_")
        var n = node
        n[attr: "id"] = .string(id)
        let att = NSMutableAttributedString(attachment: BlockAttachment(kind: kind, node: n))
        att.addAttribute(.draftBlock, value: BlockInfo(id: id, kind: kind, raw: n), range: NSRange(location: 0, length: att.length))
        undoGroup {
            if contentRange(pr).length == 0 && !b.kind.isAttachment {
                if pr.length == 0 { // trailing empty paragraph
                    replace(NSRange(location: storage.length, length: 0), with: att)
                    insertParagraphAfter(paragraphRange(at: storage.length - 1))
                } else {
                    let m = NSMutableAttributedString(attributedString: att)
                    m.append(NSAttributedString(string: "\n", attributes: [.draftBlock: BlockInfo(id: id, kind: kind, raw: n)]))
                    replace(pr, with: m, select: NSRange(location: pr.location + 2, length: 0))
                    if NSMaxRange(pr) >= storage.length - 0 && paragraphRange(at: pr.location + 2).location >= storage.length { trailing = .paragraph() }
                }
            } else {
                let end = NSMaxRange(pr)
                let hasNewline = end > 0 && ns.character(at: end - 1) == 10
                let m = NSMutableAttributedString()
                if !hasNewline { m.append(NSAttributedString(string: "\n", attributes: attrs(for: b))) }
                m.append(att)
                m.append(NSAttributedString(string: "\n", attributes: [.draftBlock: BlockInfo(id: id, kind: kind, raw: n)]))
                replace(NSRange(location: end, length: 0), with: m, select: NSRange(location: end + m.length, length: 0))
                if NSMaxRange(paragraphRange(at: end + m.length - 1)) >= storage.length { trailing = .paragraph() }
            }
        }
        updateTypingAttributes()
        textView.window?.makeFirstResponder(textView)
    }

    public func insertDivider() { insertAttachmentBlock(kind: .divider, node: Node("horizontalRule")) }

    public func insertImage(assetId: String, alt: String = "") {
        insertAttachmentBlock(kind: .image, node: Node("image", attrs: ["assetId": .string(assetId), "alt": .string(alt)]))
    }

    public func insertImageFromPicker() {
        host?.pickImage { [weak self] id in if let id { self?.insertImage(assetId: id) } }
    }

    public func insertPage(presentation: String = "card") {
        guard let (docId, title) = host?.createChildPage() else { return }
        insertAttachmentBlock(kind: .page, node: Node("pageCard", attrs: ["docId": .string(docId), "title": .string(title), "presentation": .string(presentation)]))
        host?.openPage(docId: docId)
    }

    /// Toggle a page block between card and compact page presentation.
    public func setPagePresentation(_ p: String) {
        let pr = paragraphRange(at: textView.selectedRange().location)
        guard block(at: pr).kind == .page else { insertPage(presentation: p); return }
        updateAttachment(at: pr.location) { $0[attr: "presentation"] = .string(p) }
    }

    /// Change an attachment block's node (one undo step), keeping its id and the selection.
    public func updateAttachment(at charIndex: Int, _ change: (inout Node) -> Void) {
        guard charIndex < storage.length, let a = storage.attribute(.attachment, at: charIndex, effectiveRange: nil) as? BlockAttachment else { return }
        let pr = paragraphRange(at: charIndex)
        var n = a.node
        change(&n)
        guard n != a.node else { return }
        let sel = textView.selectedRange()
        let att = NSMutableAttributedString(attachment: BlockAttachment(kind: a.kind, node: n))
        att.addAttribute(.draftBlock, value: block(at: pr).with(raw: .some(n)), range: NSRange(location: 0, length: 1))
        undoGroup { replace(NSRange(location: charIndex, length: 1), with: att) }
        textView.setSelectedRange(sel)
        imageBar.update()
        host?.editorDidChange()
    }

    // MARK: Images and files

    /// Character index of the image the selection is on, if any.
    public var selectedImageIndex: Int? {
        let sel = textView.selectedRange()
        guard storage.length > 0 else { return nil }
        let pr = paragraphRange(at: min(sel.location, storage.length - 1))
        guard NSMaxRange(sel) <= NSMaxRange(pr), block(at: pr).kind == .image, pr.length > 0 else { return nil }
        return pr.location
    }

    /// Text selections are tinted; whole blocks and a selected image are outlined instead.
    func refreshSelectionStyle() {
        let outlined = isBlockMode || (selectedImageIndex != nil && textView.selectedRange().length == 1)
        textView.selectedTextAttributes = [.backgroundColor: outlined ? NSColor.clear : theme.accentColor.withAlphaComponent(theme.isDarkPage ? 0.45 : 0.22)]
    }

    func isImageSelected(_ cell: ImageCell) -> Bool {
        guard let i = selectedImageIndex else { return false }
        return (storage.attribute(.attachment, at: i, effectiveRange: nil) as? NSTextAttachment)?.attachmentCell === cell
    }

    public func setImageWidth(_ fraction: Double) {
        if let i = selectedImageIndex { updateAttachment(at: i) { $0[attr: "width"] = fraction >= 1 ? nil : .number(fraction) } }
    }
    public func setImageCaption(_ text: String) {
        if let i = selectedImageIndex { updateAttachment(at: i) { $0[attr: "caption"] = text.isEmpty ? nil : .string(text) } }
    }
    public func setImageAlt(_ text: String) {
        if let i = selectedImageIndex { updateAttachment(at: i) { $0[attr: "alt"] = .string(text) } }
    }

    public func insertFile(assetId: String, name: String, size: Int) {
        insertAttachmentBlock(kind: .file, node: Node("file", attrs: ["assetId": .string(assetId), "name": .string(name), "size": .number(Double(size))]))
    }

    public func insertFileFromPicker() {
        host?.pickFile { [weak self] f in if let f { self?.insertFile(assetId: f.assetId, name: f.name, size: f.size) } }
    }

    /// Dropped or pasted Finder files: images become image blocks, everything else file blocks.
    public func insertFiles(_ urls: [URL]) -> Bool {
        var any = false
        for url in urls {
            let ext = url.pathExtension.lowercased()
            if ["png", "jpg", "jpeg", "gif", "heic", "webp", "tiff"].contains(ext), let data = try? Data(contentsOf: url), let id = host?.storeImage(data: data, ext: ext == "jpeg" ? "jpg" : ext) {
                insertImage(assetId: id, alt: url.deletingPathExtension().lastPathComponent); any = true
            } else if let f = host?.storeFile(at: url) {
                insertFile(assetId: f.assetId, name: f.name, size: f.size); any = true
            }
        }
        return any
    }

    /// Keep page-card titles in sync with the child documents (no undo entry, no dirtying).
    public func refreshPageTitles(_ titleFor: (String) -> String?) {
        var changed = false
        storage.enumerateAttribute(.attachment, in: NSRange(location: 0, length: storage.length)) { v, _, _ in
            guard let a = v as? BlockAttachment, a.kind == .page, let id = a.node.attrs?["docId"]?.string, let t = titleFor(id), a.node.attrs?["title"]?.string != t else { return }
            a.node[attr: "title"] = .string(t)
            changed = true
        }
        if changed { layout.invalidateDisplay(forCharacterRange: NSRange(location: 0, length: storage.length)) }
    }

    // MARK: - Find in page

    public private(set) var findMatches: [NSRange] = []
    public private(set) var findIndex = 0

    public func find(_ query: String) -> Int {
        clearFindHighlights()
        findMatches = []
        findIndex = 0
        guard !query.isEmpty else { return 0 }
        var r = NSRange(location: 0, length: storage.length)
        while true {
            let f = ns.range(of: query, options: [.caseInsensitive, .diacriticInsensitive], range: r)
            if f.location == NSNotFound { break }
            findMatches.append(f)
            r = NSRange(location: NSMaxRange(f), length: storage.length - NSMaxRange(f))
        }
        paintFind()
        if !findMatches.isEmpty { reveal(findMatches[0]) }
        return findMatches.count
    }

    public func findStep(_ delta: Int) {
        guard !findMatches.isEmpty else { return }
        findIndex = (findIndex + delta + findMatches.count) % findMatches.count
        paintFind()
        reveal(findMatches[findIndex])
    }

    func paintFind() {
        clearFindHighlights()
        for (i, r) in findMatches.enumerated() {
            layout.addTemporaryAttribute(.backgroundColor, value: i == findIndex ? NSColor(hex: "#ffd84d") : NSColor(hex: "#ffe98a", alpha: 0.55), forCharacterRange: r)
        }
    }

    public func clearFindHighlights() {
        layout.removeTemporaryAttribute(.backgroundColor, forCharacterRange: NSRange(location: 0, length: storage.length))
    }

    func reveal(_ r: NSRange) {
        textView.scrollRangeToVisible(r)
        textView.showFindIndicator(for: r)
    }

    /// Replace the current match (or all) as one undo step. Returns number replaced.
    @discardableResult
    public func replace(query: String, with replacement: String, all: Bool) -> Int {
        guard !findMatches.isEmpty else { return 0 }
        let targets = all ? findMatches : [findMatches[findIndex]]
        undoGroup {
            for r in targets.reversed() {
                let attrs = storage.attributes(at: r.location, effectiveRange: nil)
                replace(r, with: NSAttributedString(string: replacement, attributes: attrs))
            }
        }
        let n = targets.count
        _ = find(query)
        return n
    }

    // MARK: - Navigation

    public func scrollTo(blockId: String) {
        guard let pr = paragraph(withId: blockId) else { return }
        textView.window?.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: pr.location, length: 0))
        textView.scrollRangeToVisible(pr)
        if pr.length > 0 { textView.showFindIndicator(for: contentRange(pr).length > 0 ? contentRange(pr) : pr) }
    }

    public func focusStart() {
        textView.window?.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: 0, length: 0))
    }

    // MARK: - Pasteboard (keeps blocks and marks inside Draft)

    public static let pasteboardType = NSPasteboard.PasteboardType("app.draft.fragment+json")

    func fragmentData(_ range: NSRange) -> Data? {
        let sub = storage.attributedSubstring(from: range)
        let last = (sub.length > 0 ? sub.attribute(.draftBlock, at: sub.length - 1, effectiveRange: nil) as? BlockInfo : nil) ?? .paragraph()
        let node = Converter.document(from: sub, trailing: last)
        return try? DraftJSON.encode(node)
    }

    func pasteImage(_ data: Data, ext: String) -> Bool {
        guard let id = host?.storeImage(data: data, ext: ext) else { return false }
        insertImage(assetId: id)
        return true
    }
}

extension EditorController: NSLayoutManagerDelegate {
    var hasToggles: Bool {
        var found = false
        storage.enumerateAttribute(.draftBlock, in: NSRange(location: 0, length: storage.length)) { v, _, stop in
            if (v as? BlockInfo)?.kind == .toggle { found = true; stop.pointee = true }
        }
        return found
    }

    public func layoutManager(_ lm: NSLayoutManager, shouldGenerateGlyphs glyphs: UnsafePointer<CGGlyph>, properties props: UnsafePointer<NSLayoutManager.GlyphProperty>,
                              characterIndexes: UnsafePointer<Int>, font: NSFont, forGlyphRange range: NSRange) -> Int {
        guard !hiddenChars.isEmpty else { return 0 }
        var newProps = Array(UnsafeBufferPointer(start: props, count: range.length))
        var any = false
        let text = storage.string as NSString
        for i in 0..<range.length where hiddenChars.contains(characterIndexes[i]) && text.character(at: characterIndexes[i]) != 10 {
            newProps[i] = .null; any = true // newlines stay, so each hidden paragraph keeps its own (zero-height) line
        }
        guard any else { return 0 }
        newProps.withUnsafeBufferPointer { lm.setGlyphs(glyphs, properties: $0.baseAddress!, characterIndexes: characterIndexes, font: font, forGlyphRange: range) }
        return range.length
    }

    public func layoutManager(_ lm: NSLayoutManager, shouldSetLineFragmentRect lineFragmentRect: UnsafeMutablePointer<NSRect>, lineFragmentUsedRect: UnsafeMutablePointer<NSRect>,
                              baselineOffset: UnsafeMutablePointer<CGFloat>, in textContainer: NSTextContainer, forGlyphRange glyphRange: NSRange) -> Bool {
        guard !hiddenChars.isEmpty else { return false }
        let cr = lm.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
        guard cr.length > 0, hiddenChars.contains(integersIn: cr.location..<NSMaxRange(cr)) else { return false }
        lineFragmentRect.pointee.size.height = 0
        lineFragmentUsedRect.pointee.size.height = 0
        baselineOffset.pointee = 0
        return true
    }
}
