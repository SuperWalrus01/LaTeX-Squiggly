using System.Text;
using LaTeXSquiggly.Core.Suppression;

namespace LaTeXSquiggly.App.Platform;

/// <summary>
/// Tracks which application the user is typing into, and which page if that
/// application is a browser.
///
/// The Mac has to work hard here: reading a browser's URL means walking another
/// process's accessibility tree, which is slow enough that the Mac app keeps a
/// cached answer for the fast path and a verified one for the moment before it
/// types. Windows hands over the foreground window and its title for the cost of
/// two syscalls, so this can simply answer freshly every time and the whole
/// stale-cache problem does not arise.
///
/// The one expensive part, turning a process id into a name, is cached per
/// window handle.
/// </summary>
internal sealed class ForegroundWatcher
{
    /// <summary>
    /// Keyed by process id rather than window handle. Windows reuses window
    /// handles freely, and a stale name here would mean converting inside an
    /// app the user excluded, which is the one mistake this whole feature
    /// exists to prevent. Process ids are reused far more slowly, and the entry
    /// is re-read whenever the id is not one we have seen.
    /// </summary>
    private readonly Dictionary<uint, string> _processNames = new();

    /// <summary>Whether to look inside browsers. Off while conversion is off.</summary>
    public bool ReadsPages { get; set; }

    public TypingContext Current()
    {
        var window = Native.GetForegroundWindow();
        if (window == IntPtr.Zero) return new TypingContext(null);

        Native.GetWindowThreadProcessId(window, out var pid);
        if (pid == 0) return new TypingContext(null);

        // Bounded rather than allowed to grow into a map of every process the
        // user has focused since login.
        if (_processNames.Count > 64) _processNames.Clear();

        if (!_processNames.TryGetValue(pid, out var processName))
        {
            processName = ProcessNameOf(pid);
            _processNames[pid] = processName;
        }
        if (processName.Length == 0) return new TypingContext(null);

        var display = DisplayNameFor(processName);
        if (!ReadsPages || !KnownBrowsers.IsBrowser(processName))
        {
            return new TypingContext(processName, display);
        }

        var title = TitleOf(window);
        var page = title.Length > 0 ? BrowserPage.Title(title) : BrowserPage.Unreadable;
        return new TypingContext(processName, display, page);
    }

    /// <summary>The window title, which for a browser is the page title.</summary>
    public static string TitleOf(IntPtr window)
    {
        var length = Native.GetWindowTextLengthW(window);
        if (length <= 0) return "";
        var builder = new StringBuilder(length + 1);
        var written = Native.GetWindowTextW(window, builder, builder.Capacity);
        return written > 0 ? builder.ToString() : "";
    }

    /// <summary>
    /// The executable name, lowercased and without .exe, which is the closest
    /// thing Windows has to a bundle identifier: stable, not localised, and
    /// readable without asking the app anything.
    /// </summary>
    private static string ProcessNameOf(uint pid)
    {
        var handle = Native.OpenProcess(Native.PROCESS_QUERY_LIMITED_INFORMATION, false, pid);
        if (handle == IntPtr.Zero) return "";
        try
        {
            var size = 1024u;
            var builder = new StringBuilder((int)size);
            if (!Native.QueryFullProcessImageNameW(handle, 0, builder, ref size)) return "";
            return Path.GetFileNameWithoutExtension(builder.ToString()).ToLowerInvariant();
        }
        catch (Exception)
        {
            return "";
        }
        finally
        {
            Native.CloseHandle(handle);
        }
    }

    /// <summary>
    /// A name to put in a sentence. The executable name is what rules match on,
    /// but "texstudio" is a poor thing to show a person, so a known one is given
    /// its proper name and anything else is simply capitalised.
    /// </summary>
    public static string DisplayNameFor(string processName)
    {
        foreach (var (process, name) in DefaultExclusions.Apps)
        {
            if (string.Equals(process, processName, StringComparison.OrdinalIgnoreCase)) return name;
        }
        if (processName.Length == 0) return "this app";
        return char.ToUpperInvariant(processName[0]) + processName[1..];
    }
}
