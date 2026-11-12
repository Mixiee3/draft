import SwiftUI
import AppKit
import DraftCore
import DraftEditor

@main
struct DraftApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var model = AppModel.shared

    var body: some Scene {
        WindowGroup("Draft", id: "main") {
            RootView()
                .environment(model)
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
        onMain { AppModel.shared.flushAll(); AppModel.shared.assistant.shutdown() }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

struct DraftCommands: Commands {
    var model: AppModel

    func run(_ id: String) {
        guard let c = model.activeController, let cmd = EditorCommands.command(id) else { return }
        cmd.run(c)
    }

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Document") { model.createDoc() }.keyboardShortcut("n")
            Button("New Folder") { model.createFolder() }.keyboardShortcut("n", modifiers: [.command, .shift])
            Button("New from Template…") { model.templatePicker = true }.keyboardShortcut("t", modifiers: [.command, .option])
            Button("Import…") { model.chooseImport() }.keyboardShortcut("i", modifiers: [.command, .shift])
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
            Button("Version History…") { if let d = model.activeDocId { model.recovery.historyDoc = HistoryTarget(id: d) } }
                .keyboardShortcut("y", modifiers: [.command, .option]).disabled(model.activeDocId == nil)
            Button("Save Version Now") { if let d = model.activeDocId { model.saveVersionNow(d) } }
                .keyboardShortcut("s", modifiers: [.command, .option]).disabled(model.activeDocId == nil || model.readOnly != nil)
            Button("Check Vault…") { model.showSettings("recovery"); model.recovery.tab = "check"; Task { await model.checkVault() } }
            Divider()
            Button("Print…") { model.activeEditor?.controller.textView.printView(nil) }.keyboardShortcut("p").disabled(model.activeDocId == nil)
        }
        CommandGroup(replacing: .textEditing) {
            Button("Find in Page") { model.docRailTab = .find; model.railShowsFolders = false; model.findFocusNonce += 1 }
                .keyboardShortcut("f").disabled(model.activeDocId == nil)
            // ⌘G / ⇧⌘G belong to Group / Ungroup; in the Find pane Return and ⇧Return step through matches.
            Button("Find Next") { model.activeController?.findStep(1) }.disabled(model.activeDocId == nil)
            Button("Find Previous") { model.activeController?.findStep(-1) }.disabled(model.activeDocId == nil)
            Divider()
            Button(model.agentUndoName.map { "Undo Agent Change: \($0)" } ?? "Undo Agent Change") { model.undoAgentChange() }.disabled(model.agentUndoName == nil)
            Button(model.pendingAgentCount > 0 ? "Review Agent Proposals (\(model.pendingAgentCount))" : "Review Agent Proposals") { model.reviewPendingAgentProposals() }.disabled(model.pendingAgentCount == 0)
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
        CommandMenu("Table") {
            let te = { () -> TableEditor? in model.activeController.map { $0.tableEditor }.flatMap { $0.isEditing ? $0 : nil } }
            let run = { (f: (TableEditor) -> Void) in if let t = te() { f(t) } else { NSSound.beep() } }
            Button("Move Column Left") { run { $0.moveColumn(by: -1) } }.keyboardShortcut(.leftArrow, modifiers: [.command, .option, .shift])
            Button("Move Column Right") { run { $0.moveColumn(by: 1) } }.keyboardShortcut(.rightArrow, modifiers: [.command, .option, .shift])
            Button("Move Row Up") { run { $0.moveRow(by: -1) } }.keyboardShortcut(.upArrow, modifiers: [.command, .option, .shift])
            Button("Move Row Down") { run { $0.moveRow(by: 1) } }.keyboardShortcut(.downArrow, modifiers: [.command, .option, .shift])
            Divider()
            // ⌥⌘↓ / ⌥⌘→ inside a table cell; not bound here because ⌥⌘↓ moves blocks outside tables.
            Button("Add Row Below (⌥⌘↓ in a table)") { run { $0.addRow() } }
            Button("Add Column After (⌥⌘→ in a table)") { run { $0.addColumn() } }
            Button("Delete Row") { run { $0.removeRow() } }
            Button("Delete Column") { run { $0.removeColumn() } }
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
            Button("Assistant") { model.toggleAssistant() }.keyboardShortcut("j")
            Button("Calendar") { model.openView(ViewRef(kind: "calendar")) }.keyboardShortcut("1", modifiers: [.command, .option, .shift])
            Button("Tasks") { model.openView(ViewRef(kind: "tasks")) }.keyboardShortcut("2", modifiers: [.command, .option, .shift])
        }
        CommandGroup(before: .sidebar) {
            Button("Present") { if let id = model.activeDocId { model.present(id) } }
                .keyboardShortcut("p", modifiers: [.command, .option]).disabled(model.activeDocId == nil)
            Button(model.focusMode ? "Leave Focus Mode" : "Focus Mode") { withAnimation(Motion.standard(model.library.settings.reduceMotion)) { model.focusMode.toggle() } }
                .keyboardShortcut("f", modifiers: [.command, .shift]).disabled(model.activeDocId == nil && !model.focusMode)
            Button(model.library.settings.railCollapsed ? "Show Sidebar" : "Hide Sidebar") {
                model.setSettings { $0.railCollapsed.toggle() }
            }.keyboardShortcut("s", modifiers: [.command, .control])
            Divider()
            Button("Gallery") { model.setSettings { $0.libraryView = .gallery } }.keyboardShortcut("1", modifiers: [.command, .control])
            Button("Grid") { model.setSettings { $0.libraryView = .grid } }.keyboardShortcut("2", modifiers: [.command, .control])
            Button("List") { model.setSettings { $0.libraryView = .list } }.keyboardShortcut("3", modifiers: [.command, .control])
            Divider()
        }
        CommandGroup(replacing: .help) {
            Button("Keyboard Shortcuts") { model.shortcutsSheet = true }.keyboardShortcut("/")
            Divider()
            Button("Show Welcome…") { model.showWelcome() }
            Button("Take the Tour") { model.startTour() }
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
