import AppKit
import AppSuppression

/// Answers the one question the event tap asks: may I convert here?
///
/// Two answers, deliberately, because they are used at different moments and
/// have different costs.
///
/// - `cached` is free and is consulted on every keystroke, to decide whether to
///   buffer at all. Being stale costs a missed conversion.
/// - `verified()` re-reads the page and is consulted once, immediately before
///   text is replaced. Being stale here would corrupt a document, so this one
///   pays for a fresh answer.
///
/// Main thread only.
final class SuppressionGate {

    let store: ExclusionStore
    let monitor = FrontmostAppMonitor()

    /// Fires when the answer changes, so the menu can say where it stands.
    var onChange: ((SuppressionDecision) -> Void)?

    private(set) var cached: SuppressionDecision = .convert

    init(store: ExclusionStore) {
        self.store = store
        monitor.onChange = { [weak self] _ in self?.recompute() }
        store.onChange = { [weak self] in self?.recompute() }
    }

    /// Starts tracking which app is frontmost. Safe to call at launch: no
    /// browser page is read until `readsPages` is turned on.
    func start() {
        monitor.start()
        recompute()
    }

    func stop() {
        monitor.stop()
        cached = .convert
    }

    /// Mirrors whether conversion is running. See `FrontmostAppMonitor`.
    var readsPages: Bool {
        get { monitor.readsPages }
        set { monitor.readsPages = newValue }
    }

    /// True when the frontmost app is excluded by a rule the user can see and
    /// undo from the menu, as opposed to by its page.
    var frontmostApplicationIsExcluded: Bool {
        guard let bundleID = monitor.context.bundleID else { return false }
        return store.list.contains(bundleID: bundleID)
    }

    var context: AppContext { monitor.context }

    /// The authoritative answer, with a fresh page read behind it.
    ///
    /// Skips the read entirely when the frontmost app is not a browser: there
    /// is no page to go stale, so the cached bundle identifier is already the
    /// whole truth.
    func verified() -> SuppressionDecision {
        guard monitor.context.page != nil else { return cached }
        let decision = store.list.decision(for: monitor.refresh(descending: false))
        cached = decision
        return decision
    }

    private func recompute() {
        let decision = store.list.decision(for: monitor.context)
        guard decision != cached else { return }
        cached = decision
        onChange?(decision)
    }
}
