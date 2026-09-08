import AppKit
import AppSuppression
import Carbon.HIToolbox
import InputTracking

/// Owns the CGEventTap and the rolling input buffer.
///
/// Threading: the tap source is attached to the main run loop, so `handle` runs
/// on the main thread and the buffer is only ever touched there. The
/// replacement is posted synchronously from inside the callback — see the note
/// on `handle` for why that is deliberate rather than lazy.
final class EventTapController {

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var buffer = InputBuffer()
    /// The block-based observer API hands back a token, and that token is the
    /// only thing `removeObserver` will accept. Passing `self` instead removed
    /// nothing, so every stop/start cycle left another observer behind.
    private var activationObserver: NSObjectProtocol?

    /// Called with an explanation the user needs to see.
    var onNotice: ((String) -> Void)?
    /// Called when macOS disabled the tap under us, usually a revoked permission.
    var onTapDisabled: (() -> Void)?

    /// Decides whether conversion is allowed wherever the user is typing.
    /// Nil only in tests and in the diagnostics path, where it means "allowed".
    var suppression: SuppressionGate?

    private(set) var isRunning = false

    // MARK: Lifecycle

    @discardableResult
    func start() -> Bool {
        guard !isRunning else { return true }

        // Mouse-down is watched purely to forget: see `handle`. Only the down
        // events, never movement, which is a firehose and moves no caret.
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
            | CGEventMask(1 << CGEventType.leftMouseDown.rawValue)
            | CGEventMask(1 << CGEventType.rightMouseDown.rawValue)
            | CGEventMask(1 << CGEventType.otherMouseDown.rawValue)
        // .defaultTap rather than .listenOnly: completing a trigger has to
        // suppress the terminator keystroke, which a listen-only tap cannot do.
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: eventTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            // Almost always a missing permission rather than a real failure.
            return false
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        self.tap = tap
        self.runLoopSource = source
        self.isRunning = true
        buffer.reset()

        observeApplicationSwitches()
        return true
    }

    func stop() {
        guard isRunning else { return }
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        tap = nil
        runLoopSource = nil
        isRunning = false
        buffer.reset()
        if let activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
        }
        activationObserver = nil
    }

    /// Switching apps moves the cursor somewhere we know nothing about.
    /// The buffer describes text in front of a cursor that has since moved, or
    /// text in a place we are no longer allowed to touch.
    func resetBuffer() {
        buffer.reset()
    }

    private func observeApplicationSwitches() {
        guard activationObserver == nil else { return }
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            self?.buffer.reset()
        }
    }

    // MARK: The callback

    /// - Note: The replacement is posted synchronously rather than dispatched.
    ///   Dispatching leaves a window in which the next keystroke reaches the
    ///   app before our backspaces do, and the delete count then eats a
    ///   character the user meant to keep. Posting a handful of events takes
    ///   microseconds, comfortably inside the tap's timeout.
    fileprivate func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        let passthrough = Unmanaged.passUnretained(event)

        // macOS disables a tap whose callback overran, and when the user
        // revokes permission. Neither should kill the app silently.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            buffer.reset()
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            onTapDisabled?()
            return nil
        }

        // A click puts the caret somewhere the buffer knows nothing about, so
        // the buffer stops describing the text in front of it. Without this,
        // typing `\alpha`, clicking elsewhere and pressing space fired six
        // backspaces at the new position and ate the user's text.
        switch type {
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            buffer.reset()
            return passthrough
        default:
            break
        }

        guard type == .keyDown else { return passthrough }

        // Our own synthetic keystrokes come back around; ignore them or the
        // replacement feeds itself.
        if event.getIntegerValueField(.eventSourceUserData) == TextReplacer.syntheticMarker {
            return passthrough
        }

        // Per-app suppression, checked before anything is remembered: in an
        // excluded app no buffer accumulates, so a replacement there is not
        // declined late, it is structurally impossible. The cached answer is
        // used because this runs on every keystroke; the fresh one is taken
        // below, once, on the path that actually types.
        if suppression?.cached.isSuppressed == true {
            if !buffer.isEmpty { buffer.reset() }
            return passthrough
        }

        // Command and control chords are shortcuts, not text.
        if event.flags.contains(.maskCommand) || event.flags.contains(.maskControl) {
            buffer.reset()
            return passthrough
        }

        // Tab is deliberately absent: it produces U+0009 and is handled below
        // as a terminator, not as navigation.
        switch Int(event.getIntegerValueField(.keyboardEventKeycode)) {
        case kVK_Delete:
            // Option-backspace deletes a whole word, and Command-backspace the
            // whole line, which the buffer has no way to model. The Command
            // case is already gone by here; this is the Option one. Forgetting
            // is the only honest answer, because guessing one character leaves
            // the delete count larger than the text actually in front of it.
            if event.flags.contains(.maskAlternate) {
                buffer.reset()
            } else {
                buffer.deleteBackward()
            }
            return passthrough
        case kVK_ForwardDelete:
            // Deletes ahead of the cursor, which the buffer does not model.
            buffer.reset()
            return passthrough
        case kVK_Return, kVK_ANSI_KeypadEnter, kVK_Escape,
             kVK_LeftArrow, kVK_RightArrow, kVK_UpArrow, kVK_DownArrow,
             kVK_Home, kVK_End, kVK_PageUp, kVK_PageDown:
            buffer.reset()
            return passthrough
        default:
            break
        }

        guard let typed = event.typedString(), !typed.isEmpty else {
            // Dead keys and input methods produce keystrokes we cannot model.
            // Forgetting is the safe response.
            buffer.reset()
            return passthrough
        }

        if typed.count == 1,
           let character = typed.first,
           TriggerDetector.terminators.contains(character) {
            return handleTerminator(character, passthrough: passthrough)
        }

        buffer.insert(typed)
        return passthrough
    }

    private func handleTerminator(_ character: Character,
                                  passthrough: Unmanaged<CGEvent>) -> Unmanaged<CGEvent>? {
        // Options are read here, not captured at start: `handle` runs on the
        // main thread, so this is the same read the settings window writes, and
        // a switch flipped between two commands applies to the second one.
        switch TriggerDetector.outcome(buffer: buffer.text,
                                       terminator: character,
                                       options: Preferences.conversionOptions) {
        case .none:
            buffer.insert(String(character))
            return passthrough

        case .replace(let replacement):
            buffer.reset()

            // A browser tab can change without the frontmost application
            // changing, so the cached answer above may describe the page the
            // user was on a moment ago. This is the last instant at which
            // asking again is still free of consequences.
            if let decision = suppression?.verified(), let reason = decision.reason {
                DispatchQueue.main.async { [weak self] in
                    self?.onNotice?("Left as you typed it \u{2014} \(reason.explanation).")
                }
                return passthrough
            }

            TextReplacer.perform(replacement)
            if let notice = replacement.notice {
                // UI work must not run inside the callback.
                DispatchQueue.main.async { [weak self] in self?.onNotice?(notice) }
            }
            // Suppress the terminator: `replacement.insert` types it back, so
            // letting the original through would double it.
            return nil

        case .refuse(_, let reason):
            buffer.reset()
            DispatchQueue.main.async { [weak self] in self?.onNotice?(reason) }
            // The user's text is left exactly as they typed it.
            return passthrough
        }
    }
}

/// Must be a C function pointer, so context arrives through `refcon`.
private func eventTapCallback(proxy: CGEventTapProxy,
                              type: CGEventType,
                              event: CGEvent,
                              refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    return Unmanaged<EventTapController>.fromOpaque(refcon)
        .takeUnretainedValue()
        .handle(type: type, event: event)
}

private extension CGEvent {
    /// The text this keystroke produces under the current keyboard layout.
    func typedString() -> String? {
        var length = 0
        var buffer = [UniChar](repeating: 0, count: 8)
        keyboardGetUnicodeString(maxStringLength: 8,
                                 actualStringLength: &length,
                                 unicodeString: &buffer)
        guard length > 0 else { return nil }
        return String(utf16CodeUnits: buffer, count: length)
    }
}
