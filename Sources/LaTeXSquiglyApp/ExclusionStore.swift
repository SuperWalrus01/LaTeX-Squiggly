import AppKit
import AppSuppression

/// Loads, saves and seeds the exclusion list.
///
/// Main thread only, like the rest of the app-side classes here.
final class ExclusionStore {

    private static let defaultsKey = "exclusions"

    private(set) var list: ExclusionList
    /// Called after the list changes for any reason, including discovery.
    var onChange: (() -> Void)?

    init() {
        list = ExclusionStore.load() ?? ExclusionList(sites: DefaultExclusions.sites)
    }

    // MARK: Persistence

    private static func load() -> ExclusionList? {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey) else { return nil }
        return try? JSONDecoder().decode(ExclusionList.self, from: data)
    }

    func save() {
        guard let data = try? JSONEncoder().encode(list) else { return }
        UserDefaults.standard.set(data, forKey: Self.defaultsKey)
        onChange?()
    }

    // MARK: Editing

    func exclude(_ application: NSRunningApplication) {
        guard let bundleID = application.bundleIdentifier else { return }
        list.add(ExcludedApp(bundleID: bundleID,
                             name: application.localizedName ?? bundleID))
        save()
    }

    func exclude(bundleID: String, name: String) {
        list.add(ExcludedApp(bundleID: bundleID, name: name))
        save()
    }

    func removeApp(bundleID: String) {
        list.removeApp(bundleID: bundleID)
        save()
    }

    func addSite(_ input: String) -> Bool {
        guard let host = ExclusionList.normalisedHost(input) else { return false }
        // A hand-added host gets its own name as a title fragment, so the rule
        // still bites in a browser that will not hand over URLs.
        let label = host.split(separator: ".").first.map(String.init) ?? host
        list.add(ExcludedSite(host: host, titleFragments: [label]))
        save()
        return true
    }

    func removeSite(host: String) {
        list.removeSite(host: host)
        save()
    }

    func setSuppressUnidentifiedPages(_ value: Bool) {
        list.suppressUnidentifiedPages = value
        save()
    }

    func restoreDefaults() {
        list = ExclusionList(sites: DefaultExclusions.sites)
        save()
        discoverInstalledApplications()
    }

    // MARK: Seeding

    /// Adds rules for the default apps that are actually installed.
    ///
    /// Runs on every launch rather than only the first, so an editor installed
    /// later is covered without the user thinking about it. Anything the user
    /// has deleted stays deleted — `ExclusionList.declinedBundleIDs` is what
    /// stops this from being an argument the app always wins.
    /// - Parameter persisting: false leaves the defaults untouched, for the
    ///   diagnostics command, which should be able to report what the app would
    ///   do without doing it.
    func discoverInstalledApplications(persisting: Bool = true) {
        var found: [(bundleID: String, name: String)] = []

        for bundleID in DefaultExclusions.bundleIDs {
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
            else { continue }
            found.append((bundleID, Self.displayName(at: url)))
        }

        for url in Self.installedApplications(named: DefaultExclusions.applicationNames) {
            guard let bundleID = Bundle(url: url)?.bundleIdentifier else { continue }
            found.append((bundleID, Self.displayName(at: url)))
        }

        var changed = false
        for candidate in found where !list.declinedBundleIDs.contains(candidate.bundleID) {
            guard !list.contains(bundleID: candidate.bundleID) else { continue }
            list.add(ExcludedApp(bundleID: candidate.bundleID, name: candidate.name))
            changed = true
        }
        if changed, persisting { save() }
    }

    /// Matches on the app's file name, which is what the user sees and what the
    /// name list is written in. The bundle identifier is then read off the disk
    /// rather than guessed — the whole reason this path exists.
    private static func installedApplications(named names: [String]) -> [URL] {
        let wanted = Set(names.map { $0.lowercased() })
        let roots = [
            "/Applications",
            "/System/Applications",
            NSHomeDirectory() + "/Applications",
        ].map { URL(fileURLWithPath: $0) }

        var matches: [URL] = []
        let manager = FileManager.default

        for root in roots {
            guard let entries = try? manager.contentsOfDirectory(
                at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
            else { continue }

            for entry in entries {
                if entry.pathExtension == "app" {
                    if wanted.contains(entry.deletingPathExtension().lastPathComponent.lowercased()) {
                        matches.append(entry)
                    }
                    continue
                }
                // One level down covers /Applications/Utilities and the folders
                // installers like MacTeX create.
                guard let nested = try? manager.contentsOfDirectory(
                    at: entry, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
                else { continue }
                for candidate in nested where candidate.pathExtension == "app" {
                    if wanted.contains(candidate.deletingPathExtension().lastPathComponent.lowercased()) {
                        matches.append(candidate)
                    }
                }
            }
        }
        return matches
    }

    private static func displayName(at url: URL) -> String {
        FileManager.default.displayName(atPath: url.path)
            .replacingOccurrences(of: ".app", with: "")
    }
}
