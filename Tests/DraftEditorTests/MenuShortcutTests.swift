import XCTest
import AppKit
@testable import DraftEditor

final class MenuShortcutTests: XCTestCase {
    func testReadsNestedMenusAndFormatsKeys() {
        let root = NSMenu(), file = NSMenu(title: "File"), fileItem = NSMenuItem(title: "File", action: nil, keyEquivalent: "")
        fileItem.submenu = file
        root.addItem(fileItem)
        file.addItem(NSMenuItem(title: "New Document", action: nil, keyEquivalent: "n"))
        let tmpl = NSMenuItem(title: "New from Template…", action: nil, keyEquivalent: "t"); tmpl.keyEquivalentModifierMask = [.command, .option]
        file.addItem(tmpl)
        file.addItem(.separator())
        file.addItem(NSMenuItem(title: "No shortcut", action: nil, keyEquivalent: ""))
        let found = menuShortcuts(root)
        XCTAssertEqual(found, [MenuShortcut(menu: "File", title: "New Document", keys: "⌘N"), MenuShortcut(menu: "File", title: "New from Template…", keys: "⌥⌘T")])
        XCTAssertEqual(shortcutLabel(key: "D", modifiers: .command), "⇧⌘D")
    }
}
