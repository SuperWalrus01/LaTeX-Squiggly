import AppSuppression
import Foundation

func runSuppressionChecks(_ c: Checker) {

    let chrome = "com.google.Chrome"
    let firefox = "org.mozilla.firefox"

    func list() -> ExclusionList {
        ExclusionList(apps: [ExcludedApp(bundleID: "com.microsoft.VSCode", name: "Visual Studio Code")],
                      sites: [ExcludedSite(host: "overleaf.com", titleFragments: ["Overleaf"])])
    }

    func browsing(_ page: BrowserPage, in bundleID: String = "com.google.Chrome") -> AppContext {
        AppContext(bundleID: bundleID, name: "Browser", page: page)
    }

    // MARK: Applications

    c.equal(list().decision(for: AppContext(bundleID: "com.microsoft.VSCode", name: "Visual Studio Code")),
            .suppress(.excludedApp(name: "Visual Studio Code")),
            "an excluded app suppresses")

    c.equal(list().decision(for: AppContext(bundleID: "net.whatsapp.WhatsApp", name: "WhatsApp")),
            .convert,
            "an app that is not on the list converts")

    c.equal(list().decision(for: AppContext(bundleID: nil)), .convert,
            "no frontmost app is not a reason to suppress")

    // A non-browser is never asked about pages, so a nil page must not be
    // confused with a page we failed to read.
    c.equal(list().decision(for: AppContext(bundleID: "com.apple.Notes", name: "Notes")), .convert,
            "a non-browser has no page and converts")

    // MARK: Hosts

    c.expect(ExclusionList.host("overleaf.com", matches: "overleaf.com"), "exact host")
    c.expect(ExclusionList.host("www.overleaf.com", matches: "overleaf.com"), "www subdomain")
    c.expect(ExclusionList.host("fr.overleaf.com", matches: "overleaf.com"), "any subdomain")
    c.expect(ExclusionList.host("OVERLEAF.COM", matches: "overleaf.com"), "case insensitive")
    c.expect(!ExclusionList.host("notoverleaf.com", matches: "overleaf.com"),
             "a suffix without the dot is a different site")
    c.expect(!ExclusionList.host("overleaf.com.example.net", matches: "overleaf.com"),
             "a host that merely starts with the pattern is a different site")
    c.expect(!ExclusionList.host("overleaf.co", matches: "overleaf.com"), "different TLD")

    c.equal(ExclusionList.host(ofURL: "https://www.overleaf.com/project/abc"), "www.overleaf.com",
            "host out of a URL")
    c.equal(ExclusionList.host(ofURL: "https://OVERLEAF.com/x"), "overleaf.com", "host lowercased")
    c.isNil(ExclusionList.host(ofURL: "about:blank"), "about:blank has no host")
    c.isNil(ExclusionList.host(ofURL: "not a url at all"), "malformed URL has no host")
    c.isNil(ExclusionList.host(ofURL: ""), "empty URL has no host")

    // MARK: Pages, by URL

    c.equal(list().decision(for: browsing(.url("https://www.overleaf.com/project/652"))),
            .suppress(.excludedSite(host: "overleaf.com")),
            "Overleaf in a browser suppresses")

    c.equal(list().decision(for: browsing(.url("https://web.whatsapp.com/"))), .convert,
            "another tab in the same browser converts")

    c.equal(list().decision(for: browsing(.url("https://notoverleaf.com/"))), .convert,
            "a lookalike host converts")

    // MARK: Pages, by title

    c.equal(list().decision(for: browsing(.title("Report - Overleaf, Online LaTeX Editor"), in: firefox)),
            .suppress(.excludedSiteTitle(host: "overleaf.com")),
            "the title fallback catches Overleaf where the URL is unreadable")

    c.equal(list().decision(for: browsing(.title("overleaf - Google Search"), in: firefox)),
            .suppress(.excludedSiteTitle(host: "overleaf.com")),
            "the title fallback errs towards suppressing, which costs a conversion not a document")

    c.equal(list().decision(for: browsing(.title("Slack | general"), in: firefox)), .convert,
            "a title we could read that matches nothing converts, which is what keeps Firefox usable")

    // MARK: Pages we cannot identify

    c.equal(list().decision(for: browsing(.unreadable)),
            .suppress(.unidentifiedPage(app: "Browser")),
            "a page we cannot identify suppresses by default")

    c.equal(list().decision(for: browsing(.url("about:blank"))),
            .suppress(.unidentifiedPage(app: "Browser")),
            "a URL with no host is as good as no answer")

    var permissive = list()
    permissive.suppressUnidentifiedPages = false
    c.equal(permissive.decision(for: browsing(.unreadable)), .convert,
            "the user can opt out of suppressing unidentified pages")
    c.equal(permissive.decision(for: browsing(.url("https://www.overleaf.com/project/1"))),
            .suppress(.excludedSite(host: "overleaf.com")),
            "opting out of that does not disable site rules")

    // MARK: Precedence

    var excludedBrowser = list()
    excludedBrowser.add(ExcludedApp(bundleID: chrome, name: "Google Chrome"))
    c.equal(excludedBrowser.decision(for: browsing(.url("https://web.whatsapp.com/"))),
            .suppress(.excludedApp(name: "Google Chrome")),
            "excluding a whole browser beats any page rule")

    // MARK: Editing

    var edited = ExclusionList()
    edited.add(ExcludedApp(bundleID: "b", name: "Beta"))
    edited.add(ExcludedApp(bundleID: "a", name: "Alpha"))
    edited.add(ExcludedApp(bundleID: "a", name: "Alpha again"))
    c.equal(edited.apps.count, 2, "adding the same bundle id twice adds one rule")
    c.equal(edited.apps.first?.name, "Alpha", "apps are sorted by name")

    edited.removeApp(bundleID: "a")
    c.equal(edited.apps.count, 1, "removing an app removes its rule")
    c.expect(edited.declinedBundleIDs.contains("a"),
             "a removed app is remembered, so launch discovery does not put it back")

    edited.add(ExcludedApp(bundleID: "a", name: "Alpha"))
    c.expect(!edited.declinedBundleIDs.contains("a"),
             "adding it back clears the refusal")

    // MARK: Host normalisation

    c.equal(ExclusionList.normalisedHost("https://www.overleaf.com/project/1"), "overleaf.com",
            "a pasted URL becomes a host")
    c.equal(ExclusionList.normalisedHost("www.overleaf.com"), "overleaf.com", "www is dropped")
    c.equal(ExclusionList.normalisedHost("overleaf.com/"), "overleaf.com", "a trailing slash is dropped")
    c.equal(ExclusionList.normalisedHost("  Overleaf.COM "), "overleaf.com", "trimmed and lowercased")
    c.equal(ExclusionList.normalisedHost("tex.mydepartment.ac.uk"), "tex.mydepartment.ac.uk",
            "a self-hosted instance keeps its subdomain")
    c.isNil(ExclusionList.normalisedHost("overleaf"), "a host needs a dot")
    c.isNil(ExclusionList.normalisedHost(""), "empty is not a host")
    c.isNil(ExclusionList.normalisedHost("two words.com"), "a host has no spaces")
    c.isNil(ExclusionList.normalisedHost(".com"), "a leading dot is a typo")

    var sites = ExclusionList()
    sites.add(ExcludedSite(host: "https://www.overleaf.com/"))
    c.equal(sites.sites.first?.host, "overleaf.com", "a site rule stores the normalised host")
    sites.add(ExcludedSite(host: "overleaf.com"))
    c.equal(sites.sites.count, 1, "the same host twice adds one rule")
    sites.add(ExcludedSite(host: "nonsense"))
    c.equal(sites.sites.count, 1, "a host that cannot be normalised is refused, not stored broken")

    // MARK: Persistence

    let original = list()
    if let data = try? JSONEncoder().encode(original),
       let decoded = try? JSONDecoder().decode(ExclusionList.self, from: data) {
        c.equal(decoded, original, "the list survives a round trip through JSON")
    } else {
        c.fail("the exclusion list must encode and decode")
    }

    // MARK: The shipped defaults

    c.equal(Set(DefaultExclusions.bundleIDs).count, DefaultExclusions.bundleIDs.count,
            "no duplicate default bundle ids")
    c.equal(Set(DefaultExclusions.applicationNames).count, DefaultExclusions.applicationNames.count,
            "no duplicate default app names")
    c.expect(DefaultExclusions.sites.contains { $0.host == "overleaf.com" },
             "Overleaf is excluded out of the box")

    for site in DefaultExclusions.sites {
        c.equal(ExclusionList.normalisedHost(site.host), site.host,
                "default host \(site.host) is already normalised")
        c.expect(!site.titleFragments.isEmpty,
                 "default site \(site.host) has a title fragment, or it is invisible in Firefox")
    }

    for bundleID in DefaultExclusions.bundleIDs {
        c.expect(!KnownBrowsers.bundleIDs.contains(bundleID),
                 "\(bundleID) must not be both a default exclusion and a browser")
    }

    c.expect(KnownBrowsers.isBrowser("com.google.Chrome"), "Chrome is a browser")
    c.expect(KnownBrowsers.isBrowser("com.apple.Safari"), "Safari is a browser")
    c.expect(KnownBrowsers.isBrowser("org.mozilla.firefox"), "Firefox is a browser")
    c.expect(!KnownBrowsers.isBrowser("net.whatsapp.WhatsApp"), "WhatsApp is not a browser")
    c.expect(!KnownBrowsers.isBrowser(nil), "no bundle id is not a browser")

    // MARK: Saved settings outlive the version that wrote them

    // The synthesised decoder demands every key, so a build that added a field
    // could not read what an older one saved. The store swallows that failure
    // and hands back the shipped defaults, which silently restores every app
    // the user removed and loses every site they added.
    let olderSchema = #"{"apps":[{"bundleID":"com.example.editor","name":"Editor"}],"sites":[]}"#
    if let restored = try? JSONDecoder().decode(ExclusionList.self,
                                                from: Data(olderSchema.utf8)) {
        c.equal(restored.apps.count, 1, "an older payload still decodes")
        c.equal(restored.apps.first?.bundleID, "com.example.editor", "and keeps what it held")
        c.expect(restored.suppressUnidentifiedPages, "a missing field takes its default")
        c.equal(restored.declinedBundleIDs, [], "and so does a missing list")
    } else {
        c.fail("an exclusion list saved by an older build must still decode")
    }

    // A payload from some future build with a field we have dropped is data we
    // do not understand, not a reason to throw the rest away.
    let newerSchema = #"{"apps":[],"sites":[],"suppressUnidentifiedPages":false,"declinedBundleIDs":[],"somethingLater":7}"#
    if let restored = try? JSONDecoder().decode(ExclusionList.self,
                                                from: Data(newerSchema.utf8)) {
        c.expect(!restored.suppressUnidentifiedPages, "an unknown field is ignored, not fatal")
    } else {
        c.fail("an unknown field must not lose the whole list")
    }

    // MARK: Reasons are sentences a person can act on

    for reason: SuppressionReason in [.excludedApp(name: "Cursor"),
                                      .excludedSite(host: "overleaf.com"),
                                      .excludedSiteTitle(host: "overleaf.com"),
                                      .unidentifiedPage(app: "Firefox")] {
        c.expect(!reason.explanation.isEmpty, "every reason explains itself")
        c.expect(!reason.summary.isEmpty, "every reason has a menu-length summary")
    }
}
