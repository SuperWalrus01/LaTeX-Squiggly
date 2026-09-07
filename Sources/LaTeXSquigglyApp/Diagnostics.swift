import AppKit
import AppSuppression
import InputTracking

/// `LaTeX-Squiggly.app/Contents/MacOS/LaTeX-Squiggly --diagnose`
///
/// Answers "it isn't working" without guesswork. Every failure mode this app
/// has looks the same from the outside — a menu bar app that is off, missing a
/// permission, crashed, or deliberately staying quiet all present as nothing
/// happening when you type.
enum Diagnostics {

    @MainActor
    static func run() {
        let permissions = Permissions.current()
        let enabled = UserDefaults.standard.object(forKey: "conversionEnabled") as? Bool

        print("LaTeX-Squiggly diagnostics")
        print("  bundle id:         \(Bundle.main.bundleIdentifier ?? "none (running unbundled)")")
        print("  conversion:        \(enabled.map { $0 ? "enabled" : "disabled" } ?? "never configured (defaults to on)")")
        print("  Accessibility:     \(permissions.accessibility ? "granted" : "NOT GRANTED")")
        print("  Input Monitoring:  \(permissions.inputMonitoring ? "granted" : "NOT GRANTED")")

        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                                    options: .defaultTap, eventsOfInterest: mask,
                                    callback: { _, _, event, _ in Unmanaged.passUnretained(event) },
                                    userInfo: nil)
        print("  event tap:         \(tap != nil ? "can be created" : "REFUSED (permission missing)")")
        if let tap { CFMachPortInvalidate(tap) }

        // Phase 2 makes "it stopped working in one app" something that can be
        // true on purpose, so the exclusion list has to be inspectable.
        let store = ExclusionStore()
        store.discoverInstalledApplications(persisting: false)
        let list = store.list

        print("")
        print("Excluded apps (\(list.apps.count)):")
        for app in list.apps {
            print("  \(app.name.padding(toLength: 24, withPad: " ", startingAt: 0)) \(app.bundleID)")
        }
        print("Excluded sites (\(list.sites.count)):")
        for site in list.sites {
            print("  \(site.host)")
        }
        print("  unidentified browser pages: \(list.suppressUnidentifiedPages ? "suppressed" : "converted")")

        probeBrowsers(against: list)

        print("")
        if !permissions.allGranted {
            print("Next: grant \(permissions.missing.map(\.title).joined(separator: " and ")) in")
            print("System Settings > Privacy & Security, then tick Enable conversion in the menu bar.")
        } else if enabled == false {
            print("Next: click the \u{0192} in the menu bar and tick Enable conversion.")
        } else {
            print("Everything is set up. Type \\\\alpha followed by a space to test it.")
        }

        print("")
        print("Note: run this from inside the .app bundle, not via `swift run`.")
        print("macOS attributes permissions to the running bundle, so a bare")
        print("executable reports your terminal's permissions instead.")
    }

    /// Reports what can be read out of each running browser, and what the
    /// exclusion list would do about it.
    ///
    /// This answers both "why did it convert inside Overleaf" and its opposite,
    /// "why has it gone quiet in Chrome". Hosts are printed rather than whole
    /// URLs: an Overleaf link carries a share token, and a diagnostic people
    /// paste into a bug report should not carry it too.
    @MainActor
    private static func probeBrowsers(against list: ExclusionList) {
        let browsers = NSWorkspace.shared.runningApplications
            .filter { KnownBrowsers.isBrowser($0.bundleIdentifier) }

        print("")
        guard !browsers.isEmpty else {
            print("Running browsers: none.")
            return
        }

        print("Running browsers:")
        for browser in browsers {
            let name = browser.localizedName ?? browser.bundleIdentifier ?? "?"
            let page = BrowserPageReader.page(for: browser)

            let described: String
            switch page {
            case .url(let url):
                described = "URL readable, host " + (ExclusionList.host(ofURL: url) ?? "(none)")
            case .title(let title):
                described = "title only: \u{201C}\(title.prefix(48))\u{201D}"
            case .unreadable:
                described = "NOT READABLE \u{2014} pages here are suppressed"
            case nil:
                described = "not treated as a browser"
            }

            let context = AppContext(bundleID: browser.bundleIdentifier, name: name, page: page)
            let verdict = list.decision(for: context).reason.map(\.summary) ?? "would convert"

            print("  \(name.padding(toLength: 18, withPad: " ", startingAt: 0)) \(described)")
            print("  \(String(repeating: " ", count: 18)) \(verdict)")
        }
    }
}
