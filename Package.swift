// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Draft",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Draft", targets: ["Draft"]),
        .library(name: "DraftCore", targets: ["DraftCore"]),
    ],
    targets: [
        // Portable document format, vault, migrations, export. Foundation only — the
        // future Windows app re-implements or ports exactly this layer.
        .target(name: "DraftCore"),
        // AppKit/TextKit 1 block editor.
        .target(name: "DraftEditor", dependencies: ["DraftCore"]),
        // SwiftUI application shell.
        .executableTarget(name: "Draft", dependencies: ["DraftCore", "DraftEditor"]),
        .testTarget(name: "DraftCoreTests", dependencies: ["DraftCore"]),
        .testTarget(name: "DraftEditorTests", dependencies: ["DraftEditor", "DraftCore"]),
    ],
    swiftLanguageModes: [.v5]
)
