import AppKit
import SwiftUI
import DraftCore

/// Version History for one note: versions on the left (or on top when narrow), and what restoring the
/// selected one would change. Arrow keys move through versions, Return restores (after a preview),
/// Escape closes.
struct VersionHistoryView: View {
    @Environment(AppModel.self) var model
    @Environment(\.tokens) var t
    @Environment(\.dismiss) var dismiss
    let docId: String
    private var selection: String? { model.recovery.historySelection }
    private var confirming: Bool { model.recovery.historyConfirming }
    @State private var check: AppModel.RestoreCheck?
    @FocusState private var listFocused: Bool

    var body: some View {
        let _ = model.editorTick
        @Bindable var r = model.recovery
        let snaps = model.snapshots(docId)
        GeometryReader { geo in
            let narrow = geo.size.width < 720
            VStack(spacing: 0) {
                header(snaps.count)
                Divider()
                if snaps.isEmpty {
                    EmptyState(symbol: "clock.arrow.circlepath", title: "No versions yet", message: "Draft saves a version every 10 minutes while you edit. Use Save Version Now to keep this one.")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if narrow {
                    VStack(spacing: 0) { list(snaps).frame(height: min(220, geo.size.height * 0.35)); Divider(); detail(snaps) }
                } else {
                    HStack(spacing: 0) { list(snaps).frame(width: 260); Divider(); detail(snaps) }
                }
            }
        }
        .frame(width: Self.fit.width, height: Self.fit.height)
        .background(t.canvas)
        .onAppear { if selection == nil || !snaps.contains(where: { $0.id == selection }) { r.historySelection = snaps.first?.id }; r.historyConfirming = false; listFocused = true; refresh() }
        .onChange(of: model.recovery.historySelection) { model.recovery.historyConfirming = false; refresh() }
        .onExitCommand { if confirming { model.recovery.historyConfirming = false } else { dismiss() } }
    }

    /// Fits inside the window it is attached to, so narrow windows get the stacked layout.
    static var fit: CGSize {
        let w = NSApp.windows.first { $0.isVisible && $0.isMainWindow }?.frame.size ?? NSApp.windows.first { $0.isVisible }?.frame.size ?? CGSize(width: 1200, height: 800)
        return CGSize(width: min(980, max(480, w.width - 48)), height: min(720, max(420, w.height - 90)))
    }

    func refresh() {
        guard let s = model.snapshots(docId).first(where: { $0.id == selection }) else { check = nil; return }
        check = model.restoreCheck(docId, s)
    }

    func header(_ count: Int) -> some View {
        HStack(spacing: DS.s3) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Version History").font(.system(size: DS.headline, weight: .semibold)).foregroundStyle(t.text).accessibilityAddTraits(.isHeader)
                Text("“\(model.docTitle(docId))” · \(count) versions on this Mac").font(.system(size: DS.footnote)).foregroundStyle(t.secondary)
            }
            Spacer()
            Button("Save Version Now") { model.saveVersionNow(docId) }.buttonStyle(DraftButtonStyle(compact: true)).keyboardShortcut("s", modifiers: [.command, .option]).disabled(model.readOnly != nil)
            Button("Done") { dismiss() }.buttonStyle(DraftButtonStyle(compact: true))
        }.padding(DS.s4)
    }

    func list(_ snaps: [Snapshot]) -> some View {
        List(selection: Binding(get: { model.recovery.historySelection }, set: { model.recovery.historySelection = $0 })) {
            ForEach(snaps) { s in
                VStack(alignment: .leading, spacing: 2) {
                    // System styles, so the row inverts with the selection highlight.
                    Text(Date(timeIntervalSince1970: s.savedAt / 1000).formatted(date: .abbreviated, time: .shortened)).font(.system(size: DS.body)).foregroundStyle(.primary)
                    HStack(spacing: 4) {
                        Image(systemName: s.source == "manual" ? "bookmark.fill" : s.source == "auto" ? "clock" : "arrow.uturn.backward").font(.system(size: 9))
                        Text("\(s.sourceLabel) · \(relative(s.savedAt))")
                    }.font(.system(size: DS.caption)).foregroundStyle(.secondary)
                }
                .padding(.vertical, 2).tag(s.id)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(s.sourceLabel) version, \(Date(timeIntervalSince1970: s.savedAt / 1000).formatted(date: .abbreviated, time: .shortened))")
            }
        }
        .listStyle(.sidebar).scrollContentBackground(.hidden).focused($listFocused)
        .accessibilityLabel("Versions")
    }

    @ViewBuilder func detail(_ snaps: [Snapshot]) -> some View {
        if let s = snaps.first(where: { $0.id == selection }), let c = check {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: DS.s4) {
                        Text(c.diff.isEmpty ? "This version is the same as the note now." : "Restoring this version changes: \(c.diff.summary)")
                            .font(.system(size: DS.body, weight: .medium)).foregroundStyle(t.text).fixedSize(horizontal: false, vertical: true)
                        if confirming { RestoreWarnings(check: c) }
                        DiffView(diff: c.diff)
                    }.padding(DS.s4).frame(maxWidth: .infinity, alignment: .leading)
                }
                Divider()
                HStack(spacing: DS.s2) {
                    Text(confirming ? "The note as it is now is saved as a version first. Command-Z undoes the restore." : "Struck-through text is in the note now; underlined text comes back with this version.")
                        .font(.system(size: DS.footnote)).foregroundStyle(t.secondary).fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    if confirming {
                        Button("Cancel") { model.recovery.historyConfirming = false }.buttonStyle(DraftButtonStyle(compact: true)).keyboardShortcut(.cancelAction)
                        Button("Restore This Version") { model.restoreVersion(docId, s); model.recovery.historyConfirming = false; dismiss() }
                            .buttonStyle(DraftButtonStyle(role: .primary, compact: true)).keyboardShortcut(.defaultAction)
                    } else {
                        Button("Restore…") { model.recovery.historyConfirming = true }.buttonStyle(DraftButtonStyle(role: .primary, compact: true))
                            .keyboardShortcut(.defaultAction).disabled(c.diff.isEmpty || model.readOnly != nil)
                    }
                }.padding(DS.s3)
            }
        } else {
            Text("Choose a version.").foregroundStyle(t.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

/// What a restore would affect beyond the text: links into blocks it doesn't have, attachments.
struct RestoreWarnings: View {
    @Environment(\.tokens) var t
    let check: AppModel.RestoreCheck
    var body: some View {
        VStack(alignment: .leading, spacing: DS.s2) {
            note("checkmark.shield", .green, "Block ids are kept as they were in this version, so links into unchanged blocks keep working.")
            if !check.lostLinkedBlocks.isEmpty {
                note("link.badge.plus", .orange, "\(check.lostLinkedBlocks.count) blocks that other notes link to don't exist in this version. Those links are kept and work again if you undo.")
            }
            if !check.recoverableAssets.isEmpty { note("tray.and.arrow.up", .blue, "\(check.recoverableAssets.count) attachments were moved out as unused; Draft puts them back.") }
            let lost = check.missingAssets.count - check.recoverableAssets.count
            if lost > 0 { note("exclamationmark.triangle.fill", .orange, "\(lost) attachments this version uses are no longer on this Mac and will show as missing.") }
            if check.brokenLinks > 0 { note("link", .orange, "\(check.brokenLinks) links point to notes that no longer exist.") }
        }
        .padding(DS.s3).background(RoundedRectangle(cornerRadius: DS.rCard, style: .continuous).fill(t.card.opacity(t.dark ? 0.55 : 1)))
        .overlay(RoundedRectangle(cornerRadius: DS.rCard, style: .continuous).strokeBorder(t.line, lineWidth: 0.5))
    }
    func note(_ s: String, _ c: Color, _ text: LocalizedStringKey) -> some View {
        Label { Text(text).font(.system(size: DS.footnote)).foregroundStyle(t.text).fixedSize(horizontal: false, vertical: true) } icon: { Image(systemName: s).foregroundStyle(c) }
    }
}

/// A readable diff: title, look, attachments, then block changes with word-level highlights.
struct DiffView: View {
    @Environment(\.tokens) var t
    let diff: VersionDiff
    var body: some View {
        VStack(alignment: .leading, spacing: DS.s2) {
            if diff.titleBefore != diff.titleAfter { change("textformat", "Title", words: VersionDiff.words(diff.titleBefore, diff.titleAfter), notes: []) }
            ForEach(diff.lookNotes, id: \.self) { change("paintpalette", "Look", text: $0) }
            ForEach(diff.assetsAdded, id: \.self) { change("paperclip", "Attachment comes back", text: $0) }
            ForEach(diff.assetsRemoved, id: \.self) { change("paperclip", "Attachment not in this version", text: $0) }
            ForEach(diff.blocks.prefix(300)) { b in
                change(Self.symbol(b.kind), "\(b.type) · \(Self.word(b.kind))", words: b.words, notes: b.notes)
            }
            if diff.blocks.count > 300 { Text("and \(diff.blocks.count - 300) more changes").font(.system(size: DS.footnote)).foregroundStyle(t.secondary) }
        }
    }

    static func symbol(_ k: VersionDiff.Block.Kind) -> String {
        switch k { case .added: return "plus.circle"; case .removed: return "minus.circle"; case .edited: return "pencil"; case .formatted: return "bold.italic.underline"; case .moved: return "arrow.up.arrow.down" }
    }
    // The diff is from the current note to the version: "added" means restoring brings it back.
    static func word(_ k: VersionDiff.Block.Kind) -> String {
        switch k { case .added: return "comes back"; case .removed: return "not in this version"; case .edited: return "text differs"; case .formatted: return "formatting differs"; case .moved: return "in another place" }
    }

    func change(_ sym: String, _ label: String, text: String) -> some View { change(sym, label, words: [VersionDiff.Word(op: .same, text: text)], notes: []) }

    func change(_ sym: String, _ label: String, words: [VersionDiff.Word], notes: [String]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(label, systemImage: sym).font(.system(size: DS.caption, weight: .semibold)).foregroundStyle(t.secondary)
            words.reduce(Text("")) { acc, w in
                switch w.op {
                case .same: return acc + Text(w.text).foregroundColor(t.text)
                case .added: return acc + Text(w.text).foregroundColor(t.dark ? Color(hex: "#7fd88f") : Color(hex: "#1d7a32")).underline(true, color: .green)
                case .removed: return acc + Text(w.text).foregroundColor(t.dark ? Color(hex: "#ff8f86") : Color(hex: "#b3261e")).strikethrough(true, color: .red)
                }
            }
            .font(.system(size: DS.body)).lineLimit(8).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
            if !notes.isEmpty { Text(notes.joined(separator: " · ")).font(.system(size: DS.footnote)).foregroundStyle(t.secondary) }
        }
        .padding(DS.s3).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: DS.rControl, style: .continuous).fill(t.card.opacity(t.dark ? 0.55 : 1)))
        .overlay(RoundedRectangle(cornerRadius: DS.rControl, style: .continuous).strokeBorder(t.line, lineWidth: 0.5))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label). " + words.map { w in w.op == .added ? "added: \(w.text)" : w.op == .removed ? "removed: \(w.text)" : w.text }.joined() + (notes.isEmpty ? "" : ". " + notes.joined(separator: ", ")))
    }
}
