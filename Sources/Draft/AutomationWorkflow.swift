import AppKit
import DraftCore
import DraftEditor

/// `DRAFT_AUTOMATION=workflow-write | workflow-read`: templates, import and Spaces.
extension Automation {
    static func workflowWrite() async {
        var r: [String: String] = [:]
        // Templates
        guard let src = m.createDoc(title: "Kickoff") else { return }
        await wait()
        let es = m.editors[src]!
        es.focusBody(atStart: true)
        await type("Agenda #work\n[] invite people", into: es.controller)
        m.updateAppearance(src) { $0.styleId = "linen" }
        m.flushAll()
        let tpl = m.saveAsTemplate(src, category: "Meetings") ?? ""
        let fromTpl = m.createFromTemplate(tpl, open: false) ?? ""
        let ids = { (id: String) -> Set<String> in var s = Set<String>(); walk(m.ensureDoc(id)!.content) { if let i = $0.id { s.insert(i) } }; return s }
        r["templateFreshIds"] = ids(fromTpl).isDisjoint(with: ids(tpl)) ? "yes" : "no"
        r["templateStyle"] = m.docs[fromTpl]?.appearance.styleId ?? ""
        r["templateText"] = docPlainText(m.docs[fromTpl]!.content)
        var t = m.ensureDoc(tpl)!; t.content = Node("doc", content: [Node("paragraph", attrs: ["id": "b_x"], content: [.text("changed")])]); m.docs[tpl] = t; try? m.vault.saveDoc(t)
        r["earlierUnchanged"] = docPlainText(m.ensureDoc(fromTpl)!.content).contains("Agenda") ? "yes" : "no"
        r["templatesHidden"] = m.library.liveDocs.contains { $0.id == tpl } ? "no" : "yes"
        let builtIn = m.createFromTemplate("tpl_brief", open: false) ?? ""
        r["builtInTable"] = m.docs[builtIn]?.content.content?.contains { $0.type == "table" } == true ? "yes" : "no"
        // Export then import (Draft JSON reproduces docs, styles, links, folders).
        guard let a = m.createDoc(title: "Linked A"), let b = m.createDoc(title: "Linked B") else { return }
        await wait()
        let f = m.createFolder(); m.renameFolder(f, "Imports"); m.move(a, to: f)
        _ = m.saveStyle(from: src, name: "Studio")
        m.updateAppearance(a) { $0.styleId = m.library.userStyles.last!.id }
        m.editor(for: a).controller.insertDocLink(docId: b, title: "Linked B")
        m.flushAll()
        let ex = out.appendingPathComponent("export")
        try? FileManager.default.createDirectory(at: ex, withIntermediateDirectories: true)
        m.export(docIds: [a, b], name: "roundtrip", groupByFolder: true, to: ex)
        await wait(0.3)
        let json = ex.appendingPathComponent("roundtrip/draft-export.json")
        let before = m.library.docs.count
        let imported = m.importFiles([json])
        r["importedCount"] = "\(imported.count)"
        let newA = imported.first { m.docTitle($0) == "Linked A" } ?? "", newB = imported.first { m.docTitle($0) == "Linked B" } ?? ""
        var link = ""; walk(m.ensureDoc(newA)?.content ?? Node("doc")) { if let mk = $0.marks?.first(where: { $0.type == "docLink" }) { link = mk.attrs?["docId"]?.string ?? "" } }
        r["importLinks"] = link == newB && newB != b ? "yes" : "no link=\(link) newB=\(newB)"
        r["importStyle"] = m.docs[newA]?.appearance.styleId == m.docs[a]?.appearance.styleId ? "yes" : "no"
        r["importFolder"] = m.folderName(m.library.docs[newA]?.folderId)
        r["docsAdded"] = "\(m.library.docs.count - before)"
        // Markdown folder import
        let mdDir = ex.appendingPathComponent("roundtrip")
        let mdImported = m.importFiles([mdDir])
        var mdLinks = 0
        for id in mdImported { walk(m.ensureDoc(id)!.content) { if $0.marks?.contains(where: { $0.type == "docLink" }) == true { mdLinks += 1 } } }
        r["markdownImported"] = "\(mdImported.count)"; r["markdownLinks"] = "\(mdLinks)"
        // Spaces: unsaved text survives a switch; tags and tasks are per Space.
        let home = m.library.space.id
        m.createSpace("Side project"); await wait(0.3)
        let side = m.library.space.id
        guard let sdoc = m.createDoc(title: "Side note") else { return }
        await wait()
        let ed = m.editors[sdoc]!
        ed.focusBody(atStart: true)
        await type("unsaved words #sideonly", into: ed.controller)
        m.switchSpace(home); await wait(0.3)
        r["unsavedKept"] = ((try? m.vault.loadDoc(sdoc)) ?? nil).map { docPlainText($0.content).contains("unsaved words") } == true ? "yes" : "no"
        r["homeTags"] = m.index.tagCounts(live: m.liveIds).map(\.tag).sorted().joined(separator: ",")
        r["homeHasSideDoc"] = m.library.liveDocs.contains { $0.id == sdoc } ? "yes" : "no"
        m.switchSpace(side); await wait(0.3)
        r["sideTags"] = m.index.tagCounts(live: m.liveIds).map(\.tag).sorted().joined(separator: ",")
        r["sideDocs"] = m.library.liveDocs.map(\.title).sorted().joined(separator: ",")
        r["sideTabHasDoc"] = m.library.tabs.contains { $0.view.docId == sdoc } ? "yes" : "no"
        m.switchSpace(home)
        r["home"] = home; r["side"] = side; r["sdoc"] = sdoc
        m.flushAll()
        save(r, "workflow-write.json")
    }

    static func workflowRead() async {
        guard let d = try? Data(contentsOf: out.appendingPathComponent("workflow-write.json")),
              let w = try? JSONSerialization.jsonObject(with: d) as? [String: String] else { return }
        var r: [String: String] = [:]
        r["spaces"] = "\(m.library.spaces.count)"
        r["activeSpace"] = m.library.space.id == w["home"] ? "home" : "other"
        r["templates"] = "\(m.library.templates.count)"
        m.switchSpace(w["side"] ?? ""); await wait(0.3)
        r["sideTabRestored"] = m.library.tabs.contains { $0.view.docId == w["sdoc"] } ? "yes" : "no"
        r["sideText"] = m.ensureDoc(w["sdoc"] ?? "").map { docPlainText($0.content) } ?? ""
        save(r, "workflow-read.json")
    }
}

extension Automation {
    /// Live network check of the opt-in features (only run on request; uses a throwaway vault).
    static func onlineLive() async {
        var r: [String: String] = [:]
        m.setSettings { $0.onlineImageSearch = true; $0.linkPreviews = true }
        let found: [WebImage] = await withCheckedContinuation { k in m.online.searchImages("lake", enabled: true) { k.resume(returning: (try? $0.get()) ?? []) } }
        r["searchResults"] = "\(found.count)"
        r["firstHost"] = found.first.flatMap { URL(string: $0.url)?.host } ?? ""
        if let f = found.first {
            let data: Data? = await withCheckedContinuation { k in m.online.download(f.url, enabled: true) { k.resume(returning: $0) } }
            r["downloadBytes"] = "\(data?.count ?? 0)"
            r["storedAsset"] = data.flatMap { m.storeImage(data: $0, ext: "jpg") } ?? ""
        }
        let p: LinkPreview? = await withCheckedContinuation { k in m.online.linkPreview(URL(string: "https://example.com")!, enabled: true) { k.resume(returning: $0) } }
        r["previewTitle"] = p?.title ?? ""
        let before = m.online.requests
        m.setSettings { $0.onlineImageSearch = false; $0.linkPreviews = false }
        _ = await withCheckedContinuation { k in m.online.searchImages("lake", enabled: m.settings.onlineImageSearch) { _ in k.resume(returning: 0) } }
        _ = await withCheckedContinuation { k in m.online.linkPreview(URL(string: "https://example.com")!, enabled: m.settings.linkPreviews) { _ in k.resume(returning: 0) } }
        r["requestsWhileOff"] = "\(m.online.requests - before)"
        r["requestsTotal"] = "\(m.online.requests)"
        save(r, "online-live.json")
    }
}
