import SwiftUI
import AppKit
import DraftCore
import DraftEditor

@main
struct DraftApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var model = AppModel.shared

    var body: some Scene {
        WindowGroup("Draft", id: "main") {
            RootView()
                .environmentObject(model)
                .frame(minWidth: 480, minHeight: 480)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1440, height: 900)
        .commands { DraftCommands(model: model) }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        Automation.startIfRequested()
    }
    func applicationWillTerminate(_ notification: Notification) {
        onMain { AppModel.shared.flushAll() }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

struct DraftCommands: Commands {
    @ObservedObject var model: AppModel

    func run(_ id: String) {
        guard let c = model.activeController, let cmd = EditorCommands.command(id) else { return }
        cmd.run(c)
    }

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Document") { model.createDoc() }.keyboardShortcut("n")
            Button("New Folder") { model.createFolder() }.keyboardShortcut("n", modifiers: [.command, .shift])
            Divider()
            Button("Quick Open…") { model.quickOpen = true }.keyboardShortcut("o")
            Button("Today’s Daily Note") { model.openDaily() }.keyboardShortcut("d", modifiers: [.command, .shift])
        }
        CommandGroup(replacing: .saveItem) {
            Button("Close Tab") {
                if model.activeTab.view.kind == "all" { NSApp.keyWindow?.performClose(nil) } else { model.closeTab(model.activeTab.id) }
            }.keyboardShortcut("w")
            Divider()
            Button("Export Document as Markdown…") { if let d = model.activeDocId { model.exportDoc(d) } }
                .keyboardShortcut("e", modifiers: [.command, .shift]).disabled(model.activeDocId == nil)
            Button("Export All Documents…") { model.exportAll() }
            Button("Show Data Folder in Finder") { model.revealVault() }
            Divider()
            Button("Print…") { model.activeEditor?.controller.textView.printView(nil) }.keyboardShortcut("p").disabled(model.activeDocId == nil)
        }
        CommandGroup(replacing: .textEditing) {
            Button("Find in Page") { model.docRailTab = .find; model.railShowsFolders = false; model.findFocusNonce += 1 }
                .keyboardShortcut("f").disabled(model.activeDocId == nil)
            // ⌘G / ⇧⌘G belong to Group / Ungroup; in the Find pane Return and ⇧Return step through matches.
            Button("Find Next") { model.activeController?.findStep(1) }.disabled(model.activeDocId == nil)
            Button("Find Previous") { model.activeController?.findStep(-1) }.disabled(model.activeDocId == nil)
        }
        CommandMenu("Format") {
            ForEach(EditorCommands.all.filter { $0.plannedFor == nil && $0.group != "Insert" }) { cmd in
                let b = Button(cmd.title) { run(cmd.id) }.disabled(model.activeDocId == nil)
                if let k = cmd.key, let ch = k.first {
                    b.keyboardShortcut(k == "up" ? .upArrow : k == "down" ? .downArrow : KeyEquivalent(ch), modifiers: modifiers(cmd.modifiers))
                } else { b }
            }
            Divider()
            Button("Formatting Panel") { model.panel = model.panel == .format ? nil : .format }.disabled(model.activeDocId == nil)
            Button("Style Panel") { model.panel = model.panel == .style ? nil : .style }
                .keyboardShortcut("s", modifiers: [.command, .shift]).disabled(model.activeDocId == nil)
        }
        CommandMenu("Insert") {
            ForEach(EditorCommands.all.filter { $0.group == "Insert" }) { cmd in
                Button(cmd.plannedFor.map { "\(cmd.title) (planned \($0))" } ?? cmd.title) { run(cmd.id) }
                    .disabled(model.activeDocId == nil || cmd.plannedFor != nil)
            }
        }
        CommandMenu("Go") {
            Button("Back") { model.goBack() }.keyboardShortcut("[").disabled(!model.canGoBack)
            Button("Forward") { model.goForward() }.keyboardShortcut("]").disabled(!model.canGoForward)
            Divider()
            Button("Today’s Daily Note") { model.openDaily() }
            let day = model.activeDocId.flatMap { model.library.docs[$0]?.dailyDate }
            Button("Previous Day") { if let d = day { model.openDaily(Day.add(d, days: -1), inPlace: true) } }
                .keyboardShortcut(.leftArrow, modifiers: [.command, .option, .shift]).disabled(day == nil)
            Button("Next Day") { if let d = day { model.openDaily(Day.add(d, days: 1), inPlace: true) } }
                .keyboardShortcut(.rightArrow, modifiers: [.command, .option, .shift]).disabled(day == nil)
            Button("Calendar") { model.openView(ViewRef(kind: "calendar")) }.keyboardShortcut("1", modifiers: [.command, .option, .shift])
            Button("Tasks") { model.openView(ViewRef(kind: "tasks")) }.keyboardShortcut("2", modifiers: [.command, .option, .shift])
        }
        CommandGroup(before: .sidebar) {
            Button(model.library.settings.railCollapsed ? "Show Sidebar" : "Hide Sidebar") {
                model.setSettings { $0.railCollapsed.toggle() }
            }.keyboardShortcut("s", modifiers: [.command, .control])
            Divider()
            Button("Gallery") { model.setSettings { $0.libraryView = .gallery } }.keyboardShortcut("1", modifiers: [.command, .control])
            Button("Grid") { model.setSettings { $0.libraryView = .grid } }.keyboardShortcut("2", modifiers: [.command, .control])
            Button("List") { model.setSettings { $0.libraryView = .list } }.keyboardShortcut("3", modifiers: [.command, .control])
            Divider()
        }
        CommandGroup(replacing: .appSettings) {
            Button("Settings…") { model.openView(ViewRef(kind: "settings", section: "appearance")) }.keyboardShortcut(",")
        }
    }

    func modifiers(_ m: NSEvent.ModifierFlags) -> EventModifiers {
        var e: EventModifiers = []
        if m.contains(.command) { e.insert(.command) }
        if m.contains(.shift) { e.insert(.shift) }
        if m.contains(.option) { e.insert(.option) }
        if m.contains(.control) { e.insert(.control) }
        return e
    }
}
