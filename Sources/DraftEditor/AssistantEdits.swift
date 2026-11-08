import AppKit
import DraftCore

/// What the Assistant reads from and writes to a document. Writes go through the paste path,
/// so structure survives and each accepted change is one undo step.
extension EditorController {
    /// The selection widened to whole blocks, or nil when nothing is selected.
    public var selectedBlocksRange: NSRange? {
        let sel = textView.selectedRange()
        guard sel.length > 0 else { return nil }
        let first = paragraphRange(at: sel.location)
        let last = paragraphRange(at: max(sel.location, NSMaxRange(sel) - 1))
        return NSRange(location: first.location, length: NSMaxRange(last) - first.location)
    }

    public func fragment(_ range: NSRange) -> Node {
        var range = range
        if range.length > 0, (storage.string as NSString).character(at: NSMaxRange(range) - 1) == 10 { range.length -= 1 }
        let sub = storage.attributedSubstring(from: range)
        let last = (sub.length > 0 ? sub.attribute(.draftBlock, at: sub.length - 1, effectiveRange: nil) as? BlockInfo : nil) ?? .paragraph()
        return Converter.document(from: sub, trailing: last)
    }

    /// Replaces `range` with `markdown` (or inserts it as new blocks after `range` when `replace` is false).
    public func applyAssistant(_ markdown: String, range: NSRange, replace: Bool, actionName: String) {
        var flat = Converter.flatten(ensureBlockIds(Node("doc", content: MarkdownImport.blocks(markdown))))
        guard !flat.isEmpty else { return }
        let end = min(NSMaxRange(range), storage.length)
        if replace {
            var r = range
            if r.length > 0, NSMaxRange(r) <= storage.length, (storage.string as NSString).character(at: NSMaxRange(r) - 1) == 10 { r.length -= 1 }
            textView.setSelectedRange(r)
        } else {
            let pr = paragraphRange(at: max(0, end - 1))
            textView.setSelectedRange(NSRange(location: NSMaxRange(contentRange(pr)), length: 0))
            flat.insert(FlatBlock(info: .paragraph(), inline: []), at: 0)
        }
        insertFragment(flat)
        undo.setActionName(actionName)
    }
}
