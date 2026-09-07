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
    """What the app would do, straight from the app: text, status, explanation."""
    done = subprocess.run([cli, fragment], capture_output=True, text=True)
    said = done.stderr.strip()
    return done.stdout.strip(), done.returncode, said.split(": ", 1)[1] if ": " in said else ""


def rows(cli, fragments, refused):
    out = []
    for fragment in fragments:
        text, status, note = convert(cli, fragment)
        if (status == 1) != refused:
            sys.exit("make_site: %r is %s, but the page has it in the other list"
                     % (fragment, "refused" if status else "converted"))
        if refused:
            right = "<div class='out refused'>%s</div>" % html.escape(note)
        else:
            right = "<div class='out'>%s%s</div>" % (
                html.escape(text),
                "<small>%s</small>" % html.escape(note) if note else "")
        out.append("        <div class='pair'><div class='src'>%s</div>"
                   "<div class='arrow'>&#8594;</div>%s</div>"
                   % (html.escape(fragment), right))
    return "\n".join(out)


EXAMPLES = {
    "symbols": (False, [r"\alpha", r"\Rightarrow", r"\int", r"\subseteq", r"\mathbb{R}",
                        r"$x^2$", r"$a_1$", r"$\int_0^1$", r"\sin", r"\infty"]),
    "refusals": (True, [r"\vec{v}", r"\overbrace", r"\matrix", r"\mathbf{x}", r"$e^{i\pi}$"]),
    "fallbacks": (False, [r"\frac{1}{2}", r"\frac{3}{7}", r"\frac{a}{b}", r"\sqrt{2}",
                          r"\sqrt[3]{x}", r"\binom{n}{k}"]),
}


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
    for name, (refused, fragments) in EXAMPLES.items():
        begin = "<!-- BEGIN generated: %s (Tools/make_site.py) -->" % name
        end = "<!-- END generated: %s -->" % name
        marker = re.escape(begin) + ".*?" + re.escape(end)
        if not re.search(marker, page, re.S):
            sys.exit("make_site: docs/index.html has no %s region" % name)
        filled = begin + "\n" + rows(cli, fragments, refused) + "\n        " + end
        page = re.sub(marker, lambda _: filled, page, flags=re.S)
        print("docs/index.html: %d %s examples" % (len(fragments), name))
    write(page, "docs", "index.html")


if __name__ == "__main__":
    main()
