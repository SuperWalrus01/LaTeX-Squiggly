// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "LaTeXSquigly",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "LaTeXUnicode", targets: ["LaTeXUnicode"]),
        .library(name: "InputTracking", targets: ["InputTracking"]),
        .executable(name: "LaTeXSquiglyApp", targets: ["LaTeXSquiglyApp"]),
        .executable(name: "latex-squigly", targets: ["latex-squigly"]),
        .executable(name: "latex-squigly-check", targets: ["latex-squigly-check"]),
    ],
    targets: [
        // Phase 0: the conversion engine. No UI, no system APIs, no dependencies.
        // Keeps its own name: it is a LaTeX-to-Unicode converter, which is a
        // better description of the module than the app's product name.
        .target(name: "LaTeXUnicode"),

        // Phase 1 typing logic, kept free of system APIs so it stays testable.
        .target(name: "InputTracking", dependencies: ["LaTeXUnicode"]),

        // Phase 1: the menu bar app. Bundle it with Scripts/make-app.sh.
        .executableTarget(name: "LaTeXSquiglyApp", dependencies: ["LaTeXUnicode", "InputTracking"]),

        // Try conversions by hand: `swift run latex-squigly`.
        .executableTarget(name: "latex-squigly", dependencies: ["LaTeXUnicode", "InputTracking"]),

        // The test suite proper, written without XCTest so it can run on a
        // machine that has only the Command Line Tools installed.
        .target(name: "LaTeXUnicodeChecks", dependencies: ["LaTeXUnicode", "InputTracking"]),

        // Runs the suite: `swift run latex-squigly-check`.
        .executableTarget(name: "latex-squigly-check", dependencies: ["LaTeXUnicodeChecks"]),

        // The same suite under `swift test`. Needs Xcode; see README.
        .testTarget(name: "LaTeXUnicodeTests", dependencies: ["LaTeXUnicodeChecks"]),
    ]
)
