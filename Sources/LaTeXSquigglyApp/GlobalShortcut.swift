import AppKit
import Carbon.HIToolbox

/// ⌃⌥⌘L from any app: opens the renderer window.
///
/// A Carbon hot key rather than the event tap, because it needs no permission
/// and works while conversion is off: the renderer is useful to people who
/// never grant Accessibility. macOS delivers only this one combination to the
/// app; no other key is seen.
///
/// Three modifiers, because a hot key is taken from every app on the Mac. The
/// extension's Alt+Shift+E is only taken inside Chrome; system-wide, Option
/// and Shift with a letter is how a Mac types characters such as ‰ and ´.
@MainActor
final class GlobalShortcut {

    static let symbols = "\u{2303}\u{2325}\u{2318}L"

    private let action: () -> Void
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?

    init(action: @escaping () -> Void) {
        self.action = action
    }

    /// False when another app already holds the combination.
    @discardableResult
    func register() -> Bool {
        guard hotKey == nil else { return true }
        var pressed = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                    eventKind: UInt32(kEventHotKeyPressed))
        let context = Unmanaged.passUnretained(self).toOpaque()
        let installed = InstallEventHandler(GetApplicationEventTarget(), { _, _, context in
            guard let context else { return OSStatus(eventNotHandledErr) }
            let shortcut = Unmanaged<GlobalShortcut>.fromOpaque(context).takeUnretainedValue()
            Task { @MainActor in shortcut.action() }
            return noErr
        }, 1, &pressed, context, &handler)
        guard installed == noErr else { return false }

        // 'SQLY', and the only hot key the app has.
        let id = EventHotKeyID(signature: OSType(0x5351_4C59), id: 1)
        let status = RegisterEventHotKey(UInt32(kVK_ANSI_L),
                                         UInt32(controlKey | optionKey | cmdKey),
                                         id, GetApplicationEventTarget(), 0, &hotKey)
        return status == noErr
    }
}
