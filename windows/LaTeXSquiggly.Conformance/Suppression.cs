using LaTeXSquiggly.Core.Suppression;

namespace LaTeXSquiggly.Conformance;

/// <summary>
/// Checks for the part of the port that has no Swift counterpart to be compared
/// against.
///
/// The engine is proved correct by replaying the Swift reference. The
/// suppression rules cannot be: the Mac identifies an app by its bundle
/// identifier and reads a browser's URL, Windows identifies an app by its
/// executable and reads the window title. So the rules were rewritten, and
/// rewritten logic that decides whether to rewrite somebody's LaTeX source
/// deserves its own checks.
/// </summary>
internal static class SuppressionChecks
{
    public static (int Passed, List<string> Failures) Run()
    {
        var failures = new List<string>();
        var passed = 0;

        void Expect(bool condition, string label)
        {
            if (condition) passed += 1;
            else failures.Add("  " + label);
        }

        void Suppressed(ExclusionList list, TypingContext context, string label)
            => Expect(list.Decision(context).IsSuppressed, "should stay quiet: " + label);

        void Converts(ExclusionList list, TypingContext context, string label)
            => Expect(!list.Decision(context).IsSuppressed, "should convert: " + label);

        var list = DefaultExclusions.Fresh();

        // MARK: Apps

        Suppressed(list, new TypingContext("texstudio", "TeXstudio"), "TeXstudio is a TeX editor");
        Suppressed(list, new TypingContext("code", "Visual Studio Code"), "VS Code");
        Suppressed(list, new TypingContext("TEXSTUDIO", "TeXstudio"), "Windows names are case-insensitive");
        Converts(list, new TypingContext("slack", "Slack"), "Slack is where the app is for");
        Converts(list, new TypingContext(null), "no foreground app at all");

        // MARK: Browsers, by window title

        var chrome = "chrome";
        Suppressed(list,
            new TypingContext(chrome, "Chrome",
                BrowserPage.Title("Thesis - Overleaf, Online LaTeX Editor - Google Chrome")),
            "an Overleaf tab");
        Suppressed(list,
            new TypingContext(chrome, "Chrome", BrowserPage.Title("my paper - ShareLaTeX")),
            "a ShareLaTeX tab");
        Converts(list,
            new TypingContext(chrome, "Chrome", BrowserPage.Title("Slack | general | Acme")),
            "an ordinary tab");
        Suppressed(list,
            new TypingContext(chrome, "Chrome", BrowserPage.Unreadable),
            "a browser window with no title, by default");

        // The trade the default makes has to be reversible.
        var permissive = DefaultExclusions.Fresh();
        permissive.SuppressUnidentifiedPages = false;
        Converts(permissive,
            new TypingContext(chrome, "Chrome", BrowserPage.Unreadable),
            "an unreadable page once the user has said so");

        // An app rule beats a page rule, because a user who excluded their whole
        // browser meant it.
        var browserExcluded = DefaultExclusions.Fresh();
        browserExcluded.Add(new ExcludedApp(chrome, "Chrome"));
        Suppressed(browserExcluded,
            new TypingContext(chrome, "Chrome", BrowserPage.Title("Slack | general")),
            "an excluded browser, whatever the tab");

        // MARK: Host matching

        Expect(ExclusionList.HostMatches("overleaf.com", "overleaf.com"), "exact host");
        Expect(ExclusionList.HostMatches("www.overleaf.com", "overleaf.com"), "subdomain");
        Expect(ExclusionList.HostMatches("fr.overleaf.com", "overleaf.com"), "any subdomain");
        Expect(!ExclusionList.HostMatches("notoverleaf.com", "overleaf.com"), "not a suffix match");
        Expect(!ExclusionList.HostMatches("overleaf.com.example.net", "overleaf.com"), "not a prefix match");

        Expect(ExclusionList.NormalisedHost("https://www.overleaf.com/project/1") == "overleaf.com",
               "a pasted URL becomes a host");
        Expect(ExclusionList.NormalisedHost("Overleaf.com/") == "overleaf.com", "case and slash");
        Expect(ExclusionList.NormalisedHost("overleaf") is null, "a bare word is not a host");
        Expect(ExclusionList.NormalisedHost("two words.com") is null, "spaces are a typo");
        Expect(ExclusionList.NormalisedHost("") is null, "nothing is not a host");
        Expect(ExclusionList.NormalisedHost(".com") is null, "a leading dot is a typo");

        // MARK: Removing is remembered

        var edited = DefaultExclusions.Fresh();
        edited.RemoveApp("texstudio");
        Expect(!edited.Contains("texstudio"), "removing takes it out");
        Expect(edited.DeclinedProcessNames.Contains("texstudio"), "and remembers that it was removed");
        edited.Add(new ExcludedApp("texstudio", "TeXstudio"));
        Expect(!edited.DeclinedProcessNames.Contains("texstudio"), "adding it back forgets the removal");

        // MARK: The defaults themselves

        Expect(DefaultExclusions.Apps.All(app => app.Process == app.Process.ToLowerInvariant()),
               "every default executable name is lowercased, because matching assumes it");
        Expect(DefaultExclusions.Apps.All(app => !app.Process.EndsWith(".exe", StringComparison.OrdinalIgnoreCase)),
               "no default carries a .exe, because the watcher strips it");
        Expect(DefaultExclusions.Apps.Select(app => app.Process).Distinct().Count()
               == DefaultExclusions.Apps.Length,
               "no default is listed twice");
        Expect(!DefaultExclusions.Apps.Any(app => KnownBrowsers.IsBrowser(app.Process)),
               "no app is both excluded by default and treated as a browser");
        Expect(DefaultExclusions.Sites().All(site => site.TitleFragments.Count > 0),
               "every default site has a title fragment, which is all Windows gets");

        // MARK: A settings file with nulls in it

        // Hand-edited or damaged settings used to load and then throw during
        // start-up, which closed the app before it showed anything.
        const string damaged = """
            {
              "Apps": [ null, { "ProcessName": "texstudio", "Name": null }, { "ProcessName": null } ],
              "Sites": [ { "Host": null }, { "Host": "overleaf.com", "TitleFragments": null },
                         { "Host": "cocalc.com", "TitleFragments": [ "CoCalc", null ] } ],
              "DeclinedProcessNames": null
            }
            """;
        var repaired = System.Text.Json.JsonSerializer.Deserialize<ExclusionList>(damaged)!;
        repaired.Repair();
        Expect(repaired.Apps.Count == 1 && repaired.Apps[0].Name == "texstudio",
               "repair keeps the one real app and names it after its executable");
        Expect(repaired.Sites.Count == 2, "repair drops the site with no host and keeps the others");
        Expect(repaired.Sites.All(site => site.TitleFragments is not null && !site.TitleFragments.Contains(null!)),
               "repair leaves no null title fragments");
        Expect(repaired.DeclinedProcessNames is not null, "repair replaces a null list with an empty one");

        var threw = false;
        try
        {
            var snapshot = repaired.Snapshot();
            snapshot.Decision(new TypingContext("texstudio", "TeXstudio"));
            snapshot.Decision(new TypingContext(chrome, "Chrome", BrowserPage.Title("Draft - CoCalc - Google Chrome")));
            snapshot.Decision(new TypingContext(chrome, "Chrome", BrowserPage.Title("Slack")));
        }
        catch (Exception)
        {
            threw = true;
        }
        Expect(!threw, "a repaired list can be snapshotted and asked for decisions without throwing");
        Suppressed(repaired.Snapshot(), new TypingContext("texstudio", "TeXstudio"),
                   "a repaired list still excludes what it listed");
        Suppressed(repaired.Snapshot(),
                   new TypingContext(chrome, "Chrome", BrowserPage.Title("Draft - CoCalc - Google Chrome")),
                   "a repaired site still matches its surviving title fragment");

        var empty = new ExclusionList { Apps = null!, Sites = null!, DeclinedProcessNames = null! };
        empty.Repair();
        Expect(empty.Apps.Count == 0 && empty.Sites.Count == 0, "repair turns null lists into empty ones");

        return (passed, failures);
    }
}
