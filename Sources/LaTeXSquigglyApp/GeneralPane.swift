import AppKit

/// What the settings window shows first: the four switches, and the two
/// permissions everything else depends on.
///
/// The permissions are here rather than only in the menu because the menu can
/// only offer them while they are missing — it has nowhere to say "granted",
/// and an app that reads your keystrokes should be able to show you exactly
/// what it currently holds, at any time, without you having to trust that its
/// silence means the right thing.
@MainActor
final class GeneralPane: NSViewController {

    weak var host: SettingsHost?

    private var conversionCheckbox: NSButton!
    private var loginCheckbox: NSButton!
    private var noticesCheckbox: NSButton!
    private var scriptsCheckbox: NSButton!
    private var loginNote: NSTextField!
    private var permissionRows: [Permission: PermissionRow] = [:]

    override func loadView() {
        let content = NSView()

        conversionCheckbox = checkbox("Convert LaTeX as you type", #selector(toggleConversion))
        loginCheckbox = checkbox("Open at login", #selector(toggleLogin))
        noticesCheckbox = checkbox("Show a notice when a command is refused or falls back",
                                   #selector(toggleNotices))
        scriptsCheckbox = checkbox("Keep superscripts and subscripts that have no Unicode form",
                                   #selector(toggleScripts))

        loginNote = note("")
        loginNote.isHidden = true

        let grid = NSGridView(views: [
            [label("Conversion:"), conversionCheckbox],
            [NSGridCell.emptyContentView,
             note("Type a command and finish it with a space, and it is replaced "
                  + "by the character it names. Off, the app keeps running and "
                  + "leaves your typing alone.")],

            [label("Startup:"), loginCheckbox],
            [NSGridCell.emptyContentView, loginNote],

            [label("Notices:"), noticesCheckbox],
            [NSGridCell.emptyContentView,
             note("The brief message under the menu bar that says a command was "
                  + "left as you typed it, and why. Messages about the app's own "
                  + "state are always shown.")],

            [label("Scripts:"), scriptsCheckbox],
            [NSGridCell.emptyContentView,
             note("Unicode has no raised \u{221E}, so \\Sigma_{i=1}^\\infty{a_i} "
                  + "cannot be converted and is normally left alone entirely. On, "
                  + "the parts that have a form get one and the part that does not "
                  + "keeps its caret: \u{03A3}\u{1D62}\u{208C}\u{2081}^\u{221E}a\u{1D62}. "
                  + "The cost is converted characters and raw LaTeX on the same line.")],

            [label("Permissions:"), row(for: .accessibility)],
            [NSGridCell.emptyContentView, row(for: .inputMonitoring)],
            [NSGridCell.emptyContentView,
             note("Both are needed before anything can be replaced. Nothing you "
                  + "type is stored or sent anywhere.")],
        ])

        grid.translatesAutoresizingMaskIntoConstraints = false
        grid.column(at: 0).xPlacement = .trailing
        grid.column(at: 0).width = 92
        grid.rowAlignment = .firstBaseline
        grid.columnSpacing = 10

        // The explanation belongs to the checkbox above it; the gap goes
        // between groups, not inside them.
        for index in 0..<grid.numberOfRows {
            grid.row(at: index).bottomPadding = index.isMultiple(of: 2) ? 2 : 14
        }
        grid.row(at: grid.numberOfRows - 1).bottomPadding = 0

        content.addSubview(grid)
        NSLayoutConstraint.activate([
            grid.topAnchor.constraint(equalTo: content.topAnchor, constant: 20),
            grid.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            grid.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),

            // Greater-than, not equal. Pinned at both ends the grid is *given*
            // a height, and NSGridView answers a height it did not ask for by
            // sharing the slack out between its rows — which reads as random
            // gaps under the checkboxes. Anchored only at the top, the spare
            // height falls to the bottom of the pane where it belongs.
            content.bottomAnchor.constraint(greaterThanOrEqualTo: grid.bottomAnchor, constant: 20),

            // Both panes are one size, so switching tabs moves nothing. A
            // settings window that resizes under the pointer is hard to aim at.
            content.widthAnchor.constraint(equalToConstant: 620),
            content.heightAnchor.constraint(equalToConstant: 480),
        ])

        view = content
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        refresh()
    }

    /// Pulled from the host rather than pushed, so the window cannot drift out
    /// of step with the menu: both read the same answer at the moment they draw.
    func refresh() {
        guard isViewLoaded else { return }

        conversionCheckbox.state = host?.conversionEnabled == true ? .on : .off
        noticesCheckbox.state = Preferences.showNotices ? .on : .off
        scriptsCheckbox.state = Preferences.keepUnrenderableScripts ? .on : .off

        loginCheckbox.isEnabled = LoginItem.isAvailable
        loginCheckbox.state = LoginItem.isEnabled ? .on : .off

        if !LoginItem.isAvailable {
            loginNote.stringValue =
                "Only available for the installed app in /Applications, not for a "
                + "build run from the command line."
            loginNote.isHidden = false
        } else if LoginItem.needsApproval {
            loginNote.stringValue =
                "Waiting for approval in System Settings \u{203A} General \u{203A} Login Items."
            loginNote.isHidden = false
        } else {
            loginNote.isHidden = true
        }

        let state = host?.permissionState ?? PermissionState()
        for (permission, row) in permissionRows {
            row.update(granted: state.isGranted(permission))
        }
    }

    // MARK: Actions

    @objc private func toggleConversion() {
        host?.setConversionEnabled(conversionCheckbox.state == .on)
    }

    @objc private func toggleNotices() {
        Preferences.showNotices = noticesCheckbox.state == .on
    }

    /// Nothing to notify: the event tap reads `Preferences` on each keystroke
    /// rather than holding a copy, so the next command already sees this.
    @objc private func toggleScripts() {
        Preferences.keepUnrenderableScripts = scriptsCheckbox.state == .on
    }

    @objc private func toggleLogin() {
        let wanted = loginCheckbox.state == .on
        if let problem = LoginItem.setEnabled(wanted) {
            let alert = NSAlert()
            alert.messageText = wanted ? "Could not open at login" : "Could not stop opening at login"
            alert.informativeText = problem
            alert.alertStyle = .warning
            alert.beginSheetModal(for: view.window ?? NSWindow(), completionHandler: nil)
        }
        refresh()
    }

    @objc private func openPermissionSettings(_ sender: NSButton) {
        guard let permission = permissionRows.first(where: { $0.value.button === sender })?.key
        else { return }
        host?.openPermissionSettings(permission)
    }

    // MARK: Construction

    private func row(for permission: Permission) -> NSView {
        let row = PermissionRow(permission: permission,
                                target: self,
                                action: #selector(openPermissionSettings(_:)))
        permissionRows[permission] = row
        return row.view
    }

    private func checkbox(_ title: String, _ action: Selector) -> NSButton {
        let button = NSButton(checkboxWithTitle: title, target: self, action: action)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }

    private func label(_ text: String) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.alignment = .right
        field.textColor = .labelColor
        field.translatesAutoresizingMaskIntoConstraints = false
        return field
    }

    private func note(_ text: String) -> NSTextField {
        let field = NSTextField(wrappingLabelWithString: text)
        field.font = .systemFont(ofSize: 11)
        field.textColor = .secondaryLabelColor
        field.preferredMaxLayoutWidth = 470
        field.translatesAutoresizingMaskIntoConstraints = false
        return field
    }
}

/// One permission, stated plainly: what it is, whether we hold it, and the one
/// button that leads to the only place it can be changed.
@MainActor
private final class PermissionRow {

    let view: NSStackView
    let button: NSButton

    private let status = NSTextField(labelWithString: "")

    init(permission: Permission, target: AnyObject, action: Selector) {
        let name = NSTextField(labelWithString: permission.title)
        name.translatesAutoresizingMaskIntoConstraints = false
        name.widthAnchor.constraint(equalToConstant: 126).isActive = true

        status.translatesAutoresizingMaskIntoConstraints = false

        button = NSButton(title: "Open Settings\u{2026}", target: target, action: action)
        button.bezelStyle = .rounded
        button.controlSize = .small
        button.translatesAutoresizingMaskIntoConstraints = false

        view = NSStackView(views: [name, status, button])
        view.orientation = .horizontal
        view.alignment = .firstBaseline
        view.spacing = 8
        view.translatesAutoresizingMaskIntoConstraints = false
    }

    func update(granted: Bool) {
        status.stringValue = granted ? "Granted" : "Not granted"
        status.textColor = granted ? .secondaryLabelColor : .systemOrange
        // Nothing to do once it is held, and a button that opens System
        // Settings to admire a checkbox is noise.
        button.isHidden = granted
    }
}
