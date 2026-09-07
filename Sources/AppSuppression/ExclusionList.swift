import Foundation

/// An application the app must stay silent in, identified by bundle
/// identifier because that is the only stable name an app has.
public struct ExcludedApp: Codable, Equatable, Hashable, Identifiable {
    public let bundleID: String
    /// Display only. Stored so the editor can show a readable row even when the
    /// app has since been uninstalled.
    public var name: String

    public var id: String { bundleID }

    public init(bundleID: String, name: String) {
        self.bundleID = bundleID
        self.name = name
    }
}

/// A website the app must stay silent on, for the case the whole exclusion
/// list exists to solve: Overleaf is not an app, it is a tab.
public struct ExcludedSite: Codable, Equatable, Hashable, Identifiable {
    /// A host such as `overleaf.com`. Matches that host and any subdomain of
    /// it, so `www.` and `fr.` are covered without listing them.
    public var host: String

    /// Matched against the window title when the URL cannot be read, which is
    /// the Firefox case. Case-insensitive substrings.
    ///
    /// These are looser than a host match on purpose. A title match can fire on
    /// a page that merely mentions Overleaf, and that costs the user one
    /// unconverted command — much cheaper than the miss it prevents.
    public var titleFragments: [String]

    public var id: String { host }

    public init(host: String, titleFragments: [String] = []) {
        self.host = host
        self.titleFragments = titleFragments
    }
}

/// The user's exclusions, persisted whole.
public struct ExclusionList: Codable, Equatable {

    public var apps: [ExcludedApp]
    public var sites: [ExcludedSite]

    /// What to do in a browser whose page we cannot identify at all — neither
    /// URL nor title.
    ///
    /// Defaults to suppressing. The spec's rule is that an app which corrupts
    /// LaTeX source is worse than no app, and "I do not know what page this is"
    /// is not a good enough reason to start rewriting text. Exposed as a
    /// setting because a user who never opens Overleaf pays for this and
    /// should be able to stop paying.
    public var suppressUnidentifiedPages: Bool

    /// Bundle identifiers the user has deleted from the list. Kept so that
    /// first-launch discovery does not helpfully put them back every time.
    public var declinedBundleIDs: [String]

    public init(apps: [ExcludedApp] = [],
                sites: [ExcludedSite] = [],
                suppressUnidentifiedPages: Bool = true,
                declinedBundleIDs: [String] = []) {
        self.apps = apps
        self.sites = sites
        self.suppressUnidentifiedPages = suppressUnidentifiedPages
        self.declinedBundleIDs = declinedBundleIDs
    }

    // MARK: Editing

    public func contains(bundleID: String) -> Bool {
        apps.contains { $0.bundleID == bundleID }
    }

    public mutating func add(_ app: ExcludedApp) {
        guard !contains(bundleID: app.bundleID) else { return }
        apps.append(app)
        apps.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        declinedBundleIDs.removeAll { $0 == app.bundleID }
    }

    /// Removing is remembered: see `declinedBundleIDs`.
    public mutating func removeApp(bundleID: String) {
        apps.removeAll { $0.bundleID == bundleID }
        if !declinedBundleIDs.contains(bundleID) {
            declinedBundleIDs.append(bundleID)
        }
    }

    public mutating func add(_ site: ExcludedSite) {
        guard let host = ExclusionList.normalisedHost(site.host) else { return }
        guard !sites.contains(where: { $0.host == host }) else { return }
        sites.append(ExcludedSite(host: host, titleFragments: site.titleFragments))
        sites.sort { $0.host < $1.host }
    }

    public mutating func removeSite(host: String) {
        sites.removeAll { $0.host == host }
    }

    // MARK: The decision

    /// The whole point of the module.
    ///
    /// Order matters: an app rule beats everything, because a user who excluded
    /// their whole browser meant it. Only then do we look at the page.
    public func decision(for context: AppContext) -> SuppressionDecision {
        if let bundleID = context.bundleID,
           let app = apps.first(where: { $0.bundleID == bundleID }) {
            return .suppress(.excludedApp(name: app.name))
        }

        guard let page = context.page else { return .convert }

        switch page {
        case .url(let string):
            guard let host = ExclusionList.host(ofURL: string) else {
                // A URL we cannot parse tells us nothing, so it is treated
                // exactly like a page we could not read at all.
                return unidentifiedPageDecision(in: context)
            }
            if let site = sites.first(where: { ExclusionList.host(host, matches: $0.host) }) {
                return .suppress(.excludedSite(host: site.host))
            }
            return .convert

        case .title(let title):
            if let site = sites.first(where: { site in
                site.titleFragments.contains { !$0.isEmpty && title.localizedCaseInsensitiveContains($0) }
            }) {
                return .suppress(.excludedSiteTitle(host: site.host))
            }
            // A title we could read and that matches nothing is a real answer,
            // not an absence of one. Converting here is what keeps the app
            // usable in Firefox.
            return .convert

        case .unreadable:
            return unidentifiedPageDecision(in: context)
        }
    }

    private func unidentifiedPageDecision(in context: AppContext) -> SuppressionDecision {
        guard suppressUnidentifiedPages else { return .convert }
        return .suppress(.unidentifiedPage(app: context.displayName))
    }

    // MARK: Host matching

    /// Extracts a lowercased host from a URL string, or nil if there is not one
    /// — `about:blank` and `chrome://newtab` have no host, and neither does a
    /// malformed string.
    public static func host(ofURL string: String) -> String? {
        guard let host = URLComponents(string: string)?.host, !host.isEmpty else { return nil }
        return host.lowercased()
    }

    /// `overleaf.com` matches `overleaf.com` and `www.overleaf.com`, but not
    /// `notoverleaf.com` and not `overleaf.com.example.net`. The dot is what
    /// makes the difference and it is easy to leave out by accident.
    public static func host(_ host: String, matches pattern: String) -> Bool {
        let host = host.lowercased()
        let pattern = pattern.lowercased()
        return host == pattern || host.hasSuffix("." + pattern)
    }

    /// Accepts what a user is likely to paste — a full URL, a host with a
    /// `www.`, a trailing slash — and returns the bare host.
    public static func normalisedHost(_ input: String) -> String? {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !text.isEmpty else { return nil }

        if let host = host(ofURL: text) {
            text = host
        } else {
            // No scheme, so URLComponents parses it as a path rather than a
            // host. Take everything before the first slash.
            text = String(text.prefix(while: { $0 != "/" }))
        }
        if text.hasPrefix("www.") { text.removeFirst(4) }

        // A host has at least one dot and no spaces. Anything else is a typo,
        // and a rule that matches nothing is worse than a refused one.
        guard text.contains("."), !text.contains(" "), !text.hasPrefix("."), !text.hasSuffix(".") else {
            return nil
        }
        return text
    }
}

public enum SuppressionDecision: Equatable {
    case convert
    case suppress(SuppressionReason)

    public var isSuppressed: Bool {
        if case .suppress = self { return true }
        return false
    }

    public var reason: SuppressionReason? {
        if case .suppress(let reason) = self { return reason }
        return nil
    }
}

public enum SuppressionReason: Equatable {
    case excludedApp(name: String)
    case excludedSite(host: String)
    case excludedSiteTitle(host: String)
    case unidentifiedPage(app: String)

    /// Shown in the menu bar, so it completes the sentence "Off in Safari —".
    public var explanation: String {
        switch self {
        case .excludedApp(let name):
            return "\(name) is on the exclusion list"
        case .excludedSite(let host):
            return "\(host) is on the exclusion list"
        case .excludedSiteTitle(let host):
            return "this window looks like \(host)"
        case .unidentifiedPage(let app):
            return "\(app) will not say which page is open"
        }
    }

    /// Short enough for a menu row.
    public var summary: String {
        switch self {
        case .excludedApp(let name):          return "Off in \(name)"
        case .excludedSite(let host):         return "Off on \(host)"
        case .excludedSiteTitle(let host):    return "Off — looks like \(host)"
        case .unidentifiedPage:               return "Off — page unknown"
        }
    }
}
