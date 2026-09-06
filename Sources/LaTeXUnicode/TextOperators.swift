/// Named operators. LaTeX sets these in upright roman type, which in plain
/// Unicode text is simply the letters themselves — so these are genuine
/// conversions, not fallbacks.
///
/// `\inf` and `\sup` live here while `\infty` and `\supset` live in
/// `SymbolTable`; the tokenizer's longest-match rule keeps them apart.
public enum TextOperators {

    public static let operators: [String: String] = [
        "arccos": "arccos", "arcsin": "arcsin", "arctan": "arctan",
        "arg":    "arg",    "bmod":   "mod",    "cos":    "cos",
        "cosh":   "cosh",   "cot":    "cot",    "coth":   "coth",
        "csc":    "csc",    "deg":    "deg",    "det":    "det",
        "dim":    "dim",    "exp":    "exp",    "gcd":    "gcd",
        "hom":    "hom",    "inf":    "inf",    "ker":    "ker",
        "lg":     "lg",     "lim":    "lim",    "liminf": "liminf",
        "limsup": "limsup", "ln":     "ln",     "log":    "log",
        "max":    "max",    "min":    "min",    "Pr":     "Pr",
        "sec":    "sec",    "sin":    "sin",    "sinh":   "sinh",
        "sup":    "sup",    "tan":    "tan",    "tanh":   "tanh",
    ]
}
