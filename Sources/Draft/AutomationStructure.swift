import AppKit
import SwiftUI
import DraftCore
import DraftEditor

/// `DRAFT_AUTOMATION=structure-write | structure-read`: tables, collections and their views.
extension Automation {
    static func deepestScrollView(_ v: NSView) -> NSScrollView? {
        var best: NSScrollView?
        func visit(_ x: NSView) {
            if let s = x as? NSScrollView, (s.documentView?.frame.height ?? 0) > (best?.documentView?.frame.height ?? 0) { best = s }
            x.subviews.forEach(visit)
        }
        visit(v)
        return best
    }


    static func structureWrite() async {
        var r: [String: String] = [:]
        guard let w = NSApp.windows.first(where: { $0.isVisible }), let host = m.createDoc(title: "Reading list") else { return }
        await wait()
        let c = m.editors[host]!.controller
        m.editors[host]!.focusBody(atStart: true)
        EditorCommands.command("insert.table")!.run(c); await boundary()
        EditorCommands.command("insert.collection")!.run(c); await boundary()
        m.flushAll()
        guard let block = c.document().content?.first(where: { $0.type == "collection" })?.id else { return }
        r["host"] = host; r["block"] = block
        let um = UndoManager(); um.groupsByEvent = false
        func step(_ f: () -> Void) { um.beginUndoGrouping(); f(); um.endUndoGrouping() }
        var status = ""
        step { m.updateCollection(host, block, "Fields", undo: um) { d in d.fields.append(CollectionField(id: "f_pages", name: "Pages", type: "number")); status = d.fields[0].id } }
        let seeds: [(String, String, Double)] = [("Dune", "Doing", 412), ("Atlas", "To do", 120), ("Zen", "Done", 300)]
        for (t, s, p) in seeds { step { m.addCollectionItem(host, block, title: t, values: [status: .string(s), "f_pages": .number(p)], undo: um) } }
        guard var d = m.collectionData(host, block) else { return }
        r["items"] = "\(d.items.count)"
        r["itemsArePages"] = d.items.allSatisfy { m.library.docs[$0.docId]?.parentDocId == host } ? "yes" : "no"
        step { m.updateCollection(host, block, "Sort", undo: um) { d in d.views[0].sort = [SortRule(field: "f_pages", ascending: false)]; d.views[0].calc["f_pages"] = "sum" } }
        d = m.collectionData(host, block)!
        r["sorted"] = d.rows(d.views[0], title: m.pageTitle).map { m.pageTitle($0.docId) }.joined(separator: ",")
        r["sum"] = d.calculate("sum", field: "f_pages", rows: d.items, title: m.pageTitle)
        // Kanban drag: one record, one undo.
        let board = d.views.first { $0.type == "kanban" }!
        let atlas = d.items.first { m.pageTitle($0.docId) == "Atlas" }!.id
        let before = d.items
        step { m.updateCollection(host, block, "Move Card", undo: um) { $0.move(atlas, to: "Done", groupBy: board.groupBy!) } }
        let after = m.collectionData(host, block)!.items
        r["dragChanged"] = "\(zip(before, after).filter { $0 != $1 }.count)"
        um.undo()
        r["dragUndone"] = m.collectionData(host, block)!.items == before ? "yes" : "no"
        // CSV round trip into a second collection.
        let csv = out.appendingPathComponent("reading.csv")
        try? m.exportCSV(host, block, to: csv)
        c.textView.setSelectedRange(NSRange(location: (c.textView.string as NSString).length, length: 0))
        EditorCommands.command("insert.collection")!.run(c); await boundary()
        m.flushAll()
        let second = c.document().content?.filter { $0.type == "collection" }.last?.id ?? ""
        step { m.updateCollection(host, second, "Fields", undo: um) { d2 in d2.fields = d.fields } }
        var n = -1
        step { n = (try? m.importCSV(host, second, from: csv, undo: um)) ?? -1 }
        let a = m.collectionData(host, block)!, b = m.collectionData(host, second)!
        let shown = { (x: CollectionData) in x.items.map { it in ([m.pageTitle(it.docId)] + x.fields.map { x.display(it, $0.id, title: m.pageTitle) }).joined(separator: "|") }.sorted() }
        r["csvImported"] = "\(n)"
        r["csvRoundTrip"] = shown(a) == shown(b) ? "yes" : "no"
        // Open the collection screen and each view.
        m.openCollection(host, block); await wait(0.6)
        r["screen"] = m.activeView.kind
        for (i, v) in m.collectionData(host, block)!.views.enumerated() {
            m.updateCollection(host, block, "View", undo: nil) { $0.activeView = v.id }
            await wait(0.4)
            await capture("v05-collection-\(i)-\(v.type)")
        }
        r["firstItemId"] = a.items.first?.id ?? ""
        r["firstItemDoc"] = a.items.first?.docId ?? ""
        // 1,000 items: open time and scrolling.
        guard let big = m.createDoc(title: "Big collection") else { return }
        await wait(0.4)
        let bc = m.editor(for: big).controller
        bc.insertAttachmentBlock(kind: .collection, node: CollectionData.starter(name: "Thousand").node(id: "b_big"))
        m.flushAll()
        let bigBlock = bc.document().content?.first { $0.type == "collection" }?.id ?? ""
        var bd = m.collectionData(big, bigBlock)!
        let st = bd.fields[0].id
        let t0 = CFAbsoluteTimeGetCurrent()
        for i in 0..<1000 {
            let id = newId("d_")
            var doc = DocFile.empty(id: id, title: "Item \(i)")
            doc.content = Node("doc", content: [Node("paragraph", attrs: ["id": .string(newId("b_"))])])
            try? m.vault.saveDoc(doc)
            var meta = DocMeta(id: id, title: "Item \(i)", parentDocId: big); meta.spaceId = m.library.space.id
            m.library.docs[id] = meta
            bd.items.append(CollectionItem(docId: id, values: [st: .string(["To do", "Doing", "Done"][i % 3]), "f_n": .number(Double(i))]))
        }
        m.writeCollection(big, bigBlock, bd)
        r["bigSetupMs"] = String(Int((CFAbsoluteTimeGetCurrent() - t0) * 1000))
        m.openView(.doc(big)); await wait(0.3)
        let o0 = CFAbsoluteTimeGetCurrent()
        m.openCollection(big, bigBlock)
        w.contentView?.layoutSubtreeIfNeeded(); w.displayIfNeeded()
        r["openMs"] = String(Int((CFAbsoluteTimeGetCurrent() - o0) * 1000))
        await wait(0.5)
        if let sv = deepestScrollView(w.contentView!) {
            var steps: [Double] = []
            // 40 pt per frame at 60 fps ≈ 2,400 pt/s, a fast trackpad scroll.
            for k in 1...120 {
                let s0 = CFAbsoluteTimeGetCurrent()
                sv.contentView.scroll(to: NSPoint(x: 0, y: CGFloat(k) * 40))
                sv.reflectScrolledClipView(sv.contentView)
                w.contentView?.layoutSubtreeIfNeeded(); w.displayIfNeeded()
                steps.append((CFAbsoluteTimeGetCurrent() - s0) * 1000)
            }
            steps.sort()
            r["scrollP95Ms"] = String(format: "%.1f", steps[Int(Double(steps.count) * 0.95) - 1])
            r["scrollHeight"] = "\(Int(sv.documentView?.frame.height ?? 0))"
        }
        m.flushAll()
        save(r, "structure-write.json")
    }

    static func structureRead() async {
        guard let d = try? Data(contentsOf: out.appendingPathComponent("structure-write.json")),
              let w = try? JSONSerialization.jsonObject(with: d) as? [String: String], let host = w["host"], let block = w["block"] else { return }
        var r: [String: String] = [:]
        let data = m.collectionData(host, block)
        r["items"] = "\(data?.items.count ?? 0)"
        r["firstItemSame"] = data?.items.first?.id == w["firstItemId"] && data?.items.first?.docId == w["firstItemDoc"] ? "yes" : "no"
        r["itemPage"] = m.library.docs[w["firstItemDoc"] ?? ""]?.title ?? ""
        r["table"] = m.ensureDoc(host)?.content.content?.contains { $0.type == "table" } == true ? "yes" : "no"
        m.openView(.doc(w["firstItemDoc"] ?? "")); await wait(0.4)
        r["opensAsPage"] = m.activeDocId == w["firstItemDoc"] ? "yes" : "no"
        save(r, "structure-read.json")
    }
}
