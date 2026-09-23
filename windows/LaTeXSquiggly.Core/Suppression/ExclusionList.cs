using System.Text.Json.Serialization;

namespace LaTeXSquiggly.Core.Suppression;

/// <summary>
/// An application the app must stay silent in, identified by its executable
/// name because that is the most stable name a Windows app has.
/// </summary>
public sealed class ExcludedApp
{
    /// <summary>Executable name without .exe, lowercased, such as "texstudio".</summary>
    public string ProcessName { get; set; } = "";

    /// <summary>Display only, so the editor shows a readable row.</summary>
    public string Name { get; set; } = "";

    public ExcludedApp() { }

    public ExcludedApp(string processName, string name)
    {
        ProcessName = processName.ToLowerInvariant();
        Name = name;
    }
}

/// <summary>
/// A website the app must stay silent on, for the case the whole exclusion list
/// exists to solve: Overleaf is not an app, it is a tab.
/// </summary>
public sealed class ExcludedSite
{
    /// <summary>A host such as overleaf.com. Matches it and any subdomain.</summary>
    public string Host { get; set; } = "";

    /// <summary>
    /// Matched against the window title, case-insensitively. On Windows this
    /// carries the weight, because the title is all a browser reliably offers.
    /// </summary>
    public List<string> TitleFragments { get; set; } = new();

    public ExcludedSite() { }

    public ExcludedSite(string host, params string[] titleFragments)
    {
        Host = host;
        TitleFragments = titleFragments.ToList();
    }
}

public enum SuppressionReasonKind { ExcludedApp, ExcludedSite, ExcludedSiteTitle, UnidentifiedPage }

public sealed record SuppressionReason(SuppressionReasonKind Kind, string Subject)
{
    /// <summary>Completes the sentence "off in Safari, ...".</summary>
    public string Explanation => Kind switch
    {
        SuppressionReasonKind.ExcludedApp => $"{Subject} is on the exclusion list",
        SuppressionReasonKind.ExcludedSite => $"{Subject} is on the exclusion list",
        SuppressionReasonKind.ExcludedSiteTitle => $"this window looks like {Subject}",
        _ => $"{Subject} will not say which page is open",
    };

    /// <summary>Short enough for a menu row.</summary>
    public string Summary => Kind switch
    {
        SuppressionReasonKind.ExcludedApp => $"Off in {Subject}",
        SuppressionReasonKind.ExcludedSite => $"Off on {Subject}",
        SuppressionReasonKind.ExcludedSiteTitle => $"Off, looks like {Subject}",
        _ => "Off, page unknown",
    };
}

public sealed record SuppressionDecision(SuppressionReason? Reason)
{
    public static readonly SuppressionDecision Convert = new((SuppressionReason?)null);

    public static SuppressionDecision Suppress(SuppressionReason reason) => new(reason);

    public bool IsSuppressed => Reason is not null;
}

/// <summary>The user's exclusions, persisted whole.</summary>
public sealed class ExclusionList
{
    public List<ExcludedApp> Apps { get; set; } = new();

    public List<ExcludedSite> Sites { get; set; } = new();

    /// <summary>
    /// What to do in a browser whose page we cannot identify at all.
    ///
    /// Defaults to suppressing. An app which corrupts LaTeX source is worse than
    /// no app, and "I do not know what page this is" is not a good enough reason
    /// to start rewriting text.
    /// </summary>
    public bool SuppressUnidentifiedPages { get; set; } = true;

    /// <summary>
    /// Executables the user has deleted from the list. Kept so that discovery
    /// does not helpfully put them back every launch.
    /// </summary>
    public List<string> DeclinedProcessNames { get; set; } = new();

    [JsonIgnore]
    public int Version => 1;

    // MARK: Editing

    public bool Contains(string processName) => Find(processName) is not null;

    /// <summary>
    /// A plain loop rather than LINQ. This is on the path every keystroke takes
    /// and a lambda here allocates a closure per call, which over a day of
    /// typing is a garbage collection that did not need to happen.
    /// </summary>
    private ExcludedApp? Find(string processName)
    {
        foreach (var app in Apps)
        {
            if (string.Equals(app.ProcessName, processName, StringComparison.OrdinalIgnoreCase))
            {
                return app;
            }
        }
        return null;
    }

    /// <summary>
    /// A copy nobody is going to edit.
    ///
    /// The hook runs on its own thread and reads these rules on every keystroke;
    /// the settings window adds, removes and sorts them from the UI thread.
    /// Rather than lock the two together, which would put the settings window in
    /// front of the machine's keyboard, the app hands the hook a snapshot and
    /// replaces it wholesale when the user changes something.
    /// </summary>
    public ExclusionList Snapshot()
    {
        var copy = new ExclusionList
        {
            SuppressUnidentifiedPages = SuppressUnidentifiedPages,
            Apps = new List<ExcludedApp>(Apps),
            DeclinedProcessNames = new List<string>(DeclinedProcessNames),
            Sites = new List<ExcludedSite>(Sites.Count),
        };
        foreach (var site in Sites)
        {
            copy.Sites.Add(new ExcludedSite
            {
                Host = site.Host,
                TitleFragments = new List<string>(site.TitleFragments),
            });
        }
        return copy;
    }

    public void Add(ExcludedApp app)
    {
        if (Contains(app.ProcessName)) return;
        Apps.Add(app);
        Apps.Sort((a, b) => string.Compare(a.Name, b.Name, StringComparison.CurrentCultureIgnoreCase));
        DeclinedProcessNames.RemoveAll(
            name => string.Equals(name, app.ProcessName, StringComparison.OrdinalIgnoreCase));
    }

    /// <summary>Removing is remembered: see DeclinedProcessNames.</summary>
    public void RemoveApp(string processName)
    {
        Apps.RemoveAll(app => string.Equals(app.ProcessName, processName, StringComparison.OrdinalIgnoreCase));
        if (!DeclinedProcessNames.Any(
                name => string.Equals(name, processName, StringComparison.OrdinalIgnoreCase)))
        {
            DeclinedProcessNames.Add(processName.ToLowerInvariant());
        }
    }

    public void Add(ExcludedSite site)
    {
        var host = NormalisedHost(site.Host);
        if (host is null) return;
        foreach (var existing in Sites)
        {
            if (existing.Host == host) return;
        }
        Sites.Add(new ExcludedSite { Host = host, TitleFragments = site.TitleFragments });
        Sites.Sort((a, b) => string.CompareOrdinal(a.Host, b.Host));
    }

    public void RemoveSite(string host) => Sites.RemoveAll(site => site.Host == host);

    // MARK: The decision

    /// <summary>
    /// The whole point of the module.
    ///
    /// Order matters: an app rule beats everything, because a user who excluded
    /// their whole browser meant it. Only then do we look at the page.
    /// </summary>
    public SuppressionDecision Decision(TypingContext context)
    {
        if (context.ProcessName is not null)
        {
            var app = Find(context.ProcessName);
            if (app is not null)
            {
                return SuppressionDecision.Suppress(
                    new SuppressionReason(SuppressionReasonKind.ExcludedApp, app.Name));
            }
        }

        if (context.Page is null) return SuppressionDecision.Convert;

        switch (context.Page.Kind)
        {
            case BrowserPageKind.Url:
            {
                var host = HostOfUrl(context.Page.Value!);
                if (host is null)
                {
                    // A URL we cannot parse tells us nothing, so it is treated
                    // exactly like a page we could not read at all.
                    return UnidentifiedPageDecision(context);
                }
                ExcludedSite? site = null;
                foreach (var candidate in Sites)
                {
                    if (HostMatches(host, candidate.Host)) { site = candidate; break; }
                }
                return site is not null
                    ? SuppressionDecision.Suppress(
                        new SuppressionReason(SuppressionReasonKind.ExcludedSite, site.Host))
                    : SuppressionDecision.Convert;
            }

            case BrowserPageKind.Title:
            {
                var title = context.Page.Value!;
                // Ordinal, not culture-aware. The fragments are ASCII product
                // names, a culture-aware Contains is an ICU call per fragment per
                // check, and a culture-aware answer here would mean the app could
                // behave differently on a Turkish machine than on an English one.
                var site = SiteMatchingTitle(title);
                if (site is not null)
                {
                    return SuppressionDecision.Suppress(
                        new SuppressionReason(SuppressionReasonKind.ExcludedSiteTitle, site.Host));
                }
                // A title we could read that matches nothing is a real answer,
                // not an absence of one. Converting here is what keeps the app
                // usable in a browser at all.
                return SuppressionDecision.Convert;
            }

            default:
                return UnidentifiedPageDecision(context);
        }
    }

    private ExcludedSite? SiteMatchingTitle(string title)
    {
        foreach (var candidate in Sites)
        {
            foreach (var fragment in candidate.TitleFragments)
            {
                if (fragment.Length > 0
                    && title.Contains(fragment, StringComparison.OrdinalIgnoreCase))
                {
                    return candidate;
                }
            }
        }
        return null;
    }

    private SuppressionDecision UnidentifiedPageDecision(TypingContext context) =>
        SuppressUnidentifiedPages
            ? SuppressionDecision.Suppress(
                new SuppressionReason(SuppressionReasonKind.UnidentifiedPage, context.DisplayName))
            : SuppressionDecision.Convert;

    // MARK: Host matching

    /// <summary>
    /// A lowercased host, or null if there is not one: about:blank and
    /// chrome://newtab have none, and neither does a malformed string.
    /// </summary>
    public static string? HostOfUrl(string text)
    {
        if (!Uri.TryCreate(text, UriKind.Absolute, out var uri)) return null;
        return string.IsNullOrEmpty(uri.Host) ? null : uri.Host.ToLowerInvariant();
    }

    /// <summary>
    /// overleaf.com matches overleaf.com and www.overleaf.com, but not
    /// notoverleaf.com and not overleaf.com.example.net. The dot is what makes
    /// the difference and it is easy to leave out by accident.
    /// </summary>
    public static bool HostMatches(string host, string pattern)
    {
        host = host.ToLowerInvariant();
        pattern = pattern.ToLowerInvariant();
        return host == pattern || host.EndsWith("." + pattern, StringComparison.Ordinal);
    }

    /// <summary>
    /// Accepts what a user is likely to paste, a full URL or a host with a www.
    /// or a trailing slash, and returns the bare host.
    /// </summary>
    public static string? NormalisedHost(string input)
    {
        var text = input.Trim().ToLowerInvariant();
        if (text.Length == 0) return null;

        var host = HostOfUrl(text);
        if (host is not null)
        {
            text = host;
        }
        else
        {
            // No scheme, so it parses as a path rather than a host. Take
            // everything before the first slash.
            var slash = text.IndexOf('/');
            if (slash >= 0) text = text[..slash];
        }
        if (text.StartsWith("www.", StringComparison.Ordinal)) text = text[4..];

        // A host has at least one dot and no spaces. Anything else is a typo,
        // and a rule that matches nothing is worse than a refused one.
        if (!text.Contains('.') || text.Contains(' ')
            || text.StartsWith('.') || text.EndsWith('.'))
        {
            return null;
        }
        return text;
    }
}
