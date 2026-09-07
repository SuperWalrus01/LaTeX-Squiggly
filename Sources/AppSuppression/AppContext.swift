import Foundation

/// Everything the app knows about wherever the user is currently typing.
///
/// Deliberately a plain value with no system types in it: the decision about
/// whether to suppress is pure, and the messy business of asking macOS what is
/// frontmost lives in the app target where it can be kept out of the event tap
/// callback.
public struct AppContext: Equatable {

    /// `nil` when macOS reports no frontmost application, which happens briefly
    /// during app switches and at login.
    public let bundleID: String?

    /// For display in the menu and in notices. Never used for matching — two
    /// apps can share a display name, and a name changes with the system
    /// language while a bundle identifier does not.
    public let name: String?

    /// `nil` when the frontmost app is not a browser we know how to read.
    public let page: BrowserPage?

    public init(bundleID: String?, name: String? = nil, page: BrowserPage? = nil) {
        self.bundleID = bundleID
        self.name = name
        self.page = page
    }

    /// Whatever we have to call this app in a sentence.
    public var displayName: String {
        name ?? bundleID ?? "this app"
    }
}

/// What a browser is showing, in descending order of how much we can trust it.
///
/// The three cases exist because browsers differ in what they expose through
/// the Accessibility API. Safari and the Chromium family hand over the page
/// URL; Firefox generally does not, leaving only the window title, which is the
/// page title and so still says "Overleaf" on an Overleaf tab.
public enum BrowserPage: Equatable {
    /// The page URL, read from the accessibility tree.
    case url(String)
    /// The URL could not be read; this is the window title instead.
    case title(String)
    /// Neither could be read.
    case unreadable
}
