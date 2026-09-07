namespace LaTeXSquiggly.Core.Suppression;

/// <summary>
/// Browsers whose page the app tries to identify before converting.
///
/// An app that is not on this list is treated as an ordinary application: its
/// executable name is checked against the exclusion list and that is all. So a
/// browser missing from here does not misbehave, it simply gets no site rules,
/// and the user's fallback is to exclude the whole browser, which the tray menu
/// makes a one-click job.
///
/// Names are without the .exe and compared case-insensitively, because Windows
/// filenames are.
/// </summary>
public static class KnownBrowsers
{
    public static readonly IReadOnlySet<string> ProcessNames =
        new HashSet<string>(StringComparer.OrdinalIgnoreCase)
        {
            // Chromium
            "chrome", "msedge", "brave", "vivaldi", "opera", "opera_gx",
            "chromium", "arc", "dia", "whale", "comet", "sidekick",
            "duckduckgo", "yandex", "thorium", "ungoogled-chromium",

            // Gecko
            "firefox", "waterfox", "librewolf", "floorp", "zen", "tor browser",
            "palemoon", "basilisk",

            // Other
            "iexplore", "safari",
        };

    public static bool IsBrowser(string? processName) =>
        processName is not null && ProcessNames.Contains(processName);
}
