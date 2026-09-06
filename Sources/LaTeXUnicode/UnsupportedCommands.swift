/// Commands that are recognised but deliberately refused, each with the
/// explanation the user sees.
///
/// Recognising them matters: "Unknown command \vec" suggests a typo, whereas
/// "an arrow cannot be drawn over a letter in plain text" tells the user the
/// truth about the constraint.
public enum UnsupportedCommands {

    /// `\{` and friends: an escaped literal is just that character.
    public static let escapedLiterals: [Character: Character] = [
        "{": "{", "}": "}", "$": "$", "%": "%",
        "&": "&", "#": "#", "_": "_",
    ]

    /// Control symbols that are recognised but have no inline form.
    public static let symbolReasons: [Character: String] = [
        "\\": "A line break has no inline form — the replacement has to stay on one line.",
        ",":  "Spacing commands such as \\, are typographic adjustments with no plain-text equivalent.",
        ";":  "Spacing commands such as \\; are typographic adjustments with no plain-text equivalent.",
        ":":  "Spacing commands such as \\: are typographic adjustments with no plain-text equivalent.",
        "!":  "Spacing commands such as \\! are typographic adjustments with no plain-text equivalent.",
        " ":  "Spacing commands are typographic adjustments with no plain-text equivalent.",
    ]

    private static let twoDimensional =
        "needs two-dimensional layout, which has no inline Unicode form."
    private static let overlay =
        "cannot be drawn over other characters in plain text."

    public static let reasons: [String: String] = [
        // Stacked constructions.
        "overbrace":       "An overbrace \(overlay)",
        "underbrace":      "An underbrace \(overlay)",
        "overline":        "An overline \(overlay)",
        "underline":       "An underline \(overlay)",
        "overrightarrow":  "An arrow \(overlay)",
        "overleftarrow":   "An arrow \(overlay)",
        "stackrel":        "\\stackrel \(twoDimensional)",
        "substack":        "\\substack \(twoDimensional)",
        "atop":            "\\atop \(twoDimensional)",
        "over":            "\\over \(twoDimensional) Try \\frac{a}{b}, which falls back to a/b.",
        "choose":          "\\choose \(twoDimensional) Try \\binom{n}{k}, which falls back to C(n, k).",
        "cases":           "The cases environment \(twoDimensional)",
        "matrix":          "A matrix \(twoDimensional)",

        // Accents. Unicode combining marks exist but render inconsistently
        // across the apps this tool types into, so they are out of scope.
        "hat":       "An accent \(overlay)",
        "widehat":   "An accent \(overlay)",
        "bar":       "An accent \(overlay)",
        "vec":       "An accent \(overlay)",
        "dot":       "An accent \(overlay)",
        "ddot":      "An accent \(overlay)",
        "tilde":     "An accent \(overlay)",
        "widetilde": "An accent \(overlay)",
        "acute":     "An accent \(overlay)",
        "grave":     "An accent \(overlay)",
        "breve":     "An accent \(overlay)",
        "mathring":  "An accent \(overlay)",

        // Alternate alphabets. Unicode has these planes; they are simply not
        // part of Phase 0.
        "mathbf":     "Bold, script and fraktur alphabets are not supported yet.",
        "boldsymbol": "Bold, script and fraktur alphabets are not supported yet.",
        "mathcal":    "Bold, script and fraktur alphabets are not supported yet.",
        "mathscr":    "Bold, script and fraktur alphabets are not supported yet.",
        "mathfrak":   "Bold, script and fraktur alphabets are not supported yet.",
        "mathit":     "Italic alphabets are not supported yet.",
        "mathsf":     "Sans-serif alphabets are not supported yet.",
        "mathtt":     "Monospace alphabets are not supported yet.",

        // Layout and document commands with nothing to convert to.
        "displaystyle": "\\displaystyle only affects typeset size; there is nothing to insert.",
        "textstyle":    "\\textstyle only affects typeset size; there is nothing to insert.",
        "limits":       "\\limits only affects typeset placement; there is nothing to insert.",
        "nolimits":     "\\nolimits only affects typeset placement; there is nothing to insert.",
        "quad":         "Spacing commands are typographic adjustments with no plain-text equivalent.",
        "qquad":        "Spacing commands are typographic adjustments with no plain-text equivalent.",
        "phantom":      "\\phantom reserves typeset space; there is nothing to insert.",
        "hspace":       "Spacing commands are typographic adjustments with no plain-text equivalent.",
        "vspace":       "Spacing commands are typographic adjustments with no plain-text equivalent.",
        "label":        "\\label belongs to a LaTeX document, not to inline text.",
        "ref":          "\\ref belongs to a LaTeX document, not to inline text.",
        "cite":         "\\cite belongs to a LaTeX document, not to inline text.",
        "footnote":     "\\footnote belongs to a LaTeX document, not to inline text.",
        "textbf":       "Bold, script and fraktur alphabets are not supported yet.",
        "textit":       "Italic alphabets are not supported yet.",
        "emph":         "Italic alphabets are not supported yet.",
    ]
}
