import Foundation

/// What the app excludes out of the box.
///
/// Two lists, because bundle identifiers cannot be written from memory any more
/// safely than Unicode codepoints can. A wrong identifier fails silently and
/// the first thing the user notices is a corrupted document, so:
///
/// - `bundleIDs` holds identifiers verified against installed copies of the
///   apps, or well enough established to be safe.
/// - `applicationNames` is resolved against what is actually on the disk at
///   launch, reading each app's real identifier out of its bundle. This is how
///   the TeX editors get covered: their identifiers are not ones to guess at,
///   and the answer is sitting in `/Applications` waiting to be read.
///
/// Both lists only ever produce rules for apps that are installed, so the
/// exclusion editor shows a short, true list rather than a wall of software the
/// user does not have.
public enum DefaultExclusions {

    public static let bundleIDs: [String] = [
        // Terminals — a shell is nothing but backslashes.
        "com.apple.Terminal",
        "com.googlecode.iterm2",
        "net.kovidgoyal.kitty",
        "com.mitchellh.ghostty",
        "dev.warp.Warp-Stable",
        "com.github.wez.wezterm",
        "co.zeit.hyper",

        // Code editors — where a .tex file is most likely to be open.
        "com.microsoft.VSCode",
        "com.microsoft.VSCodeInsiders",
        "com.todesktop.230313mzl4w4u92",   // Cursor
        "com.apple.dt.Xcode",
        "com.sublimetext.4",
        "com.sublimetext.3",
        "com.barebones.bbedit",
        "org.gnu.Emacs",
        "org.vim.MacVim",
        "dev.zed.Zed",
        "com.panic.Nova",
        "com.rstudio.desktop",             // Sweave and R Markdown are LaTeX
    ]

    /// Matched against `CFBundleName` and the file name of each installed app.
    ///
    /// The TeX editors are here rather than above because their identifiers are
    /// exactly the kind of thing that looks obvious and is wrong.
    public static let applicationNames: [String] = [
        "TeXShop",
        "TeXstudio",
        "Texifier",
        "Texpad",
        "TeXmaker",
        "Texmaker",
        "TeXworks",
        "TeXnicCenter",
        "LyX",
        "Overleaf",

        // Repeated from `bundleIDs` on purpose: if an identifier up there is
        // wrong, the name catches the app anyway.
        "Visual Studio Code",
        "VSCodium",
        "Cursor",
        "Sublime Text",
        "Zed",
        "Nova",
        "CotEditor",
        "MacVim",
        "Emacs",
        "BBEdit",
        "RStudio",
    ]

    /// Overleaf is the case the whole phase exists for: it is not an app, it is
    /// a tab in a browser the user also chats in.
    public static let sites: [ExcludedSite] = [
        ExcludedSite(host: "overleaf.com",
                     titleFragments: ["Overleaf"]),
        ExcludedSite(host: "sharelatex.com",
                     titleFragments: ["ShareLaTeX"]),
        ExcludedSite(host: "papeeria.com",
                     titleFragments: ["Papeeria"]),
        ExcludedSite(host: "cocalc.com",
                     titleFragments: ["CoCalc"]),
        ExcludedSite(host: "latexbase.com",
                     titleFragments: ["LaTeX Base"]),
    ]
}
