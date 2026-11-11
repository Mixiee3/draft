import SwiftUI
import AppKit
import DraftCore

extension AppModel {
    /// View > Present: the document's headings become slides in a full-screen window, on a second
    /// display when there is one.
    func present(_ docId: String) {
        saveDirtyDocs()
        guard let d = docs[docId] else { return }
        let deck = slides(editors[docId]?.controller.document() ?? d.content, title: d.title.isEmpty ? "Untitled" : d.title)
        let screen = NSScreen.screens.first { $0 != NSApp.mainWindow?.screen } ?? NSApp.mainWindow?.screen ?? NSScreen.main
        let frame = screen?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let w = PresentWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        w.level = .normal
        w.collectionBehavior = [.fullScreenPrimary]
        w.isReleasedWhenClosed = false
        w.contentView = NSHostingView(rootView: PresentView(deck: deck, tokens: displayTokens(d.appearance), close: { [weak w] in w?.close() }))
        w.setFrame(frame, display: true)
        w.makeKeyAndOrderFront(nil)
        presentWindow = w
        // Back in the note with the caret and selection where they were, so the formatting bar and
        // typing work right away.
        let main = NSApp.windows.first { $0.isVisible && $0 !== w && !($0 is NSPanel) }
        var token: NSObjectProtocol?
        token = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: w, queue: .main) { [weak self] _ in
            if let token { NotificationCenter.default.removeObserver(token) }
            main?.makeKeyAndOrderFront(nil)
            if let tv = self?.editors[docId]?.controller.textView { main?.makeFirstResponder(tv) }
        }
    }
}

final class PresentWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

struct PresentView: View {
    let deck: [Slide]
    let tokens: StyleTokens
    let close: () -> Void
    @State private var index = 0
    @FocusState private var focused: Bool

    var body: some View {
        let page = Color(hex: tokens.pageColor), ink = Color(hex: tokens.textColor), accent = Color(hex: tokens.accent)
        let design: Font.Design = tokens.font == "serif" ? .serif : tokens.font == "mono" ? .monospaced : tokens.font == "rounded" ? .rounded : .default
        GeometryReader { g in
            let scale = min(g.size.width / 1280, g.size.height / 800)
            let slide = deck[index]
            ZStack(alignment: .bottomTrailing) {
                page.ignoresSafeArea()
                VStack(alignment: .leading, spacing: 22 * scale) {
                    Text(slide.title).font(.system(size: (index == 0 ? 72 : 56) * scale, weight: .bold, design: design)).foregroundStyle(ink)
                        .accessibilityAddTraits(.isHeader)
                    ForEach(Array(slide.lines.enumerated()), id: \.offset) { _, l in line(l, ink: ink, accent: accent, design: design, scale: scale) }
                }
                .padding(.horizontal, 110 * scale).padding(.vertical, 90 * scale)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: index == 0 ? .leading : .topLeading)
                .id(index)
                .transition(.opacity)
                Text("\(index + 1) / \(deck.count)").font(.system(size: 15 * scale, weight: .medium)).foregroundStyle(ink.opacity(0.45)).padding(28 * scale)
                    .accessibilityLabel("Slide \(index + 1) of \(deck.count)")
            }
            .animation(Motion.standard(false), value: index)
        }
        .focusable().focused($focused).focusEffectDisabled()
        .onAppear { focused = true }
        .onKeyPress(keys: [.rightArrow, .downArrow, .space, .return, .pageDown]) { _ in step(1) }
        .onKeyPress(keys: [.leftArrow, .upArrow, .pageUp, .delete]) { _ in step(-1) }
        .onKeyPress(.escape) { close(); return .handled }
        .onTapGesture { _ = step(1) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Presentation. Arrow keys change slides, Escape ends.")
    }

    func step(_ d: Int) -> KeyPress.Result {
        index = min(max(0, index + d), deck.count - 1)
        return .handled
    }

    @ViewBuilder func line(_ l: SlideLine, ink: Color, accent: Color, design: Font.Design, scale: CGFloat) -> some View {
        let size = 30 * scale
        HStack(alignment: .firstTextBaseline, spacing: 14 * scale) {
            switch l.kind {
            case .bullet: Circle().fill(accent).frame(width: 9 * scale, height: 9 * scale).accessibilityHidden(true)
            case .task, .done: Image(systemName: l.kind == .done ? "checkmark.square.fill" : "square").font(.system(size: size * 0.85)).foregroundStyle(accent).accessibilityHidden(true)
            case .quote: Rectangle().fill(accent).frame(width: 4 * scale, height: size * 1.2).accessibilityHidden(true)
            default: EmptyView()
            }
            Text(l.text)
                .font(l.kind == .code ? .system(size: size * 0.8, design: .monospaced) : .system(size: l.kind == .subheading ? size * 1.1 : size, weight: l.kind == .subheading ? .semibold : .regular, design: design))
                .italic(l.kind == .quote)
                .strikethrough(l.kind == .done)
                .foregroundStyle(ink.opacity(l.kind == .done ? 0.5 : 0.92))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.leading, CGFloat(l.depth) * 34 * scale)
    }
}
