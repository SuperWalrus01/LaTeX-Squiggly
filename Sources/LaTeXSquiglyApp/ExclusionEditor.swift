import AppKit
import AppSuppression
import UniformTypeIdentifiers

/// The exclusion list editor: the piece of Phase 3's UI that could not exist
/// until there was a Phase 2 to edit.
///
/// Two lists, because there are two kinds of place to stay quiet in. An
/// application is named by its bundle identifier, which is why apps are added
/// with a file picker rather than a text field — the identifier is read off the
/// bundle instead of typed, and cannot be got wrong. A website is named by its
/// host, which the user does have to type, so `normalisedHost` accepts a pasted
/// URL and refuses anything that is not a host at all.
@MainActor
final class ExclusionEditor: NSObject, NSWindowDelegate {

    private let store: ExclusionStore

    private var window: NSWindow?
    private var appTable: NSTableView!
    private var siteTable: NSTableView!
    private var siteField: NSTextField!
    private var unidentifiedCheckbox: NSButton!

    init(store: ExclusionStore) {
        self.store = store
        super.init()
    }

    func show() {
        if let window {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            reload()
            return
        }
        let window = makeWindow()
        self.window = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        reload()
    }

    // MARK: Construction

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 660, height: 420),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false)
        window.title = "Excluded Apps and Sites"
        window.delegate = self
        window.center()
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 560, height: 340)

        let content = NSView()

        appTable = makeTable()
        siteTable = makeTable()

        let appScroll = scrollView(around: appTable)
        let siteScroll = scrollView(around: siteTable)

        let appHeading = heading("Applications")
        let siteHeading = heading("Websites")

        let addApp = button("Add\u{2026}", #selector(addApplication))
        let removeApp = button("Remove", #selector(removeApplication))
        let removeSite = button("Remove", #selector(removeSite))

        siteField = NSTextField()
        siteField.placeholderString = "overleaf.com"
        siteField.target = self
        siteField.action = #selector(addSite)
        siteField.translatesAutoresizingMaskIntoConstraints = false
        let addSiteButton = button("Add", #selector(addSite))

        unidentifiedCheckbox = NSButton(
            checkboxWithTitle: "Stay off when a browser will not say which page is open",
            target: self, action: #selector(toggleUnidentified))
        unidentifiedCheckbox.translatesAutoresizingMaskIntoConstraints = false

        let explanation = NSTextField(wrappingLabelWithString:
            "Firefox does not hand over page addresses, so on those pages only the window "
            + "title can be checked. Leaving this on trades the odd missed conversion for "
            + "never rewriting a document that turns out to be LaTeX source.")
        explanation.font = .systemFont(ofSize: 11)
        explanation.textColor = .secondaryLabelColor
        explanation.translatesAutoresizingMaskIntoConstraints = false

        let restore = button("Restore Defaults", #selector(restoreDefaults))

        for view in [appHeading, siteHeading, appScroll, siteScroll, addApp, removeApp,
                     siteField!, addSiteButton, removeSite, unidentifiedCheckbox!,
                     explanation, restore] {
            content.addSubview(view)
        }

        let gutter: CGFloat = 12
        NSLayoutConstraint.activate([
            appHeading.topAnchor.constraint(equalTo: content.topAnchor, constant: gutter),
            appHeading.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: gutter),
            siteHeading.topAnchor.constraint(equalTo: appHeading.topAnchor),
            siteHeading.leadingAnchor.constraint(equalTo: siteScroll.leadingAnchor),

            appScroll.topAnchor.constraint(equalTo: appHeading.bottomAnchor, constant: 6),
            appScroll.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: gutter),
            appScroll.bottomAnchor.constraint(equalTo: addApp.topAnchor, constant: -8),

            siteScroll.topAnchor.constraint(equalTo: appScroll.topAnchor),
            siteScroll.leadingAnchor.constraint(equalTo: appScroll.trailingAnchor, constant: gutter),
            siteScroll.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -gutter),
            siteScroll.bottomAnchor.constraint(equalTo: appScroll.bottomAnchor),
            siteScroll.widthAnchor.constraint(equalTo: appScroll.widthAnchor),

            addApp.leadingAnchor.constraint(equalTo: appScroll.leadingAnchor),
            addApp.bottomAnchor.constraint(equalTo: unidentifiedCheckbox.topAnchor, constant: -14),
            removeApp.leadingAnchor.constraint(equalTo: addApp.trailingAnchor, constant: 8),
            removeApp.centerYAnchor.constraint(equalTo: addApp.centerYAnchor),

            siteField.leadingAnchor.constraint(equalTo: siteScroll.leadingAnchor),
            siteField.centerYAnchor.constraint(equalTo: addApp.centerYAnchor),
            siteField.trailingAnchor.constraint(equalTo: addSiteButton.leadingAnchor, constant: -8),
            addSiteButton.centerYAnchor.constraint(equalTo: addApp.centerYAnchor),
            addSiteButton.trailingAnchor.constraint(equalTo: removeSite.leadingAnchor, constant: -8),
            removeSite.trailingAnchor.constraint(equalTo: siteScroll.trailingAnchor),
            removeSite.centerYAnchor.constraint(equalTo: addApp.centerYAnchor),

            unidentifiedCheckbox.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: gutter),
            unidentifiedCheckbox.bottomAnchor.constraint(equalTo: explanation.topAnchor, constant: -4),

            explanation.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: gutter),
            explanation.trailingAnchor.constraint(equalTo: restore.leadingAnchor, constant: -12),
            explanation.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -gutter),

            restore.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -gutter),
            restore.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -gutter),
        ])

        window.contentView = content
        return window
    }

    private func makeTable() -> NSTableView {
        let table = NSTableView()
        table.dataSource = self
        table.delegate = self
        table.rowHeight = 32
        table.headerView = nil
        table.usesAlternatingRowBackgroundColors = true
        table.allowsMultipleSelection = false
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("rule"))
        column.width = 280
        table.addTableColumn(column)
        return table
    }

    private func scrollView(around table: NSTableView) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.translatesAutoresizingMaskIntoConstraints = false
        return scroll
    }

    private func heading(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 12, weight: .semibold)
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }

    private func button(_ title: String, _ action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .rounded
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }

    // MARK: Actions

    @objc private func addApplication() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = "Exclude"
        panel.message = "Choose apps LaTeX-Squigly should leave alone."

        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK else { return }

        for url in panel.urls {
            // Read the identifier rather than trusting a name: two apps can
            // share a name, and only one of them is the one in front of you.
            guard let bundle = Bundle(url: url), let bundleID = bundle.bundleIdentifier else {
                continue
            }
            let name = FileManager.default.displayName(atPath: url.path)
                .replacingOccurrences(of: ".app", with: "")
            store.exclude(bundleID: bundleID, name: name)
        }
        reload()
    }

    @objc private func removeApplication() {
        let row = appTable.selectedRow
        guard row >= 0, row < store.list.apps.count else { return }
        store.removeApp(bundleID: store.list.apps[row].bundleID)
        reload()
    }

    @objc private func addSite() {
        let input = siteField.stringValue
        guard !input.trimmingCharacters(in: .whitespaces).isEmpty else { return }

        guard store.addSite(input) else {
            let alert = NSAlert()
            alert.messageText = "That is not a website address"
            alert.informativeText =
                "Enter a host such as overleaf.com, or paste a link to the site. "
                + "A rule that matches nothing would look like protection without being any."
            alert.alertStyle = .warning
            alert.runModal()
            return
        }
        siteField.stringValue = ""
        reload()
    }

    @objc private func removeSite() {
        let row = siteTable.selectedRow
        guard row >= 0, row < store.list.sites.count else { return }
        store.removeSite(host: store.list.sites[row].host)
        reload()
    }

    @objc private func toggleUnidentified() {
        store.setSuppressUnidentifiedPages(unidentifiedCheckbox.state == .on)
    }

    @objc private func restoreDefaults() {
        let alert = NSAlert()
        alert.messageText = "Restore the default exclusions?"
        alert.informativeText =
            "Everything you have added or removed will be replaced by the apps and sites "
            + "LaTeX-Squigly ships with."
        alert.addButton(withTitle: "Restore")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        store.restoreDefaults()
        reload()
    }

    private func reload() {
        unidentifiedCheckbox?.state = store.list.suppressUnidentifiedPages ? .on : .off
        appTable?.reloadData()
        siteTable?.reloadData()
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
    }
}

extension ExclusionEditor: NSTableViewDataSource {
    func numberOfRows(in tableView: NSTableView) -> Int {
        tableView === appTable ? store.list.apps.count : store.list.sites.count
    }
}

extension ExclusionEditor: NSTableViewDelegate {
    func tableView(_ tableView: NSTableView,
                   viewFor tableColumn: NSTableColumn?,
                   row: Int) -> NSView? {
        let title: String
        let subtitle: String

        if tableView === appTable {
            guard row < store.list.apps.count else { return nil }
            let app = store.list.apps[row]
            title = app.name
            subtitle = app.bundleID
        } else {
            guard row < store.list.sites.count else { return nil }
            let site = store.list.sites[row]
            title = site.host
            subtitle = "and every subdomain"
        }

        let identifier = NSUserInterfaceItemIdentifier("rule")
        let cell = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView
            ?? makeCell(identifier: identifier)
        cell.textField?.stringValue = title
        (cell.subviews.last as? NSTextField)?.stringValue = subtitle
        return cell
    }

    private func makeCell(identifier: NSUserInterfaceItemIdentifier) -> NSTableCellView {
        let cell = NSTableCellView()
        cell.identifier = identifier

        let title = NSTextField(labelWithString: "")
        title.font = .systemFont(ofSize: 12)
        title.lineBreakMode = .byTruncatingTail
        title.translatesAutoresizingMaskIntoConstraints = false

        let subtitle = NSTextField(labelWithString: "")
        subtitle.font = .systemFont(ofSize: 10)
        subtitle.textColor = .secondaryLabelColor
        subtitle.lineBreakMode = .byTruncatingMiddle
        subtitle.translatesAutoresizingMaskIntoConstraints = false

        cell.addSubview(title)
        cell.addSubview(subtitle)
        cell.textField = title

        NSLayoutConstraint.activate([
            title.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
            title.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
            title.topAnchor.constraint(equalTo: cell.topAnchor, constant: 2),
            subtitle.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            subtitle.trailingAnchor.constraint(equalTo: title.trailingAnchor),
            subtitle.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 1),
        ])
        return cell
    }
}
