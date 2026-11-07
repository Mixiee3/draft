import AppKit
import DraftCore

/// One command, shared by every entry point: selection toolbar, `Aa` panel, slash menu,
/// `+` insert menu, menu bar and keyboard shortcuts.
public struct EditorCommand: Identifiable {
    public let id: String
    public let title: String
    public let symbol: String
    public let group: String
    public let keywords: [String]
    /// Display form, e.g. "⌘B".
    public let shortcut: String?
    /// For menu bar registration.
    public let key: String?
    public let modifiers: NSEvent.ModifierFlags
    /// When non-nil, the command is not available yet and names the planned version.
    public let plannedFor: String?
    public let isActive: (EditorController) -> Bool
    public let isEnabled: (EditorController) -> Bool
    public let run: (EditorController) -> Void

    init(_ id: String, _ title: String, _ symbol: String, group: String, keywords: [String] = [], shortcut: String? = nil, key: String? = nil, modifiers: NSEvent.ModifierFlags = [], plannedFor: String? = nil,
         isActive: @escaping (EditorController) -> Bool = { _ in false }, isEnabled: @escaping (EditorController) -> Bool = { _ in true }, run: @escaping (EditorController) -> Void = { _ in }) {
        self.id = id; self.title = title; self.symbol = symbol; self.group = group; self.keywords = keywords; self.shortcut = shortcut
        self.key = key; self.modifiers = modifiers; self.plannedFor = plannedFor; self.isActive = isActive; self.isEnabled = isEnabled; self.run = run
    }

    public func matches(_ q: String) -> Bool {
        guard !q.isEmpty else { return true }
        let q = q.lowercased()
        return title.lowercased().contains(q) || keywords.contains { $0.hasPrefix(q) } || id.contains(q)
    }
}

public enum EditorCommands {
    static func textBlock(_ c: EditorController) -> Bool { !c.currentBlock.kind.isAttachment }

    public static let all: [EditorCommand] = [
        // Text styles (semantic block types)
        EditorCommand("block.title", "Title", "textformat.size.larger", group: "Text", keywords: ["h1", "heading", "title"], shortcut: "⌘⌥1", key: "1", modifiers: [.command, .option],
                      isActive: { $0.isBlockKind(.heading, level: 1) }, isEnabled: textBlock, run: { $0.setBlockKind(.heading, level: 1) }),
        EditorCommand("block.subtitle", "Subtitle", "textformat.size", group: "Text", keywords: ["h2", "heading", "subtitle"], shortcut: "⌘⌥2", key: "2", modifiers: [.command, .option],
                      isActive: { $0.isBlockKind(.heading, level: 2) }, isEnabled: textBlock, run: { $0.setBlockKind(.heading, level: 2) }),
        EditorCommand("block.heading", "Heading", "textformat", group: "Text", keywords: ["h3", "heading"], shortcut: "⌘⌥3", key: "3", modifiers: [.command, .option],
                      isActive: { $0.isBlockKind(.heading, level: 3) }, isEnabled: textBlock, run: { $0.setBlockKind(.heading, level: 3) }),
        EditorCommand("block.strong", "Strong", "bold", group: "Text", keywords: ["h4", "strong", "emphasis"], shortcut: "⌘⌥4", key: "4", modifiers: [.command, .option],
                      isActive: { $0.isBlockKind(.heading, level: 4) }, isEnabled: textBlock, run: { $0.setBlockKind(.heading, level: 4) }),
        EditorCommand("block.body", "Body", "text.alignleft", group: "Text", keywords: ["paragraph", "text", "body", "normal"], shortcut: "⌘⌥0", key: "0", modifiers: [.command, .option],
                      isActive: { $0.isBlockKind(.paragraph) }, isEnabled: textBlock, run: { $0.setBlockKind(.paragraph) }),
        EditorCommand("block.caption", "Caption", "textformat.size.smaller", group: "Text", keywords: ["caption", "small", "note"],
                      isActive: { $0.isBlockKind(.paragraph, variant: "caption") }, isEnabled: textBlock, run: { $0.setBlockKind(.paragraph, variant: "caption") }),
        EditorCommand("block.quote", "Quote", "text.quote", group: "Text", keywords: ["quote", "blockquote", "citation"],
                      isActive: { $0.isBlockKind(.quote) }, isEnabled: textBlock, run: { $0.setBlockKind(.quote) }),
        EditorCommand("block.code", "Code Block", "curlybraces", group: "Text", keywords: ["code", "snippet", "pre"],
                      isActive: { $0.isBlockKind(.code) }, isEnabled: textBlock, run: { $0.setBlockKind(.code) }),
        // Lists
        EditorCommand("list.bullet", "Bulleted List", "list.bullet", group: "Lists", keywords: ["bullet", "list", "ul"], shortcut: "⌘⇧8", key: "8", modifiers: [.command, .shift],
                      isActive: { $0.isBlockKind(.bullet) }, isEnabled: textBlock, run: { $0.toggleList(.bullet) }),
        EditorCommand("list.ordered", "Numbered List", "list.number", group: "Lists", keywords: ["number", "ordered", "ol"], shortcut: "⌘⇧7", key: "7", modifiers: [.command, .shift],
                      isActive: { $0.isBlockKind(.ordered) }, isEnabled: textBlock, run: { $0.toggleList(.ordered) }),
        EditorCommand("list.task", "Checklist", "checklist", group: "Lists", keywords: ["todo", "task", "check"], shortcut: "⌘⇧9", key: "9", modifiers: [.command, .shift],
                      isActive: { $0.isBlockKind(.task) }, isEnabled: textBlock, run: { $0.toggleList(.task) }),
        EditorCommand("list.toggle", "Toggle List", "chevron.right.square", group: "Lists", keywords: ["toggle", "collapse"], plannedFor: "v0.2", isEnabled: { _ in false }),
        // Insert
        EditorCommand("insert.page", "Page", "doc.text", group: "Insert", keywords: ["page", "subpage", "nested"], run: { $0.insertPage(presentation: "page") }),
        EditorCommand("insert.card", "Card", "rectangle.portrait.on.rectangle.portrait", group: "Insert", keywords: ["card", "page"], run: { $0.insertPage(presentation: "card") }),
        EditorCommand("insert.image", "Image", "photo", group: "Insert", keywords: ["image", "picture", "photo"], run: { $0.insertImageFromPicker() }),
        EditorCommand("insert.divider", "Separator", "minus", group: "Insert", keywords: ["divider", "separator", "line", "hr"], run: { $0.insertDivider() }),
        EditorCommand("insert.file", "File", "paperclip", group: "Insert", keywords: ["file", "attachment"], plannedFor: "v0.2", isEnabled: { _ in false }),
        EditorCommand("insert.table", "Table", "tablecells", group: "Insert", keywords: ["table"], plannedFor: "v0.5", isEnabled: { _ in false }),
        EditorCommand("insert.collection", "Collection", "square.grid.3x2", group: "Insert", keywords: ["collection", "database"], plannedFor: "v0.5", isEnabled: { _ in false }),
        EditorCommand("insert.formula", "Formula", "function", group: "Insert", keywords: ["math", "equation"], plannedFor: "later", isEnabled: { _ in false }),
        EditorCommand("insert.pagebreak", "Page Break", "arrow.down.to.line", group: "Insert", keywords: ["break"], plannedFor: "v0.2", isEnabled: { _ in false }),
        // Inline marks
        EditorCommand("mark.bold", "Bold", "bold", group: "Format", shortcut: "⌘B", key: "b", modifiers: [.command], isActive: { $0.isMarkActive(.bold) }, run: { $0.toggleMark(.bold) }),
        EditorCommand("mark.italic", "Italic", "italic", group: "Format", shortcut: "⌘I", key: "i", modifiers: [.command], isActive: { $0.isMarkActive(.italic) }, run: { $0.toggleMark(.italic) }),
        EditorCommand("mark.underline", "Underline", "underline", group: "Format", shortcut: "⌘U", key: "u", modifiers: [.command], isActive: { $0.isMarkActive(.underline) }, run: { $0.toggleMark(.underline) }),
        EditorCommand("mark.strike", "Strikethrough", "strikethrough", group: "Format", shortcut: "⌘⇧X", key: "x", modifiers: [.command, .shift], isActive: { $0.isMarkActive(.strike) }, run: { $0.toggleMark(.strike) }),
        EditorCommand("mark.code", "Inline Code", "chevron.left.forwardslash.chevron.right", group: "Format", shortcut: "⌘E", key: "e", modifiers: [.command], isActive: { $0.isMarkActive(.code) }, run: { $0.toggleMark(.code) }),
        EditorCommand("mark.link", "Link…", "link", group: "Format", shortcut: "⌘K", key: "k", modifiers: [.command], isEnabled: { $0.textView.selectedRange().length > 0 },
                      run: { c in c.toolbar.update(); c.toolbar.openLink() }),
        EditorCommand("mark.reapply", "Reapply Last Color", "paintbrush.pointed", group: "Format", shortcut: "⌘⇧B", key: "b", modifiers: [.command, .shift], isEnabled: { $0.lastColor != nil }, run: { $0.reapplyLastColor() }),
        EditorCommand("block.moveUp", "Move Block Up", "arrow.up", group: "Blocks", shortcut: "⌥⌘↑", key: "up", modifiers: [.command, .option], run: { $0.moveSelectedBlocks(by: -1) }),
        EditorCommand("block.moveDown", "Move Block Down", "arrow.down", group: "Blocks", shortcut: "⌥⌘↓", key: "down", modifiers: [.command, .option], run: { $0.moveSelectedBlocks(by: 1) }),
        EditorCommand("block.moveTop", "Move Block to Top", "arrow.up.to.line", group: "Blocks", shortcut: "⌃⌥⌘↑", key: "up", modifiers: [.command, .option, .control], run: { $0.moveSelectedBlocksToEdge(top: true) }),
        EditorCommand("block.moveBottom", "Move Block to Bottom", "arrow.down.to.line", group: "Blocks", shortcut: "⌃⌥⌘↓", key: "down", modifiers: [.command, .option, .control], run: { $0.moveSelectedBlocksToEdge(top: false) }),
        EditorCommand("block.select", "Select Block", "rectangle.dashed", group: "Blocks", shortcut: "Esc", run: { c in c.isBlockMode ? c.exitBlockMode() : c.enterBlockMode() }),
        EditorCommand("block.delete", "Delete Block", "trash", group: "Blocks", isEnabled: { $0.isBlockMode }, run: { $0.deleteSelectedBlocks() }),
        EditorCommand("block.indent", "Indent", "increase.indent", group: "Format", shortcut: "⇥", isEnabled: { $0.canIndent }, run: { $0.indent() }),
        EditorCommand("block.outdent", "Outdent", "decrease.indent", group: "Format", shortcut: "⇧⇥", isEnabled: { $0.canOutdent }, run: { $0.outdent() }),
    ]

    public static func command(_ id: String) -> EditorCommand? { all.first { $0.id == id } }
    public static var slashCommands: [EditorCommand] { all.filter { ["Text", "Lists", "Insert"].contains($0.group) } }
}
