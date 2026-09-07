#!/usr/bin/env python3
"""Regenerates the parts of docs/ that must agree with the app.

    python3 Tools/make_site.py

The site demonstrates the converter, so it has to use the converter's own
tables rather than a second copy typed out by hand — the same argument that
makes Tools/generate_tables.py exist. Two things are generated:

    docs/assets/data.js         the symbol, script, fraction and operator
                                tables, plus every refusal reason
    docs/index.html             the worked examples, between the marked
                                regions, each one produced by running the
                                real binary and capturing what it printed

Everything else in docs/ is written by hand and never touched here.

Needs the release CLI, which this builds if it is missing:

    swift build -c release --product latex-squiggly
"""
import html
import io
import json
import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SOURCES = os.path.join(ROOT, "Sources", "LaTeXUnicode")


def read(*parts):
    with io.open(os.path.join(ROOT, *parts), encoding="utf-8") as handle:
        return handle.read()


def write(text, *parts):
    path = os.path.join(ROOT, *parts)
    with io.open(path, "w", encoding="utf-8") as handle:
        handle.write(text)
    return path


# ---------------------------------------------------------------- the tables

def symbols():
    """The coverage table, with the MARK comments as categories."""
    entries, category = [], None
    for line in read("Sources", "LaTeXUnicode", "SymbolTableData.swift").splitlines():
        heading = re.match(r"\s*// MARK: (.+)", line)
        if heading:
            category = heading.group(1).strip()
        entry = re.match(
            r'\s*\.init\(command: "([^"]+)",\s*glyph: "(.+?)",\s*'
            r'unicodeName: "([^"]+)", category: "([^"]+)"\)', line)
        if entry:
            entries.append({"c": entry.group(1), "g": entry.group(2),
                            "n": entry.group(3), "k": entry.group(4)})
    return entries


def character_table(source, name):
    body = re.search(r"static let %s: \[Character: Character\] = \[(.*?)\n    \]"
                     % name, source, re.S)
    return dict(re.findall(r'"(.+?)": "(.+?)",', body.group(1))) if body else {}


def tables():
    scripts = read("Sources", "LaTeXUnicode", "ScriptTables.swift")
    vulgar = re.search(r"vulgarFractions: \[String: String\] = \[(.*?)\n    \]",
                       scripts, re.S).group(1)

    operators = re.search(r"operators: \[String: String\] = \[(.*?)\n    \]",
                          read("Sources", "LaTeXUnicode", "TextOperators.swift"), re.S)

    # The refusal reasons, with the two shared clauses spliced back in the way
    # Swift's string interpolation would have.
    unsupported = read("Sources", "LaTeXUnicode", "UnsupportedCommands.swift")
    body = re.search(r"reasons: \[String: String\] = \[(.*?)\n    \]", unsupported, re.S).group(1)
    clauses = {
        "\\(twoDimensional)": "needs two-dimensional layout, which has no inline Unicode form.",
        "\\(overlay)": "cannot be drawn over other characters in plain text.",
    }
    reasons = {}
    for command, why in re.findall(r'"([A-Za-z]+)":\s*"(.*?)",?\n', body):
        for token, text in clauses.items():
            why = why.replace(token, text)
        reasons[command] = why.replace("\\\\", "\\")

    return {
        "symbols": symbols(),
        "sup": character_table(scripts, "superscripts"),
        "sub": character_table(scripts, "subscripts"),
        "vulgar": dict(re.findall(r'"([0-9]+/[0-9]+)":\s*"(.)"', vulgar)),
        "operators": dict(re.findall(r'"([^"]+)":\s*"([^"]+)"', operators.group(1))),
        "reasons": reasons,
    }


# -------------------------------------------------------------- the examples

def binary():
    path = subprocess.run(["swift", "build", "-c", "release", "--show-bin-path"],
                          cwd=ROOT, capture_output=True, text=True).stdout.strip()
    cli = os.path.join(path, "latex-squiggly")
    if not os.path.exists(cli):
        subprocess.run(["swift", "build", "-c", "release", "--product", "latex-squiggly"],
                       cwd=ROOT, check=True)
    return cli


def convert(cli, fragment):
    """What the app would do, straight from the app: text, status, explanation.

    --app-only matters here. Without it the tool falls through to the raw
    engine for anything the app would not fire on, so `x^2` prints x-squared
    even though typing it in the app does nothing at all — and a page built
    from that output would be advertising a conversion that never happens.
    """
    done = subprocess.run([cli, "--app-only", fragment], capture_output=True, text=True)
    said = done.stderr.strip()
    return done.stdout.strip(), done.returncode, said.split(": ", 1)[1] if ": " in said else ""


# What the exit status means, and how the page draws it.
OUTCOMES = {0: "convert", 1: "refuse", 2: "quiet"}


def rows(cli, examples):
    out = []
    for fragment, expected in examples:
        text, status, note = convert(cli, fragment)
        actual = OUTCOMES.get(status, "?")
        if actual != expected:
            sys.exit("make_site: %r now %ss, but the page says it should %s"
                     % (fragment, actual, expected))

        if actual == "refuse":
            right = "<div class='out refused'>%s</div>" % html.escape(note)
        elif actual == "quiet":
            right = "<div class='out quiet'>left exactly as typed</div>"
        else:
            right = "<div class='out'>%s%s</div>" % (
                html.escape(text),
                "<small>%s</small>" % html.escape(note) if note else "")
        out.append("        <div class='pair'><div class='src'>%s</div>"
                   "<div class='arrow'>&#8594;</div>%s</div>"
                   % (html.escape(fragment), right))
    return "\n".join(out)


# Each example carries the outcome the page claims for it, so a change in the
# engine breaks the build rather than quietly rewriting the page's argument.
EXAMPLES = {
    "symbols": [(r"\alpha", "convert"), (r"\Rightarrow", "convert"), (r"\int", "convert"),
                (r"\subseteq", "convert"), (r"\mathbb{R}", "convert"), (r"$x^2$", "convert"),
                (r"$a_1$", "convert"), (r"$\int_0^1$", "convert"), (r"\sin", "convert"),
                (r"\infty", "convert")],
    "refusals": [(r"\vec{v}", "refuse"), (r"\overbrace", "refuse"), (r"\matrix", "refuse"),
                 (r"\mathbf{x}", "refuse"), (r"$e^{i\pi}$", "refuse")],
    "fallbacks": [(r"\frac{1}{2}", "convert"), (r"\frac{3}{7}", "convert"),
                  (r"\frac{a}{b}", "convert"), (r"\sqrt{2}", "convert"),
                  (r"\sqrt[3]{x}", "convert"), (r"\binom{n}{k}", "convert")],
    "dollars": [("I have $5$ left", "quiet"), ("that costs $20 and $30 more", "quiet"),
                (r"$a$", "quiet"), (r"x^2", "quiet"), (r"2^3", "quiet"),
                (r"$x^2$", "convert"), (r"$5x^2$", "convert")],
}


def counts():
    """
    The numbers the page quotes about its own test suites.

    Typed by hand, these go stale at the first release that adds a check, and
    nothing notices: the page keeps claiming 1,674 while the suite says 1,709.
    The macOS number comes from running the suite; the Windows numbers come from
    the file the conformance runner writes when it passes, so this needs no
    .NET SDK to be able to state them.
    """
    result = {}

    output = subprocess.run(
        ["swift", "run", "-c", "release", "latex-squiggly-check"],
        cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
        text=True, check=True).stdout
    found = re.search(r"([\d,]+) checks passed", output)
    if not found:
        sys.exit("make_site: the check suite did not report a total")
    result["checks"] = "{:,}".format(int(found.group(1).replace(",", "")))

    summary = os.path.join(ROOT, "windows", "LaTeXSquiggly.Conformance", "result.json")
    if os.path.exists(summary):
        with io.open(summary, encoding="utf-8") as handle:
            windows = json.load(handle)
        result["winchecks"] = "{:,}".format(windows["total"])
        result["corpus"] = "{:,}".format(windows["fragments"])
    else:
        sys.exit("make_site: no windows/LaTeXSquiggly.Conformance/result.json; "
                 "run ./windows/build.sh")
    return result


def main():
    data = tables()
    write("// Generated by Tools/make_site.py from Sources/LaTeXUnicode.\n"
          "// Do not edit by hand: edit the tables and regenerate.\n"
          "const DATA = %s;\n" % json.dumps(data, ensure_ascii=False, separators=(",", ":")),
          "docs", "assets", "data.js")
    print("docs/assets/data.js: %d symbols, %d superscripts, %d subscripts, "
          "%d fractions, %d operators, %d reasons"
          % (len(data["symbols"]), len(data["sup"]), len(data["sub"]),
             len(data["vulgar"]), len(data["operators"]), len(data["reasons"])))

    cli = binary()
    page = read("docs", "index.html")
    for name, examples in EXAMPLES.items():
        begin = "<!-- BEGIN generated: %s (Tools/make_site.py) -->" % name
        end = "<!-- END generated: %s -->" % name
        marker = re.escape(begin) + ".*?" + re.escape(end)
        if not re.search(marker, page, re.S):
            sys.exit("make_site: docs/index.html has no %s region" % name)
        filled = begin + "\n" + rows(cli, examples) + "\n        " + end
        page = re.sub(marker, lambda _: filled, page, flags=re.S)
        print("docs/index.html: %d %s examples" % (len(examples), name))

    for name, value in counts().items():
        begin = "<!-- BEGIN generated: %s -->" % name
        end = "<!-- END generated: %s -->" % name
        marker = re.escape(begin) + ".*?" + re.escape(end)
        if not re.search(marker, page, re.S):
            sys.exit("make_site: docs/index.html has no %s region" % name)
        page = re.sub(marker, lambda _, v=value, b=begin, e=end: b + v + e, page, flags=re.S)
        print("docs/index.html: %s = %s" % (name, value))

    write(page, "docs", "index.html")


if __name__ == "__main__":
    main()
