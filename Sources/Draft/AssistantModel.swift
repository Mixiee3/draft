import SwiftUI
import Observation
import DraftCore
import DraftEditor
import DraftAssistant

/// The Assistant: local model install, context gathering, streaming generation and per-Space
/// history. Note text only ever goes to the in-process engine.
@MainActor
@Observable
final class AssistantModel {
    enum Status: Equatable {
        case notInstalled, downloading(Double), installed, loading, ready
        case failed(String)
    }

    struct Streaming: Equatable { var thinking = ""; var answer = ""; var inThought = false }

    /// What an Insert or Replace would change, shown before anything is written.
    struct Preview: Identifiable, Equatable {
        let id = UUID()
        var docId: String
        var range: NSRange
        var original: String
        var markdown: String
        var canReplace: Bool
    }

    var isOpen = false
    var status: Status = .notInstalled
    var chat: AssistantChat
    var streaming: Streaming?
    var scope: AssistantScope = .document
    var draft = ""
    var notice: String?
    var preview: Preview?

    @ObservationIgnored unowned let app: AppModel
    @ObservationIgnored let store: ModelStore
    @ObservationIgnored var makeEngine: (URL, LocalModel) throws -> TextGenerator = { try LlamaEngine(path: $0, minimumMemory: $1.minimumMemory) }
    @ObservationIgnored private var engine: TextGenerator?
    @ObservationIgnored private var engineModel: String?
    @ObservationIgnored private var cancelFlag: CancelFlag?
    /// Where an editing request came from, so its result can be previewed against the same text.
    @ObservationIgnored private var target: (docId: String, range: NSRange, original: String)?

    init(app: AppModel, store: ModelStore = ModelStore()) {
        self.app = app
        self.store = store
        chat = AssistantChat.load(app.vault, spaceId: app.library.space.id)
        refreshStatus()
    }

    var model: LocalModel { LocalModel.all.first { $0.id == app.library.settings.assistantModel } ?? .lfm2_6 }
    var isRunning: Bool { streaming != nil }

    func refreshStatus() {
        if case .downloading = status { return }
        status = store.isInstalled(model) ? (engine != nil && engineModel == model.id ? .ready : .installed) : .notInstalled
    }

    func spaceChanged() {
        stop()
        chat = AssistantChat.load(app.vault, spaceId: app.library.space.id)
    }

    /// The model can be created before the library loads, so the Space is checked again on use.
    private func syncSpace() { if chat.spaceId != app.library.space.id { chat = AssistantChat.load(app.vault, spaceId: app.library.space.id) } }

    func toggle() {
        isOpen.toggle()
        if isOpen { syncSpace(); refreshStatus(); scope = defaultScope } else { stop(); unload() }
    }

    var defaultScope: AssistantScope {
        guard let d = app.activeDocId else { return .space }
        return app.editors[d]?.controller.selectedBlocksRange != nil ? .selection : .document
    }

    // MARK: Model install

    func download() {
        guard case .notInstalled = status else { return }
        let m = model
        if SystemMemory.physical < m.minimumMemory {
            status = .failed("This Mac has \(SystemMemory.physical >> 30) GB of memory; \(m.name) needs \(m.minimumMemory >> 30) GB. Choose the smaller model.")
            return
        }
        status = .downloading(0)
        store.download(m, progress: { p in Task { @MainActor in if case .downloading = self.status { self.status = .downloading(p) } } }) { r in
            Task { @MainActor in
                switch r {
                case .success: self.status = .installed
                case .failure(let e as NSError) where e.code == NSURLErrorCancelled: self.status = .notInstalled
                case .failure(let e): self.status = .failed(e.localizedDescription)
                }
            }
        }
    }

    func cancelDownload() { store.cancel(); status = .notInstalled }

    func remove() {
        stop(); unload()
        try? store.remove(model)
        status = .notInstalled
    }

    func chooseModel(_ id: String) {
        stop(); unload()
        app.setSettings { $0.assistantModel = id }
        status = .notInstalled
        refreshStatus()
    }

    func unload() { engine = nil; engineModel = nil; if status == .ready { status = .installed } }

    /// llama.cpp's Metal backend must be freed before the process exits, so quitting stops any
    /// answer, waits briefly for its thread, then releases the model.
    func shutdown() {
        stop()
        let t0 = Date()
        while Generations.active > 0 && Date().timeIntervalSince(t0) < 3 { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
        engine = nil; engineModel = nil
    }

    // MARK: Context

    func markdown(of node: Node) -> String {
        var d = DocFile.empty(id: "assistant", title: "")
        d.content = node
        return Markdown.render(d, assetPath: { _ in "" }, pageLink: { _, _ in nil }, pageTitle: { [app] in app.docTitle($0) }).markdown
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func request(_ action: AssistantAction, question: String) -> AssistantRequest? {
        target = nil
        switch scope {
        case .space:
            let live = Dictionary(app.library.liveDocs.map { ($0.id, $0.title) }, uniquingKeysWith: { a, _ in a })
            let entries = app.index.entries.filter { live[$0.key] != nil }
            let hits = Retrieval.rank(question.isEmpty ? (app.activeDocId.map { app.docTitle($0) } ?? "") : question, entries: entries, titles: live, limit: 10)
            let sources = hits.enumerated().map { i, h -> AssistantSource in
                let full = app.ensureDoc(h.docId)?.content.block(h.blockId).map(docPlainText) ?? h.text
                return AssistantSource(n: i + 1, docId: h.docId, blockId: h.blockId, title: live[h.docId] ?? "", text: String(full.prefix(900)))
            }
            return AssistantRequest(action: action, scope: .space, question: question, retrieved: sources)
        case .selection, .document:
            guard let d = app.activeDocId, let ed = app.editors[d] else { notice = "Open a document first, or ask about this Space."; return nil }
            app.flushAll()
            let c = ed.controller
            let range: NSRange
            if scope == .selection {
                guard let r = c.selectedBlocksRange else { notice = "Select some text in the document first."; return nil }
                range = r
            } else {
                range = NSRange(location: 0, length: c.storage.length)
            }
            let text = markdown(of: scope == .selection ? c.fragment(range) : c.document())
            guard !text.isEmpty else { notice = "There is no text to work with yet."; return nil }
            target = (d, range, (c.storage.string as NSString).substring(with: range))
            return AssistantRequest(action: action, scope: scope, question: question, text: text, docId: d, docTitle: app.docTitle(d))
        }
    }

    // MARK: Run

    func send(_ action: AssistantAction = .ask) {
        guard !isRunning else { return }
        syncSpace()
        let question = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        if action == .ask, question.isEmpty { return }
        guard status == .installed || status == .ready else { notice = "Download the model first (below)."; return }
        notice = nil
        guard let req = request(action, question: question) else { return }
        let history = chat.turns
        let prepared = AssistantPrompt.prepare(req, history: req.scope == .space ? history : [], budgetTokens: 5200)
        if prepared.includedFraction < 1 {
            notice = "This document is longer than the model can read at once; it used the first \(Int(prepared.includedFraction * 100))%."
        }
        let label = action == .ask ? question : action.title + (question.isEmpty ? "" : ": " + question)
        chat.messages.append(AssistantMessage(role: "user", text: label, action: action, scope: req.scope))
        draft = ""
        streaming = Streaming()
        let flag = CancelFlag()
        cancelFlag = flag
        let m = model, path = store.path(for: m)
        let existing = engineModel == m.id ? engine : nil
        let make = makeEngine
        if existing == nil { status = .loading }
        let target = self.target
        Generations.begin()
        Thread.detachNewThread { [weak self] in
            defer { Generations.end() }
            Thread.current.qualityOfService = .userInitiated
            let activity = ProcessInfo.processInfo.beginActivity(options: [.userInitiated], reason: "Assistant answer")
            defer { ProcessInfo.processInfo.endActivity(activity) }
            var splitter = ThinkSplitter()
            var lastPublish = Date.distantPast
            let result: Result<GenerationStats, Error> = Result {
                let e = try existing ?? make(path, m)
                if existing == nil { onMainSync { self?.engineLoaded(e, id: m.id) } }
                let s = try e.generate(prepared.turns, maxTokens: 1536, cancel: flag) { piece in
                    splitter.feed(piece)
                    if Date().timeIntervalSince(lastPublish) > 0.06 {
                        lastPublish = Date()
                        let snap = Streaming(thinking: splitter.thinking, answer: splitter.answer, inThought: splitter.inThought)
                        Task { @MainActor in if self?.cancelFlag === flag { self?.streaming = snap } }
                    }
                }
                return s
            }
            splitter.finish()
            let final = splitter
            Task { @MainActor in self?.finished(result, final, prepared: prepared, action: action, scope: req.scope, target: target, flag: flag) }
        }
    }

    private func engineLoaded(_ e: TextGenerator, id: String) {
        engine = e; engineModel = id
        status = .ready
    }

    /// Timing of the last finished answer (the follow-up speed check reads it).
    @ObservationIgnored var lastStats: GenerationStats?

    private func finished(_ result: Result<GenerationStats, Error>, _ s: ThinkSplitter, prepared: PreparedPrompt, action: AssistantAction, scope: AssistantScope,
                          target: (docId: String, range: NSRange, original: String)?, flag: CancelFlag) {
        guard cancelFlag === flag else { return }
        streaming = nil
        cancelFlag = nil
        switch result {
        case .success(let stats):
            lastStats = stats
            var answer = s.answer.trimmingCharacters(in: .whitespacesAndNewlines)
            if answer.isEmpty && !s.thinking.isEmpty { answer = stats.cancelled ? "" : "The model ran out of room before answering. Try a shorter request or a smaller context." }
            if stats.cancelled { answer += answer.isEmpty ? "Stopped." : "\n\n(Stopped.)" }
            let cited = Citations.cited(in: answer, sourceCount: prepared.sources.count)
            let sources = scope == .space ? prepared.sources.filter { cited.contains($0.n) } : prepared.sources
            var msg = AssistantMessage(role: "assistant", text: answer, action: action, scope: scope, sources: sources.isEmpty ? nil : sources)
            if stats.cancelled { msg.failed = true }
            chat.messages.append(msg)
            if let t = target, action.producesText, !stats.cancelled { lastTarget[msg.id] = t }
        case .failure(let e):
            chat.messages.append(AssistantMessage(role: "assistant", text: e.localizedDescription, action: action, scope: scope, failed: true))
            if engine == nil { refreshStatus() }
        }
        try? chat.save(app.vault)
    }

    @ObservationIgnored private var lastTarget: [String: (docId: String, range: NSRange, original: String)] = [:]

    func stop() { cancelFlag?.cancel() }

    func clearHistory() {
        stop()
        chat.messages = []
        AssistantChat.delete(app.vault, spaceId: chat.spaceId)
    }

    // MARK: Insert / Replace

    func canEdit(_ m: AssistantMessage) -> Bool { lastTarget[m.id] != nil || (m.role == "assistant" && m.failed != true && app.activeDocId != nil && m.action?.producesText == true) }

    /// Builds the preview. Replace is offered only while the original text is still there unchanged.
    func previewEdit(_ m: AssistantMessage) {
        if let t = lastTarget[m.id], let ed = app.editors[t.docId] {
            let s = ed.controller.storage.string as NSString
            let still = NSMaxRange(t.range) <= s.length && s.substring(with: t.range) == t.original
            preview = Preview(docId: t.docId, range: still ? t.range : ed.controller.textView.selectedRange(), original: still ? t.original : "", markdown: m.text, canReplace: still)
        } else if let d = app.activeDocId, let ed = app.editors[d] {
            let sel = ed.controller.selectedBlocksRange ?? ed.controller.textView.selectedRange()
            preview = Preview(docId: d, range: sel, original: "", markdown: m.text, canReplace: false)
        }
    }

    func apply(_ p: Preview, replace: Bool) {
        guard let ed = app.editors[p.docId] else { preview = nil; return }
        if app.activeDocId != p.docId { app.openView(.doc(p.docId)) }
        ed.controller.applyAssistant(p.markdown, range: p.range, replace: replace && p.canReplace,
                                     actionName: replace && p.canReplace ? "Replace with Assistant Text" : "Insert Assistant Text")
        preview = nil
    }

    func open(_ s: AssistantSource) {
        if let b = s.blockId { app.openBlock(s.docId, b) } else { app.openView(.doc(s.docId)) }
    }
}

/// Generation threads still running (read on quit).
enum Generations {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var count = 0
    static var active: Int { lock.lock(); defer { lock.unlock() }; return count }
    static func begin() { lock.lock(); count += 1; lock.unlock() }
    static func end() { lock.lock(); count -= 1; lock.unlock() }
}

/// Runs `body` on the main thread and waits, so a loaded engine is owned by the model before
/// generation starts (a quit in between can then still free it).
func onMainSync(_ body: @escaping @MainActor () -> Void) {
    DispatchQueue.main.sync { onMain(body) }
}
