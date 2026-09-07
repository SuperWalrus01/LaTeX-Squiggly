import AppKit

/// A transient, non-interactive panel for telling the user that a fallback
/// happened or that something was refused.
///
/// Deliberately not a system notification: those need a notification
/// permission, persist in Notification Centre, and are the wrong weight for
/// something that happens mid-sentence. This appears under the menu bar and
/// fades out.
///
/// `.nonactivatingPanel` and `ignoresMouseEvents` matter more than they look —
/// stealing focus from the app the user is typing into would break the very
/// thing we just replaced.
@MainActor
final class NoticePanel {

    private var panel: NSPanel?
    private var dismissTask: DispatchWorkItem?

    private let horizontalPadding: CGFloat = 16
    private let verticalPadding: CGFloat = 12
    private let maximumWidth: CGFloat = 380

    func show(_ message: String, duration: TimeInterval = 4.0) {
        dismissTask?.cancel()

        let label = NSTextField(wrappingLabelWithString: message)
        label.font = .systemFont(ofSize: 12)
        label.textColor = .labelColor
        label.isSelectable = false
        label.preferredMaxLayoutWidth = maximumWidth - horizontalPadding * 2

        let size = label.fittingSize
        let contentRect = NSRect(x: 0, y: 0,
                                 width: min(maximumWidth, size.width + horizontalPadding * 2),
                                 height: size.height + verticalPadding * 2)

        let panel = self.panel ?? makePanel()
        self.panel = panel

        let effect = NSVisualEffectView(frame: contentRect)
        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 10
        effect.layer?.masksToBounds = true

        label.frame = NSRect(x: horizontalPadding, y: verticalPadding,
                             width: contentRect.width - horizontalPadding * 2,
                             height: size.height)
        effect.addSubview(label)
        panel.contentView = effect
        panel.setContentSize(contentRect.size)
        position(panel, size: contentRect.size)

        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            panel.animator().alphaValue = 1
        }

        let task = DispatchWorkItem { [weak self] in self?.dismiss() }
        dismissTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: task)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: .zero,
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered,
                            defer: false)
        panel.level = .statusBar
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        return panel
    }

    /// The screen under the pointer, not `NSScreen.main`.
    ///
    /// `NSScreen.main` is the screen holding the key window, and an accessory
    /// app has no key window while the user is typing in someone else's, so on
    /// two displays the notice could appear on the one nobody was looking at.
    private static func activeScreen() -> NSScreen? {
        let pointer = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(pointer) }
            ?? NSScreen.main
            ?? NSScreen.screens.first
    }

    private func position(_ panel: NSPanel, size: NSSize) {
        guard let screen = Self.activeScreen() else { return }
        let frame = screen.visibleFrame
        panel.setFrameOrigin(NSPoint(x: frame.maxX - size.width - 16,
                                     y: frame.maxY - size.height - 8))
    }

    private func dismiss() {
        guard let panel else { return }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.25
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak panel] in
            panel?.orderOut(nil)
        })
    }
}
