import AppKit

/// What the settings window needs from the app, and the only way it is allowed
/// to reach back into it.
///
/// State is read through this rather than copied into the window, so the two
/// surfaces that show the same switch — the menu and the settings — cannot
/// disagree: both ask the same object at the moment they draw.
@MainActor
protocol SettingsHost: AnyObject {
    var conversionEnabled: Bool { get }
    var permissionState: PermissionState { get }
    func setConversionEnabled(_ enabled: Bool)
    func openPermissionSettings(_ permission: Permission)
}

/// The settings window: a toolbar of panes, in the shape macOS has used for
/// preferences since long before System Settings.
///
/// `NSTabViewController` in `.toolbar` mode supplies the toolbar, the selection
/// and the resize between panes, which is why there is no toolbar code here.
/// The window is deliberately not resizable — settings windows are sized by
/// their contents, and a resizable one only ever ends up the wrong shape.
@MainActor
final class SettingsWindow: NSObject, NSWindowDelegate {

    enum Pane: Int, CaseIterable {
        case general
        case exclusions

        var title: String {
            switch self {
            case .general:    return "General"
            case .exclusions: return "Exclusions"
            }
        }

        /// The toolbar icon. Both are template symbols, so they follow the
        /// window's appearance the same way the menu bar mark follows the bar's.
        var symbolName: String {
            switch self {
            case .general:    return "gearshape"
            case .exclusions: return "nosign"
            }
        }
    }

    weak var host: SettingsHost? {
        didSet { general.host = host }
    }

    private let general = GeneralPane()
    private let exclusions: ExclusionsPane
    private var window: NSWindow?

    init(store: ExclusionStore) {
        self.exclusions = ExclusionsPane(store: store)
        super.init()
    }

    func show(_ pane: Pane = .general) {
        let window = self.window ?? makeWindow()
        self.window = window

        (window.contentViewController as? NSTabViewController)?.selectedTabViewItemIndex = pane.rawValue

        // An accessory app is never frontmost on its own, so a window ordered
        // front without this opens behind whatever the user was typing in.
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        refresh()
    }

    /// Called when the app's state changes under the window — a permission
    /// granted in System Settings, conversion toggled from the menu — so the
    /// pane does not have to be reopened to be right.
    ///
    /// Does nothing when the window is closed: a hidden pane is re-read by
    /// `viewWillAppear` before it is next seen.
    func refresh() {
        guard window?.isVisible == true else { return }
        general.refresh()
    }

    // MARK: Construction

    private func makeWindow() -> NSWindow {
        general.host = host
        general.title = Pane.general.title
        exclusions.title = Pane.exclusions.title

        let tabs = PaneController()
        tabs.tabStyle = .toolbar
        for (pane, controller) in zip(Pane.allCases, [general as NSViewController, exclusions]) {
            let item = NSTabViewItem(viewController: controller)
            item.label = pane.title
            item.image = NSImage(systemSymbolName: pane.symbolName,
                                 accessibilityDescription: pane.title)
            tabs.addTabViewItem(item)
        }

        let window = NSWindow(contentViewController: tabs)
        window.styleMask = [.titled, .closable]
        window.toolbarStyle = .preference
        window.delegate = self
        window.isReleasedWhenClosed = false
        window.center()
        return window
    }

    func windowWillClose(_ notification: Notification) {
        // Kept rather than dropped: rebuilding it loses the selected pane and
        // the scroll position in a list the user was halfway through editing.
        window?.orderOut(nil)
    }
}

/// Only here to keep the window title in step with the toolbar, which
/// `NSTabViewController` does not do on its own.
@MainActor
private final class PaneController: NSTabViewController {
    override func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) {
        super.tabView(tabView, didSelect: tabViewItem)
        view.window?.title = tabViewItem?.label ?? "Settings"
    }
}
