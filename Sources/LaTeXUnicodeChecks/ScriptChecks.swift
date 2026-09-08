import LaTeXUnicode

func runScriptChecks(_ c: Checker) {

    // All ten digits exist in both forms.
    for digit in "0123456789" {
        guard let sup = ScriptTables.superscripts[digit],
              let sub = ScriptTables.subscripts[digit] else {
            c.fail("missing script form for \(digit)")
            continue
        }
        c.converted("x^\(digit)", "x\(sup)")
        c.converted("x_\(digit)", "x\(sub)")
    }

    // The spec's own examples.
    c.converted("x^2", "x²")
    c.converted("\\int_5^6", "∫₅⁶")

    // Superscript letters: every lowercase letter except q.
    for letter in "abcdefghijklmnoprstuvwxyz" {
        guard let sup = ScriptTables.superscripts[letter] else {
            c.fail("missing superscript \(letter)")
            continue
        }
        c.converted("x^\(letter)", "x\(sup)")
    }
    c.isNil(ScriptTables.superscripts["q"], "superscript q must not exist")
    c.unsupported("x^q", containing: "no unicode superscript")

    // Subscript letters: only a e h i j k l m n o p r s t u v x.
    for letter in "aehijklmnoprstuvx" {
        guard let sub = ScriptTables.subscripts[letter] else {
            c.fail("missing subscript \(letter)")
            continue
        }
        c.converted("x_\(letter)", "x\(sub)")
    }

    // Requesting a missing letter returns .unsupported, never a silent
    // literal. This is the single most likely place for a silent partial
    // conversion to creep in.
    for letter in "bcdfgqwyz" {
        c.isNil(ScriptTables.subscripts[letter], "subscript \(letter) must not exist")
        c.unsupported("x_\(letter)", containing: "no unicode subscript")
    }

    // Capitals have no script forms at all.
    c.unsupported("x^A", containing: "no unicode superscript")
    c.unsupported("x_A", containing: "no unicode subscript")

    // Multi-character scripts.
    c.converted("x^{10}", "x¹⁰")
    c.converted("x^{n+1}", "xⁿ⁺¹")
    c.converted("x^{-1}", "x⁻¹")
    c.converted("x_{ij}", "xᵢⱼ")
    c.converted("\\sum_{i=1}^{n}", "∑ᵢ₌₁ⁿ")

    // One missing character poisons the whole group — no half conversion.
    c.unsupported("x_{ab}", containing: "no unicode subscript")
    c.unsupported("x^{1q}", containing: "no unicode superscript")

    // A symbol with no script form is refused too.
    c.unsupported("\\int_0^\\infty", containing: "no unicode superscript")
    c.unsupported("x^\\alpha", containing: "no unicode superscript")

    // Nesting has no Unicode form.
    c.unsupported("x^{a^b}", containing: "nested")
    c.unsupported("x_{a_b}", containing: "nested")
    c.unsupported("e^{-x^2}", containing: "nested")

    // Malformed scripts.
    c.unsupported("x^", containing: "nothing after it")
    c.unsupported("x_", containing: "nothing after it")
    c.unsupported("x^{}", containing: "empty")
    c.unsupported("x_{}", containing: "empty")

    // Not valid LaTeX, but there is nothing dishonest about the output.
    c.converted("^2", "²")

    // MARK: Keeping a script Unicode cannot make

    // Off by default, so everything above still describes the shipped engine.
    // What follows is the same kind of input under the one option that moves it.
    let keep = ConversionOptions(keepUnrenderableScripts: true)

    // The case the option exists for. Every part with a Unicode form gets one,
    // and only the script without one keeps the way it was typed.
    c.fallback("\\Sigma_{i=1}^\\infty{a_i}", "Σᵢ₌₁^∞aᵢ", options: keep)
    c.fallback("\\int_0^\\infty", "∫₀^∞", options: keep)
    c.fallback("x^\\alpha", "x^α", options: keep)

    // Still all or nothing *within* one script: half of `^{1q}` raised and half
    // of it not would read as a typo, so the whole script is kept as typed.
    c.fallback("x^{1q}", "x^(1q)", options: keep)
    c.fallback("x_{ab}", "x_(ab)", options: keep)

    // Parenthesised only past one character, for the reason \frac parenthesises:
    // x^(n+1) says something x^n+1 does not.
    c.fallback("x^{\\infty}", "x^∞", options: keep)
    c.fallback("x^{\\infty+1}", "x^(∞+1)", options: keep)

    // Kept script or not, linear maths gets the real minus sign.
    c.fallback("x^{-\\infty}", "x^(−∞)", options: keep)

    // Nesting fails for the same reason and leaves by the same door.
    c.fallback("x^{a^b}", "x^(aᵇ)", options: keep)
    c.fallback("e^{-x^2}", "e^(−x²)", options: keep)

    // The option reaches scripts and nothing else. A command with no Unicode
    // form is still refused, and a malformed script is still malformed.
    c.unsupported("\\vec{v}", containing: "accent", options: keep)
    c.unsupported("\\begin{matrix}", containing: "matrix", options: keep)
    c.unsupported("x^", containing: "nothing after it", options: keep)
    c.unsupported("x^{}", containing: "empty", options: keep)

    // Whatever already converted converts identically: this adds a way out of
    // failure, it does not change a success.
    c.converted("\\int_5^6", "∫₅⁶", options: keep)
    c.converted("\\sum_{i=1}^{n}", "∑ᵢ₌₁ⁿ", options: keep)
    c.converted("\\alpha", "α", options: keep)

    // A fallback has to name what failed and show what was written instead.
    if case .fallback(_, let reason) = convert("\\int_0^\\infty", options: keep) {
        c.expect(reason.contains("superscript"), "the fallback names what failed")
        c.expect(reason.contains("^∞"), "the fallback shows what it wrote")
    } else {
        c.fail("\\int_0^\\infty should fall back when scripts are kept")
    }
}
