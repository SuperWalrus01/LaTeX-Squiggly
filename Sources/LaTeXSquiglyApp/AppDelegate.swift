import AppKit
import InputTracking

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    /// Off on first launch, deliberately. There is no per-app suppression, so
    /// an always-on replacement rewrites LaTeX source as you type it. The
    /// choice to enable it is the user's.
    private static let enabledKey = "conversionEnabled"

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let tap = EventTapController()
    private let notices = NoticePanel()
    private let browser = SymbolBrowser()

    private var permissions = PermissionState()
    private var permissionTimer: Timer?

    private var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: Self.enabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.enabledKey) }
    }

    // MARK: Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        tap.onNotice = { [weak self] message in self?.notices.show(message) }
        tap.onTapDisabled = { [weak self] in self?.handleTapDisabled() }

        installMainMenu()
        permissions = Permissions.current()

        // Permission can be revoked while we run, and the only reliable signal
        // is to keep asking.
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshPermissions() }
        }

        if isEnabled { startTapIfPermitted() }
        rebuildMenu()

        // A menu bar app that starts switched off looks identical to one that
        // failed to launch. Say what happened and where to find it.
        if isFirstRun { showWelcome() }

        // `--symbols` opens the browser straight away, which makes it
        // scriptable and gives the UI a smoke test that does not need a human
        // to click a menu bar icon.
        if CommandLine.arguments.contains("--symbols") { browser.show() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        permissionTimer?.invalidate()
        tap.stop()
    }

    private var isFirstRun: Bool {
        UserDefaults.standard.object(forKey: Self.enabledKey) == nil
    }

    private func showWelcome() {
        // Recording the preference is what makes this the *first* run only.
        isEnabled = false

        let alert = NSAlert()
        alert.messageText = "LaTeX-Squigly is running in your menu bar"
        alert.informativeText =
            "Look for the \u{0192} icon near the clock, at the top right of your screen.\n\n"
            + "Conversion is switched OFF right now. It needs two macOS permissions "
            + "before it can work, and there is no per-app exclusion list \u{2014} so turn it "
            + "off before writing .tex files or using Overleaf, or it will convert your "
            + "source as you type it.\n\nNothing you type is stored or sent anywhere."
        alert.addButton(withTitle: "Set Up Now")
        alert.addButton(withTitle: "Later")
        alert.alertStyle = .informational

        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            isEnabled = true
            startTapIfPermitted()
            rebuildMenu()
        }
    }

    // MARK: Permissions

    private func refreshPermissions() {
        let latest = Permissions.current()
        guard latest != permissions else { return }
        permissions = latest

        if isEnabled, !latest.allGranted, tap.isRunning {
            tap.stop()
            notices.show("Conversion stopped: \(latest.missing.map(\.title).joined(separator: " and ")) permission was turned off.")
        } else if isEnabled, latest.allGranted, !tap.isRunning {
            startTapIfPermitted()
        }
        rebuildMenu()
    }

    private func handleTapDisabled() {
        // Re-enabling already happened in the callback; this only refreshes
        // what the menu claims.
        refreshPermissions()
    }

    // MARK: Enable / disable

    @objc private func toggleEnabled() {
        isEnabled.toggle()
        if isEnabled {
            startTapIfPermitted()
        } else {
            tap.stop()
        }
        rebuildMenu()
    }

    private func startTapIfPermitted() {
        permissions = Permissions.current()
        guard permissions.allGranted else {
            promptForMissingPermissions()
            return
        }
        if !tap.start() {
            notices.show("Could not start the keyboard listener. Check Accessibility and Input Monitoring in System Settings.")
        }
        rebuildMenu()
    }

    private func promptForMissingPermissions() {
        let missing = permissions.missing
        guard let first = missing.first else { return }

        let alert = NSAlert()
        alert.messageText = "\(missing.map(\.title).joined(separator: " and ")) needed"
        alert.informativeText = missing
            .map { "\u{2022} \($0.title) \u{2014} \($0.why)." }
            .joined(separator: "\n")
            + "\n\nNothing you type is stored or sent anywhere. The app keeps a short in-memory buffer and discards it as soon as a command completes."
        alert.addButton(withTitle: "Open \(first.title) Settings")
        alert.addButton(withTitle: "Later")
        alert.alertStyle = .informational

        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            Permissions.request(first)
            Permissions.openSettings(first)
        }
    }

    // MARK: Status item

    /// SF Symbols has no `function.slash`, so the off state is composited.
    /// Dimming the icon instead was worse: a faded \u{0192} in the menu bar is
    /// invisible, which makes "off" indistinguishable from "crashed".
    private func statusImage(active: Bool) -> NSImage? {
        let configuration = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        guard let symbol = NSImage(systemSymbolName: "function",
                                   accessibilityDescription: "LaTeX-Squigly")?
            .withSymbolConfiguration(configuration)
        else { return nil }

        guard !active else {
            symbol.isTemplate = true
            return symbol
        }

        let composed = NSImage(size: symbol.size, flipped: false) { rect in
            symbol.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 0.55)
            let slash = NSBezierPath()
            slash.move(to: NSPoint(x: rect.minX + 1.5, y: rect.minY + 1.5))
            slash.line(to: NSPoint(x: rect.maxX - 1.5, y: rect.maxY - 1.5))
            slash.lineWidth = 1.5
            NSColor.black.setStroke()
            slash.stroke()
            return true
        }
        composed.isTemplate = true
        return composed
    }

    private func rebuildMenu() {
        let running = tap.isRunning
        statusItem.button?.image = statusImage(active: running)
        statusItem.button?.toolTip = running
            ? "LaTeX-Squigly \u{2014} converting as you type"
            : "LaTeX-Squigly \u{2014} off"

        let menu = NSMenu()

        let status = NSMenuItem(
            title: running ? "Converting as you type" : (isEnabled ? "Paused \u{2014} permission needed" : "Off"),
            action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)
        menu.addItem(.separator())

        let toggle = NSMenuItem(title: "Enable conversion",
                                action: #selector(toggleEnabled),
                                keyEquivalent: "")
        toggle.target = self
        toggle.state = isEnabled ? .on : .off
        menu.addItem(toggle)

        for permission in Permission.allCases where !permissions.isGranted(permission) {
            let item = NSMenuItem(title: "Grant \(permission.title)\u{2026}",
                                  action: #selector(openPermissionSettings(_:)),
                                  keyEquivalent: "")
            item.target = self
            item.representedObject = permission
            menu.addItem(item)
        }

        menu.addItem(.separator())

        let symbols = NSMenuItem(title: "Symbols\u{2026}",
                                 action: #selector(showBrowser),
                                 keyEquivalent: "")
        symbols.target = self
        menu.addItem(symbols)

        menu.addItem(.separator())

        // No per-app suppression exists. A tester who does not know that will
        // find out by corrupting a document, so say it where they will look.
        let warning = NSMenuItem(title: "Turn off before writing .tex or Overleaf",
                                 action: nil, keyEquivalent: "")
        warning.isEnabled = false
        menu.addItem(warning)
        menu.addItem(.separator())

        menu.addItem(NSMenuItem(title: "Quit LaTeX-Squigly",
                                action: #selector(NSApplication.terminate(_:)),
                                keyEquivalent: ""))

        statusItem.menu = menu
    }

    @objc private func openPermissionSettings(_ sender: NSMenuItem) {
        guard let permission = sender.representedObject as? Permission else { return }
        Permissions.request(permission)
        Permissions.openSettings(permission)
    }

    @objc private func showBrowser() {
        browser.show()
    }

    /// An accessory app has no menu bar of its own, which leaves the symbol
    /// browser's search field without ⌘C, ⌘V or ⌘W. This is the minimum that
    /// makes a window behave like a window.
    private func installMainMenu() {
        let mainMenu = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit LaTeX-Squigly",
                        action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        mainMenu.addItem(appItem)

        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu
        mainMenu.addItem(editItem)

        let windowItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowItem.submenu = windowMenu
        mainMenu.addItem(windowItem)

        NSApp.mainMenu = mainMenu
    }
}
