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
}
