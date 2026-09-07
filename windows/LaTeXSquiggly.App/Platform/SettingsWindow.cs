using System.Drawing;
using System.Windows.Forms;
using LaTeXSquiggly.Core.Engine;
using LaTeXSquiggly.Core.Suppression;

namespace LaTeXSquiggly.App.Platform;

/// <summary>
/// The settings window: the switches, the exclusion list editor, and the
/// searchable symbol table.
///
/// State is read from the tray application rather than copied into the window,
/// so the two surfaces that show the same switch cannot disagree.
/// </summary>
internal sealed class SettingsWindow : Form
{
    private readonly TrayApplication _host;

    /// <summary>
    /// Set while Refresh writes the controls' values. Without it, opening the
    /// window fires every CheckedChanged handler, which would rewrite the
    /// settings file and the startup registry key on each open, and would show
    /// a warning box if the registry write happened to fail.
    /// </summary>
    private bool _updating;

    private readonly CheckBox _conversion = new();
    private readonly CheckBox _notices = new();
    private readonly CheckBox _startup = new();
    private readonly CheckBox _unidentified = new();
    private readonly ListBox _apps = new();
    private readonly ListBox _sites = new();
    private readonly TextBox _siteField = new();
    private readonly TextBox _search = new();
    private readonly ListView _symbols = new();

    public SettingsWindow(TrayApplication host)
    {
        _host = host;

        Text = "LaTeX Squiggly";
        Size = new Size(680, 500);
        MinimumSize = new Size(560, 420);
        StartPosition = FormStartPosition.CenterScreen;
        Icon = AppIcon.Window;

        var tabs = new TabControl { Dock = DockStyle.Fill };
        tabs.TabPages.Add(GeneralPage());
        tabs.TabPages.Add(ExclusionsPage());
        tabs.TabPages.Add(SymbolsPage());
        Controls.Add(tabs);

        Refresh();
    }

    // MARK: General

    private TabPage GeneralPage()
    {
        var page = new TabPage("General") { Padding = new Padding(16) };
        var layout = new FlowLayoutPanel
        {
            Dock = DockStyle.Fill,
            FlowDirection = FlowDirection.TopDown,
            WrapContents = false,
            AutoScroll = true,
        };

        _conversion.Text = "Convert LaTeX as I type";
        _conversion.AutoSize = true;
        _conversion.CheckedChanged += (_, _) =>
        {
            if (_updating) return;
            _host.SetConversionEnabled(_conversion.Checked);
        };
        layout.Controls.Add(_conversion);
        layout.Controls.Add(Note(
            "Type a command and finish it with a space, and it is replaced by the character "
            + "it names. Switched off, the app keeps running and leaves your typing alone."));

        _notices.Text = "Show a notice when a command is refused or falls back";
        _notices.AutoSize = true;
        _notices.CheckedChanged += (_, _) =>
        {
            if (_updating) return;
            _host.Settings.ShowNotices = _notices.Checked;
            _host.Settings.Save();
        };
        layout.Controls.Add(_notices);
        layout.Controls.Add(Note(
            "The brief message above the tray that says a command was left as you typed it, "
            + "and why. Messages about the app's own state are always shown."));

        _startup.Text = "Open at login";
        _startup.AutoSize = true;
        _startup.CheckedChanged += (_, _) =>
        {
            if (_updating) return;
            var problem = LoginItem.SetEnabled(_startup.Checked);
            if (problem is not null)
            {
                MessageBox.Show(this, problem, "LaTeX Squiggly",
                                MessageBoxButtons.OK, MessageBoxIcon.Warning);
            }
        };
        layout.Controls.Add(_startup);
        layout.Controls.Add(Note(
            "Adds LaTeX Squiggly to this user's startup items. Nothing is written outside "
            + "your own account, and removing the app removes the setting."));

        layout.Controls.Add(Note(
            "\r\nWindows asks for no special permission to do any of this, so there is nothing "
            + "to grant. Nothing you type is stored or sent anywhere: the app keeps a 64 "
            + "character buffer in memory and discards it as soon as a command completes, or "
            + "you click, or you press Return, or you switch app."));

        page.Controls.Add(layout);
        return page;
    }

    // MARK: Exclusions

    private TabPage ExclusionsPage()
    {
        var page = new TabPage("Exclusions") { Padding = new Padding(12) };

        var appLabel = new Label { Text = "Applications", AutoSize = true, Location = new Point(12, 10) };
        _apps.SetBounds(12, 32, 300, 240);
        var removeApp = new Button { Text = "Remove", Location = new Point(12, 280), Width = 90 };
        removeApp.Click += (_, _) =>
        {
            if (_apps.SelectedIndex < 0) return;
            var app = _host.Settings.Exclusions.Apps[_apps.SelectedIndex];
            _host.Settings.Exclusions.RemoveApp(app.ProcessName);
            _host.ExclusionsChanged();
            Refresh();
        };
        var addApp = new Button { Text = "Add...", Location = new Point(110, 280), Width = 90 };
        addApp.Click += (_, _) => AddApplication();

        var siteLabel = new Label { Text = "Websites", AutoSize = true, Location = new Point(330, 10) };
        _sites.SetBounds(330, 32, 300, 240);
        _siteField.SetBounds(330, 280, 150, 24);
        _siteField.PlaceholderText = "overleaf.com";
        var addSite = new Button { Text = "Add", Location = new Point(488, 279), Width = 60 };
        addSite.Click += (_, _) => AddSite();
        var removeSite = new Button { Text = "Remove", Location = new Point(554, 279), Width = 76 };
        removeSite.Click += (_, _) =>
        {
            if (_sites.SelectedIndex < 0) return;
            _host.Settings.Exclusions.RemoveSite(_host.Settings.Exclusions.Sites[_sites.SelectedIndex].Host);
            _host.ExclusionsChanged();
            Refresh();
        };

        _unidentified.Text = "Stay off when a browser will not say which page is open";
        _unidentified.AutoSize = true;
        _unidentified.Location = new Point(12, 318);
        _unidentified.CheckedChanged += (_, _) =>
        {
            if (_updating) return;
            _host.Settings.Exclusions.SuppressUnidentifiedPages = _unidentified.Checked;
            _host.ExclusionsChanged();
        };

        var explanation = Note(
            "On Windows a browser is identified by its window title, which is the page "
            + "title, so an Overleaf tab is recognised without reading any address. "
            + "Leaving this on trades the odd missed conversion for never rewriting a "
            + "document that turns out to be LaTeX source.");
        explanation.SetBounds(12, 344, 470, 60);

        var restore = new Button { Text = "Restore Defaults", Location = new Point(500, 350), Width = 130 };
        restore.Click += (_, _) =>
        {
            var answer = MessageBox.Show(this,
                "Everything you have added or removed will be replaced by the apps and sites "
                + "LaTeX Squiggly ships with.",
                "Restore the default exclusions?", MessageBoxButtons.OKCancel, MessageBoxIcon.Warning);
            if (answer != DialogResult.OK) return;
            _host.Settings.Exclusions = DefaultExclusions.Fresh();
            _host.ExclusionsChanged();
            Refresh();
        };

        page.Controls.AddRange(new Control[]
        {
            appLabel, _apps, removeApp, addApp,
            siteLabel, _sites, _siteField, addSite, removeSite,
            _unidentified, explanation, restore,
        });
        return page;
    }

    private void AddApplication()
    {
        using var dialog = new OpenFileDialog
        {
            Title = "Choose an app LaTeX Squiggly should leave alone",
            Filter = "Programs (*.exe)|*.exe",
            CheckFileExists = true,
        };
        if (dialog.ShowDialog(this) != DialogResult.OK) return;

        // The executable name is read off the file rather than typed, so it
        // cannot be got wrong.
        var process = Path.GetFileNameWithoutExtension(dialog.FileName);
        if (process.Length == 0) return;
        _host.Settings.Exclusions.Add(
            new ExcludedApp(process, ForegroundWatcher.DisplayNameFor(process.ToLowerInvariant())));
        _host.ExclusionsChanged();
        Refresh();
    }

    private void AddSite()
    {
        var input = _siteField.Text.Trim();
        if (input.Length == 0) return;

        var host = ExclusionList.NormalisedHost(input);
        if (host is null)
        {
            MessageBox.Show(this,
                "Enter a host such as overleaf.com, or paste a link to the site. "
                + "A rule that matches nothing would look like protection without being any.",
                "That is not a website address", MessageBoxButtons.OK, MessageBoxIcon.Warning);
            return;
        }
        // A hand-added host gets its own name as a title fragment, because the
        // title is what a rule actually matches on here.
        var label = host.Split('.').FirstOrDefault() ?? host;
        _host.Settings.Exclusions.Add(new ExcludedSite(host, label));
        _host.ExclusionsChanged();
        _siteField.Clear();
        Refresh();
    }

    // MARK: Symbols

    private TabPage SymbolsPage()
    {
        var page = new TabPage("Symbols") { Padding = new Padding(12) };

        _search.Dock = DockStyle.Top;
        _search.PlaceholderText = "Search: alpha, greek capital, double-struck...";
        _search.TextChanged += (_, _) => FillSymbols();

        _symbols.Dock = DockStyle.Fill;
        _symbols.View = View.Details;
        _symbols.FullRowSelect = true;
        _symbols.MultiSelect = false;
        _symbols.Columns.Add("", 46);
        _symbols.Columns.Add("Command", 150);
        _symbols.Columns.Add("Unicode name", 260);
        _symbols.Columns.Add("Category", 140);

        var buttons = new FlowLayoutPanel
        {
            Dock = DockStyle.Bottom,
            FlowDirection = FlowDirection.RightToLeft,
            Height = 36,
        };
        var copySymbol = new Button { Text = "Copy Symbol", Width = 110 };
        copySymbol.Click += (_, _) => CopySelected(glyph: true);
        var copyCommand = new Button { Text = "Copy Command", Width = 120 };
        copyCommand.Click += (_, _) => CopySelected(glyph: false);
        buttons.Controls.Add(copySymbol);
        buttons.Controls.Add(copyCommand);

        _symbols.DoubleClick += (_, _) => CopySelected(glyph: true);

        page.Controls.Add(_symbols);
        page.Controls.Add(buttons);
        page.Controls.Add(_search);
        FillSymbols();
        return page;
    }

    private void FillSymbols()
    {
        var terms = _search.Text.ToLowerInvariant()
            .Split(' ', StringSplitOptions.RemoveEmptyEntries);

        _symbols.BeginUpdate();
        _symbols.Items.Clear();
        foreach (var entry in SymbolTable.Entries)
        {
            var haystack = $"\\{entry.Command} {entry.UnicodeName} {entry.Category} {entry.Glyph}"
                .ToLowerInvariant();
            if (!terms.All(haystack.Contains)) continue;

            var row = new ListViewItem(entry.Glyph);
            row.SubItems.Add("\\" + entry.Command);
            row.SubItems.Add(Capitalised(entry.UnicodeName));
            row.SubItems.Add(entry.Category);
            row.Tag = entry;
            _symbols.Items.Add(row);
        }
        _symbols.EndUpdate();
    }

    private void CopySelected(bool glyph)
    {
        if (_symbols.SelectedItems.Count == 0) return;
        if (_symbols.SelectedItems[0].Tag is not SymbolEntry entry) return;
        try { Clipboard.SetText(glyph ? entry.Glyph : "\\" + entry.Command); }
        catch (Exception) { /* another app can hold the clipboard open */ }
    }

    /// <summary>Title case reads better than the shouting of the Unicode database.</summary>
    private static string Capitalised(string text) =>
        System.Globalization.CultureInfo.CurrentCulture.TextInfo.ToTitleCase(text.ToLowerInvariant());

    // MARK: State

    public new void Refresh()
    {
        _updating = true;
        try { RefreshControls(); }
        finally { _updating = false; }
        base.Refresh();
    }

    private void RefreshControls()
    {
        var settings = _host.Settings;
        _conversion.Checked = settings.ConversionEnabled ?? true;
        _notices.Checked = settings.ShowNotices;
        _startup.Checked = LoginItem.IsEnabled;
        _unidentified.Checked = settings.Exclusions.SuppressUnidentifiedPages;

        _apps.BeginUpdate();
        _apps.Items.Clear();
        foreach (var app in settings.Exclusions.Apps)
        {
            _apps.Items.Add($"{app.Name}   ({app.ProcessName}.exe)");
        }
        _apps.EndUpdate();

        _sites.BeginUpdate();
        _sites.Items.Clear();
        foreach (var site in settings.Exclusions.Sites)
        {
            _sites.Items.Add($"{site.Host}   (and every subdomain)");
        }
        _sites.EndUpdate();
    }

    private static Label Note(string text) => new()
    {
        Text = text,
        AutoSize = false,
        Width = 600,
        Height = 46,
        ForeColor = SystemColors.GrayText,
        Font = new Font(SystemFonts.MessageBoxFont!.FontFamily, 8.25f),
        Margin = new Padding(22, 0, 0, 12),
    };

    protected override void OnFormClosing(FormClosingEventArgs e)
    {
        // Kept rather than dropped: rebuilding loses the selected tab and the
        // scroll position in a list the user was halfway through editing.
        if (e.CloseReason == CloseReason.UserClosing)
        {
            e.Cancel = true;
            Hide();
            return;
        }
        base.OnFormClosing(e);
    }
}
