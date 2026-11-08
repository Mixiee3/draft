import SwiftUI
import AppKit
import DraftCore
import DraftAssistant
import ThinkingOrbsKit

/// The Assistant surface: the same view pinned beside the editor or in its own floating window.
struct AssistantView: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var a: AssistantModel
    @Environment(\.tokens) var t
    var floating = false
    @FocusState private var composerFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.5)
            if a.provider == .openai {
                if a.cloudKeyAvailable { conversation } else { CloudSetupCard(a: a) }
            } else if installed, a.status != .notInstalled { conversation } else { InstallCard(a: a) }
        }
        .background(t.canvas)
        .modifier(EffectsGate(reduce: model.library.settings.reduceMotion))
        .sheet(item: $a.preview) { p in EditPreview(a: a, preview: p).environment(\.tokens, t) }
        .sheet(item: $a.cloudConsent) { c in CloudConsentView(a: a, consent: c).environment(\.tokens, t) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Assistant")
    }

    var installed: Bool { a.store.isInstalled(a.model) }

    var header: some View {
        HStack(spacing: DS.s2) {
            if a.isRunning {
                AssistantOrb(state: orbState, side: 20)
            } else {
                Image(systemName: "sparkle").font(.system(size: DS.headline, weight: .semibold)).foregroundStyle(t.accent).frame(width: 20).accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 0) {
                Text("Assistant").font(.system(size: DS.headline, weight: .semibold)).foregroundStyle(t.text)
                Text(a.provider == .local ? "Runs on this Mac · \(a.model.name)" : "OpenAI API · \(model.library.settings.openAIModel)")
                    .font(.system(size: DS.caption)).foregroundStyle(t.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
            Menu {
                Picker("Provider", selection: Binding(get: { a.provider }, set: { a.chooseProvider($0) })) {
                    ForEach(AssistantProvider.allCases, id: \.self) { provider in Text(provider.title).tag(provider) }
                }
                Divider()
                Button("Clear History for This Space", role: .destructive) { a.clearHistory() }.disabled(a.chat.messages.isEmpty)
                Button("Assistant Settings…") { model.openView(ViewRef(kind: "settings", section: "assistant")) }
            } label: { Image(systemName: "ellipsis").frame(width: 24, height: 24) }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().help("More").accessibilityLabel("More")
            IconButton(symbol: floating ? "sidebar.right" : "macwindow.on.rectangle", label: floating ? "Pin to the Window" : "Float in Its Own Window", size: 26) {
                model.setAssistantPinned(floating)
            }
            IconButton(symbol: "xmark", label: "Close Assistant (⌘J)", size: 26) { model.toggleAssistant() }
        }
        .padding(.horizontal, DS.s4).frame(height: 54)
    }

    var orbState: OrbState {
        guard let s = a.streaming else { return .breathing }
        if a.status == .loading { return .breathing }
        if s.answer.isEmpty && s.thinking.isEmpty { return a.scope == .space ? .searching : .working }
        return s.inThought ? .solving : .composing
    }

    // MARK: Conversation

    var conversation: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: DS.s3) {
                        if a.chat.messages.isEmpty && a.streaming == nil { EmptyAssistant(a: a) }
                        ForEach(a.chat.messages) { m in MessageRow(a: a, m: m).id(m.id) }
                        if let s = a.streaming { StreamingRow(a: a, s: s, state: orbState).id("streaming") }
                    }
                    .padding(DS.s4)
                }
                .onChange(of: a.chat.messages.count) { _, _ in withAnimation(Motion.quick(model.library.settings.reduceMotion)) { proxy.scrollTo(a.chat.messages.last?.id, anchor: .bottom) } }
                .onChange(of: a.streaming?.answer.count ?? -1) { _, _ in proxy.scrollTo("streaming", anchor: .bottom) }
            }
            if let n = a.notice {
                Label(n, systemImage: "info.circle").font(.system(size: DS.footnote)).foregroundStyle(t.secondary)
                    .padding(.horizontal, DS.s4).padding(.vertical, DS.s2).frame(maxWidth: .infinity, alignment: .leading)
            }
            composer
        }
    }

    var composer: some View {
        VStack(alignment: .leading, spacing: DS.s2) {
            DraftSegmented("Context", selection: $a.scope, symbols: [(.selection, "Selection", "text.cursor"), (.document, "Document", "doc.text"), (.space, "Space", "square.stack")], stretch: true)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: DS.s1 + 2), count: 3), spacing: DS.s1 + 2) {
                ForEach([AssistantAction.summarize, .explain, .rewrite, .shorten, .expand, .outline], id: \.self) { act in
                    ChipButton(title: act == .outline ? "Outline" : act.title, font: .system(size: DS.footnote, weight: .medium), isEnabled: !a.isRunning && a.scope != .space, height: DS.controlSmall + 4) { a.send(act) }
                }
            }
            ActiveBeam(active: a.isRunning, radius: DS.rCard) {
                HStack(alignment: .bottom, spacing: DS.s2) {
                    TextField(a.scope == .space ? "Ask about the notes in this Space…" : "Ask about this text…", text: $a.draft, axis: .vertical)
                        .textFieldStyle(.plain).font(.system(size: DS.body)).lineLimit(1...5)
                        .focused($composerFocused)
                        .onSubmit { a.send() }
                        .padding(.vertical, 7)
                        .accessibilityLabel("Message to the Assistant")
                    SendButton(running: a.isRunning, enabled: a.isRunning || !a.draft.trimmingCharacters(in: .whitespaces).isEmpty) { a.isRunning ? a.stop() : a.send() }
                }
                .padding(.leading, DS.s3).padding(.trailing, DS.s1 + 2).padding(.vertical, DS.s1 + 1)
                .background(RoundedRectangle(cornerRadius: DS.rCard, style: .continuous).fill(t.card))
                .overlay(RoundedRectangle(cornerRadius: DS.rCard, style: .continuous).strokeBorder(composerFocused ? t.accent.opacity(0.55) : t.line, lineWidth: 1))
            }
            Text(a.provider == .local
                 ? "Answers come only from the notes you choose and can be wrong. Nothing leaves this Mac."
                 : "OpenAI receives only the context you review before sending. Answers may be wrong; API usage may be billed.")
                .font(.system(size: DS.caption)).foregroundStyle(t.tertiary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(DS.s4)
        .onAppear { composerFocused = true }
    }
}

/// The primary action: liquid-metal edge while idle, Stop while generating.
struct SendButton: View {
    @Environment(\.tokens) var t
    var running: Bool
    var enabled: Bool
    var action: () -> Void
    @State private var hover = false
    var body: some View {
        Button(action: action) {
            Image(systemName: running ? "stop.fill" : "arrow.up")
                .font(.system(size: DS.body, weight: .bold))
                .foregroundStyle(enabled ? Color.white : t.tertiary)
                .frame(width: 32, height: 32)
                .background(Circle().fill(enabled ? (t.dark ? Color(hex: "#2d2f36") : Color(hex: "#1f2026")) : t.hover))
                .overlay(LiquidMetalEdge(cornerRadius: 16, lineWidth: 1.8, lively: enabled && (hover || running)).opacity(enabled ? 1 : 0))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .onHover { hover = $0 }
        .keyboardShortcut(running ? "." : .return, modifiers: running ? .command : [])
        .help(running ? "Stop (⌘.)" : "Send (Return)")
        .accessibilityLabel(running ? "Stop generating" : "Send")
    }
}

struct EmptyAssistant: View {
    @ObservedObject var a: AssistantModel
    @Environment(\.tokens) var t
    var body: some View {
        VStack(alignment: .leading, spacing: DS.s2) {
            Text("Ask about your notes, or pick an action below.").font(.system(size: DS.body, weight: .medium)).foregroundStyle(t.text)
            Text("Selection and Document work on the open document. Space searches every note in this Space and shows which ones it used.")
                .font(.system(size: DS.footnote)).foregroundStyle(t.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(DS.s3).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: DS.rCard, style: .continuous).fill(t.hover))
    }
}

struct MessageRow: View {
    @ObservedObject var a: AssistantModel
    let m: AssistantMessage
    @Environment(\.tokens) var t

    var body: some View {
        if m.role == "user" {
            HStack {
                Spacer(minLength: 40)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(m.text).font(.system(size: DS.body)).foregroundStyle(t.text).textSelection(.enabled)
                    if let s = m.scope { Text(s.title).font(.system(size: DS.caption)).foregroundStyle(t.tertiary) }
                }
                .padding(.horizontal, DS.s3).padding(.vertical, DS.s2)
                .background(RoundedRectangle(cornerRadius: DS.rCard, style: .continuous).fill(t.accent.opacity(t.dark ? 0.22 : 0.1)))
            }
        } else {
            VStack(alignment: .leading, spacing: DS.s2) {
                MarkdownText(text: m.text).foregroundStyle(m.failed == true ? t.secondary : t.text)
                if let sources = m.sources, !sources.isEmpty, m.scope == .space {
                    SourceList(a: a, sources: sources)
                }
                if m.failed != true, m.action?.producesText == true || m.scope != .space {
                    HStack(spacing: DS.s1 + 2) {
                        if a.canEdit(m) {
                            ChipButton(title: "Insert or Replace…", symbol: "text.insert", font: .system(size: DS.footnote, weight: .medium), height: DS.controlSmall + 2) { a.previewEdit(m) }.fixedSize()
                        }
                        ChipButton(title: "Copy", symbol: "doc.on.doc", font: .system(size: DS.footnote, weight: .medium), height: DS.controlSmall + 2) {
                            NSPasteboard.general.clearContents(); NSPasteboard.general.setString(m.text, forType: .string)
                        }.fixedSize()
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Assistant answer")
        }
    }
}

/// Inline Markdown (bold, italics, links, code) per line, with lists and headings kept readable.
struct MarkdownText: View {
    let text: String
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(Array(text.components(separatedBy: "\n").enumerated()), id: \.offset) { _, line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                let heading = trimmed.hasPrefix("#")
                let body = heading ? String(trimmed.drop { $0 == "#" }).trimmingCharacters(in: .whitespaces) : line
                Text((try? AttributedString(markdown: body, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(body))
                    .font(.system(size: heading ? DS.headline : DS.body, weight: heading ? .semibold : .regular))
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
        }
    }
}

struct SourceList: View {
    @ObservedObject var a: AssistantModel
    let sources: [AssistantSource]
    @Environment(\.tokens) var t
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("SOURCES").font(.system(size: DS.caption, weight: .semibold)).foregroundStyle(t.tertiary)
            ForEach(sources) { s in
                Button { a.open(s) } label: {
                    HStack(alignment: .top, spacing: DS.s2) {
                        Text("\(s.n)").font(.system(size: DS.caption, weight: .bold)).foregroundStyle(t.accent)
                            .frame(width: 18, height: 18).background(Circle().fill(t.accent.opacity(0.14)))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(s.title.isEmpty ? "Untitled" : s.title).font(.system(size: DS.footnote, weight: .semibold)).foregroundStyle(t.text).lineLimit(1)
                            Text(s.text).font(.system(size: DS.footnote)).foregroundStyle(t.secondary).lineLimit(2)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "arrow.up.right").font(.system(size: DS.caption, weight: .semibold)).foregroundStyle(t.tertiary)
                    }
                    .padding(DS.s2).contentShape(Rectangle())
                    .background(RoundedRectangle(cornerRadius: DS.rControl, style: .continuous).fill(t.hover))
                }
                .buttonStyle(.plain)
                .help("Open “\(s.title)” at this block")
                .accessibilityLabel("Source \(s.n): \(s.title). \(s.text)")
                .accessibilityHint("Opens the document at this block")
            }
        }
    }
}

struct StreamingRow: View {
    @ObservedObject var a: AssistantModel
    let s: AssistantModel.Streaming
    let state: OrbState
    @Environment(\.tokens) var t
    @State private var showThinking = false
    var body: some View {
        VStack(alignment: .leading, spacing: DS.s2) {
            HStack(spacing: DS.s2) {
                AssistantOrb(state: state, side: 22)
                Text(statusText).font(.system(size: DS.footnote, weight: .medium)).foregroundStyle(t.secondary)
                if !s.thinking.isEmpty {
                    Button(showThinking ? "Hide reasoning" : "Show reasoning") { showThinking.toggle() }
                        .buttonStyle(.plain).font(.system(size: DS.footnote)).foregroundStyle(t.accent)
                }
            }
            if showThinking, !s.thinking.isEmpty {
                Text(s.thinking).font(.system(size: DS.footnote)).foregroundStyle(t.tertiary).lineLimit(12).textSelection(.enabled)
            }
            if !s.answer.isEmpty { MarkdownText(text: s.answer).foregroundStyle(t.text) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(statusText + (s.answer.isEmpty ? "" : ". " + s.answer))
    }
    var statusText: String {
        if a.provider == .openai { return s.answer.isEmpty ? "Contacting OpenAI…" : "Writing…" }
        if a.status == .loading { return "Loading the model…" }
        if s.answer.isEmpty && s.thinking.isEmpty { return a.scope == .space ? "Searching this Space…" : "Reading…" }
        return s.inThought ? "Thinking…" : "Writing…"
    }
}

struct InstallCard: View {
    @ObservedObject var a: AssistantModel
    @Environment(\.tokens) var t
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.s3) {
                Text("A private assistant for your notes").font(.system(size: DS.title3, weight: .semibold)).foregroundStyle(t.text)
                Text("Draft can summarize, explain and rewrite your notes, and answer questions about them, with a language model that runs entirely on this Mac. No account, no subscription, and your notes are never sent anywhere.")
                    .font(.system(size: DS.body)).foregroundStyle(t.secondary).fixedSize(horizontal: false, vertical: true)
                ModelFacts(model: a.model)
                switch a.status {
                case .downloading(let p):
                    VStack(alignment: .leading, spacing: DS.s1) {
                        ProgressView(value: p).progressViewStyle(.linear).accessibilityLabel("Download progress")
                        HStack {
                            Text("\(ByteCountFormatter.string(fromByteCount: Int64(Double(a.model.bytes) * p), countStyle: .file)) of \(ByteCountFormatter.string(fromByteCount: a.model.bytes, countStyle: .file))")
                                .font(.system(size: DS.footnote)).foregroundStyle(t.secondary).monospacedDigit()
                            Spacer()
                            Button("Cancel") { a.cancelDownload() }.controlSize(.small)
                        }
                    }
                case .failed(let msg):
                    Label(msg, systemImage: "exclamationmark.triangle").font(.system(size: DS.footnote)).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                    downloadButton(retry: true)
                default:
                    downloadButton(retry: false)
                }
                Text("The download comes from Liquid AI's page on Hugging Face and is checked against its published checksum. After that, the Assistant works with networking turned off. You can remove the model any time in Settings → Assistant.")
                    .font(.system(size: DS.caption)).foregroundStyle(t.tertiary).fixedSize(horizontal: false, vertical: true)
            }
            .padding(DS.s4)
        }
    }

    func downloadButton(retry: Bool) -> some View {
        Button { if retry { a.status = .notInstalled }; a.download() } label: {
            Text("\(retry ? "Try Again" : "Download") · \(ByteCountFormatter.string(fromByteCount: a.model.bytes, countStyle: .file))")
                .font(.system(size: DS.body, weight: .semibold)).foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: DS.controlLarge)
                .background(RoundedRectangle(cornerRadius: DS.rCard, style: .continuous).fill(t.dark ? Color(hex: "#2d2f36") : Color(hex: "#1f2026")))
                .overlay(LiquidMetalEdge(cornerRadius: DS.rCard, lineWidth: 1.6, lively: true))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Download \(a.model.name), \(ByteCountFormatter.string(fromByteCount: a.model.bytes, countStyle: .file))")
    }
}

struct CloudSetupCard: View {
    @ObservedObject var a: AssistantModel
    @Environment(\.tokens) var t
    var body: some View {
        VStack(alignment: .leading, spacing: DS.s3) {
            Text("Connect OpenAI").font(.system(size: DS.title3, weight: .semibold))
            Text("Add your own OpenAI API key in Settings → Assistant. Draft will ask you to review the exact note context before each request. Your local Assistant remains available offline.")
                .font(.system(size: DS.body)).foregroundStyle(t.secondary)
            Button("Open Assistant Settings") { a.app.openView(ViewRef(kind: "settings", section: "assistant")) }
        }
        .padding(DS.s4).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

struct CloudConsentView: View {
    @ObservedObject var a: AssistantModel
    let consent: AssistantModel.CloudConsent
    @Environment(\.tokens) var t
    var body: some View {
        VStack(alignment: .leading, spacing: DS.s3) {
            Text("Review what OpenAI will receive").font(.system(size: DS.headline, weight: .semibold))
            Text("Context: \(consent.request.scope.title) · Model: \(a.app.library.settings.openAIModel)")
                .font(.system(size: DS.footnote)).foregroundStyle(t.secondary)
            ScrollView {
                Text(consent.prepared.turns.filter { $0.role != "system" }.map { "\($0.role.capitalized):\n\($0.text)" }.joined(separator: "\n\n"))
                    .font(.system(size: DS.footnote, design: .monospaced)).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(DS.s3)
            }
            .frame(minHeight: 150, maxHeight: 330)
            .background(RoundedRectangle(cornerRadius: DS.rControl).fill(t.hover))
            Text("Only the context and conversation shown here are sent. The API key is sent only to OpenAI for authentication; Draft does not send your whole vault.")
                .font(.system(size: DS.caption)).foregroundStyle(t.secondary)
            HStack {
                Button("Cancel") { a.cloudConsent = nil }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Send to OpenAI") { a.confirmCloudSend() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(DS.s5).frame(width: 560)
    }
}

struct ModelFacts: View {
    let model: LocalModel
    @Environment(\.tokens) var t
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            fact("Model", "\(model.name) by Liquid AI (\(model.parameters))")
            fact("Size", ByteCountFormatter.string(fromByteCount: model.bytes, countStyle: .file))
            HStack(alignment: .firstTextBaseline, spacing: DS.s2) {
                Text("License").font(.system(size: DS.footnote, weight: .medium)).foregroundStyle(t.secondary).frame(width: 64, alignment: .leading)
                Link(model.license + " (open weights)", destination: model.licenseURL).font(.system(size: DS.footnote))
            }
        }
        .padding(DS.s3).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: DS.rCard, style: .continuous).fill(t.hover))
    }
    func fact(_ k: String, _ v: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.s2) {
            Text(k).font(.system(size: DS.footnote, weight: .medium)).foregroundStyle(t.secondary).frame(width: 64, alignment: .leading)
            Text(v).font(.system(size: DS.footnote)).foregroundStyle(t.text)
        }
    }
}

/// Shows exactly what would change before anything is written to the note.
struct EditPreview: View {
    @ObservedObject var a: AssistantModel
    let preview: AssistantModel.Preview
    @Environment(\.tokens) var t
    @Environment(\.dismiss) var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: DS.s3) {
            Text(preview.canReplace ? "Review the change" : "Review the text to insert").font(.system(size: DS.headline, weight: .semibold))
            ScrollView {
                diffText.font(.system(size: DS.body)).frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled).padding(DS.s3)
            }
            .frame(minHeight: 160, maxHeight: 360)
            .background(RoundedRectangle(cornerRadius: DS.rControl, style: .continuous).fill(t.hover))
            if preview.canReplace {
                HStack(spacing: DS.s3) {
                    Label("Removed", systemImage: "minus").foregroundStyle(.red)
                    Label("Added", systemImage: "plus").foregroundStyle(.green)
                }.font(.system(size: DS.caption))
            } else {
                Text("The original text changed or isn't selected, so the result can only be inserted after the selection or cursor.").font(.system(size: DS.footnote)).foregroundStyle(t.secondary)
            }
            HStack {
                Button("Cancel") { a.preview = nil }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Insert Below") { a.apply(preview, replace: false) }
                if preview.canReplace { Button("Replace") { a.apply(preview, replace: true) }.keyboardShortcut(.defaultAction) }
            }
            Text("You can undo the change with ⌘Z.").font(.system(size: DS.caption)).foregroundStyle(t.tertiary)
        }
        .padding(DS.s5)
        .frame(width: 520)
    }

    var diffText: Text {
        guard preview.canReplace else { return Text(preview.markdown) }
        return WordDiff.diff(preview.original, preview.markdown).reduce(Text("")) { acc, p in
            switch p.op {
            case .same: return acc + Text(p.text)
            case .removed: return acc + Text(p.text).strikethrough().foregroundColor(.red)
            case .added: return acc + Text(p.text).foregroundColor(.green).underline()
            }
        }
    }
}

struct AssistantSettings: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var a: AssistantModel
    @Environment(\.tokens) var t
    @State private var keyInput = ""
    @State private var keyNotice: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: DS.s2) {
                Text("Assistant provider").font(.system(size: DS.body, weight: .semibold))
                DraftSegmented("Provider", selection: Binding(get: { a.provider }, set: { a.chooseProvider($0) }),
                               options: AssistantProvider.allCases.map { ($0, $0.title) })
                Text("On This Mac remains available without an account or network. OpenAI API is optional and uses your own API key.")
                    .font(.system(size: DS.footnote)).foregroundStyle(t.secondary)
            }
            VStack(alignment: .leading, spacing: DS.s2) {
                Text("OpenAI API").font(.system(size: DS.body, weight: .semibold))
                TextField("Model ID", text: Binding(get: { model.library.settings.openAIModel }, set: { value in model.setSettings { $0.openAIModel = value } }))
                    .textFieldStyle(.roundedBorder)
                Text(a.cloudKeyAvailable ? "API key saved in this Mac's Keychain" : "No API key saved")
                    .font(.system(size: DS.footnote)).foregroundStyle(t.secondary)
                SecureField("Paste OpenAI API key", text: $keyInput).textFieldStyle(.roundedBorder)
                HStack {
                    Button("Save Key") {
                        keyNotice = OpenAIKeyStore.save(keyInput.trimmingCharacters(in: .whitespacesAndNewlines)) ? "Key saved." : "Could not save the key."
                        keyInput = ""
                        a.refreshCloudKey()
                    }.disabled(keyInput.isEmpty)
                    Button("Remove Key", role: .destructive) {
                        _ = OpenAIKeyStore.remove()
                        keyNotice = "Key removed."
                        a.refreshCloudKey()
                    }.disabled(!a.cloudKeyAvailable)
                }
                if let keyNotice { Text(keyNotice).font(.system(size: DS.footnote)).foregroundStyle(t.secondary) }
                Text("Cloud requests use the OpenAI Responses API. Draft shows the context before each request and never stores the key in the vault.")
                    .font(.system(size: DS.footnote)).foregroundStyle(t.secondary)
            }
            VStack(alignment: .leading, spacing: DS.s2) {
                Text("Local model").font(.system(size: DS.body, weight: .semibold))
                DraftSegmented("Model", selection: Binding(get: { a.model.id }, set: { a.chooseModel($0) }),
                               options: LocalModel.all.map { ($0.id, $0.name + " · " + ByteCountFormatter.string(fromByteCount: $0.bytes, countStyle: .file)) })
                ModelFacts(model: a.model)
                HStack(spacing: DS.s2) {
                    Text(statusText).font(.system(size: DS.body)).foregroundStyle(t.secondary)
                    Spacer()
                    if a.store.isInstalled(a.model) {
                        Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([a.store.path(for: a.model)]) }
                        Button("Remove Model…", role: .destructive) { a.remove() }
                    } else if case .downloading = a.status {
                        Button("Cancel Download") { a.cancelDownload() }
                    } else {
                        Button("Download") { a.status = .notInstalled; a.download() }
                    }
                }
            }
            VStack(alignment: .leading, spacing: DS.s2) {
                Text("Privacy").font(.system(size: DS.body, weight: .semibold))
                Text("The local model runs inside Draft on this Mac and does not send note content online. If you choose OpenAI API, Draft shows the exact context and conversation before every request. Chat history is saved separately by provider and Space in your vault (assistant/), and Clear History removes the selected conversation.")
                    .font(.system(size: DS.footnote)).foregroundStyle(t.secondary).fixedSize(horizontal: false, vertical: true)
                Text("Models are stored in \(a.store.directory.path), outside your vault, so backups and exports never include them.")
                    .font(.system(size: DS.footnote)).foregroundStyle(t.tertiary).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: DS.s2) {
                Text("Limits").font(.system(size: DS.body, weight: .semibold))
                Text("A small local model reads only the context you choose: a selection, the open document (very long ones are cut to what fits), or the most relevant blocks of this Space. It can misread notes or be wrong; check answers against the sources it shows.")
                    .font(.system(size: DS.footnote)).foregroundStyle(t.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    var statusText: String {
        switch a.status {
        case .notInstalled: return "Not downloaded"
        case .downloading(let p): return "Downloading… \(Int(p * 100))%"
        case .installed: return "Downloaded and verified"
        case .loading: return "Loading…"
        case .ready: return "Loaded and ready"
        case .failed(let m): return m
        }
    }
}
