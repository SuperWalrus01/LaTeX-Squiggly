import LaTeXUnicode

/// Autocomplete for LaTeX commands, shown where iOS would suggest words.
enum CommandSuggestions {

    struct Suggestion: Hashable {
        /// The command without its backslash, `alpha`.
        let command: String
        /// What it looks like, `α`, or nil for structures like `\frac`.
        let glyph: String?
        /// What to type for it, `\frac{}{}` for a structure.
        let source: String
        /// How far back from the end the cursor goes, into the first brace.
        let back: Int
    }

    /// Structures the symbol table does not list, typed with empty braces.
    private static let templates: [String: (source: String, back: Int)] = [
        "frac": ("\\frac{}{}", 3), "sqrt": ("\\sqrt{}", 1), "text": ("\\text{}", 1),
        "mathbb": ("\\mathbb{}", 1), "mathrm": ("\\mathrm{}", 1), "binom": ("\\binom{}{}", 3),
    ]

    /// Ranked ahead of the alphabet, so `\al` offers alpha before aleph.
    private static let common = [
        "alpha", "beta", "gamma", "delta", "epsilon", "theta", "lambda", "mu", "pi",
        "sigma", "phi", "omega", "infty", "sum", "int", "frac", "sqrt", "partial",
        "nabla", "pm", "times", "cdot", "leq", "geq", "neq", "approx", "to",
        "rightarrow", "in", "subset", "cup", "cap", "forall", "exists", "Delta",
        "Sigma", "Omega", "text", "mathbb",
    ]
    private static let rank = Dictionary(uniqueKeysWithValues: common.enumerated().map { ($1, $0) })

    /// The command being typed at the end of `before`, `al` for `x = \al`.
    static func partialCommand(in before: String) -> String? {
        let letters = before.reversed().prefix { $0.isASCII && $0.isLetter }
        let index = before.index(before.endIndex, offsetBy: -letters.count)
        guard index > before.startIndex, before[before.index(before: index)] == "\\" else { return nil }
        return String(letters.reversed())
    }

    /// Up to `limit` completions for `prefix`, best first. An exact match comes
    /// first so the user can see what their command will become.
    static func suggestions(for prefix: String, limit: Int = 3) -> [Suggestion] {
        guard !prefix.isEmpty else { return [] }
        let names = Set(SymbolTable.symbols.keys).union(templates.keys)
        let matches = names.filter { $0.hasPrefix(prefix) }.sorted { a, b in
            if (a == prefix) != (b == prefix) { return a == prefix }
            let ra = rank[a] ?? .max, rb = rank[b] ?? .max
            if ra != rb { return ra < rb }
            if a.count != b.count { return a.count < b.count }
            return a < b
        }
        return matches.prefix(limit).map { name in
            if let template = templates[name] {
                return Suggestion(command: name, glyph: nil, source: template.source, back: template.back)
            }
            return Suggestion(command: name, glyph: SymbolTable.symbols[name],
                              source: "\\" + name, back: 0)
        }
    }
}
