import AppKit
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

    /// Called with an explanation the user needs to see.
    var onNotice: ((String) -> Void)?
    /// Called when macOS disabled the tap under us, usually a revoked permission.
    var onTapDisabled: (() -> Void)?

    private(set) var isRunning = false

    // MARK: Lifecycle

    @discardableResult
    func start() -> Bool {
        guard !isRunning else { return true }

        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
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
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    /// Switching apps moves the cursor somewhere we know nothing about.
    private func observeApplicationSwitches() {
        NSWorkspace.shared.notificationCenter.addObserver(
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

        guard type == .keyDown else { return passthrough }

        // Our own synthetic keystrokes come back around; ignore them or the
        // replacement feeds itself.
        if event.getIntegerValueField(.eventSourceUserData) == TextReplacer.syntheticMarker {
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
            buffer.deleteBackward()
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
        switch TriggerDetector.outcome(buffer: buffer.text, terminator: character) {
        case .none:
            buffer.insert(String(character))
            return passthrough

        case .replace(let replacement):
            buffer.reset()
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
