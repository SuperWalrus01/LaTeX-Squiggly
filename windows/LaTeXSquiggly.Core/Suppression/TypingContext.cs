namespace LaTeXSquiggly.Core.Suppression;

/// <summary>
/// What a browser is showing, in descending order of how much we can trust it.
///
/// The Mac reads the page URL out of the accessibility tree. Windows has no
/// equivalent that is cheap and reliable across every browser, so this port uses
/// the window title, which every browser sets to the page title. That is the
/// same path the Mac app already takes for Firefox, and the same trade: a title
/// match can fire on a page that merely mentions Overleaf, which costs one
/// unconverted command, far less than the miss it prevents.
/// </summary>
public enum BrowserPageKind { Url, Title, Unreadable }

public sealed record BrowserPage(BrowserPageKind Kind, string? Value)
{
    public static BrowserPage Url(string url) => new(BrowserPageKind.Url, url);
    public static BrowserPage Title(string title) => new(BrowserPageKind.Title, title);
    public static readonly BrowserPage Unreadable = new(BrowserPageKind.Unreadable, null);
}

/// <summary>
/// Everything the app knows about wherever the user is currently typing.
/// Named for what it describes rather than for the app, because
/// System.AppContext already exists and the collision is not worth it.
///
/// On Windows an application is named by its executable, which is the closest
/// thing to a bundle identifier: stable, not localised, and readable without
/// asking the app anything.
/// </summary>
public sealed record TypingContext(string? ProcessName, string? Name = null, BrowserPage? Page = null)
{
    /// <summary>Whatever we have to call this app in a sentence.</summary>
    public string DisplayName => Name ?? ProcessName ?? "this app";
}
