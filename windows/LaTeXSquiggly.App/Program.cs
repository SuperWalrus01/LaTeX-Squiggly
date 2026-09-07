using System.Windows.Forms;
using LaTeXSquiggly.App.Platform;

namespace LaTeXSquiggly.App;

internal static class Program
{
    /// <summary>
    /// Two copies of this app would each install a keyboard hook, and every
    /// command would be replaced twice. The mutex is what makes launching it
    /// again simply do nothing.
    /// </summary>
    private const string InstanceName = @"Local\LaTeXSquiggly.SingleInstance";

    [STAThread]
    private static void Main()
    {
        using var instance = new Mutex(initiallyOwned: true, InstanceName, out var isFirst);
        if (!isFirst)
        {
            MessageBox.Show(
                "LaTeX Squiggly is already running. Look for its mark near the clock.",
                "LaTeX Squiggly", MessageBoxButtons.OK, MessageBoxIcon.Information);
            return;
        }

        ApplicationConfiguration.Initialize();

        // A hook callback that throws takes the hook down with it, and the user
        // is left with an app that has silently stopped converting. Neither of
        // these should ever fire, but "should" is not a plan.
        Application.ThreadException += (_, e) => Report(e.Exception);
        AppDomain.CurrentDomain.UnhandledException += (_, e) => Report(e.ExceptionObject as Exception);

        Application.Run(new TrayApplication());
    }

    private static void Report(Exception? error)
    {
        if (error is null) return;
        try
        {
            var log = Path.Combine(Settings.Directory, "crash.log");
            Directory.CreateDirectory(Settings.Directory);
            File.AppendAllText(log, $"{DateTime.Now:u}  {error}\n\n");
            MessageBox.Show(
                $"LaTeX Squiggly hit an error and may have stopped converting.\n\n{error.Message}\n\n"
                + $"Details were written to {log}",
                "LaTeX Squiggly", MessageBoxButtons.OK, MessageBoxIcon.Error);
        }
        catch (Exception)
        {
            // Nothing useful left to do.
        }
    }
}
