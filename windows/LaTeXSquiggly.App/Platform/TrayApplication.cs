using System.Drawing;
using System.Runtime.InteropServices;
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
    /// <summary>
    /// How often the icon is brought up to date, and the keyboard layout
    /// checked. A browser tab can change without the foreground window
    /// changing, and there is no notification for that, so this is the one
    /// thing still polled.
    /// </summary>
    private const int TabPollIntervalMs = 4000;

    private readonly Settings _settings = Settings.Load();
    private readonly InputThread _hook = new();
    private readonly ForegroundWatcher _watcher = new();
    private readonly NoticeWindow _notices = new();
    private readonly NotifyIcon _tray = new();
    private readonly System.Windows.Forms.Timer _tabPoll;

    /// <summary>
    /// A control that is never shown, kept for its handle: BeginInvoke on it is
    /// how work from the input thread reaches the UI thread without waiting.
    /// </summary>
    private readonly Control _ui = new();

    /// <summary>
    /// The exclusion rules the input thread reads: a snapshot, replaced
    /// wholesale when the user changes them, so the hook never locks against
    /// the settings window.
    /// </summary>
    private volatile ExclusionList _rules;

    private Icon? _activeIcon;
    private Icon? _inactiveIcon;
    private SettingsWindow? _window;

    /// <summary>Set once quitting starts, so nothing posted late touches a disposed control.</summary>
    private bool _quitting;

    public TrayApplication()
    {
        if (_settings.DiscoverDefaults()) _settings.Save();

        _rules = _settings.Exclusions.Snapshot();
        _ = _ui.Handle;   // created now, on the UI thread, so BeginInvoke works from the start

        // The input thread calls these on its own thread, and must never wait
        // for the UI, so both only post.
        _hook.Rules = () => _rules;
        _hook.OnNotice = message => Post(() => ShowNotice(message));
        _hook.OnForegroundChanged = () => Post(RefreshIcon);

        _tray.Text = "LaTeX Squiggly";
        _tray.Visible = true;
        _tray.DoubleClick += (_, _) => ShowSettings();

        BuildIcons();
        RebuildMenu();

        // Keeps the icon honest about whether it is converting right now, and
        // notices a change of keyboard layout. The table is built off the UI
        // thread: it is 2,048 calls to ToUnicodeEx.
        _tabPoll = new System.Windows.Forms.Timer { Interval = TabPollIntervalMs };
        _tabPoll.Tick += (_, _) =>
        {
            RefreshIcon();
            ThreadPool.QueueUserWorkItem(_ => BuildLayoutTable());
        };

        if (_settings.ConversionEnabled ?? true) StartConverting();

        // The menu is rebuilt lazily rather than on every foreground change:
        // there is no cheap notification for a browser tab changing, and the
        // only thing that goes stale is a line of text nobody is reading while
        // it is closed.
        _tray.ContextMenuStrip!.Opening += (_, _) => RebuildMenu();

        // Posted, so the tray icon is up before the welcome message blocks.
        if (_settings.IsFirstRun) Post(ShowWelcome);
    }

    /// <summary>
    /// Runs work on the UI thread without waiting for it. Safe to call from any
    /// thread, and a no-op once quitting has started.
    /// </summary>
    private void Post(Action work)
    {
        if (_quitting) return;
        try
        {
            if (!_ui.IsDisposed && _ui.IsHandleCreated) _ui.BeginInvoke(work);
        }
        catch (Exception)
        {
            // The control went away between the check and the call.
        }
    }

    // MARK: The decision

    /// <summary>
    /// For the icon and the menu, on the UI thread. The input thread makes its
    /// own decisions, with its own watcher; see InputThread.
    /// </summary>
    private SuppressionDecision CurrentDecision() =>
        _rules.Decision(_watcher.Current());

    /// <summary>
    /// Builds the keyboard layout table for the layout in front, if it has
    /// changed, and hands it to the input thread. Never runs on the input
    /// thread; see KeyboardLayoutTable for why.
    /// </summary>
    private void BuildLayoutTable()
    {
        try
        {
            var window = Native.GetForegroundWindow();
            var thread = window != IntPtr.Zero ? Native.GetWindowThreadProcessId(window, out _) : 0;
            var layout = Native.GetKeyboardLayout(thread);
            if (layout != IntPtr.Zero && layout != _hook.LayoutHandle)
            {
                _hook.UseLayout(KeyboardLayoutTable.Build(layout));
            }
        }
        catch (Exception error)
        {
            Diagnostics.Log("reading the keyboard layout failed: " + error);
        }
    }

    private bool IsEnabled => _settings.ConversionEnabled ?? true;

    private void StartConverting()
    {
        // Started first and in the background, so the table is usually ready
        // before the first keystroke. Until it is, keys type nothing the buffer
        // records, which is the safe way to be wrong.
        ThreadPool.QueueUserWorkItem(_ => BuildLayoutTable());

        if (!_hook.Start())
        {
            Diagnostics.Log("SetWindowsHookEx refused the keyboard hook");
            MessageBox.Show(
                "Windows would not let LaTeX Squiggly watch the keyboard.\n\n"
                + "This usually means another tool already holds a low-level keyboard "
                + "hook, or the app was blocked by security software.",
                "LaTeX Squiggly", MessageBoxButtons.OK, MessageBoxIcon.Warning);
            return;
        }
        // Window titles are only read while conversion is actually running.
        _watcher.ReadsPages = true;
        _tabPoll?.Start();
        RefreshIcon();
    }

    private void StopConverting()
    {
        Diagnostics.Log("conversion switched off; " + _hook.Summary());
        _hook.Stop();
        _watcher.ReadsPages = false;
        _tabPoll?.Stop();
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
        _rules = _settings.Exclusions.Snapshot();
        _hook.ResetBuffer();
        RebuildMenu();
    }

    private void ShowNotice(string message)
    {
        if (!_settings.ShowNotices) return;
        // Logged without the message: a notice can quote what was typed.
        Diagnostics.Log("notice: showing");
        try
        {
            _notices.ShowNotice(message);
        }
        catch (Exception error)
        {
            Diagnostics.Log("notice: failed, " + error);
            return;
        }
        Diagnostics.Log("notice: shown");
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
        if (_quitting) return;
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

        // Clearing a menu does not dispose its items, and the menu is rebuilt
        // every time it opens, so without this each opening leaked a handful.
        var old = new ToolStripItem[menu.Items.Count];
        menu.Items.CopyTo(old, 0);
        menu.Items.Clear();
        foreach (var item in old) item.Dispose();

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

        var diagnostics = new ToolStripMenuItem("Copy diagnostics");
        diagnostics.Click += (_, _) => CopyDiagnostics();
        menu.Items.Add(diagnostics);

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

    /// <summary>
    /// A summary to paste into a bug report: version, architecture, whether the
    /// hook is in and how fast it has been, and which executable is in front.
    /// No window titles, no page titles, nothing typed.
    /// </summary>
    private void CopyDiagnostics()
    {
        var context = _watcher.Current();
        var decision = CurrentDecision();
        var text = string.Join(Environment.NewLine,
            "LaTeX Squiggly " + Application.ProductVersion,
            $"{Environment.OSVersion.VersionString}, {RuntimeInformation.ProcessArchitecture} process "
                + $"on {RuntimeInformation.OSArchitecture}",
            "conversion " + (IsEnabled ? "on" : "off") + ", " + _hook.Summary(),
            $"notices {(_settings.ShowNotices ? "on" : "off")}, {_settings.Exclusions.Apps.Count} apps and "
                + $"{_settings.Exclusions.Sites.Count} sites excluded",
            "in front: " + (context.ProcessName ?? "unknown") + ", " + (decision.Reason?.Summary ?? "converting"),
            "log: " + Diagnostics.Path_);
        try
        {
            Clipboard.SetText(text);
        }
        catch (Exception)
        {
            // Another program is holding the clipboard.
        }
        _notices.ShowNotice("Diagnostics copied to the clipboard.");
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
        Diagnostics.Log("quit from the tray menu; " + _hook.Summary());
        _quitting = true;
        _tabPoll.Stop();
        _tabPoll.Dispose();
        _hook.Dispose();
        _tray.Visible = false;
        _tray.Dispose();
        _notices.Dispose();
        _ui.Dispose();
        ExitThread();
    }

    protected override void Dispose(bool disposing)
    {
        if (disposing)
        {
            _quitting = true;
            _tabPoll?.Dispose();
            _hook.Dispose();
            _tray.Dispose();
            _notices.Dispose();
            _ui.Dispose();
        }
        base.Dispose(disposing);
    }
}
