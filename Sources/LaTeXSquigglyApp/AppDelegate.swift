import AppKit
import AppSuppression
import InputTracking

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let tap = EventTapController()
    private let notices = NoticePanel()
    private let browser = SymbolBrowser()
    private let exclusions = ExclusionStore()
    private lazy var gate = SuppressionGate(store: exclusions)
    private lazy var settings = SettingsWindow(store: exclusions)

    private var permissions = PermissionState()
    private var permissionTimer: Timer?

    private var isEnabled: Bool {
        get { Preferences.conversionEnabled }
        set { Preferences.conversionEnabled = newValue }
    }

    // MARK: Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        Preferences.registerDefaults()
        settings.host = self

        // Read at the moment of the notice, not captured: the switch can be
        // flipped in the settings window between one conversion and the next.
        tap.onNotice = { [weak self] message in
            guard Preferences.showNotices else { return }
            self?.notices.show(message)
        }
        tap.onTapDisabled = { [weak self] in self?.handleTapDisabled() }
        tap.suppression = gate

        // A change of app or of tab means the buffer describes text somewhere
        // we can no longer see, and may describe text we are no longer allowed
        // to touch.
        // Rebuilding the menu is deferred: this fires from inside the event
        // tap callback on the path that re-reads the page before typing, and
        // AppKit work there is exactly what disables a tap.
        gate.onChange = { [weak self] _ in
            self?.tap.resetBuffer()
            DispatchQueue.main.async { self?.rebuildMenu() }
        }

        // Picks up a TeX editor installed since the last launch. Anything the
        // user has deleted from the list stays deleted.
        exclusions.discoverInstalledApplications()
        gate.start()

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
        if Preferences.isFirstRun { showWelcome() }

        // `--symbols` opens the browser straight away, which makes it
        // scriptable and gives the UI a smoke test that does not need a human
        // to click a menu bar icon.
        if CommandLine.arguments.contains("--symbols") { browser.show() }
        if CommandLine.arguments.contains("--settings") { settings.show() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        permissionTimer?.invalidate()
        tap.stop()
        gate.stop()
    }

    private func showWelcome() {
        // Recording the preference is what makes this the *first* run only.
        isEnabled = true

        let excluded = exclusions.list.apps.count

        let alert = NSAlert()
        alert.messageText = "LaTeX Squiggly is running in your menu bar"
        alert.informativeText =
            "Look for the LaTeX Squiggly mark near the clock, at the top right of "
            + "your screen.\n\n"
            + "It stays out of the way where LaTeX source is written: "
            + "\(excluded) app\(excluded == 1 ? "" : "s") on this Mac "
            + "\(excluded == 1 ? "is" : "are") already excluded, and so is Overleaf in any "
            + "browser. Add your own in Settings, or exclude whatever is in front of "
            + "you straight from the menu.\n\n"
            + "Two macOS permissions are needed before it can type for you. "
            + "Nothing you type is stored or sent anywhere."
        alert.addButton(withTitle: "Set Up Now")
        alert.addButton(withTitle: "Later")
        alert.alertStyle = .informational

        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            startTapIfPermitted()
        } else {
            isEnabled = false
            rebuildMenu()
        }
    }

    // MARK: Permissions

    private func refreshPermissions() {
        let latest = Permissions.current()
        guard latest != permissions else { return }
        permissions = latest

        if isEnabled, !latest.allGranted, tap.isRunning {
            stopConverting()
            notices.show("Conversion stopped: \(latest.missing.map(\.title).joined(separator: " and ")) permission was turned off.")
        } else if isEnabled, latest.allGranted, !tap.isRunning {
            startTapIfPermitted()
        }
        rebuildMenu()
        settings.refresh()
    }

    private func handleTapDisabled() {
        // Re-enabling already happened in the callback; this only refreshes
        // what the menu claims.
        refreshPermissions()
    }

    // MARK: Enable / disable

    @objc private func toggleEnabled() {
        setConversionEnabled(!isEnabled)
    }

    private func startTapIfPermitted() {
        permissions = Permissions.current()
        guard permissions.allGranted else {
            promptForMissingPermissions()
            return
        }
        if tap.start() {
            // Browser pages are only read while conversion is actually
            // running: see FrontmostAppMonitor.readsPages.
            gate.readsPages = true
        } else {
            notices.show("Could not start the keyboard listener. Check Accessibility and Input Monitoring in System Settings.")
        }
        rebuildMenu()
    }

    private func stopConverting() {
        tap.stop()
        gate.readsPages = false
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

    /// The height the mark draws at. The artwork is taller than it is wide, so
    /// this is the dimension worth pinning: 18 pt is the usual ceiling for a
    /// status item inside a 24 pt menu bar.
    private static let markHeight: CGFloat = 18

    /// The mark, sized for the menu bar. Loaded fresh each time because the
    /// inactive state draws into it, and a shared NSImage would accumulate.
    private func statusMark() -> NSImage? {
        guard let mark = NSImage(data: MenuBarIconData.png), mark.size.height > 0 else { return nil }
        let aspect = mark.size.width / mark.size.height
        mark.size = NSSize(width: (Self.markHeight * aspect).rounded(),
                           height: Self.markHeight)
        // Template rendering is what lets one file sit on a light menu bar, a
        // dark one and a highlighted status item: macOS keeps the alpha and
        // supplies the colour. The mark's orange survives in the app icon,
        // where the background is ours to choose.
        mark.isTemplate = true
        return mark
    }

    /// There is no struck-through mark to switch to, so the inactive state is
    /// composited. Dimming alone was worse: a faded mark in the menu bar is
    /// invisible, which makes "off" indistinguishable from "crashed".
    ///
    /// Two states, not three. The icon answers "is it converting right now",
    /// which is the same answer whether the app is switched off or merely
    /// staying quiet in Cursor; the menu answers "why not". A third glyph that
    /// meant "off, but for a different reason" would be read as neither.
    private func statusImage(active: Bool) -> NSImage? {
        guard let mark = statusMark() else { return nil }
        guard !active else { return mark }

        let composed = NSImage(size: mark.size, flipped: false) { rect in
            mark.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 0.5)

            let slash = NSBezierPath()
            slash.move(to: NSPoint(x: rect.minX + 1, y: rect.minY + 1))
            slash.line(to: NSPoint(x: rect.maxX - 1, y: rect.maxY - 1))
            slash.lineCapStyle = .round

            // The gap comes first. A bar laid straight onto a solid mark at
            // 18 pt merges into it and reads as a thicker letter, not as a
            // strike; clearing a little space around the bar is what makes the
            // two shapes separate at that size.
            if let cg = NSGraphicsContext.current?.cgContext {
                cg.saveGState()
                cg.setBlendMode(.clear)
                slash.lineWidth = 3.5
                slash.stroke()
                cg.restoreGState()
            }

            slash.lineWidth = 1.6
            NSColor.black.setStroke()
            slash.stroke()
            return true
        }
        composed.isTemplate = true
        return composed
    }

    private func rebuildMenu() {
        let suppression = gate.cached
        let converting = tap.isRunning && !suppression.isSuppressed

        statusItem.button?.image = statusImage(active: converting)

        let menu = NSMenu()

        let statusTitle: String
        if !isEnabled {
            statusTitle = "Off"
        } else if !tap.isRunning {
            statusTitle = "Paused \u{2014} permission needed"
        } else if let reason = suppression.reason {
            statusTitle = reason.summary
        } else {
            statusTitle = "Converting as you type"
        }
        statusItem.button?.toolTip = "LaTeX Squiggly \u{2014} " + statusTitle.lowercased()

        let status = NSMenuItem(title: statusTitle, action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)

        // Staying quiet looks exactly like being broken unless the app says
        // which rule it is obeying.
        if tap.isRunning, let reason = suppression.reason {
            let detail = NSMenuItem(title: reason.explanation, action: nil, keyEquivalent: "")
            detail.isEnabled = false
            menu.addItem(detail)
        }

        menu.addItem(.separator())

        let toggle = NSMenuItem(title: "Enable conversion",
                                action: #selector(toggleEnabled),
                                keyEquivalent: "")
        toggle.target = self
        toggle.state = isEnabled ? .on : .off
        menu.addItem(toggle)

        for permission in Permission.allCases where !permissions.isGranted(permission) {
            let item = NSMenuItem(title: "Grant \(permission.title)\u{2026}",
                                  action: #selector(grantPermission(_:)),
                                  keyEquivalent: "")
            item.target = self
            item.representedObject = permission
            menu.addItem(item)
        }

        // One click to fix a miss. A default list cannot know about every TeX
        // editor, and the moment the user notices is the moment they are
        // looking at the wrong app. This is the only exclusion the menu carries:
        // it is the one that needs the app in front of you to mean anything.
        //
        // The list itself lives in Settings and nowhere else. Where the app
        // stays quiet is a setting, and a second front door to the same editor
        // only made "what is this configured to do" a question with two places
        // to look.
        if gate.context.bundleID != nil {
            menu.addItem(.separator())
            let name = gate.context.displayName
            let item = NSMenuItem(title: "Do not convert in \(name)",
                                  action: #selector(toggleFrontmostApplication),
                                  keyEquivalent: "")
            item.target = self
            item.state = gate.frontmostApplicationIsExcluded ? .on : .off
            menu.addItem(item)
        }

        menu.addItem(.separator())

        // The comma is what people reach for, so it is bound here even though a
        // status menu only sees it while it is open.
        let settingsItem = NSMenuItem(title: "Settings\u{2026}",
                                      action: #selector(showSettings),
                                      keyEquivalent: ",")
        settingsItem.keyEquivalentModifierMask = .command
        settingsItem.target = self
        menu.addItem(settingsItem)

        let symbols = NSMenuItem(title: "Symbols\u{2026}",
                                 action: #selector(showBrowser),
                                 keyEquivalent: "")
        symbols.target = self
        menu.addItem(symbols)

        menu.addItem(.separator())

        menu.addItem(NSMenuItem(title: "Quit LaTeX Squiggly",
                                action: #selector(NSApplication.terminate(_:)),
                                keyEquivalent: ""))

        statusItem.menu = menu
    }

    /// The frontmost app is whatever was in front before the menu opened:
    /// `FrontmostAppMonitor` ignores our own activation for exactly this.
    @objc private func toggleFrontmostApplication() {
        guard let bundleID = gate.context.bundleID else { return }
        if gate.frontmostApplicationIsExcluded {
            exclusions.removeApp(bundleID: bundleID)
        } else {
            exclusions.exclude(bundleID: bundleID, name: gate.context.displayName)
        }
        tap.resetBuffer()
        rebuildMenu()
    }

    @objc private func showSettings() {
        settings.show(.general)
    }

    @objc private func grantPermission(_ sender: NSMenuItem) {
        guard let permission = sender.representedObject as? Permission else { return }
        openPermissionSettings(permission)
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
        appMenu.addItem(withTitle: "Settings\u{2026}",
                        action: #selector(showSettings), keyEquivalent: ",").target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit LaTeX Squiggly",
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

// MARK: - SettingsHost

/// The settings window reads the app's state through this instead of keeping a
/// copy, which is what stops the menu and the window from disagreeing about
/// whether conversion is on.
extension AppDelegate: SettingsHost {

    var conversionEnabled: Bool { isEnabled }

    var permissionState: PermissionState { permissions }

    func setConversionEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }
        isEnabled = enabled
        if enabled {
            startTapIfPermitted()
        } else {
            stopConverting()
        }
        rebuildMenu()
        settings.refresh()
    }

    func openPermissionSettings(_ permission: Permission) {
        Permissions.request(permission)
        Permissions.openSettings(permission)
    }
}
