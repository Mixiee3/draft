import SwiftUI
import AppKit
import DraftCore
import DraftEditor

/// First-use welcome and the five-step tour (docs/UI_AUDIT_V06.md §6).
enum Onboarding: Equatable {
    case welcome
    case tour(Int)

    static let version = 1
}

enum TourTarget: Hashable { case sidebar, newNote, page, style, assistant }

struct TourAnchorKey: PreferenceKey {
    static let defaultValue: [TourTarget: Anchor<CGRect>] = [:]
    static func reduce(value: inout [TourTarget: Anchor<CGRect>], nextValue: () -> [TourTarget: Anchor<CGRect>]) {
        let next = nextValue()
        if !next.isEmpty { value.merge(next) { $1 } }
    }
}

extension View {
    /// Marks a control the tour can point at.
    func tourAnchor(_ target: TourTarget) -> some View { anchorPreference(key: TourAnchorKey.self, value: .bounds) { [target: $0] } }
}

struct TourStep {
    let target: TourTarget
    let title: String
    let text: String
    var note: String? = nil
}

extension AppModel {
    static let tourSteps: [TourStep] = [
        TourStep(target: .sidebar, title: "Your sidebar and Spaces",
                 text: "Everything in this Space is here: all notes, Today, Calendar and Tasks. Click the Space name to make another Space for work, study or home."),
        TourStep(target: .newNote, title: "Start a note",
                 text: "Click + or press ⌘N. Notes are saved as you type, as plain files in Draft's folder on this Mac.",
                 note: "Settings → Data & Storage shows the folder."),
        TourStep(target: .page, title: "Write, then format",
                 text: "Select words to bold, highlight or link them. On an empty line, type / to add a heading, checklist, table or collection."),
        TourStep(target: .style, title: "Make it look yours",
                 text: "Aa formats the current block. The brush opens styles: backdrops, paper, fonts and separators. Style never changes your words."),
        TourStep(target: .assistant, title: "A private Assistant, if you want one",
                 text: "Ask about a note or your whole Space, or have it summarize and rewrite. It needs a one-time 1.6 GB download and then runs entirely on this Mac.",
                 note: "Download it now, later from Settings → Assistant, or never. Draft works fully without it."),
    ]

    static let tourSample = "Select these words to see the formatting bar.\nOn an empty line, type / to add a block."

    /// Shown once on first launch (not during automation).
    func showWelcomeIfNeeded() {
        guard library.settings.onboardingSeen < Onboarding.version, ProcessInfo.processInfo.environment["DRAFT_AUTOMATION"] == nil else { return }
        onboarding = .welcome
    }

    func showWelcome() { onboarding = .welcome }

    func startTour() {
        if activeView.kind != "all" { activateTab(tabs[0].id) }
        onboarding = .tour(0)
    }

    func tourGo(_ step: Int) {
        guard step >= 0, step < Self.tourSteps.count else { finishOnboarding(startWriting: step >= Self.tourSteps.count); return }
        let target = Self.tourSteps[step].target
        switch target {
        case .sidebar, .newNote:
            if activeView.kind != "all" { activateTab(tabs[0].id) }
        case .page, .style:
            if tourNote == nil || docs[tourNote!] == nil {
                tourNote = createDoc(title: "Draft tour")
                if let id = tourNote {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in self?.editors[id]?.controller.pastePlainForAutomation(Self.tourSample) }
                }
            } else if activeDocId != tourNote { openView(.doc(tourNote!)) }
            if target == .page, let id = tourNote {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                    guard let c = self?.editors[id]?.controller else { return }
                    c.textView.window?.makeFirstResponder(c.textView)
                    c.textView.setSelectedRange((c.textView.string as NSString).range(of: "these words"))
                }
            }
        case .assistant:
            break
        }
        onboarding = .tour(step)
    }

    func finishOnboarding(startWriting: Bool) {
        onboarding = nil
        setSettings { $0.onboardingSeen = Onboarding.version }
        if let id = tourNote, let c = editors[id]?.controller, c.textView.string == Self.tourSample || c.textView.string.isEmpty {
            deleteForever([id])
        }
        tourNote = nil
        if startWriting { createDoc() }
    }
}

// MARK: - Welcome

struct WelcomeView: View {
    @Environment(AppModel.self) var model
    @Environment(\.tokens) var t
    @FocusState private var focused: Bool

    var body: some View {
        ZStack {
            Rectangle().fill(.black.opacity(t.dark ? 0.35 : 0.18)).ignoresSafeArea()
            VStack(spacing: 0) {
                DraftMark().frame(width: 72, height: 72).padding(.bottom, DS.s5)
                Text("Welcome to Draft").font(.system(size: DS.display, weight: .bold)).foregroundStyle(t.text).accessibilityAddTraits(.isHeader)
                Text("A quiet place to write. Your notes live on this Mac.").font(.system(size: DS.headline)).foregroundStyle(t.secondary).padding(.top, DS.s1 + 2)
                VStack(alignment: .leading, spacing: DS.s4) {
                    point("folder", "Plain files you own", "Every note is a file in a folder you can open. No account, no cloud, nothing to sign in to.")
                    point("square.stack", "Spaces for each part of life", "Keep work, study and home apart. Each Space has its own notes, tags and tabs.")
                    point("textformat", "Write first, format later", "Just type. Select text for formatting, or type / to add a heading, list, table and more.")
                    point("sparkle", "An optional private Assistant", "Download a 1.6 GB model later if you like. It runs on this Mac, works offline, and never sends your notes anywhere.")
                }
                .frame(width: 440, alignment: .leading).padding(.top, DS.s5 + 4)
                VStack(spacing: DS.s2 + 2) {
                    Button { model.finishOnboarding(startWriting: true) } label: { Text("Start Writing").frame(width: 260) }
                        .buttonStyle(.draftPrimary).keyboardShortcut(.defaultAction)
                    Button { model.tourGo(0) } label: { Text("Take the 1-minute Tour").frame(width: 260) }
                        .buttonStyle(.draft)
                    HStack(spacing: DS.s3) {
                        Button("Import notes…") { model.finishOnboarding(startWriting: false); model.chooseImport() }.buttonStyle(.link)
                        Text("·").foregroundStyle(t.tertiary).accessibilityHidden(true)
                        Button("Show me the folder") { model.revealVault() }.buttonStyle(.link)
                    }.font(.system(size: DS.footnote)).padding(.top, DS.s1)
                }
                .padding(.top, DS.s5 + 4)
            }
            .padding(.vertical, 40).padding(.horizontal, 48)
            .surface(.overlay, radius: 26)
            .focusable().focused($focused).focusEffectDisabled()
            .onKeyPress(.escape) { model.finishOnboarding(startWriting: false); return .handled }
            .onAppear { focused = true }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Welcome to Draft")
        }
    }

    func point(_ symbol: String, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: DS.s3 + 2) {
            Image(systemName: symbol).font(.system(size: DS.headline, weight: .semibold)).foregroundStyle(t.accent)
                .frame(width: 34, height: 34).background(RoundedRectangle(cornerRadius: DS.rControl, style: .continuous).fill(t.accent.opacity(0.12)))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: DS.body, weight: .semibold)).foregroundStyle(t.text)
                Text(text).font(.system(size: DS.footnote + 0.5)).foregroundStyle(t.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Draft's own mark: a page on an indigo tile (drawn, no image asset).
struct DraftMark: View {
    var body: some View {
        GeometryReader { g in
            let s = g.size.width
            ZStack {
                RoundedRectangle(cornerRadius: s * 0.28, style: .continuous)
                    .fill(LinearGradient(colors: [Color(hex: "#7b8cff"), Color(hex: "#5b6cf0")], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .shadow(color: Color(hex: "#5b6cf0").opacity(0.35), radius: s * 0.22, y: s * 0.1)
                RoundedRectangle(cornerRadius: s * 0.07, style: .continuous).fill(.white).frame(width: s * 0.44, height: s * 0.58)
                    .overlay(alignment: .top) {
                        VStack(alignment: .leading, spacing: s * 0.05) {
                            ForEach(0..<4, id: \.self) { i in Capsule().fill(Color(hex: "#5b6cf0").opacity(0.5)).frame(width: s * (i == 0 ? 0.24 : 0.3), height: s * 0.04) }
                        }.padding(.top, s * 0.1)
                    }
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

// MARK: - Tour

/// Reads the anchors only while the tour runs: an always-on reader made SwiftUI reduce the
/// preference across the whole window on every update (half of a tab switch).
struct TourLayer: ViewModifier {
    let step: Int?
    func body(content: Content) -> some View {
        if let step {
            content.overlayPreferenceValue(TourAnchorKey.self) { TourOverlay(step: step, anchors: $0) }
        } else {
            content
        }
    }
}

struct TourOverlay: View {
    @Environment(AppModel.self) var model
    @Environment(\.tokens) var t
    let step: Int
    let anchors: [TourTarget: Anchor<CGRect>]
    @FocusState private var focused: Bool

    var body: some View {
        GeometryReader { proxy in
            let info = AppModel.tourSteps[step]
            let spot = anchors[info.target].map { a -> CGRect in
                let r = proxy[a]
                // The editor fills the window; point at the writing area at the top of the page instead.
                if info.target == .page { return CGRect(x: r.midX - min(380, r.width / 2 - 24), y: r.minY + 150, width: min(760, r.width - 48), height: 160) }
                return r.insetBy(dx: -8, dy: -8)
            }
            ZStack(alignment: .topLeading) {
                Rectangle().fill(Color.black.opacity(0.42))
                    .mask {
                        ZStack {
                            Rectangle()
                            if let spot { RoundedRectangle(cornerRadius: 14, style: .continuous).frame(width: spot.width, height: spot.height).position(x: spot.midX, y: spot.midY).blendMode(.destinationOut) }
                        }.compositingGroup()
                    }
                    .ignoresSafeArea()
                    .onTapGesture { }
                    .accessibilityHidden(true) // only blocks clicks behind the tour
                if let spot {
                    RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.white.opacity(0.9), lineWidth: 2)
                        .frame(width: spot.width, height: spot.height).position(x: spot.midX, y: spot.midY)
                        .shadow(color: t.accent.opacity(0.55), radius: 10)
                        .allowsHitTesting(false)
                }
                card(info).frame(width: 320)
                    .position(cardCenter(spot: spot, in: proxy.size))
            }
            .animation(Motion.emphasis(model.library.settings.reduceMotion), value: step)
        }
        .focusable().focused($focused).focusEffectDisabled()
        .onAppear { focused = true }
        .onKeyPress(.rightArrow) { model.tourGo(step + 1); return .handled }
        .onKeyPress(.leftArrow) { model.tourGo(step - 1); return .handled }
        .onKeyPress(.return) { model.tourGo(step + 1); return .handled }
        .onKeyPress(.escape) { model.finishOnboarding(startWriting: false); return .handled }
    }

    func cardCenter(spot: CGRect?, in size: CGSize) -> CGPoint {
        let w: CGFloat = 320, h: CGFloat = 210
        guard let s = spot else { return CGPoint(x: size.width / 2, y: size.height / 2) }
        var x = s.maxX + 20 + w / 2
        var y = s.minY + h / 2
        if s.minY < 120, s.width < size.width / 2 { x = min(size.width - 16 - w / 2, max(16 + w / 2, s.maxX - w / 2)); y = s.maxY + 16 + h / 2 }
        else if x + w / 2 > size.width - 16 { x = s.minX - 20 - w / 2 }
        if x - w / 2 < 16 { x = min(size.width - 16 - w / 2, max(16 + w / 2, s.midX)); y = s.maxY + 20 + h / 2 }
        y = min(size.height - 16 - h / 2, max(16 + h / 2, y))
        return CGPoint(x: x, y: y)
    }

    func card(_ info: TourStep) -> some View {
        let total = AppModel.tourSteps.count
        let last = step == total - 1
        return VStack(alignment: .leading, spacing: DS.s2 + 2) {
            HStack {
                Text("\(step + 1) of \(total)").font(.system(size: DS.caption, weight: .semibold)).foregroundStyle(t.accent)
                Spacer()
                Button("Skip Tour") { model.finishOnboarding(startWriting: false) }.buttonStyle(.plain).font(.system(size: DS.footnote)).foregroundStyle(t.secondary)
            }
            Text(info.title).font(.system(size: DS.headline + 1, weight: .semibold)).foregroundStyle(t.text)
            Text(info.text).font(.system(size: DS.body)).foregroundStyle(t.secondary).fixedSize(horizontal: false, vertical: true)
            if let note = info.note { Text(note).font(.system(size: DS.footnote)).foregroundStyle(t.tertiary).fixedSize(horizontal: false, vertical: true) }
            if last, !model.assistant.store.isInstalled(model.assistant.model) {
                Button("Download Model (\(ByteCountFormatter.string(fromByteCount: model.assistant.model.bytes, countStyle: .file)))") {
                    model.setSettings { $0.assistantPinned = true }
                    if !model.assistant.isOpen { model.toggleAssistant() }
                    model.assistant.download()
                    model.finishOnboarding(startWriting: false)
                }.buttonStyle(DraftButtonStyle(compact: true))
            }
            HStack(spacing: 6) {
                ForEach(0..<total, id: \.self) { i in Capsule().fill(i == step ? t.accent : t.line).frame(width: i == step ? 16 : 6, height: 6) }
                    .accessibilityHidden(true)
                Spacer()
                if step > 0 { Button("Back") { model.tourGo(step - 1) }.buttonStyle(DraftButtonStyle(compact: true)) }
                Button(last ? "Start Writing" : "Next") { model.tourGo(step + 1) }.buttonStyle(DraftButtonStyle(role: .primary, compact: true))
            }
            .padding(.top, DS.s1)
        }
        .padding(DS.s4 + 2)
        .surface(.overlay, radius: 18)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Tour step \(step + 1) of \(total): \(info.title). \(info.text)")
    }
}
