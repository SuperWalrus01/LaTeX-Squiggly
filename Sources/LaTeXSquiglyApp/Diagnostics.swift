import AppKit
import InputTracking

/// `LaTeX-Squigly.app/Contents/MacOS/LaTeX-Squigly --diagnose`
///
/// Answers "it isn't working" without guesswork. Every failure mode this app
/// has looks the same from the outside — a menu bar app that is off, missing a
/// permission, or crashed all present as nothing happening when you type.
enum Diagnostics {

    @MainActor
    static func run() {
        let permissions = Permissions.current()
        let enabled = UserDefaults.standard.object(forKey: "conversionEnabled") as? Bool

        print("LaTeX-Squigly diagnostics")
        print("  bundle id:         \(Bundle.main.bundleIdentifier ?? "none (running unbundled)")")
        print("  conversion:        \(enabled.map { $0 ? "enabled" : "disabled" } ?? "never configured (defaults to off)")")
        print("  Accessibility:     \(permissions.accessibility ? "granted" : "NOT GRANTED")")
        print("  Input Monitoring:  \(permissions.inputMonitoring ? "granted" : "NOT GRANTED")")

        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                                    options: .defaultTap, eventsOfInterest: mask,
                                    callback: { _, _, event, _ in Unmanaged.passUnretained(event) },
                                    userInfo: nil)
        print("  event tap:         \(tap != nil ? "can be created" : "REFUSED (permission missing)")")
        if let tap { CFMachPortInvalidate(tap) }

        print("")
        if !permissions.allGranted {
            print("Next: grant \(permissions.missing.map(\.title).joined(separator: " and ")) in")
            print("System Settings > Privacy & Security, then tick Enable conversion in the menu bar.")
        } else if enabled != true {
            print("Next: click the \u{0192} in the menu bar and tick Enable conversion.")
        } else {
            print("Everything is set up. Type \\\\alpha followed by a space to test it.")
        }

        print("")
        print("Note: run this from inside the .app bundle, not via `swift run`.")
        print("macOS attributes permissions to the running bundle, so a bare")
        print("executable reports your terminal's permissions instead.")
    }
}
