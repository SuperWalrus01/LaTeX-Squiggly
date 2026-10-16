// The selection menu's rules, which only Android has, so there is no Swift
// answer to compare with: the expected results are written out here.

package io.github.superwalrus01.squiggly.engine

internal fun selectionChecks(failures: MutableList<String>): Int {
    val stripping = listOf(
        "\$x^2\$" to "x^2",
        "  \$\$\\int_0^1\$\$ " to "\\int_0^1",
        "\\[a+b\\]" to "a+b",
        "\\(\\alpha\\)" to "\\alpha",
        "\$a\$ and \$b\$" to "\$a\$ and \$b\$",
        "costs \$5 and \$6" to "costs \$5 and \$6",
        "\$" to "\$",
        "\\alpha" to "\\alpha",
    )
    // Expected text, or null when it must be refused.
    val converting = listOf(
        "\\alpha" to "α",
        "\$x^2\$" to "x²",
        " \\alpha " to " α ",
        "Let \\alpha \\in \\mathbb{R}" to "Let α ∈ ℝ",
        "where \$x^2\$ is \$\\leq 1\$" to "where x² is ≤ 1",
        "costs \$5 and \$6" to "costs \$5 and \$6",
        "costs \$5 and \$6 for \$x^2\$" to "costs \$5 and \$6 for x²",
        "\$a\$ and \$b\$" to "\$a\$ and \$b\$",
        "an odd \$x^2" to "an odd \$x\u00b2",
        "\\vec{v}" to null,
        "where \$\\vec{v}\$ is" to null,
        "   " to null,
    )

    var checks = 0
    for ((input, want) in stripping) {
        checks += 1
        val got = Selection.stripDelimiters(input)
        if (got != want) failures.add("  strip [$input]: expected [$want], got [$got]")
    }
    for ((input, want) in converting) {
        checks += 1
        val got = Selection.convert(input).textOrNull
        if (got != want) failures.add("  selection [$input]: expected [${want ?: "(refused)"}], got [${got ?: "(refused)"}]")
    }
    return checks
}
