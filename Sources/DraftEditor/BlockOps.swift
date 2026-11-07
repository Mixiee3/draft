import AppKit
import DraftCore

/// Whole-block operations: block selection, move up/down, drag reorder, delete.
/// Blocks are moved by rebuilding the text from the flat block list, so ids, marks and
/// attachments travel unchanged, and each operation is a single undo step.
extension EditorController {
    func flatBlocks() -> [FlatBlock] { Converter.flat(from: storage, trailing: trailing) }

    /// Index of the paragraph (flat block) that contains `loc`.
    func blockIndex(at loc: Int) -> Int {
        let end = min(loc, storage.length)
        var n = 0
        ns.enumerateSubstrings(in: NSRange(location: 0, length: end), options: [.byComposedCharacterSequences]) { s, _, _, _ in if s == "\n" { n += 1 } }
        return n
    }

    /// Indices of the blocks touched by the current selection (or block selection).
    public var selectedBlockRange: ClosedRange<Int> {
        let sel = textView.selectedRange()
        let a = blockIndex(at: sel.location)
        var endLoc = NSMaxRange(sel)
        // A selection that ends right after a newline does not include the next block.
        if sel.length > 0, endLoc > 0, ns.character(at: endLoc - 1) == 10 { endLoc -= 1 }
        return a...max(a, blockIndex(at: endLoc))
    }

    /// Make the document equal `flat` as ONE undo step, replacing only the paragraphs that
    /// differ (unchanged blocks, their attachments and the undo selection stay put), then select
    /// the given blocks.
    func rebuild(_ flat: [FlatBlock], select ids: [String], blockMode: Bool, alsoUndo: (() -> Void)? = nil) {
        let (s, newTrailing) = Converter.attributed(flat: flat)
        let old = flatBlocks()
        let oldParas = Self.paragraphStarts(storage), newParas = Self.paragraphStarts(s)
        func same(_ a: FlatBlock, _ b: FlatBlock) -> Bool { a.info.isEqual(b.info) && a.inline == b.inline }
        // Common leading/trailing paragraphs (a prefix paragraph must end with a newline in both).
        var p = 0
        while p < min(old.count, flat.count) - 1, same(old[p], flat[p]) { p += 1 }
        var t = 0
        while t < min(old.count, flat.count) - p, same(old[old.count - 1 - t], flat[flat.count - 1 - t]) { t += 1 }
        let oldRange = NSRange(location: oldParas[p], length: (t > 0 ? oldParas[old.count - t] : storage.length) - oldParas[p])
        let newRange = NSRange(location: newParas[p], length: (t > 0 ? newParas[flat.count - t] : s.length) - newParas[p])
        undoGroup {
            alsoUndo?()
            setTrailingUndoable(newTrailing)
            if oldRange.length > 0 || newRange.length > 0 { replace(oldRange, with: s.attributedSubstring(from: newRange)) }
        }
        if blockMode { selectBlocks(ids: ids) }
        else if let first = ids.first, let pr = paragraph(withId: first) { textView.setSelectedRange(NSRange(location: pr.location, length: 0)) }
        textView.scrollRangeToVisible(textView.selectedRange())
        host?.editorDidChange()
    }

    /// Start offset of every paragraph, plus one for the empty trailing paragraph when the text
    /// ends with a newline (matching `Converter.flat`).
    static func paragraphStarts(_ s: NSAttributedString) -> [Int] {
        let ns = s.string as NSString
        var out: [Int] = []
        var loc = 0
        while loc < ns.length { out.append(loc); loc = NSMaxRange(ns.paragraphRange(for: NSRange(location: loc, length: 0))) }
        if ns.length == 0 || ns.character(at: ns.length - 1) == 10 { out.append(ns.length) }
        return out
    }

    func setTrailingUndoable(_ b: BlockInfo) {
        let old = trailing
        textView.undoManager?.registerUndo(withTarget: self) { $0.setTrailingUndoable(old) }
        trailing = b
    }

    /// Move blocks a...b so they start at boundary `to` (0…count, measured before removal).
    public func moveBlocks(_ range: ClosedRange<Int>, to boundary: Int) {
        var flat = flatBlocks()
        guard range.upperBound < flat.count, boundary >= 0, boundary <= flat.count else { return }
        if boundary >= range.lowerBound && boundary <= range.upperBound + 1 { return } // no-op
        let moving = Array(flat[range])
        flat.removeSubrange(range)
        let dest = boundary > range.upperBound ? boundary - moving.count : boundary
        flat.insert(contentsOf: moving, at: dest)
        rebuild(flat, select: moving.map(\.info.id), blockMode: isBlockMode)
    }

    public func moveSelectedBlocks(by delta: Int) {
        let r = selectedBlockRange
        let count = flatBlocks().count
        if delta < 0 { guard r.lowerBound > 0 else { NSSound.beep(); return }; moveBlocks(r, to: r.lowerBound - 1) }
        else { guard r.upperBound < count - 1 else { NSSound.beep(); return }; moveBlocks(r, to: r.upperBound + 2) }
    }

    public func moveSelectedBlocksToEdge(top: Bool) {
        let r = selectedBlockRange
        moveBlocks(r, to: top ? 0 : flatBlocks().count)
    }

    // MARK: Block selection mode

    public var isBlockMode: Bool { !blockSelectionIds.isEmpty }

    public func selectBlocks(ids: [String]) {
        let ranges = ids.compactMap { paragraph(withId: $0) }
        guard let first = ranges.first, let last = ranges.last else { exitBlockMode(); return }
        var union = NSUnionRange(first, last)
        // Keep the final newline out so the selection reads as "these blocks".
        if union.length > 0, NSMaxRange(union) <= storage.length, NSMaxRange(union) > 0, ns.character(at: NSMaxRange(union) - 1) == 10 { union.length -= 1 }
        blockSelectionIds = ids
        expectedBlockSelection = union
        textView.setSelectedRange(union)
        refreshSelectionStyle()
        layout.invalidateDisplay(forCharacterRange: NSRange(location: 0, length: storage.length))
        toolbar.update()
        host?.editorStateDidChange()
    }

    /// Esc: select the block(s) around the caret / selection.
    public func enterBlockMode() {
        let flat = flatBlocks()
        let ids = flat[selectedBlockRange].map(\.info.id)
        selectBlocks(ids: ids)
    }

    public func exitBlockMode(caretAtEnd: Bool = false) {
        guard isBlockMode else { return }
        let sel = textView.selectedRange()
        blockSelectionIds = []
        expectedBlockSelection = nil
        refreshSelectionStyle()
        textView.setSelectedRange(NSRange(location: caretAtEnd ? NSMaxRange(sel) : sel.location, length: 0))
        layout.invalidateDisplay(forCharacterRange: NSRange(location: 0, length: storage.length))
        host?.editorStateDidChange()
    }

    /// ↑/↓ in block mode; with `extend`, grow/shrink from the anchor.
    public func stepBlockSelection(_ delta: Int, extend: Bool) {
        let flat = flatBlocks()
        let idx = blockSelectionIds.compactMap { id in flat.firstIndex { $0.info.id == id } }.sorted()
        guard let lo = idx.first, let hi = idx.last else { return }
        if extend {
            let newHi = min(max(hi + delta, lo), flat.count - 1)
            let newLo = delta < 0 && hi == lo ? max(lo - 1, 0) : lo
            selectBlocks(ids: flat[newLo...max(newLo, newHi)].map(\.info.id))
        } else {
            let i = min(max((delta < 0 ? lo : hi) + delta, 0), flat.count - 1)
            selectBlocks(ids: [flat[i].info.id])
        }
    }

    public func deleteSelectedBlocks() {
        var flat = flatBlocks()
        let r = selectedBlockRange
        let next = r.lowerBound > 0 ? flat[r.lowerBound - 1].info.id : nil
        flat.removeSubrange(r)
        blockSelectionIds = []
        expectedBlockSelection = nil
        refreshSelectionStyle()
        rebuild(flat, select: next.map { [$0] } ?? [], blockMode: false)
        if let n = next, let pr = paragraph(withId: n) { textView.setSelectedRange(NSRange(location: NSMaxRange(contentRange(pr)), length: 0)) }
    }

    /// Called on every selection change: leaving the expected range ends block mode.
    func selectionChangedForBlockMode() {
        guard isBlockMode, let e = expectedBlockSelection else { return }
        if textView.selectedRange() != e {
            blockSelectionIds = []
            expectedBlockSelection = nil
            refreshSelectionStyle()
            layout.invalidateDisplay(forCharacterRange: NSRange(location: 0, length: storage.length))
        }
    }
}
