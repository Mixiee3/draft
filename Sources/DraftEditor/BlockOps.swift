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

    /// Replace the whole document with `flat` as ONE undo step, then select the given blocks.
    func rebuild(_ flat: [FlatBlock], select ids: [String], blockMode: Bool) {
        let (s, newTrailing) = Converter.attributed(flat: flat)
        undoGroup {
            setTrailingUndoable(newTrailing)
            replace(NSRange(location: 0, length: storage.length), with: s)
        }
        if blockMode { selectBlocks(ids: ids) }
        else if let first = ids.first, let pr = paragraph(withId: first) { textView.setSelectedRange(NSRange(location: pr.location, length: 0)) }
        textView.scrollRangeToVisible(textView.selectedRange())
        host?.editorDidChange()
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
        textView.selectedTextAttributes = [.backgroundColor: NSColor.clear]
        textView.setSelectedRange(union)
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
        textView.selectedTextAttributes = [.backgroundColor: theme.accentColor.withAlphaComponent(theme.isDarkPage ? 0.45 : 0.22)]
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
        textView.selectedTextAttributes = [.backgroundColor: theme.accentColor.withAlphaComponent(theme.isDarkPage ? 0.45 : 0.22)]
        rebuild(flat, select: next.map { [$0] } ?? [], blockMode: false)
        if let n = next, let pr = paragraph(withId: n) { textView.setSelectedRange(NSRange(location: NSMaxRange(contentRange(pr)), length: 0)) }
    }

    /// Called on every selection change: leaving the expected range ends block mode.
    func selectionChangedForBlockMode() {
        guard isBlockMode, let e = expectedBlockSelection else { return }
        if textView.selectedRange() != e {
            blockSelectionIds = []
            expectedBlockSelection = nil
            textView.selectedTextAttributes = [.backgroundColor: theme.accentColor.withAlphaComponent(theme.isDarkPage ? 0.45 : 0.22)]
            layout.invalidateDisplay(forCharacterRange: NSRange(location: 0, length: storage.length))
        }
    }
}
