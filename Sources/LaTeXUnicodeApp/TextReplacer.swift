import AppKit
import Carbon.HIToolbox
import InputTracking

/// Turns a `Replacement` into synthetic keystrokes.
///
/// Insertion goes through `keyboardSetUnicodeString`, never the clipboard:
/// clipboard swapping destroys whatever the user had copied and races against
/// anything else reading the pasteboard.
enum TextReplacer {

    /// Stamped on every event we post so the tap can recognise its own output
    /// and not treat it as typing.
    static let syntheticMarker: Int64 = 0x4C54_5855   // "LTXU"

    /// Apps that batch synthetic input — Electron ones especially — can drop
    /// events delivered with no gap at all. A microsecond-scale pause costs
    /// nothing perceptible and is far below the event tap's timeout.
    static let interEventDelay: useconds_t = 900

    static func perform(_ replacement: Replacement) {
        guard let source = CGEventSource(stateID: .privateState) else { return }
        source.userData = syntheticMarker

        for _ in 0..<replacement.deleteCount {
            postKey(CGKeyCode(kVK_Delete), source: source)
            usleep(interEventDelay)
        }

        guard !replacement.insert.isEmpty else { return }
        postText(replacement.insert, source: source)
    }

    private static func postKey(_ key: CGKeyCode, source: CGEventSource) {
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false)
        else { return }
        // Whatever the user is physically holding must not leak into our
        // synthetic events, or a held shift turns backspace into something else.
        down.flags = []
        up.flags = []
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }

    private static func postText(_ text: String, source: CGEventSource) {
        var utf16 = Array(text.utf16)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
        else { return }
        down.flags = []
        up.flags = []
        down.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: &utf16)
        up.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: &utf16)
        down.post(tap: .cghidEventTap)
        usleep(interEventDelay)
        up.post(tap: .cghidEventTap)
    }
}
