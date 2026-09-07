import AppKit
import ApplicationServices
import IOKit.hid

/// The two permissions the event tap needs, and the difference matters:
/// Input Monitoring lets us observe keystrokes, Accessibility lets us post
/// synthetic ones. Having only the first gives an app that watches you type
/// and can do nothing about it.
enum Permission: CaseIterable {
    case accessibility
    case inputMonitoring

    var title: String {
        switch self {
        case .accessibility:   return "Accessibility"
        case .inputMonitoring: return "Input Monitoring"
        }
    }

    var why: String {
        switch self {
        case .accessibility:   return "to replace the text you typed"
        case .inputMonitoring: return "to notice when you type a command"
        }
    }

    /// System Settings deep link. The pane identifier is still the old
    /// `com.apple.preference.security` one even on Ventura and later.
    var settingsURL: URL? {
        let anchor: String
        switch self {
        case .accessibility:   anchor = "Privacy_Accessibility"
        case .inputMonitoring: anchor = "Privacy_ListenEvent"
        }
        return URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)")
    }
}

struct PermissionState: Equatable {
    var accessibility = false
    var inputMonitoring = false

    var allGranted: Bool { accessibility && inputMonitoring }

    var missing: [Permission] {
        var result: [Permission] = []
        if !accessibility { result.append(.accessibility) }
        if !inputMonitoring { result.append(.inputMonitoring) }
        return result
    }

    func isGranted(_ permission: Permission) -> Bool {
        switch permission {
        case .accessibility:   return accessibility
        case .inputMonitoring: return inputMonitoring
        }
    }
}

enum Permissions {

    static func current() -> PermissionState {
        PermissionState(
            accessibility: AXIsProcessTrusted(),
            inputMonitoring: IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
        )
    }

    /// Shows the system's own prompt. macOS only shows it once per app; after
    /// that the call is a no-op and the user has to go to Settings, which is
    /// why `openSettings` exists alongside it.
    static func request(_ permission: Permission) {
        switch permission {
        case .accessibility:
            let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
            _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
        case .inputMonitoring:
            _ = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
        }
    }

    static func openSettings(_ permission: Permission) {
        guard let url = permission.settingsURL else { return }
        NSWorkspace.shared.open(url)
    }
}
