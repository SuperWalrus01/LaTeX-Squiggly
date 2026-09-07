#!/usr/bin/env python3
"""
Builds the list of fragments the Swift engine and the C# port are both asked
about, and records Swift's answers as the reference.

The Windows build cannot run on a Mac, so this is the only way to know the port
is faithful: ask both the same few thousand questions and diff the answers.
Every symbol, every script character, every refusal message and every trigger
rule is covered, because a port that is right about \\alpha and wrong about
\\varsigma is not obviously wrong until somebody types \\varsigma.

Run:  swift build && python3 Tools/generate_conformance_corpus.py
"""

import json, os, subprocess, string, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "windows", "LaTeXSquiggly.Conformance")


def corpus(tables):
    seen, cases = set(), []

    def add(fragment):
        if fragment not in seen:
            seen.add(fragment)
            cases.append(fragment)

    commands = [e["command"] for e in tables["entries"]]
    operators = sorted(tables["operators"])
    refused = sorted(tables["unsupportedReasons"])

    # Every symbol, on its own and in the shapes people actually type.
    for command in commands:
        add(f"\\{command}")
        add(f"\\{command} ")
        add(f"${{\\{command}}}$".replace("{", "").replace("}", ""))
        add(f"\\{command}\\{command}")
        add(f"x\\{command}")
    for name in operators + refused:
        add(f"\\{name}")
        add(f"\\{name}{{x}}")

    # Scripts, over the whole printable range, both ways round.
    for ch in string.printable.strip():
        add(f"$x^{ch}$")
        add(f"$x_{ch}$")
        add(f"$a^{{{ch}}}$")
    for n in range(0, 40):
        add(f"$x^{{{n}}}$")
        add(f"$x_{{{n}}}$")

    # Fractions: the precomposed ones, the composable ones, and the rest.
    parts = ["1", "2", "3", "7", "10", "17", "0", "100", "a", "b", "x", "n",
             "x+1", "y-2", "\\alpha", "\\pi", ""]
    for top in parts:
        for bottom in parts:
            add(f"\\frac{{{top}}}{{{bottom}}}")
    add("\\frac12")
    add("\\frac 1 2")
    add("\\dfrac{1}{2}")
    add("\\tfrac{3}{4}")
    add("\\frac{1}{\\frac{1}{2}}")

    # Roots, including the degenerate indices.
    for index in ["", "0", "1", "2", "3", "4", "5", "10", "-2", "n", "\\alpha"]:
        add(f"\\sqrt[{index}]{{8}}")
        add(f"\\sqrt[{index}]{{x+1}}")
    add("\\sqrt{2}")
    add("\\sqrt 2")
    add("\\sqrt{}")
    add("\\sqrt")
    add("\\sqrt[3{x}")
    add("\\sqrt{\\alpha}")

    # The remaining structural commands.
    for a in ["n", "k", "x+1", "\\alpha", ""]:
        add(f"\\binom{{{a}}}{{k}}")
        add(f"\\dbinom{{n}}{{{a}}}")
    for letter in string.ascii_letters:
        add(f"\\mathbb{{{letter}}}")
    add("\\mathbb R")
    add("\\mathbb{RR}")
    add("\\mathbb")
    for wrapper in ["text", "textrm", "mathrm", "operatorname"]:
        add(f"\\{wrapper}{{well-known}}")
        add(f"\\{wrapper}{{}}")
        add(f"\\{wrapper}")
    add("\\left(\\alpha\\right)")
    add("\\left[x\\right]")
    add("\\begin{cases}")
    add("\\end{matrix}")
    add("\\begin")

    # Control symbols and brace shapes.
    for ch in "{}$%&#_,;:! \\":
        add("\\" + ch)
        add("x\\" + ch)
    for fragment in ["{", "}", "{}", "{a}", "\\alpha}", "{\\alpha", "\\alpha}{2}",
                     "\\", "\\\\", "", " ", "  ", "{{a}}", "}{"]:
        add(fragment)

    # The dollar rule, including everything that must not fire.
    for fragment in ["$x^2$", "$a_1$", "$\\alpha$", "$\\alpha + x^2$", "$5$", "$100$",
                     "I have $5$", "it cost $5 and $10", "$x$", "$x^2", "$$", "$ $",
                     "$\\frac{a}{b}$", "$x^q$", "$\\left(\\alpha\\right)$",
                     "let me write $x^2$", "$" + "x^2" * 30 + "$",
                     "$x^2$ and $y_1$", "$\\alpha\\beta$", "$a^b^c$", "$x^{y^z}$"]:
        add(fragment)

    # Silence in ordinary typing, which is what the app is judged on.
    for fragment in ["hello", "x^2", "2^3", "a_b", "C:\\Users", "C:\\Users\\me",
                     "C:\\path\\to\\file", "\\foo", "\\alpha beta", "\\notacommand",
                     "the \\alpha", "we know \\frac{\\alpha}{2}", "\\foo\\alpha",
                     "\\alpha\\vec{v}", "\\vec{v}\\alpha", "a\\b\\c",
                     "https://example.com", "50% off", "e_mail_address"]:
        add(fragment)

    # Nesting and adjacency, the case the Mac app got wrong.
    for fragment in ["\\alpha\\beta", "\\alpha\\beta\\gamma", "\\frac{\\alpha}{\\beta}",
                     "\\sqrt{\\frac{1}{2}}", "\\lim_{x\\to0}", "\\sum_{i=1}^{n}",
                     "\\int_5^6", "\\alpha_b", "\\frac{\\alpha_b}{2}",
                     "\\text{a}b\\gamma", "\\mathbb{R}\\times\\mathbb{R}"]:
        add(fragment)

    # Long input, to exercise the buffer and span limits.
    add("\\alpha" * 12)
    add("$" + "\\alpha" * 12 + "$")
    add("x" * 70 + "\\alpha")

    return cases


def main():
    binary = os.path.join(ROOT, ".build", "debug", "latex-squiggly")
    if not os.path.exists(binary):
        sys.exit("build the Swift engine first: swift build")

    tables = json.loads(subprocess.check_output([binary, "--dump-tables"]))
    cases = corpus(tables)

    # Newlines cannot survive a line-per-fragment protocol, and none of the
    # fragments need one.
    cases = [c for c in cases if "\n" not in c and "\r" not in c]

    reference = subprocess.run(
        [binary, "--conformance"],
        input="\n".join(cases).encode("utf-8"),
        stdout=subprocess.PIPE, check=True).stdout

    records = json.loads(reference)
    if len(records) != len(cases):
        sys.exit(f"expected {len(cases)} records, got {len(records)}")

    os.makedirs(OUT, exist_ok=True)
    with open(os.path.join(OUT, "reference.json"), "w", encoding="utf-8") as handle:
        json.dump(records, handle, ensure_ascii=False, indent=1, sort_keys=True)

    kinds = {}
    for record in records:
        kinds[record["trigger"]["kind"]] = kinds.get(record["trigger"]["kind"], 0) + 1
    print(f"{len(records)} fragments recorded from the Swift engine")
    print("  trigger outcomes: " + ", ".join(f"{k} {v}" for k, v in sorted(kinds.items())))


if __name__ == "__main__":
    main()
