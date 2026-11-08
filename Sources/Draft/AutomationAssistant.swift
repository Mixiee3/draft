import AppKit
import SwiftUI
import DraftCore
import DraftAssistant

/// `DRAFT_AUTOMATION=assistant-bench DRAFT_BENCH_MODELS=a.gguf:b.gguf`: load time, memory, speed and
/// the answers of each model on Draft's own prompts, written to `assistant-bench.json`.
extension Automation {
    static let benchNote = """
    # Garden co-op planning

    We met on Tuesday with Mira, Tomas and Ines. The co-op has 14 beds and 9 active members.
    - Decision: the spring plant sale moves to Saturday 18 April, 10:00–14:00, at the north gate.
    - Ines will order 40 bags of compost from Hollow Farm before 1 April (budget 320 euros).
    - Tomas fixes the rain-barrel pump; parts cost about 45 euros.
    - Open question: whether to accept the school's offer to adopt two beds.
    Mira reminded everyone that the water key is in the blue box by the shed.
    Next meeting: 2 April at 19:00 in the library annex.
    """

    static let benchSources: [AssistantSource] = [
        AssistantSource(n: 1, docId: "d1", blockId: "b1", title: "Garden co-op planning", text: "Ines will order 40 bags of compost from Hollow Farm before 1 April (budget 320 euros)."),
        AssistantSource(n: 2, docId: "d2", blockId: "b2", title: "Bike trip packing", text: "Pack the patch kit, two spare tubes and the small pump; the hostel in Gorz has no lockers."),
        AssistantSource(n: 3, docId: "d1", blockId: "b3", title: "Garden co-op planning", text: "Decision: the spring plant sale moves to Saturday 18 April, 10:00–14:00, at the north gate."),
    ]

    static func offMain<T>(_ work: @escaping () -> T) async -> T {
        await withCheckedContinuation { c in
            Thread.detachNewThread {
                Thread.current.qualityOfService = .userInitiated
                let activity = ProcessInfo.processInfo.beginActivity(options: [.userInitiated, .idleSystemSleepDisabled], reason: "Assistant generation")
                let v = work()
                ProcessInfo.processInfo.endActivity(activity)
                c.resume(returning: v)
            }
        }
    }

    static func assistantBench() async {
        let paths = (ProcessInfo.processInfo.environment["DRAFT_BENCH_MODELS"] ?? "").split(separator: ":").map(String.init)
        var report: [[String: Any]] = []
        let tasks: [(String, AssistantRequest)] = [
            ("summarize", AssistantRequest(action: .summarize, scope: .document, text: benchNote, docId: "d1", docTitle: "Garden co-op planning")),
            ("grounded", AssistantRequest(action: .ask, scope: .space, question: "When is the plant sale and who orders compost?", retrieved: benchSources)),
            ("notInNotes", AssistantRequest(action: .ask, scope: .space, question: "What is the co-op's bank account number?", retrieved: benchSources)),
            ("shorten", AssistantRequest(action: .shorten, scope: .selection, text: "Mira reminded everyone that the water key is in the blue box by the shed, and she asked that whoever uses it last in the evening should put it back there so that the early volunteers can find it in the morning.", docId: "d1", docTitle: "Garden co-op planning")),
            ("outline", AssistantRequest(action: .outline, scope: .selection, text: "A short guide for new co-op members: beds, watering, tools, compost and the yearly plant sale.", docId: "d1", docTitle: "Member guide")),
            ("rewriteStructure", AssistantRequest(action: .rewrite, scope: .selection, text: "## Tasks\n- [ ] order compost from hollow farm b4 april\n- [ ] fix pump, parts ~45eur", docId: "d1", docTitle: "Garden co-op planning")),
        ]
        for path in paths {
            var r: [String: Any] = ["model": (path as NSString).lastPathComponent]
            let before = SystemMemory.footprint
            let t0 = Date()
            let engine: LlamaEngine
            do { engine = try LlamaEngine(path: URL(fileURLWithPath: path), minimumMemory: 0) } catch { r["error"] = "\(error)"; report.append(r); continue }
            r["loadSeconds"] = Date().timeIntervalSince(t0)
            r["footprintAfterLoadMB"] = Int((SystemMemory.footprint - before) >> 20)
            r["residentAfterLoadMB"] = Int(SystemMemory.resident >> 20)
            var peak = SystemMemory.footprint
            var results: [String: Any] = [:]
            for (name, req) in tasks {
                let p = AssistantPrompt.prepare(req)
                var text = ""
                let flag = CancelFlag()
                let s = await offMain { (try? engine.generate(p.turns, maxTokens: Int(ProcessInfo.processInfo.environment["DRAFT_BENCH_TOKENS"] ?? "300") ?? 300, cancel: flag) { text += $0; peak = max(peak, SystemMemory.footprint) }) ?? GenerationStats() }
                results[name] = ["text": text, "promptTokens": s.promptTokens, "tokens": s.generatedTokens, "ttft": s.firstTokenSeconds, "tps": s.tokensPerSecond,
                                 "cited": Citations.cited(in: text, sourceCount: p.sources.count)]
                var partial = r; partial["results"] = results
                if let d = try? JSONSerialization.data(withJSONObject: report + [partial], options: [.prettyPrinted, .sortedKeys]) { try? d.write(to: out.appendingPathComponent("assistant-bench.json")) }
            }
            // Cancellation: stop after the first piece and check that generation ends promptly.
            let flag = CancelFlag()
            var pieces = 0
            let c0 = Date()
            let s = await offMain { try? engine.generate(AssistantPrompt.prepare(tasks[4].1).turns, maxTokens: 300, cancel: flag) { _ in pieces += 1; if pieces == 3 { flag.cancel() } } }
            results["cancel"] = ["cancelled": s?.cancelled ?? false, "tokens": s?.generatedTokens ?? -1, "seconds": Date().timeIntervalSince(c0)]
            r["peakFootprintMB"] = Int((peak - before) >> 20)
            r["results"] = results
            report.append(r)
        }
        if let d = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) { try? d.write(to: out.appendingPathComponent("assistant-bench.json")) }
    }
}

/// `assistant-write` / `assistant-read`: the Assistant end to end in the app, against the real model
/// in `DRAFT_MODELS_DIR`: Space answer with sources, rewrite preview and one-step undo, cancel,
/// chat saved per Space, then a relaunch that reads the history back.
extension Automation {
    static func untilIdle(_ a: AssistantModel, timeout: Double = 240) async {
        let t0 = Date()
        await wait(0.2)
        while a.isRunning && Date().timeIntervalSince(t0) < timeout { await wait(0.2) }
    }

    static func assistantWrite() async {
        guard let w = NSApp.windows.first(where: { $0.isVisible }) else { return }
        w.setFrame(NSRect(x: 60, y: 60, width: 1440, height: 900), display: true)
        var r: [String: String] = [:]
        func make(_ title: String, _ md: String) -> String {
            let id = newId("d_")
            var doc = DocFile.empty(id: id, title: title)
            doc.content = ensureBlockIds(Node("doc", content: MarkdownImport.blocks(md)))
            try? m.vault.saveDoc(doc)
            var meta = DocMeta(id: id, title: title); meta.applyDerived(from: doc); meta.spaceId = m.library.space.id
            m.library.docs[id] = meta
            return id
        }
        let garden = make("Garden co-op planning", benchNote.components(separatedBy: "\n").dropFirst(2).joined(separator: "\n"))
        _ = make("Bike trip packing", "Pack the patch kit, two spare tubes and the small pump.\n\nThe hostel in Gorz has no lockers.")
        m.rebuildIndex()
        m.openView(.doc(garden)); await wait()
        let gc = m.editor(for: garden).controller
        let a = m.assistant
        m.setSettings { $0.assistantPinned = true }
        m.toggleAssistant(); await wait(0.6)
        r["status"] = "\(a.status)"
        await capture("v051-assistant-empty")

        a.scope = .space
        a.draft = "When is the plant sale, and who orders the compost?"
        a.send(); await untilIdle(a)
        let answer = a.chat.messages.last
        r["spaceAnswer"] = answer?.text ?? ""
        r["spaceSources"] = (answer?.sources ?? []).map { "\($0.n):\(m.docTitle($0.docId))" }.joined(separator: ",")
        r["sourcesFromGarden"] = (answer?.sources ?? []).contains { $0.docId == garden && $0.blockId != nil } ? "yes" : "no"
        r["answerMentionsDate"] = (answer?.text ?? "").contains("18 April") ? "yes" : "no"
        await capture("v051-assistant-space-answer")
        if let s = answer?.sources?.first { a.open(s); await wait(0.6); r["jumpOpened"] = m.activeDocId == s.docId ? "yes" : "no" }

        m.openView(.doc(garden)); await wait(0.4)
        let ns = gc.storage.string as NSString
        gc.textView.setSelectedRange(ns.range(of: "Mira reminded everyone that the water key is in the blue box by the shed."))
        a.scope = .selection
        let before = docPlainText(gc.document())
        a.send(.shorten); await untilIdle(a)
        let short = a.chat.messages.last!
        r["shortened"] = short.text
        a.previewEdit(short)
        r["previewCanReplace"] = a.preview?.canReplace == true ? "yes" : "no"
        await wait(0.6)
        if let sheet = w.attachedSheet { await captureWindow(sheet, "v051-assistant-preview") }
        if let p = a.preview { a.apply(p, replace: true) }
        await boundary()
        let after = docPlainText(gc.document())
        r["replaced"] = after != before && !after.contains("Mira reminded everyone that the water key") ? "yes" : "no"
        gc.undo.undo(); await boundary()
        r["oneUndoRestores"] = docPlainText(gc.document()) == before ? "yes" : "no"

        a.scope = .document
        let count = a.chat.messages.count
        a.send(.summarize)
        let t0 = Date()
        while a.streaming?.thinking.isEmpty != false && a.streaming?.answer.isEmpty != false && Date().timeIntervalSince(t0) < 60 { await wait(0.1) }
        let c0 = Date()
        a.stop(); await untilIdle(a, timeout: 20)
        r["cancelSeconds"] = String(format: "%.2f", Date().timeIntervalSince(c0))
        r["cancelRecorded"] = a.chat.messages.count == count + 2 && a.chat.messages.last?.failed == true ? "yes" : "no"

        // Follow-ups: a Space question resets the saved state, then two questions about the same note.
        a.scope = .space; a.draft = "Who has the water key?"; a.send(); await untilIdle(a)
        a.scope = .document
        var firsts: [Double] = []
        for q in ["When is the plant sale?", "Who orders the compost?"] {
            a.draft = q; a.send(); await untilIdle(a)
            firsts.append(a.lastStats?.firstTokenSeconds ?? -1)
            r["followUpReused\(firsts.count)"] = "\(a.lastStats?.reusedTokens ?? -1)/\(a.lastStats?.promptTokens ?? -1)"
        }
        r["firstQuestionStartSeconds"] = String(format: "%.2f", firsts[0])
        r["followUpStartSeconds"] = String(format: "%.2f", firsts[1])
        r["followUpSpeedup"] = String(format: "%.1f", firsts[1] > 0 ? firsts[0] / firsts[1] : 0)

        // A note several times longer than the context, with the fact near the end.
        let filler = (0..<260).map { "Week \($0 + 1): the volunteers watered the beds, weeded the paths and logged the rainfall in the shed notebook." }
        let long = make("Season log", (filler + ["The harvest festival password is heliotrope."]).joined(separator: "\n\n"))
        m.openView(.doc(long)); await wait(0.5)
        a.scope = .document; a.draft = "What is the harvest festival password?"
        let l0 = Date()
        a.send(); await untilIdle(a, timeout: 400)
        r["longDocSeconds"] = String(format: "%.0f", Date().timeIntervalSince(l0))
        r["longDocNotice"] = a.notice ?? ""
        r["longDocAnswer"] = a.chat.messages.last?.text ?? ""
        r["longDocFoundEnd"] = (a.chat.messages.last?.text ?? "").lowercased().contains("heliotrope") ? "yes" : "no"

        for (theme, tag) in [("light", ""), ("dark", "dark-")] {
            m.setSettings { $0.theme = theme }
            for (wd, h, n) in [(1440.0, 900.0, ""), (760.0, 700.0, "narrow-")] {
                w.setFrame(NSRect(x: 60, y: 60, width: wd, height: h), display: true); await wait(0.6)
                await capture(n + tag + "v051-assistant-pinned")
            }
        }
        m.setSettings { $0.theme = "light" }
        w.setFrame(NSRect(x: 60, y: 60, width: 1440, height: 900), display: true)
        m.setAssistantPinned(false); await wait(0.8)
        if let p = m.assistantWindow { await captureWindow(p, "v051-assistant-floating") }
        m.setAssistantPinned(true)
        r["messages"] = "\(a.chat.messages.count)"
        r["space"] = m.library.space.id
        m.flushAll()
        save(r, "assistant-write.json")
    }

    static func assistantRead() async {
        guard let d = try? Data(contentsOf: out.appendingPathComponent("assistant-write.json")),
              let w = try? JSONSerialization.jsonObject(with: d) as? [String: String] else { return }
        var r: [String: String] = [:]
        let chat = AssistantChat.load(m.vault, spaceId: w["space"] ?? "")
        r["messages"] = "\(chat.messages.count)"
        r["sourcesKept"] = chat.messages.contains { !($0.sources ?? []).isEmpty } ? "yes" : "no"
        m.createSpace("Other")
        r["otherSpaceEmpty"] = m.assistant.chat.messages.isEmpty ? "yes" : "no"
        save(r, "assistant-read.json")
    }

    static func captureWindow(_ win: NSWindow, _ name: String) async {
        if let cg = CGWindowListCreateImage(.null, .optionIncludingWindow, CGWindowID(win.windowNumber), [.boundsIgnoreFraming, .bestResolution]),
           let png = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) {
            try? png.write(to: out.appendingPathComponent(name + ".png")); return
        }
        guard let v = win.contentView, let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) else { return }
        v.cacheDisplay(in: v.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: out.appendingPathComponent(name + ".png"))
    }
}

/// `motion-frames`: numbered frames (≈15 fps) of the Assistant opening, answering, the Format panel
/// opening, and the same Assistant moment with Reduce Animations on, for short recordings.
extension Automation {
    static func frames(_ w: NSWindow, _ name: String, seconds: Double, crop: CGRect? = nil) async {
        let dir = out.appendingPathComponent("frames-" + name, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let n = Int(seconds * 15)
        for i in 0..<n {
            let t0 = Date()
            if let cg = CGWindowListCreateImage(.null, .optionIncludingWindow, CGWindowID(w.windowNumber), [.boundsIgnoreFraming, .bestResolution]) {
                let img = crop.flatMap { c -> CGImage? in
                    let s = CGFloat(cg.width) / w.frame.width
                    return cg.cropping(to: CGRect(x: c.minX * s, y: c.minY * s, width: c.width * s, height: c.height * s))
                } ?? cg
                try? NSBitmapImageRep(cgImage: img).representation(using: .png, properties: [:])?.write(to: dir.appendingPathComponent(String(format: "%04d.png", i)))
            }
            let spent = Date().timeIntervalSince(t0)
            if spent < 1.0 / 15 { try? await Task.sleep(nanoseconds: UInt64((1.0 / 15 - spent) * 1e9)) }
        }
    }

    static func motionFrames() async {
        guard let w = NSApp.windows.first(where: { $0.isVisible }) else { return }
        w.setFrame(NSRect(x: 60, y: 60, width: 1280, height: 800), display: true)
        let id = newId("d_")
        var doc = DocFile.empty(id: id, title: "Garden co-op planning")
        doc.content = ensureBlockIds(Node("doc", content: MarkdownImport.blocks(benchNote.components(separatedBy: "\n").dropFirst(2).joined(separator: "\n"))))
        try? m.vault.saveDoc(doc)
        var meta = DocMeta(id: id, title: doc.title); meta.applyDerived(from: doc); meta.spaceId = m.library.space.id
        m.library.docs[id] = meta
        m.rebuildIndex()
        m.openView(.doc(id)); await wait()
        m.setSettings { $0.assistantPinned = true }
        let assistantRect = CGRect(x: 1280 - 380, y: 0, width: 380, height: 800)
        Task { await frames(w, "assistant-open", seconds: 1.2) }
        try? await Task.sleep(nanoseconds: 150_000_000)
        m.toggleAssistant()
        await wait(1.3)
        let a = m.assistant
        a.scope = .space
        a.draft = "When is the plant sale, and who orders the compost?"
        a.send()
        await wait(0.3)
        await frames(w, "assistant-answering", seconds: 3, crop: assistantRect)
        await untilIdle(a)
        m.toggleAssistant(); await wait(0.6)
        Task { await frames(w, "format-panel-open", seconds: 1) }
        try? await Task.sleep(nanoseconds: 150_000_000)
        withAnimation(Motion.panel(m.library.settings.reduceMotion)) { m.panel = .format }
        await wait(1.2)
        m.panel = nil
        m.setSettings { $0.reduceMotion = true }
        m.toggleAssistant(); await wait(0.6)
        a.draft = "Who fixes the pump?"
        a.send(); await wait(0.3)
        await frames(w, "assistant-answering-reduced", seconds: 1.5, crop: assistantRect)
        await untilIdle(a)
        m.setSettings { $0.reduceMotion = false }
    }
}
