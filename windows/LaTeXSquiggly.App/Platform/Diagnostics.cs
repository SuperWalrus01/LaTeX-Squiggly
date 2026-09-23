using System.Text;

namespace LaTeXSquiggly.App.Platform;

/// <summary>
/// A small running log, in <c>%APPDATA%\LaTeXSquiggly\log.txt</c>.
///
/// It exists because the worst failure this app has had, the hook thread
/// hanging and taking the machine's keyboard with it, left nothing behind: the
/// process was killed, so no exception handler ran. A log written as the app
/// goes, with a line at start and at exit, turns that into something a user can
/// attach to a bug report: if the last run never reached its exit line, the
/// next run says so, and quotes the last thing it did.
///
/// It records what the app did, never what was typed.
/// </summary>
internal static class Diagnostics
{
    /// <summary>
    /// Past this the log is cut to its newer half. Checked every 64 writes
    /// rather than every write, so the size check is not a file system call per
    /// line.
    /// </summary>
    private const long MaximumBytes = 256 * 1024;

    private static readonly object Gate = new();

    /// <summary>
    /// First-chance exceptions already logged. The same one thrown in a loop
    /// would otherwise fill the log with a single line.
    /// </summary>
    private static readonly HashSet<string> SeenFaults = new();

    private static int _writes;

    public static string Path_ => Path.Combine(Settings.Directory, "log.txt");

    /// <summary>
    /// Never throws. A diagnostic that can take the app down is worse than no
    /// diagnostic.
    /// </summary>
    public static void Log(string message)
    {
        try
        {
            lock (Gate)
            {
                Directory.CreateDirectory(Settings.Directory);
                if (++_writes % 64 == 0) Trim();
                File.AppendAllText(Path_, $"{DateTime.Now:HH:mm:ss.fff}  {message}{Environment.NewLine}");
            }
        }
        catch (Exception)
        {
            // Nothing useful left to do.
        }
    }

    /// <summary>
    /// Every exception, caught or not, the first time it is seen. Most are
    /// harmless and handled, but a caught exception on the input thread is
    /// exactly the kind of thing that explains a hang afterwards.
    /// </summary>
    public static void FirstChance(Exception error)
    {
        try
        {
            var key = error.GetType().FullName + "|" + error.Message;
            lock (Gate)
            {
                if (SeenFaults.Count > 40 || !SeenFaults.Add(key)) return;
            }
            var where = error.StackTrace?.Split('\n').FirstOrDefault()?.Trim() ?? "no stack";
            Log($"### {error.GetType().Name}: {error.Message}  at {where}");
        }
        catch (Exception)
        {
            // Nothing useful left to do.
        }
    }

    /// <summary>
    /// Starts a run's section of the log, first saying so if the previous run
    /// ended without reaching its exit line: the one sign left behind by a
    /// process that was killed rather than quit.
    /// </summary>
    public static void OpenSession(string header)
    {
        try
        {
            if (PreviousRunEndedAbruptly(out var lastLine))
            {
                Log("!!! the previous run was killed: it never reached its exit line.");
                Log("!!! the last thing it did was: " + lastLine);
            }
        }
        catch (Exception)
        {
            // A log that cannot be read is no reason not to start.
        }
        Log(header);
    }

    private static bool PreviousRunEndedAbruptly(out string lastLine)
    {
        lastLine = "nothing";
        if (!File.Exists(Path_)) return false;

        var lines = File.ReadAllLines(Path_);
        var lastStart = -1;
        var lastExit = -1;
        for (var i = 0; i < lines.Length; i++)
        {
            if (lines[i].Contains("--- started", StringComparison.Ordinal)) lastStart = i;
            if (lines[i].EndsWith("exiting", StringComparison.Ordinal)) lastExit = i;
        }
        if (lastStart < 0 || lastExit > lastStart) return false;

        for (var i = lines.Length - 1; i > lastStart; i--)
        {
            if (lines[i].Trim().Length != 0)
            {
                lastLine = lines[i];
                return true;
            }
        }
        lastLine = "nothing after starting";
        return true;
    }

    private static void Trim()
    {
        var file = new FileInfo(Path_);
        if (!file.Exists || file.Length <= MaximumBytes) return;

        var lines = File.ReadAllLines(Path_);
        var kept = new StringBuilder();
        for (var i = lines.Length / 2; i < lines.Length; i++) kept.AppendLine(lines[i]);
        File.WriteAllText(Path_, kept.ToString());
    }
}
