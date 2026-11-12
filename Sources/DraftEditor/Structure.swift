import AppKit
import DraftCore

/// Inline marks of a table cell drawn as attributed text.
func cellText(_ inline: [Node]?, theme: EditorTheme, header: Bool, size: CGFloat = 14) -> NSAttributedString {
    let out = NSMutableAttributedString()
    for n in inline ?? [] where n.type == "text" {
        let marks = Set((n.marks ?? []).map(\.type))
        var f = theme.font(size: size, weight: header ? .semibold : .regular, bold: marks.contains("bold"), italic: marks.contains("italic"))
        if marks.contains("code") { f = theme.font(size: size * 0.9, weight: .regular, design: .monospaced) }
        var a: [NSAttributedString.Key: Any] = [.font: f, .foregroundColor: theme.text]
        if marks.contains("strike") { a[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
        if marks.contains("link") || marks.contains("docLink") { a[.foregroundColor] = theme.accentColor }
        out.append(NSAttributedString(string: n.text ?? "", attributes: a))
    }
    return out
}

/// A simple table drawn in place. Clicking a cell starts editing it.
final class TableCell: BlockCell {
    static let rowHeight: CGFloat = 34
    override func height(forWidth w: CGFloat) -> CGFloat { CGFloat(max(1, node.content?.count ?? 1)) * Self.rowHeight + 2 }
    override func wantsToTrackMouse() -> Bool { true }

    func cellRect(row: Int, column: Int, in f: NSRect) -> NSRect {
        let cols = max(1, Tables.columnCount(node))
        let w = (f.width - 2) / CGFloat(cols)
        return NSRect(x: f.minX + 1 + CGFloat(column) * w, y: f.minY + 1 + CGFloat(row) * Self.rowHeight, width: w, height: Self.rowHeight)
    }

    override func trackMouse(with event: NSEvent, in cellFrame: NSRect, of controlView: NSView?, untilMouseUp flag: Bool) -> Bool {
        guard let tv = controlView, let id = node.id else { return true }
        let p = tv.convert(event.locationInWindow, from: nil)
        let cols = max(1, Tables.columnCount(node))
        let row = max(0, min((node.content?.count ?? 1) - 1, Int((p.y - cellFrame.minY) / Self.rowHeight)))
        let col = max(0, min(cols - 1, Int((p.x - cellFrame.minX) / ((cellFrame.width - 2) / CGFloat(cols)))))
        DispatchQueue.main.async { [weak controller] in controller?.tableEditor.begin(tableId: id, row: row, column: col) }
        return true
    }

    /// Where the table was last drawn, in text-view coordinates (the editor aligns to it).
    var drawnFrame: NSRect?

    override func draw(withFrame f: NSRect, in controlView: NSView?) {
        drawnFrame = f
        let rows = Tables.cells(node)
        let outer = NSBezierPath(roundedRect: f.insetBy(dx: 0.5, dy: 0.5), xRadius: 8, yRadius: 8)
        NSGraphicsContext.saveGraphicsState()
        outer.addClip()
        if !rows.isEmpty {
            theme.text.withAlphaComponent(theme.isDarkPage ? 0.1 : 0.045).setFill()
            NSRect(x: f.minX, y: f.minY, width: f.width, height: Self.rowHeight + 1).fill()
        }
        let line = theme.text.withAlphaComponent(0.13)
        line.setFill()
        for c in 1..<max(1, Tables.columnCount(node)) { NSRect(x: cellRect(row: 0, column: c, in: f).minX, y: f.minY, width: 1, height: f.height).fill() }
        for (r, row) in rows.enumerated() {
            // Drawing text resets the fill color, so set it again for each line.
            if r > 0 { line.setFill(); NSRect(x: f.minX, y: f.minY + CGFloat(r) * Self.rowHeight + 0.5, width: f.width, height: 1).fill() }
            for c in row.indices {
                let cr = cellRect(row: r, column: c, in: f)
                cellText(row[c].content, theme: theme, header: r == 0).draw(with: cr.insetBy(dx: 10, dy: 8), options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
            }
        }
        NSGraphicsContext.restoreGraphicsState()
        theme.text.withAlphaComponent(0.18).setStroke(); outer.lineWidth = 1; outer.stroke()
    }
}

/// Fields laid over a table's cells while it is edited. Each committed cell is one undo step.
public final class TableEditor: NSView, NSTextFieldDelegate {
    unowned let controller: EditorController
    public private(set) var tableId: String?
    var fields: [[NSTextField]] = []
    public private(set) var current: (row: Int, column: Int) = (0, 0)
    /// Set while the fields are replaced after a structural change: the old field ending its editing
    /// must not write its text into the changed table (it would land in a neighbouring cell).
    var rebuilding = false

    init(controller: EditorController) {
        self.controller = controller
        super.init(frame: .zero)
        setAccessibilityRole(.table)
        setAccessibilityLabel("Table editor")
    }
    required init?(coder: NSCoder) { fatalError() }
    public override var isFlipped: Bool { true }
    public override func resetCursorRects() { addCursorRect(bounds, cursor: .iBeam) }

    var table: (Node, NSRange)? {
        guard let id = tableId, let pr = controller.paragraph(withId: id), pr.length > 0,
              let a = controller.storage.attribute(.attachment, at: pr.location, effectiveRange: nil) as? BlockAttachment, a.node.type == "table" else { return nil }
        return (a.node, pr)
    }

    public func begin(tableId id: String, row: Int, column: Int) {
        tableId = id
        controller.overlayHost?.addSubview(self)
        rebuild()
        focus(row: row, column: column)
    }

    public func end() {
        commitCurrent()
        tableId = nil
        fields = []
        subviews.forEach { $0.removeFromSuperview() }
        removeFromSuperview()
    }

    public func reposition() {
        guard let (_, pr) = table, let host = controller.overlayHost else { return }
        let tv = controller.textView
        let cell = (controller.storage.attribute(.attachment, at: pr.location, effectiveRange: nil) as? BlockAttachment)?.attachmentCell as? TableCell
        if cell?.drawnFrame == nil { tv.displayIfNeeded() }
        if let f = cell?.drawnFrame { frame = tv.convert(f, to: host); return }
        let gr = controller.layout.glyphRange(forCharacterRange: NSRange(location: pr.location, length: 1), actualCharacterRange: nil)
        let r = controller.layout.boundingRect(forGlyphRange: gr, in: controller.container)
        frame = tv.convert(r.offsetBy(dx: tv.textContainerOrigin.x, dy: tv.textContainerOrigin.y), to: host)
    }

    func rebuild() {
        guard let (t, _) = table else { end(); return }
        reposition()
        subviews.forEach { $0.removeFromSuperview() }
        let rows = Tables.cells(t)
        let cols = max(1, Tables.columnCount(t))
        let w = (bounds.width - 2) / CGFloat(cols)
        fields = rows.enumerated().map { ri, row in
            (0..<cols).map { ci in
                let f = NSTextField(string: "")
                var lossy = Set<String>()
                f.stringValue = ci < row.count ? Markdown.inline(row[ci].content, &lossy) : ""
                f.isBordered = false; f.drawsBackground = true; f.focusRingType = .none
                f.backgroundColor = NSColor(hex: controller.theme.pageColor)
                f.textColor = controller.theme.text
                f.font = controller.theme.font(size: 14, weight: ri == 0 ? .semibold : .regular)
                f.delegate = self
                f.cell?.usesSingleLineMode = true
                f.cell?.lineBreakMode = .byTruncatingTail
                f.frame = NSRect(x: 1 + CGFloat(ci) * w + 9, y: 1 + CGFloat(ri) * TableCell.rowHeight + 7, width: w - 18, height: TableCell.rowHeight - 12)
                f.setAccessibilityLabel("Row \(ri + 1), column \(ci + 1)\(ri == 0 ? ", header" : "")")
                addSubview(f)
                return f
            }
        }
    }

    func focus(row: Int, column: Int) {
        guard fields.indices.contains(row), fields[row].indices.contains(column) else { return }
        current = (row, column)
        window?.makeFirstResponder(fields[row][column])
    }

    /// Write the focused field back into the table (one undo step when it changed).
    func commitCurrent() {
        guard let (t, pr) = table, fields.indices.contains(current.row), fields[current.row].indices.contains(current.column) else { return }
        let text = fields[current.row][current.column].stringValue
        var lossy = Set<String>()
        let cells = Tables.cells(t)
        let old = current.column < (cells[safe: current.row]?.count ?? 0) ? Markdown.inline(cells[current.row][current.column].content, &lossy) : ""
        guard text != old else { return }
        let changed = Tables.settingCell(t, row: current.row, column: current.column, inline: MarkdownImport.inline(text))
        controller.updateAttachment(at: pr.location) { $0 = changed }
    }

    func change(_ f: (Node) -> Node, focusRow: Int, focusColumn: Int) {
        commitCurrent()
        guard let (t, pr) = table else { return }
        rebuilding = true
        defer { rebuilding = false }
        controller.updateAttachment(at: pr.location) { $0 = f(t) }
        rebuild()
        focus(row: min(focusRow, fields.count - 1), column: min(focusColumn, (fields.first?.count ?? 1) - 1))
    }

    public func addRow() { change({ Tables.insertingRow($0, at: self.current.row + 1) }, focusRow: current.row + 1, focusColumn: current.column) }
    public func addColumn() { change({ Tables.insertingColumn($0, at: self.current.column + 1) }, focusRow: current.row, focusColumn: current.column + 1) }
    public func removeRow() { change({ Tables.removingRow($0, at: self.current.row) }, focusRow: max(0, current.row - 1), focusColumn: current.column) }
    public func removeColumn() { change({ Tables.removingColumn($0, at: self.current.column) }, focusRow: current.row, focusColumn: max(0, current.column - 1)) }

    public var isEditing: Bool { tableId != nil }

    /// Moves the current column (or row) one place; cells keep their ids, content and formatting,
    /// and one Undo puts it back.
    public func moveColumn(by d: Int) {
        let to = current.column + d, n = fields.first?.count ?? 0
        guard isEditing, to >= 0, to < n else { NSSound.beep(); return }
        change({ Tables.movingColumn($0, from: self.current.column, to: to) }, focusRow: current.row, focusColumn: to)
        controller.undo.setActionName("Move Column")
        announce("Column moved to position \(to + 1) of \(n)")
    }

    public func moveRow(by d: Int) {
        let to = current.row + d, n = fields.count
        guard isEditing, to >= 0, to < n else { NSSound.beep(); return }
        change({ Tables.movingRow($0, from: self.current.row, to: to) }, focusRow: to, focusColumn: current.column)
        controller.undo.setActionName("Move Row")
        announce("Row moved to position \(to + 1) of \(n)")
    }

    func announce(_ s: String) {
        NSAccessibility.post(element: fields[safe: current.row]?[safe: current.column] ?? self, notification: .announcementRequested,
                             userInfo: [.announcement: s, .priority: NSAccessibilityPriorityLevel.high.rawValue])
    }

    public func move(by d: Int) {
        let n = fields.count, m = fields.first?.count ?? 1
        let i = current.row * m + current.column + d
        guard i >= 0, i < n * m else { return }
        commitCurrent()
        focus(row: i / m, column: i % m)
    }

    public func controlTextDidBeginEditing(_ obj: Notification) {
        guard let f = obj.object as? NSTextField else { return }
        for (r, row) in fields.enumerated() { if let c = row.firstIndex(of: f) { current = (r, c) } }
    }
    public func controlTextDidEndEditing(_ obj: Notification) { if !rebuilding { commitCurrent() } }

    public func control(_ control: NSControl, textView: NSTextView, doCommandBy sel: Selector) -> Bool {
        switch sel {
        case #selector(NSResponder.insertTab(_:)): move(by: 1); return true
        case #selector(NSResponder.insertBacktab(_:)): move(by: -1); return true
        case #selector(NSResponder.insertNewline(_:)): if current.row + 1 < fields.count { commitCurrent(); focus(row: current.row + 1, column: current.column) } else { addRow() }; return true
        case #selector(NSResponder.cancelOperation(_:)):
            let id = tableId
            end()
            controller.textView.window?.makeFirstResponder(controller.textView)
            if let id { controller.selectBlocks(ids: [id]) }
            return true
        default: return false
        }
    }

    public override func performKeyEquivalent(with e: NSEvent) -> Bool {
        let mods = e.modifierFlags.intersection([.command, .option, .shift, .control])
        if mods == [.command, .option, .shift] {
            switch e.keyCode {
            case 123: moveColumn(by: -1); return true // ←
            case 124: moveColumn(by: 1); return true  // →
            case 126: moveRow(by: -1); return true    // ↑
            case 125: moveRow(by: 1); return true     // ↓
            default: break
            }
        }
        guard mods == [.command, .option] else { return super.performKeyEquivalent(with: e) }
        switch e.keyCode {
        case 125: addRow(); return true          // ↓
        case 124: addColumn(); return true       // →
        case 51: removeRow(); return true        // ⌫
        case 117: removeColumn(); return true    // ⌦
        default: return super.performKeyEquivalent(with: e)
        }
    }
}

extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}

/// A collection shown as a preview in the document; it opens in its own view.
final class CollectionCell: BlockCell {
    var data: CollectionData? { CollectionData(node: node) }
    override func height(forWidth w: CGFloat) -> CGFloat { 54 + CGFloat(min(5, data?.items.count ?? 0)) * 28 + ((data?.items.count ?? 0) > 5 ? 26 : 8) + 10 }
    override func wantsToTrackMouse() -> Bool { true }
    override func trackMouse(with event: NSEvent, in cellFrame: NSRect, of controlView: NSView?, untilMouseUp flag: Bool) -> Bool {
        if event.type == .leftMouseDown, let id = node.id { DispatchQueue.main.async { [weak controller] in controller?.linkHost?.openCollection(blockId: id) } }
        return true
    }
    override func draw(withFrame f: NSRect, in controlView: NSView?) {
        guard let c = data else { return }
        let r = f.insetBy(dx: 0, dy: 3)
        let box = NSBezierPath(roundedRect: r, xRadius: 12, yRadius: 12)
        theme.text.withAlphaComponent(theme.isDarkPage ? 0.07 : 0.03).setFill(); box.fill()
        theme.text.withAlphaComponent(0.13).setStroke(); box.lineWidth = 1; box.stroke()
        let symbol = c.view?.type == "kanban" ? "rectangle.split.3x1" : c.view?.type == "gallery" ? "square.grid.2x2" : "tablecells"
        NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?.withSymbolConfiguration(.init(paletteColors: [theme.accentColor]))?.draw(in: NSRect(x: r.minX + 14, y: r.minY + 16, width: 18, height: 16))
        (c.name as NSString).draw(at: NSPoint(x: r.minX + 40, y: r.minY + 13), withAttributes: [.font: theme.font(size: 16, weight: .semibold), .foregroundColor: theme.text])
        let meta = "\(c.items.count) item\(c.items.count == 1 ? "" : "s") · \(c.view?.name ?? "Table") · Open ›"
        let ma: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: theme.secondary]
        let mw = (meta as NSString).size(withAttributes: ma).width
        (meta as NSString).draw(at: NSPoint(x: r.maxX - mw - 14, y: r.minY + 17), withAttributes: ma)
        let shown = Array(c.items.prefix(5))
        let cols = [CollectionData.titleField] + c.fields.prefix(2).map(\.id)
        let cw = (r.width - 28) / CGFloat(cols.count)
        let title: (String) -> String = { [weak controller] id in controller?.host?.pageInfo(docId: id)?.title.nilIfEmpty ?? "Untitled" }
        let ps = NSMutableParagraphStyle(); ps.lineBreakMode = .byTruncatingTail
        for (i, it) in shown.enumerated() {
            let y = r.minY + 48 + CGFloat(i) * 28
            theme.text.withAlphaComponent(0.08).setFill(); NSRect(x: r.minX + 14, y: y, width: r.width - 28, height: 1).fill()
            for (k, fid) in cols.enumerated() {
                (c.display(it, fid, title: title) as NSString).draw(in: NSRect(x: r.minX + 14 + CGFloat(k) * cw, y: y + 6, width: cw - 10, height: 18),
                                                                  withAttributes: [.font: theme.font(size: 13, weight: k == 0 ? .medium : .regular), .foregroundColor: k == 0 ? theme.text : theme.secondary, .paragraphStyle: ps])
            }
        }
        if c.items.count > 5 { ("+ \(c.items.count - 5) more" as NSString).draw(at: NSPoint(x: r.minX + 14, y: r.minY + 48 + 5 * 28 + 4), withAttributes: ma) }
        if c.items.isEmpty { ("Empty — open it to add items" as NSString).draw(at: NSPoint(x: r.minX + 14, y: r.minY + 46), withAttributes: ma) }
    }
}

public extension String { var nilIfEmpty: String? { isEmpty ? nil : self } }

extension EditorController {
    /// An attachment block's node, read from the attachment instead of converting the document.
    public func attachmentNode(blockId: String) -> Node? {
        guard let pr = paragraph(withId: blockId), pr.length > 0 else { return nil }
        return (storage.attribute(.attachment, at: pr.location, effectiveRange: nil) as? BlockAttachment)?.node
    }

    /// Replace a block's attachment node without an undo step in this document (the app records
    /// the change in the view that made it, e.g. the collection screen).
    public func replaceAttachmentQuietly(blockId: String, with node: Node) -> Bool {
        guard let pr = paragraph(withId: blockId), pr.length > 0, let a = storage.attribute(.attachment, at: pr.location, effectiveRange: nil) as? BlockAttachment else { return false }
        a.node = node
        storage.addAttribute(.draftBlock, value: block(at: pr).with(raw: .some(node)), range: pr)
        layout.invalidateLayout(forCharacterRange: pr, actualCharacterRange: nil)
        layout.invalidateDisplay(forCharacterRange: pr)
        textView.needsDisplay = true
        host?.editorDidChange()
        return true
    }
}
