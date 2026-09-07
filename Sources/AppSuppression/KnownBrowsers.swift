import Foundation

/// Browsers whose frontmost page the app tries to identify before converting.
///
/// An app that is not on this list is treated as an ordinary application: its
/// bundle identifier is checked against the exclusion list and that is all. So
/// a browser missing from here does not misbehave, it simply gets no site
/// rules — the user's fallback is to exclude the whole browser by name, which
/// the menu makes a one-click job.
public enum KnownBrowsers {

    /// Chromium and WebKit browsers expose the page URL through the
    /// accessibility tree. Gecko browsers generally do not, and fall back to
    /// the window title, which is the page title and so still names the site.
    public static let bundleIDs: Set<String> = [
        // WebKit
        "com.apple.Safari",
        "com.apple.SafariTechnologyPreview",
        "com.kagi.kagimacOS",              // Orion

        // Chromium
        "com.google.Chrome",
        "com.google.Chrome.beta",
        "com.google.Chrome.dev",
        "com.google.Chrome.canary",
        "org.chromium.Chromium",
        "com.microsoft.edgemac",
        "com.microsoft.edgemac.Beta",
        "com.brave.Browser",
        "com.brave.Browser.beta",
        "com.brave.Browser.nightly",
        "company.thebrowser.Browser",      // Arc
        "company.thebrowser.dia",          // Dia
        "com.vivaldi.Vivaldi",
        "com.operasoftware.Opera",
        "com.operasoftware.OperaGX",
        "com.operasoftware.OperaDeveloper",
        "ai.perplexity.comet",
        "com.duckduckgo.mobile.ios",       // the macOS build keeps the iOS id
        "com.pushplaylabs.sidekick",
        "com.naver.Whale",

        // Gecko
        "org.mozilla.firefox",
        "org.mozilla.firefoxdeveloperedition",
        "org.mozilla.nightly",
        "app.zen-browser.zen",
        "io.github.zen-browser.zen",
        "org.torproject.torbrowser",
    ]

    public static func isBrowser(_ bundleID: String?) -> Bool {
        guard let bundleID else { return false }
        return bundleIDs.contains(bundleID)
    }
}
