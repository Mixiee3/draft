import Foundation

/// The app's translation of a UI string that reaches AppKit or a view as a plain String (command
/// titles, menu items, tooltips). The key is the English text; missing translations fall back to it.
public func loc(_ s: String) -> String { Bundle.main.localizedString(forKey: s, value: s, table: nil) }

/// Dates and times in the app's language with the person's region (Foundation's `Locale.current`
/// keeps the system language even when Draft runs in Czech or German).
public let appLocale: Locale = {
    let lang = Bundle.main.preferredLocalizations.first ?? "en"
    guard let region = Locale.current.region?.identifier else { return Locale(identifier: lang) }
    return Locale(identifier: "\(lang)_\(region)")
}()
