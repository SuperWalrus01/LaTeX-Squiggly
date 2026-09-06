import AppKit
import LaTeXUnicode

/// A searchable list of every symbol the converter knows, for when you cannot
/// remember whether it is `\succeq` or `\suceq`.
///
/// Search runs over the command, the Unicode name and the category together, so
/// "greek capital" narrows to eleven rows and "double-struck" finds the
/// blackboard bold letters without knowing they are called that.
@MainActor
final class SymbolBrowser: NSObject, NSWindowDelegate {

    private var window: NSWindow?
    private var tableView: NSTableView!
    private var searchField: NSSearchField!
    private var statusLabel: NSTextField!

    private let allEntries = SymbolTable.entries
    private var visibleEntries: [SymbolEntry] = SymbolTable.entries

    func show() {
        if let window {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }
        let window = makeWindow()
        self.window = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(searchField)
    }

    // MARK: Construction

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 460),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false)
        window.title = "Symbols"
        window.delegate = self
        window.center()
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 480, height: 300)

        let content = NSView()

        searchField = NSSearchField()
        searchField.placeholderString = "Search 「alpha」, 「greek capital」, 「double-struck」\u{2026}"
        searchField.target = self
        searchField.action = #selector(searchChanged)
        searchField.sendsSearchStringImmediately = true
        searchField.translatesAutoresizingMaskIntoConstraints = false

        tableView = NSTableView()
        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowHeight = 26
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.doubleAction = #selector(copySymbol)
        tableView.target = self
        tableView.allowsMultipleSelection = false

        addColumn("glyph", "", width: 46)
        addColumn("command", "Command", width: 150)
        addColumn("name", "Unicode name", width: 260)
        addColumn("category", "Category", width: 140)

        let scrollView = NSScrollView()
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        let copySymbolButton = NSButton(title: "Copy Symbol", target: self, action: #selector(copySymbol))
        let copyCommandButton = NSButton(title: "Copy Command", target: self, action: #selector(copyCommand))
        copySymbolButton.keyEquivalent = "\r"
        for button in [copySymbolButton, copyCommandButton] {
            button.bezelStyle = .rounded
            button.translatesAutoresizingMaskIntoConstraints = false
        }

        statusLabel = NSTextField(labelWithString: "")
        statusLabel.font = .systemFont(ofSize: 11)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.translatesAutoresizingMaskIntoConstraints = false

        for view in [searchField!, scrollView, copySymbolButton, copyCommandButton, statusLabel!] {
            content.addSubview(view)
        }

        NSLayoutConstraint.activate([
            searchField.topAnchor.constraint(equalTo: content.topAnchor, constant: 12),
            searchField.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            searchField.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),

            scrollView.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 10),
            scrollView.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            scrollView.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            scrollView.bottomAnchor.constraint(equalTo: copySymbolButton.topAnchor, constant: -10),

            copySymbolButton.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            copySymbolButton.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -12),
            copyCommandButton.trailingAnchor.constraint(equalTo: copySymbolButton.leadingAnchor, constant: -8),
            copyCommandButton.bottomAnchor.constraint(equalTo: copySymbolButton.bottomAnchor),

            statusLabel.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            statusLabel.centerYAnchor.constraint(equalTo: copySymbolButton.centerYAnchor),
            statusLabel.trailingAnchor.constraint(lessThanOrEqualTo: copyCommandButton.leadingAnchor, constant: -8),
        ])

        window.contentView = content
        updateStatus()
        return window
    }

    private func addColumn(_ identifier: String, _ title: String, width: CGFloat) {
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(identifier))
        column.title = title
        column.width = width
        tableView.addTableColumn(column)
    }

    // MARK: Actions

    @objc private func searchChanged() {
        let query = searchField.stringValue.trimmingCharacters(in: .whitespaces)
        visibleEntries = query.isEmpty ? allEntries : allEntries.filter { $0.matches(query) }
        tableView.reloadData()
        updateStatus()
    }

    private var selectedEntry: SymbolEntry? {
        let row = tableView.selectedRow
        guard row >= 0, row < visibleEntries.count else { return nil }
        return visibleEntries[row]
    }

    @objc private func copySymbol() {
        guard let entry = selectedEntry else { return }
        copy(entry.glyph, describedAs: entry.glyph)
    }

    @objc private func copyCommand() {
        guard let entry = selectedEntry else { return }
        copy("\\" + entry.command, describedAs: "\\" + entry.command)
    }

    private func copy(_ text: String, describedAs description: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        statusLabel.stringValue = "Copied \(description)"
    }

    private func updateStatus() {
        let count = visibleEntries.count
        statusLabel.stringValue = count == allEntries.count
            ? "\(count) symbols \u{00B7} type the command, or double-click to copy"
            : "\(count) of \(allEntries.count) symbols"
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
    }
}

extension SymbolBrowser: NSTableViewDataSource {
    func numberOfRows(in tableView: NSTableView) -> Int { visibleEntries.count }
}

extension SymbolBrowser: NSTableViewDelegate {
    func tableView(_ tableView: NSTableView,
                   viewFor tableColumn: NSTableColumn?,
                   row: Int) -> NSView? {
        guard let tableColumn, row < visibleEntries.count else { return nil }
        let entry = visibleEntries[row]

        let identifier = tableColumn.identifier
        let cell = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView
            ?? makeCell(identifier: identifier)

        switch identifier.rawValue {
        case "glyph":
            cell.textField?.stringValue = entry.glyph
            cell.textField?.font = .systemFont(ofSize: 17)
            cell.textField?.alignment = .center
        case "command":
            cell.textField?.stringValue = "\\" + entry.command
            cell.textField?.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        case "name":
            // Title case reads better than the shouting of the Unicode database.
            cell.textField?.stringValue = entry.unicodeName.capitalized
            cell.textField?.font = .systemFont(ofSize: 12)
        default:
            cell.textField?.stringValue = entry.category
            cell.textField?.font = .systemFont(ofSize: 11)
            cell.textField?.textColor = .secondaryLabelColor
        }
        return cell
    }

    private func makeCell(identifier: NSUserInterfaceItemIdentifier) -> NSTableCellView {
        let cell = NSTableCellView()
        cell.identifier = identifier
        let field = NSTextField(labelWithString: "")
        field.translatesAutoresizingMaskIntoConstraints = false
        field.lineBreakMode = .byTruncatingTail
        cell.addSubview(field)
        cell.textField = field
        NSLayoutConstraint.activate([
            field.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
            field.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -2),
            field.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        return cell
    }
}
