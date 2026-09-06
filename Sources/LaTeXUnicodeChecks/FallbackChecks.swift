import Foundation
import LaTeXUnicode

/// Fallbacks are linear approximations the user must be told about.
func runFallbackChecks(_ c: Checker) {

    // The spec's own example.
    c.fallback("\\frac{x+1}{y-2}", "(x+1)/(y-2)")

    // Single-character arguments need no parentheses.
    c.fallback("\\frac{1}{2}", "1/2")
    c.fallback("\\frac12", "1/2")
    c.fallback("\\frac{a}{b+c}", "a/(b+c)")
    c.fallback("\\frac{\\alpha}{\\beta}", "α/β")

    c.fallback("\\dfrac{1}{2}", "1/2")
    c.fallback("\\tfrac{1}{2}", "1/2")
    c.fallback("\\frac{\\frac{1}{2}}{3}", "(1/2)/3")

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
    if case .fallback(_, let reason) = convert("\\frac{1}{2}") {
        c.expect(reason.lowercased().contains("fraction"),
                 "fallback reason should name the construction: \(reason)")
        c.expect(reason.hasSuffix("."),
                 "fallback reason should read as a sentence: \(reason)")
    } else {
        c.fail("expected a fallback for \\frac{1}{2}")
    }

    // Repeated fallbacks of the same kind produce one explanation, not four.
    if case .fallback(let text, let reason) = convert("\\frac{1}{2} + \\frac{3}{4}") {
        c.equal(text, "1/2 + 3/4", "two fractions")
        c.equal(reason.components(separatedBy: "A fraction").count - 1, 1,
                "fallback reasons should be deduplicated: \(reason)")
    } else {
        c.fail("expected a fallback for two fractions")
    }

    c.fallback("\\alpha = \\frac{1}{2}", "α = 1/2")

    // .unsupported beats .fallback: a fallback next to something impossible
    // must not be emitted.
    c.unsupported("\\frac{1}{2} \\vec{v}")
    c.unsupported("\\frac{1}{2} \\begin{matrix}")

    // Malformed fallback constructions.
    c.unsupported("\\frac{1}", containing: "two arguments")
    c.unsupported("\\frac", containing: "two arguments")
    c.unsupported("\\frac{}{2}", containing: "empty")
    c.unsupported("\\sqrt", containing: "needs an argument")
    c.unsupported("\\sqrt{}", containing: "empty")
    c.unsupported("\\sqrt[3{x}", containing: "never closed")
    c.unsupported("\\binom{n}", containing: "two arguments")
}
