using System.Drawing;
using System.Windows.Forms;
using LaTeXSquiggly.Core.Suppression;

namespace LaTeXSquiggly.App.Platform;

/// <summary>
/// Wiring: the tray icon, the menu, and the one object that decides whether
/// conversion is allowed where the user is typing.
///
/// This is the Windows counterpart of the Mac's AppDelegate, and it keeps the
/// same rule: the menu never holds its own copy of the app's state, it asks at
/// the moment it draws, so the menu and the settings window cannot disagree.
/// </summary>
internal sealed class TrayApplication : ApplicationContext
{
    private readonly Settings _settings = Settings.Load();
    private readonly KeyboardHook _hook = new();
    private readonly ForegroundWatcher _watcher = new();
    private readonly NoticeWindow _notices = new();
    private readonly NotifyIcon _tray = new();
    private readonly System.Windows.Forms.Timer _menuRefresh;

    private Icon? _activeIcon;
    private Icon? _inactiveIcon;
    private SettingsWindow? _window;

    public TrayApplication()
    {
        if (_settings.DiscoverDefaults()) _settings.Save();

        _hook.OnNotice = ShowNotice;
        _hook.Suppression = CurrentDecision;

        _tray.Text = "LaTeX Squiggly";
        _tray.Visible = true;
        _tray.DoubleClick += (_, _) => ShowSettings();

        BuildIcons();
        RebuildMenu();

        if (_settings.ConversionEnabled ?? true) StartConverting();

        // The menu is rebuilt lazily rather than on every foreground change:
        // there is no cheap notification for a browser tab changing, and the
        // only thing that goes stale is a line of text nobody is reading while
        // it is closed.
        _tray.ContextMenuStrip!.Opening += (_, _) => RebuildMenu();

        // Keeps the icon honest about whether it is converting right now, which
        // changes when the user switches into an excluded app.
        _menuRefresh = new System.Windows.Forms.Timer { Interval = 1500 };
        _menuRefresh.Tick += (_, _) => RefreshIcon();
        _menuRefresh.Start();

        if (_settings.IsFirstRun) ShowWelcome();
    }

    // MARK: The decision

    /// <summary>
    /// Asked on every keystroke, and again immediately before anything is
    /// typed. Cheap enough on Windows to answer freshly both times: see
    /// ForegroundWatcher for why the Mac cannot.
    /// </summary>
    private SuppressionDecision CurrentDecision() =>
        _settings.Exclusions.Decision(_watcher.Current());

    private bool IsEnabled => _settings.ConversionEnabled ?? true;

    private void StartConverting()
    {
        if (!_hook.Start())
        {
            MessageBox.Show(
                "Windows would not let LaTeX Squiggly watch the keyboard.\n\n"
                + "This usually means another tool already holds a low-level keyboard "
                + "hook, or the app was blocked by security software.",
                "LaTeX Squiggly", MessageBoxButtons.OK, MessageBoxIcon.Warning);
            return;
        }
        // Window titles are only read while conversion is actually running.
        _watcher.ReadsPages = true;
        RefreshIcon();
    }

    private void StopConverting()
    {
        _hook.Stop();
        _watcher.ReadsPages = false;
        RefreshIcon();
    }

    public void SetConversionEnabled(bool enabled)
    {
        if (enabled == IsEnabled) return;
        _settings.ConversionEnabled = enabled;
        _settings.Save();
        if (enabled) StartConverting(); else StopConverting();
        RebuildMenu();
        _window?.Refresh();
    }

    public Settings Settings => _settings;

    public void ExclusionsChanged()
    {
        _settings.Save();
        _hook.ResetBuffer();
        RebuildMenu();
    }

    private void ShowNotice(string message)
    {
        if (!_settings.ShowNotices) return;
        _notices.ShowNotice(message);
    }

    // MARK: The icon

    /// <summary>
    /// Two states, not three. The icon answers "is it converting right now",
    /// which is the same answer whether the app is switched off or merely
    /// staying quiet in TeXstudio; the menu answers "why not".
    /// </summary>
    private void BuildIcons()
    {
        _activeIcon = AppIcon.Tray(active: true);
        _inactiveIcon = AppIcon.Tray(active: false);
        _tray.Icon = _activeIcon;
    }

    private void RefreshIcon()
    {
        var converting = _hook.IsRunning && !CurrentDecision().IsSuppressed;
        var wanted = converting ? _activeIcon : _inactiveIcon;
        if (!ReferenceEquals(_tray.Icon, wanted)) _tray.Icon = wanted;
        _tray.Text = Truncated("LaTeX Squiggly - " + StatusTitle().ToLowerInvariant());
    }

    /// <summary>A tray tooltip longer than 63 characters is silently dropped.</summary>
    private static string Truncated(string text) =>
        text.Length <= 63 ? text : text[..60] + "...";

    private string StatusTitle()
    {
        if (!IsEnabled) return "Off";
        if (!_hook.IsRunning) return "Not running";
        var reason = CurrentDecision().Reason;
        return reason?.Summary ?? "Converting as you type";
    }

    // MARK: The menu

    private void RebuildMenu()
    {
        var menu = _tray.ContextMenuStrip ?? new ContextMenuStrip();
        menu.Items.Clear();

        var decision = CurrentDecision();
        var status = new ToolStripMenuItem(StatusTitle()) { Enabled = false };
        menu.Items.Add(status);

        // Staying quiet looks exactly like being broken unless the app says
        // which rule it is obeying.
        if (_hook.IsRunning && decision.Reason is not null)
        {
            menu.Items.Add(new ToolStripMenuItem(decision.Reason.Explanation) { Enabled = false });
        }
        menu.Items.Add(new ToolStripSeparator());

        var toggle = new ToolStripMenuItem("Convert LaTeX as I type")
        {
            Checked = IsEnabled,
            CheckOnClick = true,
        };
        toggle.Click += (_, _) => SetConversionEnabled(toggle.Checked);
        menu.Items.Add(toggle);

        var notices = new ToolStripMenuItem("Show notices")
        {
            Checked = _settings.ShowNotices,
            CheckOnClick = true,
        };
        notices.Click += (_, _) =>
        {
            _settings.ShowNotices = notices.Checked;
            _settings.Save();
        };
        menu.Items.Add(notices);

        var startup = new ToolStripMenuItem("Open at login")
        {
            Checked = LoginItem.IsEnabled,
            CheckOnClick = true,
        };
        startup.Click += (_, _) =>
        {
            var problem = LoginItem.SetEnabled(startup.Checked);
            if (problem is not null)
            {
                MessageBox.Show(problem, "LaTeX Squiggly", MessageBoxButtons.OK, MessageBoxIcon.Warning);
            }
        };
        menu.Items.Add(startup);

        menu.Items.Add(new ToolStripSeparator());

        // One click to fix a miss. A default list cannot know about every TeX
        // editor, and the moment the user notices is the moment they are
        // looking at the wrong app.
        var context = _watcher.Current();
        if (context.ProcessName is not null)
        {
            var excluded = _settings.Exclusions.Contains(context.ProcessName);
            var item = new ToolStripMenuItem($"Do not convert in {context.DisplayName}")
            {
                Checked = excluded,
            };
            var processName = context.ProcessName;
            var displayName = context.DisplayName;
            item.Click += (_, _) =>
            {
                if (excluded) _settings.Exclusions.RemoveApp(processName);
                else _settings.Exclusions.Add(new ExcludedApp(processName, displayName));
                ExclusionsChanged();
            };
            menu.Items.Add(item);
        }

        var settings = new ToolStripMenuItem("Settings and Symbols...");
        settings.Click += (_, _) => ShowSettings();
        menu.Items.Add(settings);

        menu.Items.Add(new ToolStripSeparator());

        var quit = new ToolStripMenuItem("Quit LaTeX Squiggly");
        quit.Click += (_, _) => Quit();
        menu.Items.Add(quit);

        _tray.ContextMenuStrip = menu;
        RefreshIcon();
    }

    private void ShowSettings()
    {
        if (_window is null || _window.IsDisposed)
        {
            _window = new SettingsWindow(this);
        }
        _window.Show();
        _window.WindowState = FormWindowState.Normal;
        _window.Activate();
    }

    private void ShowWelcome()
    {
        _settings.ConversionEnabled = true;
        _settings.Save();

        var excluded = _settings.Exclusions.Apps.Count;
        MessageBox.Show(
            "LaTeX Squiggly is running in your system tray.\n\n"
            + "Look for its mark near the clock, at the bottom right of your screen. "
            + "You may need to click the arrow to show hidden icons, and drag it out.\n\n"
            + "Type a command and finish it with a space: \\alpha becomes a Greek alpha.\n\n"
            + $"It stays out of the way where LaTeX source is written. {excluded} apps are "
            + "already excluded, and so is Overleaf in any browser. Add your own from the "
            + "tray menu.\n\n"
            + "Nothing you type is stored or sent anywhere.",
            "LaTeX Squiggly", MessageBoxButtons.OK, MessageBoxIcon.Information);
    }

    private void Quit()
    {
        _menuRefresh.Stop();
        _hook.Dispose();
        _tray.Visible = false;
        _tray.Dispose();
        _notices.Dispose();
        ExitThread();
    }

    protected override void Dispose(bool disposing)
    {
        if (disposing)
        {
            _hook.Dispose();
            _tray.Dispose();
            _notices.Dispose();
        }
        base.Dispose(disposing);
    }
}
