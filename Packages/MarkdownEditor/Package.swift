// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MarkdownEditor",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .library(name: "MarkdownEditor", targets: ["MarkdownEditorSwiftUI"]),
        .library(name: "MarkdownEditorCore", targets: ["MarkdownEditorCore"]),
    ],
    targets: [
        .target(name: "MarkdownEditorCore"),
        .target(name: "MarkdownEditorTextKit", dependencies: ["MarkdownEditorCore"]),
        .target(name: "MarkdownEditorUIKit", dependencies: ["MarkdownEditorCore", "MarkdownEditorTextKit"]),
        .target(name: "MarkdownEditorAppKit", dependencies: ["MarkdownEditorCore", "MarkdownEditorTextKit"]),
        .target(name: "MarkdownEditorSwiftUI", dependencies: ["MarkdownEditorCore", "MarkdownEditorTextKit", "MarkdownEditorUIKit", "MarkdownEditorAppKit"]),
        .testTarget(name: "MarkdownEditorCoreTests", dependencies: ["MarkdownEditorCore"], resources: [.copy("Fixtures")]),
        .testTarget(name: "MarkdownEditorAppKitTests", dependencies: ["MarkdownEditorAppKit", "MarkdownEditorCore"]),
    ]
)
