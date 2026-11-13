import AppKit
import DraftCore

/// Group into page / ungroup, duplicate, copy link, and the block context menu.
extension EditorController {
    var selectedFlat: (all: [FlatBlock], range: ClosedRange<Int>) { (flatBlocks(), selectedBlockRange) }

    public var canGroup: Bool {
        let (all, r) = selectedFlat
        return all[r].contains { !$0.inline.isEmpty || $0.info.kind.isAttachment } // not just empty lines
    }

    public var canUngroup: Bool {
        let (all, r) = selectedFlat
        return r.count == 1 && all[r.lowerBound].info.kind == .page
    }

    /// Undo/redo hook that flips a grouped page between active and in the trash.
    func registerPageState(_ id: String, current: Bool) {
        textView.undoManager?.registerUndo(withTarget: self) { c in
            c.host?.setGroupedPage(id, active: !current)
            c.registerPageState(id, current: !current)
        }
    }

    /// ⌘G: move the selected blocks into a new nested page. The first text block becomes the
    /// page title and the page card keeps that block's id; every other block keeps its id.
    public func groupSelectionIntoPage() {
        guard canGroup, let host else { NSSound.beep(); return }
        moveSelectionIntoNewPage(presentation: "page") { host.createGroupedPage(title: $0, content: $1) }
    }

    /// ⌥⌘N: like Group into Page, but the blocks become a new top-level document (same folder).
    public func moveSelectedBlocksToNewDocument() {
        guard canGroup, let h = linkHost else { NSSound.beep(); return }
        moveSelectionIntoNewPage(presentation: "card") { h.createDocument(title: $0, content: $1) }
    }

    func moveSelectionIntoNewPage(presentation: String, create: (String, Node) -> String?) {
        var (flat, r) = selectedFlat
        var blocks = Array(flat[r])
        var title = ""
        var titleNode: Node? = nil
        var cardId = newId("b_")
        if let first = blocks.first, !first.info.kind.isAttachment, first.info.kind != .code, !first.inline.isEmpty {
            title = nodeText(Node("paragraph", content: first.inline)).replacingOccurrences(of: "\n", with: " ")
            titleNode = Converter.tree(from: [first]).content?.first
            cardId = first.info.id
            blocks.removeFirst()
        }
        let content = Converter.tree(from: blocks)
        guard let pageId = create(title, content) else { NSSound.beep(); return }
        var attrs: [String: JSONValue] = ["id": .string(cardId), "docId": .string(pageId), "title": .string(title), "presentation": .string(presentation)]
        if let t = titleNode, let v = try? JSONDecoder().decode(JSONValue.self, from: DraftJSON.encode(t)) { attrs["titleNode"] = v }
        let card = Node("pageCard", attrs: attrs)
        flat.replaceSubrange(r, with: [FlatBlock(info: BlockInfo(id: cardId, kind: .page, raw: card), inline: [])])
        clearBlockModeState()
        rebuild(flat, select: [cardId], blockMode: true, alsoUndo: { self.registerPageState(pageId, current: true) })
    }

    /// ⇧⌘G: put a nested page's blocks back in place of its card (ids kept) and move the page
    /// to Recently Deleted. Undo brings the page back.
    public func ungroupPage() {
        guard canUngroup, let host else { NSSound.beep(); return }
        var (flat, r) = selectedFlat
        let card = flat[r.lowerBound]
        guard let raw = card.info.raw, let pageId = raw.attrs?["docId"]?.string, let page = host.pageDocument(docId: pageId) else { NSSound.beep(); return }
        var inserted: [FlatBlock] = []
        if let v = raw.attrs?["titleNode"], let data = try? DraftJSON.encode(v), let node = try? JSONDecoder().decode(Node.self, from: data), nodeText(node) == page.title {
            inserted = Converter.flatten(Node("doc", content: [node]))
        } else if !page.title.isEmpty {
            inserted = [FlatBlock(info: BlockInfo(id: card.info.id), inline: [.text(page.title)])]
        }
        if !inserted.isEmpty { inserted[0].info = inserted[0].info.with(id: card.info.id) }
        var body = Converter.flatten(page.content)
        if body.count == 1, body[0].inline.isEmpty, !body[0].info.kind.isAttachment { body = [] } // an empty page adds nothing
        inserted += body
        if inserted.isEmpty { inserted = [FlatBlock(info: BlockInfo(id: card.info.id), inline: [])] }
        flat.replaceSubrange(r, with: inserted)
        clearBlockModeState()
        host.setGroupedPage(pageId, active: false)
        rebuild(flat, select: inserted.map(\.info.id), blockMode: true, alsoUndo: { self.registerPageState(pageId, current: false) })
    }

    /// ⌘D: copies of the selected blocks right after them, with new ids.
    public func duplicateSelectedBlocks() {
        var (flat, r) = selectedFlat
        let copies = flat[r].map { FlatBlock(info: $0.info.with(id: newId("b_"), innerId: .some(nil)), inline: $0.inline) }
        flat.insert(contentsOf: copies, at: r.upperBound + 1)
        clearBlockModeState()
        rebuild(flat, select: copies.map(\.info.id), blockMode: true)
    }

    /// Move the selected blocks to the end of another document (ids kept). Undo takes them back.
    public func moveSelectedBlocks(toDocument target: String) {
        guard let host else { return }
        var (flat, r) = selectedFlat
        let moving = Array(flat[r])
        let content = Converter.tree(from: moving)
        guard host.appendBlocks(content, toDocument: target) else { NSSound.beep(); return }
        let before = r.lowerBound > 0 ? flat[r.lowerBound - 1].info.id : nil
        flat.removeSubrange(r)
        if flat.isEmpty { flat = [FlatBlock(info: .paragraph(), inline: [])] }
        clearBlockModeState()
        rebuild(flat, select: before.map { [$0] } ?? [flat[0].info.id], blockMode: false,
                alsoUndo: { self.registerMoveState(content: content, ids: moving.map(\.info.id), target: target, present: true) })
    }

    /// Move the selected blocks to today's daily note and leave a card that opens it.
    public func moveSelectedBlocksToToday() {
        guard canGroup, let h = linkHost, let today = h.dailyNoteId(create: true), let host else { NSSound.beep(); return }
        var (flat, r) = selectedFlat
        let moving = Array(flat[r])
        let content = Converter.tree(from: moving)
        guard host.appendBlocks(content, toDocument: today) else { NSSound.beep(); return }
        let cardId = newId("b_")
        let card = Node("pageCard", attrs: ["id": .string(cardId), "docId": .string(today), "title": .string(host.pageInfo(docId: today)?.title ?? ""), "presentation": "card"])
        flat.replaceSubrange(r, with: [FlatBlock(info: BlockInfo(id: cardId, kind: .page, raw: card), inline: [])])
        clearBlockModeState()
        rebuild(flat, select: [cardId], blockMode: true,
                alsoUndo: { self.registerMoveState(content: content, ids: moving.map(\.info.id), target: today, present: true) })
    }

    func registerMoveState(content: Node, ids: [String], target: String, present: Bool) {
        textView.undoManager?.registerUndo(withTarget: self) { c in
            if present { c.host?.removeBlocks(ids, fromDocument: target) } else { _ = c.host?.appendBlocks(content, toDocument: target) }
            c.registerMoveState(content: content, ids: ids, target: target, present: !present)
        }
    }

    /// Used by the app when blocks arrive from another document.
    public func appendBlocks(_ content: Node) {
        var flat = flatBlocks()
        if flat.count == 1, flat[0].inline.isEmpty, !flat[0].info.kind.isAttachment { flat = [] }
        let added = Converter.flatten(content)
        rebuild(flat + added, select: [], blockMode: false)
    }

    public func removeBlocks(ids: Set<String>) {
        var flat = flatBlocks().filter { !ids.contains($0.info.id) }
        if flat.isEmpty { flat = [FlatBlock(info: .paragraph(), inline: [])] }
        rebuild(flat, select: [], blockMode: false)
    }

    public func copyLinkToBlock() {
        let (flat, r) = selectedFlat
        guard let url = host?.link(toBlock: flat[r.lowerBound].info.id) else { NSSound.beep(); return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(url.absoluteString, forType: .string)
        pb.setString(url.absoluteString, forType: .URL)
    }

    func clearBlockModeState() {
        blockSelectionIds = []
        expectedBlockSelection = nil
    }

    // MARK: Context menu

    /// The block menu shown from the handle (right-click / ⌃-click) and inside the text's
    /// context menu. Every item runs a shared command, so state and undo match the menu bar.
    public func blockMenu() -> NSMenu {
        let menu = NSMenu(title: "Block")
        func item(_ id: String, _ title: String? = nil, into m: NSMenu) {
            guard let cmd = EditorCommands.command(id) else { return }
            let mi = ClosureMenuItem(title: title ?? cmd.title) { [weak self] in if let self { cmd.run(self) } }
            mi.image = NSImage(systemSymbolName: cmd.symbol, accessibilityDescription: nil)
            mi.isEnabled = cmd.plannedFor == nil && cmd.isEnabled(self)
            mi.state = cmd.isActive(self) ? .on : .off
            if let k = cmd.key, k.count == 1 { mi.keyEquivalent = k; mi.keyEquivalentModifierMask = cmd.modifiers.intersection([.command, .shift, .option, .control]) }
            m.addItem(mi)
        }
        let turn = NSMenu(title: "Turn Into")
        for id in ["block.body", "block.title", "block.subtitle", "block.heading", "block.strong", "block.caption", "block.quote", "block.code", "list.bullet", "list.ordered", "list.task"] {
            item(id, into: turn)
        }
        let turnItem = NSMenuItem(title: loc("Turn Into"), action: nil, keyEquivalent: "")
        turnItem.submenu = turn
        turnItem.image = NSImage(systemSymbolName: "arrow.triangle.2.circlepath", accessibilityDescription: nil)
        turnItem.isEnabled = !currentBlock.kind.isAttachment
        menu.addItem(turnItem)
        menu.addItem(.separator())
        item("block.duplicate", into: menu)
        item("block.copyLink", into: menu)
        item("block.group", into: menu)
        item("block.ungroup", into: menu)
        let targets = host?.moveTargets() ?? []
        let moveMenu = NSMenu(title: "Move to")
        item("block.moveToNewDoc", "New Document", into: moveMenu)
        item("block.moveToToday", "Today’s Daily Note", into: moveMenu)
        if !targets.isEmpty { moveMenu.addItem(.separator()) }
        for t in targets {
            moveMenu.addItem(ClosureMenuItem(title: t.title) { [weak self] in self?.moveSelectedBlocks(toDocument: t.id) })
        }
        let moveItem = NSMenuItem(title: loc("Move to"), action: nil, keyEquivalent: "")
        moveItem.submenu = moveMenu
        moveItem.image = NSImage(systemSymbolName: "arrow.turn.up.right", accessibilityDescription: nil)
        moveItem.isEnabled = moveMenu.items.contains { $0.isEnabled && !$0.isSeparatorItem }
        menu.addItem(moveItem)
        menu.addItem(.separator())
        item("block.moveUp", into: menu)
        item("block.moveDown", into: menu)
        menu.addItem(.separator())
        let del = ClosureMenuItem(title: "Delete Block") { [weak self] in
            guard let self else { return }
            if !self.isBlockMode { self.enterBlockMode() }
            self.deleteSelectedBlocks()
        }
        del.image = NSImage(systemSymbolName: "trash", accessibilityDescription: nil)
        menu.addItem(del)
        return menu
    }
}

/// Menu item that runs a closure.
final class ClosureMenuItem: NSMenuItem {
    let handler: () -> Void
    init(title: String, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: loc(title), action: #selector(fire), keyEquivalent: "")
        target = self
    }
    required init(coder: NSCoder) { fatalError() }
    @objc func fire() { handler() }
}
