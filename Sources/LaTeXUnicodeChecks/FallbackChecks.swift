import Foundation
import LaTeXUnicode

/// Fallbacks are linear approximations the user must be told about.
func runFallbackChecks(_ c: Checker) {


    // MARK: Fractions that are real fractions, not approximations

    // A precomposed character is an exact representation, so these convert.
    c.converted("\\frac{1}{2}", "\u{00BD}")
    c.converted("\\frac12", "\u{00BD}")
    c.converted("\\frac{3}{4}", "\u{00BE}")
    c.converted("\\frac{5}{8}", "\u{215D}")
    c.converted("\\frac{2}{3}", "\u{2154}")
    c.converted("\\dfrac{1}{2}", "\u{00BD}")

    // No single character exists for these, so they are composed from a
    // superscript numerator, a fraction slash and a subscript denominator.
    c.converted("\\frac{10}{17}", "\u{00B9}\u{2070}\u{2044}\u{2081}\u{2087}")
    c.converted("\\frac{7}{9}", "\u{2077}\u{2044}\u{2089}")
    c.converted("\\frac{n}{2}", "\u{207F}\u{2044}\u{2082}")

    // Composition needs every character to have its form. The subscript
    // alphabet is missing b c d f g q w y z, so these still linearise.
    c.fallback("\\frac{a}{b}", "a/b")
    c.fallback("\\frac{x+1}{y-2}", "(x+1)/(y-2)")
    c.fallback("\\frac{\\alpha}{\\beta}", "\u{03B1}/\u{03B2}")

    // Two exact fractions in one fragment need no explanation at all.
    c.converted("\\frac{1}{2} + \\frac{3}{4}", "\u{00BD} + \u{00BE}")

    // The spec's own example.
    c.fallback("\\frac{x+1}{y-2}", "(x+1)/(y-2)")

    // Single-character arguments need no parentheses.
    c.fallback("\\frac{a}{b+c}", "a/(b+c)")
    c.fallback("\\frac{\\alpha}{\\beta}", "α/β")

    c.fallback("\\dfrac{x+1}{y-2}", "(x+1)/(y-2)")
    c.fallback("\\tfrac{x+1}{y-2}", "(x+1)/(y-2)")
    // The inner half converts exactly, but a vulgar fraction has no
    // superscript form, so the outer one still has to linearise.
    c.fallback("\\frac{\\frac{1}{2}}{3}", "\u{00BD}/3")

    // Roots.
    c.fallback("\\sqrt{2}", "√2")
    c.fallback("\\sqrt{x+1}", "√(x+1)")
    c.fallback("\\sqrt[3]{x}", "∛x")
    c.fallback("\\sqrt[4]{x+1}", "∜(x+1)")

    // Only indices 2, 3 and 4 have a radical sign; anything else becomes a
    // fractional power.
    c.fallback("\\sqrt[5]{x}", "x^(1/5)")
    c.fallback("\\sqrt[n]{x+1}", "(x+1)^(1/n)")

    c.fallback("\\binom{n}{k}", "C(n, k)")
    c.fallback("\\binom{n+1}{2}", "C(n+1, 2)")

    // The reason is shown to a human, so it has to read like one.
    if case .fallback(_, let reason) = convert("\\frac{a}{b}") {
        c.expect(reason.lowercased().contains("fraction"),
                 "fallback reason should name the construction: \(reason)")
        c.expect(reason.hasSuffix("."),
                 "fallback reason should read as a sentence: \(reason)")
    } else {
        c.fail("expected a fallback for \\frac{a}{b}")
    }

    // Repeated fallbacks of the same kind produce one explanation, not four.
    if case .fallback(let text, let reason) = convert("\\frac{a}{b} + \\frac{c}{d}") {
        c.equal(text, "a/b + c/d", "two fractions")
        c.equal(reason.components(separatedBy: "A fraction").count - 1, 1,
                "fallback reasons should be deduplicated: \(reason)")
    } else {
        c.fail("expected a fallback for two fractions")
    }

    c.converted("\\alpha = \\frac{1}{2}", "α = ½")

    // .unsupported beats .fallback: a fallback next to something impossible
    // must not be emitted.
    c.unsupported("\\frac{a}{b} \\vec{v}")
    c.unsupported("\\frac{a}{b} \\begin{matrix}")

    // Malformed fallback constructions.
    c.unsupported("\\frac{1}", containing: "two arguments")
    c.unsupported("\\frac", containing: "two arguments")
    c.unsupported("\\frac{}{2}", containing: "empty")
    c.unsupported("\\sqrt", containing: "needs an argument")
    c.unsupported("\\sqrt{}", containing: "empty")
    c.unsupported("\\sqrt[3{x}", containing: "never closed")
    c.unsupported("\\binom{n}", containing: "two arguments")
}
