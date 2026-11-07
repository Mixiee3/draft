import Foundation

/// First-run content (original Draft copy): a folder, a scenic welcome doc with a nested page,
/// and a calm note.
public enum Seed {
    static func t(_ s: String, _ marks: [Mark] = []) -> Node { .text(s, marks: marks.isEmpty ? nil : marks) }
    static func code(_ s: String) -> Node { t(s, [Mark("code")]) }
    static func p(_ c: [Node]) -> Node { Node("paragraph", content: c.isEmpty ? nil : c) }
    static func p(_ s: String) -> Node { p(s.isEmpty ? [] : [t(s)]) }
    static func h(_ l: Int, _ s: String) -> Node { Node("heading", attrs: ["level": .number(Double(l))], content: [t(s)]) }
    static func li(_ c: [Node]) -> Node { Node("listItem", content: [p(c)]) }
    static func ul(_ items: [Node]) -> Node { Node("bulletList", content: items) }
    static func ol(_ items: [Node]) -> Node { Node("orderedList", attrs: ["start": 1], content: items) }
    static func task(_ done: Bool, _ s: String) -> Node { Node("taskItem", attrs: ["checked": .bool(done)], content: [p(s)]) }

    public static func firstRun() -> (library: Library, docs: [DocFile]) {
        var lib = Library.empty()
        let now = nowMs()
        let folder = Folder(name: "Getting Started", color: "#5b6cf0", createdAt: now)
        lib.folders = [folder]
        lib.expandedFolders = [folder.id]
        let welcomeId = newId("d_"), keysId = newId("d_"), quietId = newId("d_")

        func doc(_ id: String, _ title: String, _ style: String, _ blocks: [Node], _ at: Double) -> DocFile {
            DocFile(id: id, title: title, content: ensureBlockIds(Node("doc", content: blocks)), appearance: DocumentAppearance(styleId: style), createdAt: at, updatedAt: at)
        }

        let welcome = doc(welcomeId, "Welcome to Draft", "tidepool", [
            p("Draft is a quiet place to think. Start with a sentence and let structure appear when it helps. Everything you write stays on this Mac as plain files you own."),
            h(2, "Start writing"),
            ul([
                li([t("Press "), code("⌘N"), t(" for a new document and just type.")]),
                li([t("Select any words to bring up the "), t("formatting bar", [Mark("bold")]), t(", including "), t("highlights", [Mark("highlight", attrs: ["color": "#fff3a3"])]), t(".")]),
                li([t("Type "), code("/"), t(" on an empty line to insert blocks.")]),
            ]),
            h(2, "Make it yours"),
            p("Open the brush in the top-right corner to change the backdrop, paper, font and separators. Style never changes your content — only how it looks."),
            Node("blockquote", content: [p("Keep the interface fast, the data portable, and the writer in control.")]),
            h(2, "A few things to try"),
            Node("taskList", content: [task(true, "Open this document"), task(false, "Change the style to Ember or Meadow"), task(false, "Create a folder and move a document into it"), task(false, "Export a document as Markdown")]),
            Node("horizontalRule"),
            h(3, "Shortcuts live in their own page"),
            Node("pageCard", attrs: ["docId": .string(keysId), "title": "Keyboard shortcuts", "presentation": "card"]),
        ], now)

        let keys = doc(keysId, "Keyboard shortcuts", "paper", [
            h(2, "Everywhere"),
            ul([li([code("⌘N"), t(" new document")]), li([code("⌘O"), t(" quick open")]), li([code("⌘W"), t(" close tab")]), li([code("⌃⌘S"), t(" toggle sidebar")]), li([code("⌘,"), t(" settings")])]),
            h(2, "While writing"),
            ul([
                li([code("⌘B"), t(" bold, "), code("⌘I"), t(" italic, "), code("⌘U"), t(" underline, "), code("⌘K"), t(" link")]),
                li([code("⌘⇧B"), t(" reapply the last color")]),
                li([code("⌘⌥1"), t(" title, "), code("⌘⌥2"), t(" subtitle, "), code("⌘⌥3"), t(" heading, "), code("⌘⌥0"), t(" body")]),
                li([code("⌥F10"), t(" move focus into the formatting bar; "), code("Esc"), t(" returns")]),
                li([code("⌘F"), t(" find and replace in this page")]),
            ]),
            h(2, "Markdown as you type"),
            ol([li([code("# "), t(" title, "), code("## "), t(" subtitle, "), code("### "), t(" heading")]), li([code("- "), t(" bullets, "), code("1. "), t(" numbers, "), code("[] "), t(" tasks")]), li([code("> "), t(" quote, "), code("```"), t(" code, "), code("---"), t(" separator")]), li([code("**bold**"), t(", "), code("*italic*"), t(", "), code("~~strike~~"), t(", "), code("==mark==")])]),
        ], now - 1000)

        let quiet = doc(quietId, "Morning pages", "paper", [
            p("Three pages, longhand, first thing. No editing, no rereading — just moving the pen until the noise quiets down."),
            p("Today: the light through the kitchen window, a half-remembered dream about trains, and a list of things that can wait."),
        ], now - 86_400_000 * 3)

        for (d, folderId, parent) in [(welcome, Optional(folder.id), String?.none), (keys, Optional(folder.id), Optional(welcomeId)), (quiet, nil, nil)] {
            var m = DocMeta(id: d.id, folderId: folderId, parentDocId: parent, createdAt: d.createdAt, updatedAt: d.updatedAt, viewedAt: d.updatedAt)
            m.applyDerived(from: d)
            lib.docs[d.id] = m
        }
        return (lib, [welcome, keys, quiet])
    }
}

public extension DocMeta {
    /// Refresh derived index fields from the document file.
    mutating func applyDerived(from d: DocFile) {
        let s = docStats(d.content)
        let tokens = Styles.resolve(d.appearance)
        title = d.title
        excerpt = excerptOf(d.content, max: 700)
        searchText = String((d.title + "\n" + docPlainText(d.content)).prefix(50_000)) // original case; search is case-insensitive
        words = s.words
        blocks = s.blocks
        styleId = d.appearance.styleId
        tint = Styles.tint(tokens)
    }
}
