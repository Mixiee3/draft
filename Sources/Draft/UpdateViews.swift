import AppKit
import SwiftUI
import DraftCore

/// Check for Updates…: available version with notes, download progress, and the install choices.
struct UpdateSheet: View {
    @Environment(AppModel.self) var model
    @Environment(\.tokens) var t
    @Environment(\.dismiss) var dismiss
    @State private var confirmWhileEditing: UpdateItem?
    var u: UpdateController { model.updates }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.s4) {
            HStack(spacing: DS.s3) {
                DraftMark().frame(width: 40, height: 40).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Software Update").font(.system(size: DS.title2, weight: .bold)).foregroundStyle(t.text).accessibilityAddTraits(.isHeader)
                    Text("Draft \(u.version) (\(u.build)) · \(LocalizedStringKey(channelName(model.library.settings.updateChannel)))").font(.system(size: DS.footnote)).foregroundStyle(t.secondary)
                }
            }
            content
        }
        .padding(DS.s5)
        .frame(width: 520)
        .background(t.canvas)
        .alert("You're writing right now", isPresented: Binding(get: { confirmWhileEditing != nil }, set: { if !$0 { confirmWhileEditing = nil } })) {
            Button("Install and Restart") { if let i = confirmWhileEditing { installNow(i, confirmed: true) } }
            Button("Install on Quit") { if let i = confirmWhileEditing { u.installOnQuit = i; dismiss() } }
            Button("Cancel", role: .cancel) {}
        } message: { Text("Draft saves everything first, then restarts. Choose Install on Quit to keep writing.") }
    }

    @ViewBuilder var content: some View {
        switch u.phase {
        case .idle, .checking:
            HStack(spacing: DS.s2) { ProgressView().controlSize(.small); Text("Checking for updates…").foregroundStyle(t.secondary) }
            footer { Button("Close") { dismiss() }.keyboardShortcut(.cancelAction) }
        case .upToDate:
            Label("Draft is up to date.", systemImage: "checkmark.seal.fill").foregroundStyle(t.text)
            footer { Button("Done") { dismiss() }.keyboardShortcut(.defaultAction) }
        case .failed(let msg):
            Label { Text(msg).fixedSize(horizontal: false, vertical: true) } icon: { Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange) }
            footer { Button("Close") { dismiss() }.keyboardShortcut(.cancelAction) }
        case .available(let item):
            notes(item)
            footer {
                Button("Skip This Version") { model.setSettings { $0.skippedUpdate = item.id }; dismiss() }
                Button("Remind Me Later") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Download") { u.download(item) }.buttonStyle(DraftButtonStyle(role: .primary, compact: true)).keyboardShortcut(.defaultAction)
                    .disabled(Updates.compatibility(item) != .ok && { if case .needsNewerSystem = Updates.compatibility(item) { return true }; return false }())
            }
        case .downloading(let p):
            ProgressView(value: p) { Text("Downloading…") }.accessibilityValue("\(Int(p * 100)) %")
            footer { Button("Cancel Download") { u.cancelDownload() }.keyboardShortcut(.cancelAction) }
        case .ready(let item):
            notes(item)
            Label("Downloaded and verified: signed by Draft's release key, checksum and code signature checked.", systemImage: "checkmark.shield.fill")
                .font(.system(size: DS.footnote)).foregroundStyle(t.secondary)
            footer {
                Button("Remind Me Later") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Install on Quit") { u.installOnQuit = item; model.toast("Draft will update when you quit.") ; dismiss() }
                Button("Install and Restart") { installNow(item, confirmed: false) }.buttonStyle(DraftButtonStyle(role: .primary, compact: true)).keyboardShortcut(.defaultAction)
            }
        case .installing:
            HStack(spacing: DS.s2) { ProgressView().controlSize(.small); Text("Installing… Draft restarts in a moment.").foregroundStyle(t.secondary) }
        }
    }

    func installNow(_ item: UpdateItem, confirmed: Bool) {
        // Not while someone is mid-sentence, unless they say so.
        if !confirmed, let last = model.lastEditAt, Date().timeIntervalSince(last) < 60 { confirmWhileEditing = item; return }
        model.flushAll()
        do {
            if case .migration = Updates.compatibility(item) {
                let url = try BackupArchive.create(vault: model.vault, into: model.defaultBackupFolder(), appVersion: u.version)
                DraftLog.write("backup archive before migrating update \(item.version): \(url.lastPathComponent)")
            }
            try u.install(item, relaunch: true)
            DraftLog.write("installing update \(item.version) (\(item.build))")
            NSApp.terminate(nil)
        } catch { model.toast("Couldn't install the update: \(error.localizedDescription)"); u.phase = .failed(error.localizedDescription) }
    }

    @ViewBuilder func notes(_ item: UpdateItem) -> some View {
        VStack(alignment: .leading, spacing: DS.s2) {
            Text("Draft \(item.version) is available").font(.system(size: DS.headline, weight: .semibold)).foregroundStyle(t.text)
            Text("Released \(item.date) · \(ByteCountFormatter.string(fromByteCount: item.size, countStyle: .file)) · \(LocalizedStringKey(channelName(item.channel)))")
                .font(.system(size: DS.footnote)).foregroundStyle(t.secondary)
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(item.notes.enumerated()), id: \.offset) { _, n in Label { Text(verbatim: n) } icon: { Text("•").accessibilityHidden(true) } }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.frame(maxHeight: 160)
            .padding(DS.s3).background(RoundedRectangle(cornerRadius: DS.rCard, style: .continuous).fill(t.card.opacity(t.dark ? 0.55 : 1)))
            switch Updates.compatibility(item) {
            case .migration(let from, let to):
                Label("This version updates your vault's format (\(from) → \(to)). Draft makes a backup archive first; older versions of Draft can't open the updated vault.", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            case .needsNewerSystem(let v):
                Label("This version needs macOS \(v) or later.", systemImage: "xmark.octagon.fill").foregroundStyle(.red)
            case .ok: EmptyView()
            }
        }
    }

    func footer<B: View>(@ViewBuilder _ b: () -> B) -> some View {
        HStack(spacing: DS.s2) { Spacer(); b() }.buttonStyle(DraftButtonStyle(compact: true))
    }
}

func channelName(_ c: String) -> String {
    switch c { case "beta": return "Beta"; case "development": return "Development"; default: return "Stable" }
}

/// Settings › Updates.
struct UpdateSettings: View {
    @Environment(AppModel.self) var model
    @Environment(\.tokens) var t
    @State private var pendingChannel: String?
    var body: some View {
        let s = model.library.settings
        VStack(alignment: .leading, spacing: DS.s5) {
            SettingsSection(title: "Software Update", footer: "Draft only contacts the update server when you click Check for Updates or turn on automatic checks. It sends nothing about you or your notes; the request is an ordinary download of the update list.") {
                SettingsRow(title: "Draft \(model.updates.version) (\(model.updates.build))", detail: LocalizedStringKey(model.updates.lastChecked.map { String(localized: "Last checked \($0.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened, locale: appLocale)))") } ?? String(localized: "Not checked in this session"))) {
                    Button("Check for Updates…") { model.updates.sheet = true; Task { await model.updates.check(manual: true, settings: model.library.settings) } }
                        .buttonStyle(DraftButtonStyle(compact: true)).disabled(!model.updates.available && !model.updates.testMode)
                }
                SettingsSwitchRow(title: "Check for updates automatically", detail: "Once a day while Draft is open. Off: Draft never contacts the update server on its own.",
                                  isOn: Binding(get: { s.updateChecks }, set: { v in model.setSettings { $0.updateChecks = v } }))
                SettingsMenuRow(title: "Update channel", detail: "Stable is recommended. Beta gets new features earlier and may have bugs. Development is for testing builds.",
                                selection: Binding(get: { s.updateChannel }, set: { v in if v != s.updateChannel { if v == "stable" { model.setSettings { $0.updateChannel = v } } else { pendingChannel = v } } }),
                                options: [("stable", "Stable"), ("beta", "Beta"), ("development", "Development")])
                if !model.updates.available {
                    Label("This build has no release key, so it can't verify updates. Release builds can.", systemImage: "info.circle")
                        .font(.system(size: DS.footnote)).foregroundStyle(t.secondary).padding(DS.s3 + 2).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .alert("Switch to the \(LocalizedStringKey(channelName(pendingChannel ?? "")))  channel?", isPresented: Binding(get: { pendingChannel != nil }, set: { if !$0 { pendingChannel = nil } })) {
            Button("Switch") { if let c = pendingChannel { model.setSettings { $0.updateChannel = c } }; pendingChannel = nil }
            Button("Cancel", role: .cancel) { pendingChannel = nil }
        } message: {
            Text(pendingChannel == "development"
                 ? "Development builds are for testing and can break. They never replace a stable Draft on their own; keep a backup archive."
                 : "Beta versions get features earlier and may have bugs. Your notes stay in the same vault; make a backup archive first. You can switch back to Stable, but a newer vault format can't be opened by an older Draft.")
        }
    }
}

/// What's New after an update.
struct WhatsNewView: View {
    @Environment(AppModel.self) var model
    @Environment(\.tokens) var t
    var body: some View {
        let v = model.updates.version
        let n = ReleaseNotes.all.first { $0.version == v }
        VStack(alignment: .leading, spacing: DS.s4) {
            Text("What's New in Draft \(v)").font(.system(size: DS.title2, weight: .bold)).foregroundStyle(t.text).accessibilityAddTraits(.isHeader)
            if let n {
                Text(n.title).font(.system(size: DS.headline, weight: .semibold)).foregroundStyle(t.text)
                VStack(alignment: .leading, spacing: DS.s2) {
                    ForEach(Array(n.points.enumerated()), id: \.offset) { _, p in
                        Label { Text(p).fixedSize(horizontal: false, vertical: true) } icon: { Image(systemName: "sparkle").foregroundStyle(t.accent) }
                    }
                }
            }
            HStack {
                Button("Open Help") { model.closeWhatsNew(); model.showSettings("help") }.buttonStyle(DraftButtonStyle(compact: true))
                Spacer()
                Button("Continue") { model.closeWhatsNew() }.buttonStyle(DraftButtonStyle(role: .primary, compact: true)).keyboardShortcut(.defaultAction)
            }
        }
        .padding(DS.s5).frame(width: 520).background(t.canvas)
    }
}
