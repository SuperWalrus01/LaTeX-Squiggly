// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "LaTeXUnicode",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "LaTeXUnicode", targets: ["LaTeXUnicode"]),
        .executable(name: "latex-unicode-check", targets: ["latex-unicode-check"]),
    ],
    targets: [
        // Phase 0: the conversion engine. No UI, no system APIs, no dependencies.
        .target(name: "LaTeXUnicode"),

        // The test suite proper, written without XCTest so it can run on a
        // machine that has only the Command Line Tools installed.
        .target(name: "LaTeXUnicodeChecks", dependencies: ["LaTeXUnicode"]),

        // Runs the suite: `swift run latex-unicode-check`.
        .executableTarget(name: "latex-unicode-check", dependencies: ["LaTeXUnicodeChecks"]),

        // The same suite under `swift test`. Needs Xcode; see README.
        .testTarget(name: "LaTeXUnicodeTests", dependencies: ["LaTeXUnicodeChecks"]),
    ]
)
