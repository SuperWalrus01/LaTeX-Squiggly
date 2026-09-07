namespace LaTeXSquiggly.Core.Suppression;

/// <summary>
/// What the app excludes out of the box.
///
/// The Mac version resolves TeX editors off the disk because bundle identifiers
/// cannot be written from memory safely. Windows is kinder here: an app is
/// identified by its executable name, which is exactly what the user sees in
/// Task Manager and what an installer cannot quietly change. So the list is
/// literal, and a name that matches nothing installed simply never fires.
///
/// The rule behind every entry: an app that corrupts LaTeX source is worse than
/// no app at all, so anywhere LaTeX source is plausibly written, stay quiet.
/// </summary>
public static class DefaultExclusions
{
    /// <summary>Executable names, lowercased, without .exe.</summary>
    public static readonly (string Process, string Name)[] Apps =
    {
        // TeX editors. The reason this list exists.
        ("texstudio", "TeXstudio"),
        ("texmaker", "Texmaker"),
        ("texworks", "TeXworks"),
        ("miktex-texworks", "TeXworks"),
        ("texniccenter", "TeXnicCenter"),
        ("winedt", "WinEdt"),
        ("lyx", "LyX"),
        ("texifier", "Texifier"),
        ("texpad", "Texpad"),
        ("scientificworkplace", "Scientific WorkPlace"),

        // Terminals. A shell is nothing but backslashes.
        ("windowsterminal", "Windows Terminal"),
        ("cmd", "Command Prompt"),
        ("powershell", "Windows PowerShell"),
        ("pwsh", "PowerShell"),
        ("conhost", "Console Window Host"),
        ("mintty", "Git Bash"),
        ("bash", "Bash"),
        ("alacritty", "Alacritty"),
        ("wezterm-gui", "WezTerm"),
        ("putty", "PuTTY"),
        ("hyper", "Hyper"),

        // Code editors, where a .tex file is most likely to be open.
        ("code", "Visual Studio Code"),
        ("code - insiders", "Visual Studio Code Insiders"),
        ("codium", "VSCodium"),
        ("cursor", "Cursor"),
        ("windsurf", "Windsurf"),
        ("zed", "Zed"),
        ("sublime_text", "Sublime Text"),
        ("notepad++", "Notepad++"),
        ("gvim", "gVim"),
        ("vim", "Vim"),
        ("nvim", "Neovim"),
        ("emacs", "Emacs"),
        ("runemacs", "Emacs"),
        ("devenv", "Visual Studio"),
        ("rstudio", "RStudio"),          // Sweave and R Markdown are LaTeX
        ("idea64", "IntelliJ IDEA"),
        ("pycharm64", "PyCharm"),
        ("clion64", "CLion"),
        ("webstorm64", "WebStorm"),
        ("rider64", "Rider"),
        ("jupyter-notebook", "Jupyter"),
        ("obsidian", "Obsidian"),        // its maths blocks are LaTeX source
        ("typora", "Typora"),
    };

    /// <summary>
    /// Overleaf is the case the whole feature exists for: it is not an app, it
    /// is a tab in a browser the user also chats in.
    ///
    /// The title fragments do the work on Windows, where a browser gives us its
    /// window title rather than its URL.
    /// </summary>
    public static ExcludedSite[] Sites() => new[]
    {
        new ExcludedSite("overleaf.com", "Overleaf"),
        new ExcludedSite("sharelatex.com", "ShareLaTeX"),
        new ExcludedSite("papeeria.com", "Papeeria"),
        new ExcludedSite("cocalc.com", "CoCalc"),
        new ExcludedSite("latexbase.com", "LaTeX Base"),
    };

    public static ExclusionList Fresh()
    {
        var list = new ExclusionList();
        foreach (var (process, name) in Apps) list.Add(new ExcludedApp(process, name));
        foreach (var site in Sites()) list.Add(site);
        return list;
    }
}
