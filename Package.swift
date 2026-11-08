// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Draft",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Draft", targets: ["Draft"]),
        .library(name: "DraftCore", targets: ["DraftCore"]),
    ],
    dependencies: [
        // MIT. Pinned to a tested revision; only ThinkingOrbsKit, BorderBeamKit and VoiceGlowKit are used.
        .package(url: "https://github.com/Jakubantalik/Libraries.dev", revision: "9a42e88847dab0ac145733f15cf90535e9cb59ab"),
    ],
    targets: [
        // Portable document format, vault, migrations, export. Foundation only — the
        // future Windows app re-implements or ports exactly this layer.
        .target(name: "DraftCore"),
        // AppKit/TextKit 1 block editor.
        .target(name: "DraftEditor", dependencies: ["DraftCore"]),
        // llama.cpp b11722 (MIT), the on-device inference runtime for the Assistant.
        .binaryTarget(
            name: "llama",
            url: "https://github.com/ggml-org/llama.cpp/releases/download/b11722/llama-b11722-xcframework.zip",
            checksum: "871c4faa010c0e34391803e5741cb393901e222d2e82492b8e5b78882a8296e6"
        ),
        // Local model download, verification and generation.
        .target(name: "DraftAssistant", dependencies: ["DraftCore", "llama"]),
        // SwiftUI application shell.
        .executableTarget(name: "Draft", dependencies: [
            "DraftCore", "DraftEditor", "DraftAssistant",
            .product(name: "ThinkingOrbsKit", package: "Libraries.dev"),
            .product(name: "BorderBeamKit", package: "Libraries.dev"),
            .product(name: "VoiceGlowKit", package: "Libraries.dev"),
        ], resources: [.process("Effects/LiquidMetal.metal")]),
        .testTarget(name: "DraftCoreTests", dependencies: ["DraftCore"]),
        .testTarget(name: "DraftEditorTests", dependencies: ["DraftEditor", "DraftCore"]),
        .testTarget(name: "DraftAssistantTests", dependencies: ["DraftAssistant", "DraftCore"]),
    ],
    swiftLanguageModes: [.v5]
)
