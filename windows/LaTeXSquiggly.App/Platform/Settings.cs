using System.Text.Json;
using System.Text.Json.Serialization;
using LaTeXSquiggly.Core.Suppression;
using Microsoft.Win32;

namespace LaTeXSquiggly.App.Platform;

/// <summary>
/// Everything the app remembers between launches, in one JSON file under
/// %APPDATA%\LaTeXSquiggly.
///
/// Every field is optional on the way in and falls back to its own default.
/// That is deliberate: the Mac version's settings could be silently wiped by any
/// later build that added a field, because its decoder demanded every key and
/// the failure was swallowed. Losing the exclusion list is the one setting loss
/// that can go on to corrupt a document, so it is worth the care.
/// </summary>
internal sealed class Settings
{
    /// <summary>
    /// Null marks a first run, which is what triggers the welcome. A default
    /// of false here would be indistinguishable from a user who turned it off.
    /// </summary>
    public bool? ConversionEnabled { get; set; }

    public bool ShowNotices { get; set; } = true;

    public ExclusionList Exclusions { get; set; } = new();

    [JsonIgnore]
    public bool IsFirstRun => ConversionEnabled is null;

    // MARK: Persistence

    private static readonly JsonSerializerOptions Options = new()
    {
        WriteIndented = true,
        DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull,
    };

    public static string Directory =>
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),
                     "LaTeXSquiggly");

    public static string Path_ => Path.Combine(Directory, "settings.json");

    public static Settings Load()
    {
        try
        {
            if (File.Exists(Path_))
            {
                var loaded = JsonSerializer.Deserialize<Settings>(File.ReadAllText(Path_), Options);
                if (loaded is not null)
                {
                    // A file that predates the exclusion list, or one written by
                    // hand, still has to come back usable.
                    loaded.Exclusions ??= DefaultExclusions.Fresh();
                    if (loaded.Exclusions.Apps.Count == 0 && loaded.Exclusions.Sites.Count == 0
                        && loaded.Exclusions.DeclinedProcessNames.Count == 0)
                    {
                        loaded.Exclusions = DefaultExclusions.Fresh();
                    }
                    return loaded;
                }
            }
        }
        catch (Exception)
        {
            // A corrupt file is not a reason to refuse to start. The defaults
            // are the safe end of every setting in here.
        }
        return new Settings { Exclusions = DefaultExclusions.Fresh() };
    }

    public void Save()
    {
        try
        {
            System.IO.Directory.CreateDirectory(Directory);
            File.WriteAllText(Path_, JsonSerializer.Serialize(this, Options));
        }
        catch (Exception)
        {
            // Nothing here is worth interrupting the user's typing over.
        }
    }

    /// <summary>
    /// Adds rules for the default apps, skipping anything the user has removed.
    /// Runs on every launch rather than only the first, so an editor installed
    /// later is covered without the user thinking about it.
    /// </summary>
    public bool DiscoverDefaults()
    {
        var changed = false;
        foreach (var (process, name) in DefaultExclusions.Apps)
        {
            if (Exclusions.DeclinedProcessNames.Any(
                    declined => string.Equals(declined, process, StringComparison.OrdinalIgnoreCase)))
            {
                continue;
            }
            if (Exclusions.Contains(process)) continue;
            Exclusions.Add(new ExcludedApp(process, name));
            changed = true;
        }
        foreach (var site in DefaultExclusions.Sites())
        {
            if (Exclusions.Sites.Any(existing => existing.Host == site.Host)) continue;
            Exclusions.Add(site);
            changed = true;
        }
        return changed;
    }
}

/// <summary>
/// Open at login, which on Windows is one registry value under the current
/// user. No elevation, and nothing that outlives uninstalling the exe.
/// </summary>
internal static class LoginItem
{
    private const string Key = @"Software\Microsoft\Windows\CurrentVersion\Run";
    private const string Value = "LaTeX Squiggly";

    public static bool IsEnabled
    {
        get
        {
            try
            {
                using var key = Registry.CurrentUser.OpenSubKey(Key);
                return key?.GetValue(Value) is not null;
            }
            catch (Exception) { return false; }
        }
    }

    /// <returns>Null on success, or a sentence to show the user.</returns>
    public static string? SetEnabled(bool enabled)
    {
        try
        {
            using var key = Registry.CurrentUser.CreateSubKey(Key);
            if (key is null) return "Windows would not let the app write its startup setting.";
            if (enabled)
            {
                var exe = Environment.ProcessPath;
                if (exe is null) return "The app could not work out where it is installed.";
                key.SetValue(Value, "\"" + exe + "\"");
            }
            else
            {
                key.DeleteValue(Value, throwOnMissingValue: false);
            }
            return null;
        }
        catch (Exception error)
        {
            return error.Message;
        }
    }
}
