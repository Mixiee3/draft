import AppKit
import DraftCore

/// Maps formatted text from other apps (RTF/HTML on the pasteboard) to Draft blocks and marks.
/// Only semantics are kept: headings by relative size, lists, bold/italic/underline/strike,
/// monospace → code, links. Foreign fonts and colors are dropped on purpose.
enum RichImport {
    static func blocks(from s: NSAttributedString) -> [FlatBlock] {
        let ns = s.string as NSString
        guard ns.length > 0 else { return [] }
        // Body size = the most common font size.
        var sizes: [CGFloat: Int] = [:]
        s.enumerateAttribute(.font, in: NSRange(location: 0, length: ns.length)) { v, r, _ in
            if let f = v as? NSFont { sizes[f.pointSize.rounded(), default: 0] += r.length }
        }
        let body = sizes.max { $0.value < $1.value }?.key ?? 13
        var out: [FlatBlock] = []
        var loc = 0
        while loc < ns.length {
            let pr = ns.paragraphRange(for: NSRange(location: loc, length: 0))
            loc = NSMaxRange(pr)
            var content = pr
            while content.length > 0, [10, 13, 0x2029].contains(ns.character(at: NSMaxRange(content) - 1)) { content.length -= 1 }
            let ps = s.attribute(.paragraphStyle, at: pr.location, effectiveRange: nil) as? NSParagraphStyle
            var info = BlockInfo()
            if let lists = ps?.textLists, let list = lists.last {
                let f = list.markerFormat.rawValue
                let ordered = f.contains("decimal") || f.contains("alpha") || f.contains("roman")
                info = BlockInfo(kind: ordered ? .ordered : .bullet, indent: max(0, lists.count - 1))
                // AppKit puts the marker text ("\t•\t", "\t1.\t") into the string; drop it.
                let text = ns.substring(with: content)
                if let m = text.range(of: #"^\t?[^\t]{0,8}\t"#, options: .regularExpression) {
                    let cut = (String(text[m]) as NSString).length
                    content = NSRange(location: content.location + cut, length: content.length - cut)
                }
            }
            if content.length == 0 && info.kind == .paragraph { continue } // blank lines separate blocks
            var maxSize: CGFloat = 0
            s.enumerateAttribute(.font, in: content) { v, _, _ in if let f = v as? NSFont { maxSize = max(maxSize, f.pointSize) } }
            if info.kind == .paragraph, maxSize > 0 {
                let ratio = maxSize / body
                if ratio >= 1.6 { info = BlockInfo(kind: .heading, level: 1) }
                else if ratio >= 1.3 { info = BlockInfo(kind: .heading, level: 2) }
                else if ratio >= 1.12 { info = BlockInfo(kind: .heading, level: 3) }
            }
            var inline: [Node] = []
            s.enumerateAttributes(in: content) { a, r, _ in
                let t = ns.substring(with: r).replacingOccurrences(of: "\u{2028}", with: "\n")
                guard !t.isEmpty else { return }
                var marks: [Mark] = []
                if let f = a[.font] as? NSFont {
                    let traits = f.fontDescriptor.symbolicTraits
                    if traits.contains(.bold) && info.kind != .heading { marks.append(Mark("bold")) }
                    if traits.contains(.italic) { marks.append(Mark("italic")) }
                    if traits.contains(.monoSpace) { marks.append(Mark("code")) }
                }
                if let u = a[.underlineStyle] as? Int, u != 0, a[.link] == nil { marks.append(Mark("underline")) }
                if let st = a[.strikethroughStyle] as? Int, st != 0 { marks.append(Mark("strike")) }
                if let l = a[.link] { marks.append(Mark("link", attrs: ["href": .string((l as? URL)?.absoluteString ?? "\(l)")])) }
                for (i, part) in t.components(separatedBy: "\n").enumerated() {
                    if i > 0 { inline.append(Node("hardBreak")) }
                    if !part.isEmpty { inline.append(.text(part, marks: marks.isEmpty ? nil : marks)) }
                }
            }
            out.append(FlatBlock(info: info, inline: inline))
        }
        return out
    }
}

extension EditorController {
    /// Insert pasted blocks at the selection. The first pasted line joins the text before the
    /// caret and the last joins the text after it, so the surrounding block keeps its id and
    /// type; everything in between arrives as its own blocks. One undo step.
    func insertFragment(_ input: [FlatBlock]) {
        guard !input.isEmpty else { return }
        if isBlockMode { exitBlockMode(caretAtEnd: true) }
        var flat = input
        undoGroup {
            var sel = textView.selectedRange()
            if sel.length > 0 { replace(sel, with: NSAttributedString(), select: NSRange(location: sel.location, length: 0)); sel.length = 0 }
            var pr = paragraphRange(at: sel.location)
            if block(at: pr).kind.isAttachment { insertParagraphAfter(pr); sel = textView.selectedRange(); pr = paragraphRange(at: sel.location) }
            let b = block(at: pr)
            let content = contentRange(pr)
            let hasBefore = sel.location > content.location
            let hasAfter = sel.location < NSMaxRange(content)
            // Single text block: inline paste that keeps the current block.
            if flat.count == 1, !flat[0].info.kind.isAttachment {
                let s = Converter.attributed(flat: flat).0.mutableCopy() as! NSMutableAttributedString
                s.addAttribute(.draftBlock, value: b, range: NSRange(location: 0, length: s.length))
                replace(sel, with: s, select: NSRange(location: sel.location + s.length, length: 0))
                return
            }
            // Attachments never share a paragraph with text.
            if hasBefore, flat.first?.info.kind.isAttachment == true { flat.insert(FlatBlock(info: .paragraph(), inline: []), at: 0) }
            if flat.last?.info.kind.isAttachment == true { flat.append(FlatBlock(info: .paragraph(), inline: [])) }
            let (s, lastInfo) = Converter.attributed(flat: flat)
            replace(sel, with: s, select: NSRange(location: sel.location + s.length, length: 0))
            let endLoc = sel.location + s.length
            if hasBefore { setBlock(paragraphRange(at: sel.location), b) }
            let endPara = paragraphRange(at: endLoc)
            setBlock(endPara, hasAfter && !hasBefore ? b : lastInfo)
            textView.setSelectedRange(NSRange(location: endLoc, length: 0))
            dedupeAll()
        }
        textView.scrollRangeToVisible(textView.selectedRange())
        host?.editorDidChange()
    }

    func pasteFragment(_ data: Data) -> Bool {
        guard let node = try? JSONDecoder().decode(Node.self, from: data) else { return false }
        insertFragment(Converter.flatten(reId(node)))
        return true
    }

    func pastePlain(_ text: String) {
        let t = text.replacingOccurrences(of: "\r\n", with: "\n")
        if !t.contains("\n") { textView.insertText(t, replacementRange: textView.selectedRange()); return }
        let inCode = currentBlock.kind == .code
        if inCode { textView.insertText(t.replacingOccurrences(of: "\n", with: Chars.lineBreak), replacementRange: textView.selectedRange()); return }
        insertFragment(Converter.flatten(ensureBlockIds(Node("doc", content: MarkdownImport.blocks(t)))))
    }

    /// Same path as a ⌘V of plain text (used by the app's automation).
    public func pastePlainForAutomation(_ text: String) { pastePlain(text) }

    func pasteRich(_ s: NSAttributedString) {
        let flat = RichImport.blocks(from: s)
        if flat.isEmpty { pastePlain(s.string); return }
        insertFragment(flat.map { FlatBlock(info: $0.info.with(id: newId("b_")), inline: $0.inline) })
    }
}
