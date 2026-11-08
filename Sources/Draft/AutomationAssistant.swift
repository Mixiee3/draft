import AppKit
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
            var peak = SystemMemory.footprint
            var results: [String: Any] = [:]
            for (name, req) in tasks {
                let p = AssistantPrompt.prepare(req)
                var out = ""
                let flag = CancelFlag()
                let s = (try? engine.generate(p.turns, maxTokens: 300, cancel: flag) { out += $0; peak = max(peak, SystemMemory.footprint) }) ?? GenerationStats()
                results[name] = ["text": out, "promptTokens": s.promptTokens, "tokens": s.generatedTokens, "ttft": s.firstTokenSeconds, "tps": s.tokensPerSecond,
                                 "cited": Citations.cited(in: out, sourceCount: p.sources.count)]
            }
            // Cancellation: stop after the first piece and check that generation ends promptly.
            let flag = CancelFlag()
            var pieces = 0
            let c0 = Date()
            let s = try? engine.generate(AssistantPrompt.prepare(tasks[4].1).turns, maxTokens: 300, cancel: flag) { _ in pieces += 1; if pieces == 3 { flag.cancel() } }
            results["cancel"] = ["cancelled": s?.cancelled ?? false, "tokens": s?.generatedTokens ?? -1, "seconds": Date().timeIntervalSince(c0)]
            r["peakFootprintMB"] = Int((peak - before) >> 20)
            r["results"] = results
            report.append(r)
        }
        if let d = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) { try? d.write(to: out.appendingPathComponent("assistant-bench.json")) }
    }
}
