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
/// two syscalls, so this answers freshly every time it is asked; how often it is
/// asked is the input thread's decision.
///
/// It runs on the input thread, so it does not allocate once warm: the title and
/// the executable path are read into buffers it keeps, and everything worked
/// out about a process is cached together.
/// </summary>
internal sealed class ForegroundWatcher
{
    /// <summary>What is worked out once per process, rather than per question.</summary>
    private readonly record struct Identity(string ProcessName, string DisplayName, bool IsBrowser);

    /// <summary>
    /// Keyed by process id rather than window handle. Windows reuses window
    /// handles freely, and a stale name here would mean converting inside an
    /// app the user excluded, which is the one mistake this whole feature
    /// exists to prevent. Process ids are reused far more slowly, and the entry
    /// is re-read whenever the id is not one we have seen.
    /// </summary>
    private readonly Dictionary<uint, Identity> _identities = new();

    /// <summary>
    /// Room for the page titles that matter. A longer title is cut short, which
    /// costs nothing: the rules match on a product name near its end or start,
    /// never on the 512th character.
    /// </summary>
    private readonly char[] _title = new char[512];

    private readonly char[] _path = new char[1024];

    /// <summary>Whether to look inside browsers. Off while conversion is off.</summary>
    public bool ReadsPages { get; set; }

    public TypingContext Current() => Current(Native.GetForegroundWindow());

    /// <summary>
    /// The context for a given window. The input thread passes the window it
    /// was told about by the foreground event, so the answer is about the
    /// window that just came to the front, not whichever is in front by the
    /// time this runs.
    /// </summary>
    public TypingContext Current(IntPtr window)
    {
        if (window == IntPtr.Zero) return TypingContext.Unknown;

        Native.GetWindowThreadProcessId(window, out var pid);
        if (pid == 0) return TypingContext.Unknown;

        // Bounded rather than allowed to grow into a map of every process the
        // user has focused since login.
        if (_identities.Count > 64) _identities.Clear();

        if (!_identities.TryGetValue(pid, out var identity))
        {
            var processName = ProcessNameOf(pid);
            identity = new Identity(processName, DisplayNameFor(processName), KnownBrowsers.IsBrowser(processName));
            _identities[pid] = identity;
        }
        if (identity.ProcessName.Length == 0) return TypingContext.Unknown;

        if (!ReadsPages || !identity.IsBrowser)
        {
            return new TypingContext(identity.ProcessName, identity.DisplayName);
        }

        var title = TitleOf(window, _title);
        var page = title is not null ? BrowserPage.Title(title) : BrowserPage.Unreadable;
        return new TypingContext(identity.ProcessName, identity.DisplayName, page);
    }

    /// <summary>The window title, which for a browser is the page title, or null if there is none.</summary>
    public static string? TitleOf(IntPtr window, char[] buffer)
    {
        var written = Native.GetWindowTextW(window, buffer, buffer.Length);
        if (written <= 0) return null;
        return new string(buffer, 0, Math.Min(written, buffer.Length));
    }

    /// <summary>
    /// The executable name, lowercased and without .exe, which is the closest
    /// thing Windows has to a bundle identifier: stable, not localised, and
    /// readable without asking the app anything.
    ///
    /// The file name is cut out of the path by hand rather than with
    /// Path.GetFileNameWithoutExtension, which would allocate the whole path as
    /// a string first.
    /// </summary>
    private string ProcessNameOf(uint pid)
    {
        var handle = Native.OpenProcess(Native.PROCESS_QUERY_LIMITED_INFORMATION, false, pid);
        if (handle == IntPtr.Zero) return "";
        try
        {
            var size = (uint)_path.Length;
            if (!Native.QueryFullProcessImageNameW(handle, 0, _path, ref size)) return "";
            if (size == 0 || size > _path.Length) return "";

            var length = (int)size;
            var dot = -1;
            var separator = -1;
            for (var i = length - 1; i >= 0; i--)
            {
                if (_path[i] == '\\' || _path[i] == '/')
                {
                    separator = i;
                    break;
                }
                if (dot < 0 && _path[i] == '.') dot = i;
            }
            var start = separator + 1;
            var end = dot > start ? dot : length;
            return end <= start ? "" : new string(_path, start, end - start).ToLowerInvariant();
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
