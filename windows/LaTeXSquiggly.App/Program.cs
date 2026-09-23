using System.Runtime.InteropServices;
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
        // The error handlers go in first, before anything that can throw. They
        // used to be registered after the single-instance check and after
        // start-up had begun, so a failure in either closed the app with no
        // message and no line in the log: it simply vanished at launch.
        AppDomain.CurrentDomain.UnhandledException += (_, e) => Report(e.ExceptionObject as Exception);
        AppDomain.CurrentDomain.FirstChanceException += (_, e) => Diagnostics.FirstChance(e.Exception);
        Application.SetUnhandledExceptionMode(UnhandledExceptionMode.CatchException);
        Application.ThreadException += (_, e) => Report(e.Exception);

        Mutex instance;
        bool isFirst;
        try
        {
            instance = new Mutex(initiallyOwned: true, InstanceName, out isFirst);
        }
        catch (Exception error)
        {
            // Opening the mutex is refused when another copy created it with
            // different rights, which is what happens when that copy is running
            // as administrator.
            Diagnostics.Log("could not open the single-instance mutex: " + error.Message);
            MessageBox.Show(
                "LaTeX Squiggly could not start, because another copy of it seems to be running "
                + "with different rights, for example as administrator.\n\n"
                + "Quit that copy from its tray menu, or end LaTeX Squiggly in Task Manager, "
                + "then start it again.",
                "LaTeX Squiggly", MessageBoxButtons.OK, MessageBoxIcon.Warning);
            return;
        }

        using (instance)
        {
            if (!isFirst)
            {
                // A copy that has hung is still running even though its tray
                // icon is gone: Explorer removes the icon of a process that has
                // stopped responding. So say where to look.
                MessageBox.Show(
                    "LaTeX Squiggly is already running. Look for its mark near the clock.\n\n"
                    + "If you cannot find it, it may have stopped responding: end LaTeX Squiggly "
                    + "in Task Manager, then start it again.",
                    "LaTeX Squiggly", MessageBoxButtons.OK, MessageBoxIcon.Information);
                return;
            }

            ApplicationConfiguration.Initialize();

            // The start line and the exit line are how the next run tells a quit
            // from a kill; see Diagnostics.
            Diagnostics.OpenSession(
                $"--- started, version {Application.ProductVersion}, {RuntimeInformation.ProcessArchitecture} "
                + $"on {RuntimeInformation.OSArchitecture}, {Environment.OSVersion.VersionString}");
            Application.ApplicationExit += (_, _) => Diagnostics.Log("exiting");
            AppDomain.CurrentDomain.ProcessExit += (_, _) => Diagnostics.Log("exiting");

            TrayApplication tray;
            try
            {
                tray = new TrayApplication();
            }
            catch (Exception error)
            {
                // Start-up runs before the message loop, where ThreadException
                // cannot catch it. Report it here, in words, rather than let the
                // process end on an unhandled exception.
                Diagnostics.Log("start-up failed: " + error);
                Report(error);
                return;
            }

            Application.Run(tray);

            // The mutex must outlive the message loop, or a second copy could
            // start while this one is still running.
            GC.KeepAlive(instance);
        }
    }

    private static void Report(Exception? error)
    {
        if (error is null) return;
        try
        {
            var log = Path.Combine(Settings.Directory, "crash.log");
            Directory.CreateDirectory(Settings.Directory);
            File.AppendAllText(log, $"{DateTime.Now:u}  {error}\n\n");
            Diagnostics.Log("unhandled: " + error.Message);
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
