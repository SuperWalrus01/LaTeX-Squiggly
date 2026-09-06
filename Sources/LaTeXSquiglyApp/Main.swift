import AppKit

// Not named main.swift: top-level code there is not main-actor isolated, and
// every AppKit object here is.
@main
enum Main {
    @MainActor
    static func main() {
        if CommandLine.arguments.contains("--diagnose") {
            Diagnostics.run()
            return
        }

        // LSUIElement in Info.plist already makes this a menu bar app; setting
        // the policy here too keeps it Dock-less when run straight from .build
        // during development, where there is no bundle to read.
        let application = NSApplication.shared
        application.setActivationPolicy(.accessory)

        let delegate = AppDelegate()
        application.delegate = delegate
        application.run()
    }
}
