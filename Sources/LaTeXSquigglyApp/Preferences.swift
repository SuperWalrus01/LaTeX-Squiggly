import Foundation

/// Every switch the settings window offers, in one place, so adding one is a
/// line here rather than a string literal loose in a view.
///
/// `conversionEnabled` deliberately has no registered default. Its *absence* is
/// what marks the first launch — see `isFirstRun` — and a registered default
/// would be handed back by `object(forKey:)` and hide that.
enum Preferences {

    private static let conversionEnabledKey = "conversionEnabled"
    private static let showNoticesKey = "showNotices"

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [showNoticesKey: true])
    }

    /// On from the first launch, which only became a defensible default with
    /// Phase 2: an always-on replacement with no exclusion list rewrites LaTeX
    /// source as you type it, and the app used to have no way of knowing.
    static var conversionEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: conversionEnabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: conversionEnabledKey) }
    }

    static var isFirstRun: Bool {
        UserDefaults.standard.object(forKey: conversionEnabledKey) == nil
    }

    /// Covers the notices a conversion produces — a fallback, a refusal, a
    /// replacement declined because the page turned out to be excluded. The
    /// app's own state messages ("conversion stopped, permission was turned
    /// off") are not gated by this: silencing those would leave the app
    /// looking broken instead of quiet.
    static var showNotices: Bool {
        get { UserDefaults.standard.bool(forKey: showNoticesKey) }
        set { UserDefaults.standard.set(newValue, forKey: showNoticesKey) }
    }
}
