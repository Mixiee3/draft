import AppKit

/// Every shortcut in a menu tree, read from the menus themselves so a list built from it can't
/// drift from what the menu bar does.
public struct MenuShortcut: Hashable, Sendable {
    public var menu: String
    public var title: String
    public var keys: String
    public init(menu: String, title: String, keys: String) { self.menu = menu; self.title = title; self.keys = keys }
}

public func shortcutLabel(key: String, modifiers: NSEvent.ModifierFlags) -> String {
    var s = ""
    if modifiers.contains(.control) { s += "⌃" }
    if modifiers.contains(.option) { s += "⌥" }
    if modifiers.contains(.shift) || (key.count == 1 && key != key.lowercased()) { s += "⇧" }
    if modifiers.contains(.command) { s += "⌘" }
    let names: [String: String] = ["\r": "↩", "\u{1b}": "⎋", "\t": "⇥", " ": "Space", "\u{7f}": "⌫",
                                   String(UnicodeScalar(NSUpArrowFunctionKey)!): "↑", String(UnicodeScalar(NSDownArrowFunctionKey)!): "↓",
                                   String(UnicodeScalar(NSLeftArrowFunctionKey)!): "←", String(UnicodeScalar(NSRightArrowFunctionKey)!): "→",
                                   String(UnicodeScalar(NSF10FunctionKey)!): "F10"]
    return s + (names[key] ?? key.uppercased())
}

public func menuShortcuts(_ menu: NSMenu, path: String = "") -> [MenuShortcut] {
    var out: [MenuShortcut] = []
    for item in menu.items where !item.isSeparatorItem && !item.isHidden {
        if let sub = item.submenu {
            out += menuShortcuts(sub, path: path.isEmpty ? item.title : path)
        } else if !item.keyEquivalent.isEmpty {
            out.append(MenuShortcut(menu: path, title: item.title, keys: shortcutLabel(key: item.keyEquivalent, modifiers: item.keyEquivalentModifierMask)))
        }
    }
    return out
}
