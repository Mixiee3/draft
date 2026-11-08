// Out-of-process accessibility audit: lists every button, menu button, field, checkbox and slider in
// Draft's windows that VoiceOver would announce without a name. Needs the terminal running it to be
// allowed under System Settings > Privacy & Security > Accessibility.
// Usage: swift scripts/ax-audit.swift [pid]   (default: the running Draft)
import ApplicationServices
import AppKit

guard AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary) else {
    print("Allow this terminal under Privacy & Security > Accessibility, then run again."); exit(2)
}
let pid = CommandLine.arguments.dropFirst().first.flatMap { Int32($0) }
    ?? NSWorkspace.shared.runningApplications.first { $0.localizedName == "Draft" }?.processIdentifier
guard let pid else { print("Draft is not running."); exit(2) }

func attr(_ e: AXUIElement, _ k: String) -> CFTypeRef? { var v: CFTypeRef?; return AXUIElementCopyAttributeValue(e, k as CFString, &v) == .success ? v : nil }
func str(_ e: AXUIElement, _ k: String) -> String { (attr(e, k) as? String) ?? "" }
let checked: Set<String> = ["AXButton", "AXMenuButton", "AXPopUpButton", "AXTextField", "AXCheckBox", "AXRadioButton", "AXSlider", "AXComboBox"]
var unnamed: [String] = [], total = 0

func visit(_ e: AXUIElement, path: String, depth: Int) {
    guard depth < 60 else { return }
    let role = str(e, kAXRoleAttribute)
    if checked.contains(role), str(e, kAXHiddenAttribute) != "1" {
        total += 1
        let name = [kAXTitleAttribute, kAXDescriptionAttribute, "AXLabel", kAXPlaceholderValueAttribute].map { str(e, $0) }.first { !$0.isEmpty }
        if name == nil { unnamed.append("\(path) > \(role) \(str(e, kAXHelpAttribute))") }
    }
    for c in (attr(e, kAXChildrenAttribute) as? [AXUIElement]) ?? [] { visit(c, path: path + "/" + role, depth: depth + 1) }
}

let app = AXUIElementCreateApplication(pid)
for w in (attr(app, kAXWindowsAttribute) as? [AXUIElement]) ?? [] { visit(w, path: str(w, kAXTitleAttribute), depth: 0) }
print("\(total) controls checked, \(unnamed.count) without a name")
unnamed.forEach { print("  " + $0) }
exit(unnamed.isEmpty ? 0 : 1)
