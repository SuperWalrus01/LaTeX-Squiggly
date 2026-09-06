import LaTeXUnicode

/// `\in` is a prefix of `\inf`, `\infty` and `\int`. Resolution is longest
/// match on the command name; the terminator that ends the name is preserved
/// as ordinary text.
func runPrefixCollisionChecks(_ c: Checker) {

    // Longest match, with no terminator.
    c.converted("\\in", "∈")
    c.converted("\\inf", "inf")
    c.converted("\\infty", "∞")
    c.converted("\\int", "∫")

    // With a space terminator, which survives into the output.
    c.converted("\\in ", "∈ ")
    c.converted("\\inf ", "inf ")
    c.converted("\\infty ", "∞ ")
    c.converted("\\int ", "∫ ")

    // With a tab terminator.
    c.converted("\\in\t", "∈\t")
    c.converted("\\int\t", "∫\t")

    // `\int` never tokenises as `\in` followed by a literal "t". To get ∈
    // followed by "t", the command has to be terminated first.
    c.converted("\\int", "∫")
    c.converted("\\in t", "∈ t")

    // A longer unknown command must not decay into a shorter known one.
    c.unsupported("\\ints", containing: "unknown command")
    c.unsupported("\\alphax", containing: "unknown command")
    c.unsupported("\\sub", containing: "unknown command")

    // Other prefix families.
    c.converted("\\subset", "⊂")
    c.converted("\\subseteq", "⊆")
    c.converted("\\subsetneq", "⊊")

    c.converted("\\P", "ℙ")
    c.converted("\\Pr", "Pr")

    c.converted("\\pi", "π")
    c.converted("\\Pi", "Π")

    c.converted("\\le", "≤")
    c.converted("\\leq", "≤")
    c.converted("\\ll", "≪")

    c.converted("\\to", "→")
    c.converted("\\top", "⊤")
}
