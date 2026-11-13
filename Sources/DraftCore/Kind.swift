import Foundation

/// The app's translation of a UI string that reaches AppKit or a view as a plain String (command
/// titles, menu items, tooltips). The key is the English text; missing translations fall back to it.
public func loc(_ s: String) -> String { Bundle.main.localizedString(forKey: s, value: s, table: nil) }
