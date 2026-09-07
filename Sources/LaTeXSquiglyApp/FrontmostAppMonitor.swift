import AppKit
import AppSuppression

/// Tracks which application the user is typing into, and which page if that
/// application is a browser.
///
/// Main thread only. The event tap callback runs on the main run loop, so it
/// can read `context` directly; nothing here is safe from another thread.
final class FrontmostAppMonitor {

    /// How often the page is re-read while a browser is frontmost.
    ///
    /// Only the menu depends on this being quick. Correctness comes from
    /// `refresh()`, which the tap calls immediately before it replaces
    /// anything, so a stale cache costs at most a missed conversion — never a
    /// conversion in the wrong place.
    private static let pollInterval: TimeInterval = 1.0

    private(set) var context = AppContext(bundleID: nil)

    /// Whether to look inside browsers.
    ///
    /// Reading a page means reaching into another application's accessibility
    /// tree, so it is done only while conversion is actually running. With this
    /// off every app looks like a non-browser and only bundle identifier rules
    /// apply, which is all the menu needs in order to be honest about an app
    /// that is switched off anyway.
    var readsPages = false {
        didSet {
            guard readsPages != oldValue else { return }
            schedulePolling(forBrowser: KnownBrowsers.isBrowser(context.bundleID))
            refresh()
        }
    }

    /// Fires when the frontmost app or its page changes.
    var onChange: ((AppContext) -> Void)?

    private var application: NSRunningApplication?
    private var pageTimer: Timer?
    private var isRunning = false

    func start() {
        guard !isRunning else { return }
        isRunning = true

        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(self, selector: #selector(applicationActivated(_:)),
                           name: NSWorkspace.didActivateApplicationNotification, object: nil)
        center.addObserver(self, selector: #selector(applicationTerminated(_:)),
                           name: NSWorkspace.didTerminateApplicationNotification, object: nil)

        // The activation notification never fires for the app that is already
        // frontmost when we start, which on a fresh launch is every app the
        // user has.
        adopt(NSWorkspace.shared.frontmostApplication)
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        pageTimer?.invalidate()
        pageTimer = nil
        application = nil
        context = AppContext(bundleID: nil)
    }

    // MARK: Notifications

    @objc private func applicationActivated(_ notification: Notification) {
        let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
            as? NSRunningApplication
        adopt(application)
    }

    @objc private func applicationTerminated(_ notification: Notification) {
        guard let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
            as? NSRunningApplication else { return }
        BrowserPageReader.forget(pid: application.processIdentifier)
    }

    /// Our own windows — the symbol browser, the exclusion editor, the status
    /// menu — make us frontmost. Adopting ourselves would blank the context the
    /// menu is trying to describe, so the last real application is kept.
    private func adopt(_ candidate: NSRunningApplication?) {
        guard let candidate,
              candidate.processIdentifier != NSRunningApplication.current.processIdentifier
        else { return }

        application = candidate
        schedulePolling(forBrowser: KnownBrowsers.isBrowser(candidate.bundleIdentifier))
        refresh()
    }

    private func schedulePolling(forBrowser isBrowser: Bool) {
        pageTimer?.invalidate()
        pageTimer = nil
        guard isBrowser, readsPages else { return }
        pageTimer = Timer.scheduledTimer(withTimeInterval: Self.pollInterval, repeats: true) {
            [weak self] _ in
            self?.refresh()
        }
    }

    // MARK: Reading

    /// Re-reads the context and returns it.
    ///
    /// - Parameter descending: false on the path that runs inside the event tap
    ///   callback, where Safari's tree walk is too slow to be felt as anything
    ///   but a stuck keystroke. See `BrowserPageReader.page(for:descending:)`.
    @discardableResult
    func refresh(descending: Bool = true) -> AppContext {
        guard let application, !application.isTerminated else {
            return update(AppContext(bundleID: nil))
        }
        let page = readsPages
            ? BrowserPageReader.page(for: application, descending: descending)
            : nil
        return update(AppContext(bundleID: application.bundleIdentifier,
                                 name: application.localizedName,
                                 page: page))
    }

    private func update(_ new: AppContext) -> AppContext {
        guard new != context else { return context }
        context = new
        onChange?(new)
        return new
    }
}
