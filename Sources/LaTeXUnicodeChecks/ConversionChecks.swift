import LaTeXUnicode

func runConversionChecks(_ c: Checker) {

    // MARK: Every mapping converts

    // Blanket coverage: every table entry must be reachable through the
    // public API and produce exactly its mapped value.
    for (command, expected) in SymbolTable.symbols {
        c.converted("\\" + command, expected)
    }
    for (command, expected) in TextOperators.operators {
        c.converted("\\" + command, expected)
    }
    for command in UnsupportedCommands.reasons.keys {
        c.unsupported("\\" + command)
    }

    // MARK: Categories named in the spec

    c.converted("\\alpha", "α")
    c.converted("\\Omega", "Ω")
    c.converted("\\lambda", "λ")
    c.converted("\\Lambda", "Λ")

    c.converted("\\int\\sum\\prod\\pm\\times\\cdot\\infty\\partial\\nabla", "∫∑∏±×⋅∞∂∇")
    c.converted("\\leq\\geq\\neq\\approx\\equiv\\sim\\propto", "≤≥≠≈≡∼∝")
    c.converted("\\in\\notin\\subset\\subseteq\\cup\\cap\\emptyset\\forall\\exists",
                "∈∉⊂⊆∪∩∅∀∃")
    c.converted("\\leftarrow\\rightarrow\\Rightarrow\\iff\\mapsto", "←→⇒⟺↦")

    c.converted("\\R\\Q\\Z\\N\\C", "ℝℚℤℕℂ")
    c.converted("\\mathbb{R}", "ℝ")
    c.converted("\\mathbb R", "ℝ")
    c.unsupported("\\mathbb{X}", containing: "double-struck")
    c.unsupported("\\mathbb{ab}", containing: "double-struck")
    c.unsupported("\\mathbb", containing: "needs a letter")

    // Whitespace before an argument is skipped, as in LaTeX, while the
    // terminator of an argument-less command is preserved.
    c.converted("\\frac 1 2", "\u{00BD}")
    c.fallback("\\sqrt 2", "√2")
    c.converted("x^ 2", "x²")
    c.converted("\\text {ok}", "ok")
    c.unsupported("x^ ", containing: "nothing after it")

    // MARK: Whole fragments

    c.converted("hello", "hello")
    c.converted("Let \\alpha be a real number.", "Let α be a real number.")
    c.converted("\\alpha + \\beta \\leq x^2", "α + β ≤ x²")
    c.converted("\\forall x \\in \\R", "∀ x ∈ ℝ")

    c.converted("{\\alpha}", "α")
    c.converted("{{\\alpha}}", "α")

    c.converted("\\left(\\alpha\\right)", "(α)")
    c.fallback("\\left(\\frac{a}{b}\\right)", "(a\u{2215}b)")

    c.converted("\\text{if }x>0", "if x>0")
    c.converted("\\mathrm{d}x", "dx")

    c.converted("\\{\\}", "{}")
    c.converted("100\\%", "100%")
    c.converted("a\\_b", "a_b")
    c.converted("\\$\\&\\#", "$&#")

    // MARK: Unsupported

    c.unsupported("\\begin{matrix}", containing: "matrix")
    c.unsupported("\\begin{cases}", containing: "cases")
    c.unsupported("\\begin{align}", containing: "align")
    c.unsupported("\\begin{pmatrix}", containing: "two-dimensional")
    c.unsupported("\\begin", containing: "two-dimensional")

    c.unsupported("\\foo", containing: "unknown command")
    c.unsupported("\\alpha \\foo", containing: "unknown command")

    c.unsupported("\\,", containing: "spacing")
    c.unsupported("\\;", containing: "spacing")
    c.unsupported("\\quad", containing: "spacing")
    c.unsupported("\\\\", containing: "line break")

    // Recognising a refused command is what lets the message be honest
    // instead of "unknown command".
    c.unsupported("\\vec{v}", containing: "accent")
    c.unsupported("\\overbrace{x}", containing: "overbrace")
    c.unsupported("\\over", containing: "\\frac")
    c.unsupported("\\mathcal{L}", containing: "not supported yet")

    // MARK: Malformed input

    c.unsupported("", containing: "nothing to convert")
    c.unsupported("{", containing: "unbalanced")
    c.unsupported("}", containing: "unbalanced")
    c.unsupported("{\\alpha", containing: "unbalanced")
    c.unsupported("\\alpha}", containing: "unbalanced")
    c.unsupported("\\", containing: "backslash")
    c.unsupported("\\alpha\\", containing: "backslash")

    c.unsupported(String(repeating: "{", count: 200))
    c.converted(String(repeating: "{", count: 200) + String(repeating: "}", count: 200), "")
    c.converted(String(repeating: "\\alpha", count: 500), String(repeating: "α", count: 500))

    // MARK: Result API

    c.equal(convert("\\alpha").text, "α", "converted text")
    c.isNil(convert("\\alpha").reason, "a clean conversion has no reason")
    c.equal(convert("\\alpha").requiresUserNotice, false, "clean conversion needs no notice")

    c.equal(convert("\\frac{a}{b}").text, "a\u{2215}b", "fallback text")
    c.equal(convert("\\frac{a}{b}").requiresUserNotice, true, "fallback needs a notice")
    c.equal(convert("\\frac{1}{2}").requiresUserNotice, false, "an exact fraction needs none")

    c.isNil(convert("\\begin{matrix}").text, "unsupported has no text")
    c.equal(convert("\\begin{matrix}").requiresUserNotice, true, "unsupported needs a notice")

    // Every non-clean result carries a sentence, because the caller shows it
    // to a human.
    let explained = ["", "\\foo", "x_b", "x^q", "\\begin{matrix}", "\\vec{v}",
                     "{", "}", "\\", "\\,", "\\sqrt{2}",
                     "\\binom{n}{k}", "\\sqrt[5]{x}", "\\frac{a}{b}", "x^{a^b}", "\\mathbb{X}"]
    for input in explained {
        guard let reason = convert(input).reason else {
            c.fail("expected a reason for \(input)")
            continue
        }
        c.expect(reason.hasSuffix("."), "not a sentence for \(input): \(reason)")
        c.expect(reason.first?.isUppercase == true, "not a sentence for \(input): \(reason)")
    }
}
