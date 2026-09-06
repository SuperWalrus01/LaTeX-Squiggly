import LaTeXUnicode

func runTokenizerChecks(_ c: Checker) {

    // A command name stops at the first non-letter.
    c.tokenizes("\\alpha", [.command("alpha")])
    c.tokenizes("\\alpha1", [.command("alpha"), .character("1")])

    // The terminator is preserved, not consumed. This is the documented
    // divergence from TeX and the reason `\alpha + \beta ` reads as `α + β`.
    c.tokenizes("\\alpha ", [.command("alpha"), .character(" ")])
    c.tokenizes("\\alpha\t", [.command("alpha"), .character("\t")])
    c.converted("\\alpha ", "α ")
    c.converted("\\alpha\t", "α\t")
    c.converted("\\alpha\\beta", "αβ")

    // Script markers.
    c.tokenizes("x^2_i", [.character("x"), .sup, .character("2"),
                          .sub, .character("i")])

    // Groups.
    c.tokenizes("{ab}", [.group([.character("a"), .character("b")])])
    c.tokenizes("{{a}}", [.group([.group([.character("a")])])])
    c.tokenizes("{}", [.group([])])

    // Control symbols.
    c.tokenizes("\\{", [.controlSymbol("{")])
    c.tokenizes("\\\\", [.controlSymbol("\\")])

    // Brackets are ordinary characters; only \sqrt gives them meaning.
    c.tokenizes("[a]", [.character("["), .character("a"), .character("]")])
    c.converted("[\\alpha]", "[α]")

    // Malformed input throws rather than guessing.
    c.tokenizerThrows("{a", .unbalancedBrace)
    c.tokenizerThrows("{{a}", .unbalancedBrace)
    c.tokenizerThrows("a}", .unexpectedClosingBrace)
    c.tokenizerThrows("\\", .danglingBackslash)
}
