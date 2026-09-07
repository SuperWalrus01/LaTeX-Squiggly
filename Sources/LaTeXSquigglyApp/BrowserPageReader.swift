import AppKit
import ApplicationServices
import AppSuppression

/// Reads which page a browser is showing, through the Accessibility API.
///
/// This is the only part of the app that looks inside another application, and
/// it exists for one reason: Overleaf is a website, so bundle identifiers alone
/// cannot tell a LaTeX editor from a chat window when both are tabs in Chrome.
///
/// Privacy: the URL is read, compared against the exclusion list, and dropped.
/// Nothing is stored, logged or transmitted, and no attempt is made to read
/// page contents. It uses the Accessibility permission the app already needs in
/// order to type, so there is no additional prompt.
///
/// ## Measured behaviour, not assumed
///
/// Browsers differ, and not in the ways the documentation suggests. What
/// follows was measured on macOS 15.6 against Safari 26 and Chrome 152:
///
/// - **Chrome** answers `AXDocument` on its focused window with the page URL,
///   and exposes an `AXWebArea` as the focused element while you type. It
///   reports `AXWindows` as an empty array, so that attribute is never used.
///   A full read averaged 2.8 ms.
/// - **Safari** does *not* answer `AXDocument` — the widely repeated claim that
///   it does is wrong on this version. Its URL is on an `AXWebArea` six levels
///   down the window, which costs a bounded descent: 12 ms on average and 109
///   ms at worst.
/// - `AXManualAccessibility`, the supposed Chromium opt-in, returns
///   `kAXErrorAttributeUnsupported` on both. It is not set, because it does
///   nothing except in old versions, and neither browser needs it.
///
/// Firefox is expected to reach the title fallback. That is why `ExcludedSite`
/// carries title fragments.
enum BrowserPageReader {

    /// Bounds a single request. Not enough on its own: a descent makes dozens
    /// of requests, so `descentDeadline` bounds the walk as a whole.
    private static let messagingTimeout: Float = 0.05

    /// Wall-clock budget for the tree walk. Safari's typical descent fits in
    /// this several times over; a browser that has stopped answering does not,
    /// and is reported as unreadable rather than waited for.
    private static let descentDeadline: TimeInterval = 0.15

    private static let maximumDescentDepth = 8
    private static let maximumDescentNodes = 200

    /// Ancestors to climb from the focused element. A web area is a handful of
    /// levels above a text field; the limit only stops a pathological tree from
    /// becoming a long walk.
    private static let maximumAncestors = 12

    private static var cachedElements: [pid_t: AXUIElement] = [:]

    /// - Parameter descending: whether the Safari-shaped tree walk is allowed.
    ///   False on the path that runs inside the event tap callback, where the
    ///   measured 109 ms worst case would be felt as a stuck keystroke. That
    ///   path does not need it: the climb below succeeds whenever the user is
    ///   typing into a page, which is the only time it is consulted.
    /// - Returns: nil when the app is not a browser we know, so the caller can
    ///   leave `AppContext.page` nil and skip site rules entirely.
    static func page(for application: NSRunningApplication, descending: Bool = true) -> BrowserPage? {
        guard KnownBrowsers.isBrowser(application.bundleIdentifier) else { return nil }
        guard AXIsProcessTrusted() else { return .unreadable }

        let app = element(for: application.processIdentifier)

        // Cheapest and most accurate: the page the caret is actually in.
        if let focused = child(app, kAXFocusedUIElementAttribute),
           let url = urlByClimbing(from: focused) {
            return .url(url)
        }

        // Chrome answers this; Safari does not.
        guard let window = child(app, kAXFocusedWindowAttribute) else { return .unreadable }

        if let document = value(window, kAXDocumentAttribute) as? String, !document.isEmpty {
            return .url(document)
        }

        // Safari's answer, and the expensive one.
        if descending, let url = urlByDescending(from: window) {
            return .url(url)
        }

        // Every browser titles its window after the page, which is enough to
        // recognise Overleaf even when nothing else can be read.
        if let title = value(window, kAXTitleAttribute) as? String, !title.isEmpty {
            return .title(title)
        }
        return .unreadable
    }

    /// Processes die; their elements should not outlive them in a dictionary.
    static func forget(pid: pid_t) {
        cachedElements[pid] = nil
    }

    // MARK: Tree walking

    private static func urlByClimbing(from start: AXUIElement) -> String? {
        var current = start
        for _ in 0..<maximumAncestors {
            if let url = url(of: current) { return url }
            guard let parent = child(current, kAXParentAttribute) else { return nil }
            current = parent
        }
        return nil
    }

    private static func urlByDescending(from window: AXUIElement) -> String? {
        var visited = 0
        let deadline = Date().addingTimeInterval(descentDeadline)
        return descend(window, depth: 0, visited: &visited, deadline: deadline)
    }

    private static func descend(_ element: AXUIElement,
                                depth: Int,
                                visited: inout Int,
                                deadline: Date) -> String? {
        guard depth < maximumDescentDepth,
              visited < maximumDescentNodes,
              Date() < deadline
        else { return nil }
        visited += 1

        if let url = url(of: element) { return url }
        for child in children(of: element) {
            if let url = descend(child, depth: depth + 1, visited: &visited, deadline: deadline) {
                return url
            }
        }
        return nil
    }

    /// `AXURL` has no symbolic constant in ApplicationServices; the string is
    /// the whole API. It arrives as a CFURL from both engines, but a string is
    /// accepted too rather than depending on that.
    private static func url(of element: AXUIElement) -> String? {
        var raw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, "AXURL" as CFString, &raw) == .success,
              let raw
        else { return nil }

        if let url = raw as? NSURL, let string = url.absoluteString, !string.isEmpty {
            return string
        }
        if let string = raw as? String, !string.isEmpty {
            return string
        }
        return nil
    }

    private static func child(_ element: AXUIElement, _ name: String) -> AXUIElement? {
        var raw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &raw) == .success,
              let raw, CFGetTypeID(raw) == AXUIElementGetTypeID()
        else { return nil }
        return unsafeBitCast(raw, to: AXUIElement.self)
    }

    /// Bridging a CFArray of AXUIElements through `as? [AnyObject]` silently
    /// produces the wrong elements, so the array is read through CoreFoundation.
    private static func children(of element: AXUIElement) -> [AXUIElement] {
        var raw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &raw) == .success,
              let raw, CFGetTypeID(raw) == CFArrayGetTypeID()
        else { return [] }

        let array = unsafeBitCast(raw, to: CFArray.self)
        return (0..<CFArrayGetCount(array)).compactMap { index in
            guard let pointer = CFArrayGetValueAtIndex(array, index) else { return nil }
            let item = unsafeBitCast(pointer, to: CFTypeRef.self)
            guard CFGetTypeID(item) == AXUIElementGetTypeID() else { return nil }
            return unsafeBitCast(item, to: AXUIElement.self)
        }
    }

    private static func value(_ element: AXUIElement, _ name: String) -> Any? {
        var raw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &raw) == .success else {
            return nil
        }
        return raw
    }

    private static func element(for pid: pid_t) -> AXUIElement {
        if let cached = cachedElements[pid] { return cached }
        let element = AXUIElementCreateApplication(pid)
        _ = AXUIElementSetMessagingTimeout(element, messagingTimeout)
        cachedElements[pid] = element
        return element
    }
}
