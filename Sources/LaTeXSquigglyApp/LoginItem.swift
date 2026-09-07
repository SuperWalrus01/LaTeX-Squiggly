import AppKit
import ServiceManagement

/// Open at login, which macOS 13 reduced to two calls and one awkward case:
/// `SMAppService` registers a *bundle*, and a binary run straight out of
/// `.build` is not one. Rather than throw at the click, the setting reports
/// that it is unavailable and says why.
enum LoginItem {

    /// False under `swift run`, where registering would either throw or, worse,
    /// succeed and record a path that stops existing at the next build.
    static var isAvailable: Bool {
        Bundle.main.bundleURL.pathExtension == "app"
    }

    static var isEnabled: Bool {
        isAvailable && SMAppService.mainApp.status == .enabled
    }

    /// True when macOS has the registration but the user has switched it off in
    /// System Settings. Nothing the app does can override that, so the setting
    /// says so instead of fighting it.
    static var needsApproval: Bool {
        isAvailable && SMAppService.mainApp.status == .requiresApproval
    }

    /// - Returns: nil on success, or a sentence to show the user.
    @discardableResult
    static func setEnabled(_ enabled: Bool) -> String? {
        guard isAvailable else {
            return "Open at login is only available for the installed app, "
                + "not for a build run from the command line."
        }
        do {
            // Registering something already registered throws, and so does
            // unregistering something that never was.
            switch (enabled, SMAppService.mainApp.status) {
            case (true, .enabled), (false, .notRegistered), (false, .notFound):
                return nil
            case (true, _):
                try SMAppService.mainApp.register()
            case (false, _):
                try SMAppService.mainApp.unregister()
            }
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    /// System Settings' Login Items pane, for when approval is what is missing.
    static func openSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension")
        else { return }
        NSWorkspace.shared.open(url)
    }
}
