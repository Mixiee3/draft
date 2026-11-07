import XCTest
import AppKit
import DraftCore
@testable import DraftEditor

final class LinkFakeHost: FakeHost, LinkHost {
    var titles: [String: String] = ["d_plan": "Plan", "d_trip": "Trip"]
    var blocks: [String: (doc: String, text: String)] = ["b_goal": ("d_plan", "Ship v0.3")]
    var linkOpened: [(String, String?)] = []
    var created: [(String, Node)] = []
    var today = "d_today"
    var previews = false
    var fetched: [URL] = []
    var pending: ((LinkPreview?) -> Void)?
    func wantsLinkPreviews() -> Bool { previews }
    func fetchLinkPreview(_ url: URL, _ done: @escaping (LinkPreview?) -> Void) { fetched.append(url); pending = done }

    func mentionItems(trigger: String, query: String) -> [MentionItem] {
        switch trigger {
        case "#": return ["work", "writing"].filter { query.isEmpty || $0.hasPrefix(query.lowercased()) }.map { MentionItem(kind: .tag, title: "#" + $0, symbol: "number", value: $0) }
        case "@":
            return DateParse.suggestions(query, today: "2026-11-07").map { MentionItem(kind: .date, title: $0, symbol: "calendar", value: $0) }
        default:
            var out = titles.filter { query.isEmpty || $0.value.lowercased().contains(query.lowercased()) }.sorted { $0.key < $1.key }
                .map { MentionItem(kind: .doc, title: $0.value, symbol: "doc", docId: $0.key) }
            out += blocks.filter { $0.value.text.lowercased().contains(query.lowercased()) }.map { MentionItem(kind: .block, title: $0.value.text, symbol: "text.alignleft", docId: $0.value.doc, blockId: $0.key) }
            if !query.isEmpty { out.append(MentionItem(kind: .create, title: "New “\(query)”", symbol: "plus", value: query)) }
            return out
        }
    }
    func createLinkedDocument(title: String) -> String? { titles["d_new"] = title; return "d_new" }
    func openDocLink(docId: String, blockId: String?) { linkOpened.append((docId, blockId)) }
    func resolveLink(docId: String, blockId: String?) -> (docId: String, title: String)? {
        if let b = blockId { return blocks[b].map { ($0.doc, $0.text) } }
        return titles[docId].map { (docId, $0) }
    }
    func todayKey() -> String { "2026-11-07" }
    func createDocument(title: String, content: Node) -> String? { created.append((title, content)); return "d_created" }
    func dailyNoteId(create: Bool) -> String? { today }
    override func pageInfo(docId: String) -> (title: String, excerpt: String, tint: NSColor)? { titles[docId].map { ($0, "", .gray) } ?? super.pageInfo(docId: docId) }
}

final class LinkTests: XCTestCase {
    var window: NSWindow!
    var view: DocumentEditorView!
    let host = LinkFakeHost()
    var c: EditorController { view.controller }
    var tv: DraftTextView { c.textView }

    override func setUp() {
        view = DocumentEditorView(frame: NSRect(x: 0, y: 0, width: 900, height: 700))
        window = NSWindow(contentRect: view.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = view
        c.host = host
        c.load(Node("doc", content: [Node("paragraph", attrs: ["id": "b_1"], content: [.text("See ")])]))
        window.makeFirstResponder(tv)
        tv.setSelectedRange(NSRange(location: 4, length: 0))
    }
    func pump() { let e = expectation(description: "q"); DispatchQueue.main.async { e.fulfill() }; wait(for: [e], timeout: 2) }
    func type(_ s: String) { for ch in s { tv.insertText(String(ch), replacementRange: tv.selectedRange()); pump() } }
    func inline() -> [Node] { c.document().content?.first?.content ?? [] }

    func testDocLinkPickerInsertsChipAndUndoIsOneStep() {
        type("[[pl")
        XCTAssertTrue(c.mention.isOpen)
        XCTAssertEqual(c.mention.trigger, "[[")
        XCTAssertEqual(c.mention.results.first?.title, "Plan")
        tv.insertNewline(nil)
        XCTAssertFalse(c.mention.isOpen)
        XCTAssertEqual(inline().map(\.text), ["See ", "Plan", " "])
        XCTAssertEqual(inline()[1].marks, [Mark("docLink", attrs: ["docId": "d_plan"])])
        pump(); tv.undoManager?.undo()
        XCTAssertEqual(c.document().content?.first.map(nodeText), "See [[pl")
    }

    func testPickerIsAccessible() {
        type("[[pl")
        let items = c.mention.accessibilityChildren() as? [NSAccessibilityElement] ?? []
        XCTAssertEqual(items.count, c.mention.results.count)
        XCTAssertEqual(items.first?.accessibilityLabel(), "Plan")
        XCTAssertEqual(items.first?.accessibilityRole(), .menuItem)
        XCTAssertTrue(items.first?.isAccessibilitySelected() ?? false)
        XCTAssertEqual(c.mention.accessibilityRole(), .menu)
    }

    func testBlockReferenceAndCreateNew() {
        type("[[ship")
        XCTAssertEqual(c.mention.results.map(\.kind), [.block, .create])
        tv.insertNewline(nil)
        XCTAssertEqual(inline()[1].marks?.first?.attrs?["blockId"], "b_goal")
        type("[[Ideas")
        c.mention.choose(c.mention.results.count - 1)
        XCTAssertEqual(inline().last(where: { $0.marks != nil })?.marks?.first?.attrs?["docId"], "d_new")
        XCTAssertEqual(host.titles["d_new"], "Ideas")
    }

    func testDateAndTagPickers() {
        type("@tom")
        XCTAssertEqual(c.mention.results.first?.value, "2026-11-08")
        tv.insertNewline(nil)
        XCTAssertEqual(inline()[1].text, Day.chipLabel("2026-11-08", today: "2026-11-07"), "chips store a stable label")
        XCTAssertEqual(inline()[1].marks, [Mark("date", attrs: ["date": "2026-11-08"])])
        type("#wo")
        XCTAssertEqual(c.mention.trigger, "#")
        XCTAssertEqual(c.mention.results.map(\.value), ["work"])
        tv.insertTab(nil)
        XCTAssertTrue(c.document().content!.first.map(nodeText)!.hasSuffix("#work "))
        type("x # y")
        XCTAssertFalse(c.mention.isOpen, "a space after # closes the tag picker")
    }

    func testLiveTitlesMovedBlocksAndMissingTargets() {
        c.insertDocLink(docId: "d_plan", title: "Plan")
        c.insertDocLink(docId: "d_old", blockId: "b_goal", title: "old text")
        c.insertDocLink(docId: "d_gone", title: "Gone")
        host.titles["d_plan"] = "Plan B"
        host.titles["d_gone"] = nil
        XCTAssertTrue(c.refreshLinks())
        let n = inline()
        XCTAssertEqual(n.filter { $0.marks?.first?.type == "docLink" }.map(\.text), ["Plan B", "Ship v0.3", "Gone"])
        XCTAssertEqual(n.first { $0.text == "Ship v0.3" }?.marks?.first?.attrs?["docId"], "d_plan", "a moved block's link follows it")
        let goneAt = (tv.string as NSString).range(of: "Gone").location
        XCTAssertNotNil(c.storage.attribute(.draftLinkMissing, at: goneAt, effectiveRange: nil))
        XCTAssertFalse(c.refreshLinks(), "nothing left to change")
        host.titles["d_gone"] = "Back"
        c.refreshLinks()
        XCTAssertNil(c.storage.attribute(.draftLinkMissing, at: goneAt, effectiveRange: nil), "a restored target works again")
        // The missing marker is display-only.
        XCTAssertFalse(String(data: try! DraftJSON.encode(c.document()), encoding: .utf8)!.contains("issing"))
    }

    func testRenameRefreshKeepsUndoHistory() {
        c.insertDocLink(docId: "d_plan", title: "Plan")
        pump()
        type("typed")
        pump()
        host.titles["d_plan"] = "Plan B"
        c.refreshLinks()
        XCTAssertEqual(c.document().content?.first.map(nodeText), "See Plan B typed")
        XCTAssertTrue(tv.undoManager!.canUndo, "the user's history survives a title refresh")
        pump(); tv.undoManager?.undo() // the user's typing (the title update rides along)
        XCTAssertEqual(c.document().content?.first.map(nodeText), "See Plan ")
        tv.undoManager?.undo() // then the chip, with valid ranges
        XCTAssertEqual(c.document().content?.first.map(nodeText), "See ")
    }

    func testOffscreenRefreshKeepsThisDocumentsHistoryWithoutAnExtraStep() {
        let other = DocumentEditorView(frame: view.frame)
        XCTAssertFalse(other.controller.textView.undoManager === tv.undoManager, "each document has its own history")
        c.insertDocLink(docId: "d_plan", title: "Plan")
        pump()
        type("typed")
        pump()
        view.removeFromSuperview() // off screen
        other.controller.undo.registerUndo(withTarget: self) { _ in }
        host.titles["d_plan"] = "Plan C"
        c.refreshLinks()
        pump()
        XCTAssertEqual(c.document().content?.first.map(nodeText), "See Plan C typed")
        XCTAssertEqual(c.undo.undoMenuItemTitle, "Undo", "the title update is never named as a step")
        c.undo.undo()
        XCTAssertFalse(c.document().content?.first.map(nodeText)?.contains("typed") ?? true, "one ⌘Z undoes the user's last edit")
        XCTAssertTrue(c.undo.canUndo, "earlier history is still there")
        c.undo.undo()
        XCTAssertEqual(c.document().content?.first.map(nodeText), "See ", "and the edit before it")
        c.undo.redo()
        XCTAssertEqual(c.document().content?.first.map(nodeText), "See Plan ")
        XCTAssertTrue(other.controller.undo.canUndo, "another document's history is untouched")
    }

    func testBackspaceRemovesWholeChipAndClickOpensIt() {
        c.insertDocLink(docId: "d_plan", title: "Plan")
        pump() // separate user actions are separate undo steps
        tv.setSelectedRange(NSRange(location: 8, length: 0)) // right after "Plan"
        tv.deleteBackward(nil)
        XCTAssertEqual(c.document().content?.first.map(nodeText), "See  ")
        pump(); tv.undoManager?.undo()
        XCTAssertEqual(c.chipRange(at: 5)?.2, "d_plan")
        let gr = c.layout.glyphRange(forCharacterRange: NSRange(location: 5, length: 1), actualCharacterRange: nil)
        let r = c.layout.boundingRect(forGlyphRange: gr, in: c.container)
        XCTAssertTrue(c.openChip(at: 5, point: NSPoint(x: r.midX, y: r.midY)))
        XCTAssertEqual(host.linkOpened.first?.0, "d_plan")
    }

    func testTagsAreColoredButHexIsNot() {
        c.load(Node("doc", content: [Node("paragraph", attrs: ["id": "b_1"], content: [.text("#work and #fff")])]))
        let tagColor = c.storage.attribute(.foregroundColor, at: 1, effectiveRange: nil) as? NSColor
        let hexColor = c.storage.attribute(.foregroundColor, at: 11, effectiveRange: nil) as? NSColor
        XCTAssertEqual(tagColor, c.theme.tagColor("work"))
        XCTAssertEqual(hexColor, c.theme.text)
    }

    func testSetTaskCheckedFromOutside() {
        c.load(Node("doc", content: [Node("taskList", attrs: ["id": "b_l"], content: [Node("taskItem", attrs: ["id": "b_t", "checked": false], content: [Node("paragraph", attrs: ["id": "b_tp"], content: [.text("call")])])])]))
        XCTAssertTrue(c.setTaskChecked(blockId: "b_t", checked: true))
        XCTAssertEqual(c.document().content?.first?.content?.first?.attrs?["checked"], .bool(true))
        XCTAssertFalse(c.setTaskChecked(blockId: "b_nope", checked: true))
    }

    func testDueDateFromEditorAndPlainDateStyle() {
        c.load(Node("doc", content: [Node("taskList", attrs: ["id": "b_l"], content: [Node("taskItem", attrs: ["id": "b_t", "checked": false], content: [Node("paragraph", attrs: ["id": "b_tp"], content: [.text("call")])])])]))
        XCTAssertTrue(c.setTaskDue(blockId: "b_t", due: "2026-11-09T15:00"))
        let p = c.document().content?.first?.content?.first?.content?.first
        XCTAssertEqual(p?.content?.last?.marks, [Mark("date", attrs: ["date": "2026-11-09T15:00"])])
        XCTAssertTrue(p?.content?.last?.text?.hasSuffix("15:00") ?? false)
        pump(); tv.undoManager?.undo()
        XCTAssertEqual(c.document().content?.first?.content?.first?.content?.first?.content?.map(\.text), ["call"], "one undo removes the date")
        tv.undoManager?.redo()
        let at = (tv.string as NSString).range(of: "15:00").location
        XCTAssertNotNil(c.storage.attribute(.backgroundColor, at: at, effectiveRange: nil), "chip style")
        var th = c.theme; th.dateChips = false; c.theme = th
        XCTAssertNil(c.storage.attribute(.backgroundColor, at: at, effectiveRange: nil), "plain text style")
        XCTAssertEqual(c.document().content?.first?.content?.first?.content?.first?.content?.last?.marks?.first?.type, "date", "the stored date is unchanged")
    }

    func testMoveToNewDocumentAndTodayLeaveCards() {
        c.load(Node("doc", content: [
            Node("paragraph", attrs: ["id": "b_a"], content: [.text("Idea")]),
            Node("paragraph", attrs: ["id": "b_b"], content: [.text("details")]),
            Node("paragraph", attrs: ["id": "b_c"], content: [.text("keep")]),
        ]))
        c.selectBlocks(ids: ["b_a", "b_b"])
        EditorCommands.command("block.moveToNewDoc")!.run(c)
        XCTAssertEqual(c.document().content?.map(\.type), ["pageCard", "paragraph"])
        XCTAssertEqual(c.document().content?.first?.attrs?["docId"], "d_created")
        XCTAssertEqual(host.created.first?.0, "Idea")
        XCTAssertEqual(host.created.first?.1.content?.first?.id, "b_b", "moved blocks keep their ids")
        pump(); tv.undoManager?.undo()
        XCTAssertEqual(c.document().content?.count, 3)
        c.selectBlocks(ids: ["b_c"])
        c.moveSelectedBlocksToToday()
        XCTAssertEqual(c.document().content?.last?.type, "pageCard")
        XCTAssertEqual(c.document().content?.last?.attrs?["docId"], "d_today")
        XCTAssertEqual(host.appended["d_today"]?.first?.id, "b_c")
        pump(); tv.undoManager?.undo()
        XCTAssertEqual(c.document().content?.last?.id, "b_c")
        XCTAssertEqual(host.appended["d_today"]?.count, 0)
    }

    func testConverterRoundTripsChips() {
        let doc = Node("doc", content: [Node("paragraph", attrs: ["id": "b_1"], content: [
            .text("A", marks: [Mark("docLink", attrs: ["docId": "d_x", "blockId": "b_y"])]), .text(" "), .text("Today", marks: [Mark("date", attrs: ["date": "2026-11-07"])]),
        ])])
        let (s, t) = Converter.attributed(from: doc)
        XCTAssertEqual(Converter.document(from: s, trailing: t), doc)
    }
}
