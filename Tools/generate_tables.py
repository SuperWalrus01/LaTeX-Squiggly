#!/usr/bin/env python3
"""
Generates Sources/LaTeXUnicode/SymbolTable.swift, ScriptTables.swift and
Tests/LaTeXUnicodeTests/GeneratedCodepointTests.swift.

Why a generator: LaTeX->Unicode tables written by hand (or by an LLM) get
codepoints wrong in ways that look right. Here every entry is specified by its
*Unicode character name*, and the character is resolved by unicodedata.lookup
against the Unicode database shipped with Python. A wrong name is a hard error
at generation time rather than a wrong glyph at runtime.

Run:  python3 Tools/generate_tables.py
"""

import unicodedata, sys, os

# ---------------------------------------------------------------------------
# (latex command without backslash, Unicode character name)
# ---------------------------------------------------------------------------

GREEK_LOWER = [
    ("alpha",      "GREEK SMALL LETTER ALPHA"),
    ("beta",       "GREEK SMALL LETTER BETA"),
    ("gamma",      "GREEK SMALL LETTER GAMMA"),
    ("delta",      "GREEK SMALL LETTER DELTA"),
    # TeX renders \epsilon as the lunate form and \varepsilon as the "curly"
    # one; unicode-math maps them this way round. See README "Variant letters".
    ("epsilon",    "GREEK LUNATE EPSILON SYMBOL"),
    ("varepsilon", "GREEK SMALL LETTER EPSILON"),
    ("zeta",       "GREEK SMALL LETTER ZETA"),
    ("eta",        "GREEK SMALL LETTER ETA"),
    ("theta",      "GREEK SMALL LETTER THETA"),
    ("vartheta",   "GREEK THETA SYMBOL"),
    ("iota",       "GREEK SMALL LETTER IOTA"),
    ("kappa",      "GREEK SMALL LETTER KAPPA"),
    ("lambda",     "GREEK SMALL LETTER LAMDA"),
    ("mu",         "GREEK SMALL LETTER MU"),
    ("nu",         "GREEK SMALL LETTER NU"),
    ("xi",         "GREEK SMALL LETTER XI"),
    ("omicron",    "GREEK SMALL LETTER OMICRON"),
    ("pi",         "GREEK SMALL LETTER PI"),
    ("varpi",      "GREEK PI SYMBOL"),
    ("rho",        "GREEK SMALL LETTER RHO"),
    ("varrho",     "GREEK RHO SYMBOL"),
    ("sigma",      "GREEK SMALL LETTER SIGMA"),
    ("varsigma",   "GREEK SMALL LETTER FINAL SIGMA"),
    ("tau",        "GREEK SMALL LETTER TAU"),
    ("upsilon",    "GREEK SMALL LETTER UPSILON"),
    ("phi",        "GREEK PHI SYMBOL"),
    ("varphi",     "GREEK SMALL LETTER PHI"),
    ("chi",        "GREEK SMALL LETTER CHI"),
    ("psi",        "GREEK SMALL LETTER PSI"),
    ("omega",      "GREEK SMALL LETTER OMEGA"),
]

# Only the capitals TeX actually defines: the rest are Latin lookalikes.
GREEK_UPPER = [
    ("Gamma",   "GREEK CAPITAL LETTER GAMMA"),
    ("Delta",   "GREEK CAPITAL LETTER DELTA"),
    ("Theta",   "GREEK CAPITAL LETTER THETA"),
    ("Lambda",  "GREEK CAPITAL LETTER LAMDA"),
    ("Xi",      "GREEK CAPITAL LETTER XI"),
    ("Pi",      "GREEK CAPITAL LETTER PI"),
    ("Sigma",   "GREEK CAPITAL LETTER SIGMA"),
    ("Upsilon", "GREEK CAPITAL LETTER UPSILON"),
    ("Phi",     "GREEK CAPITAL LETTER PHI"),
    ("Psi",     "GREEK CAPITAL LETTER PSI"),
    ("Omega",   "GREEK CAPITAL LETTER OMEGA"),
]

OPERATORS = [
    ("int",       "INTEGRAL"),
    ("iint",      "DOUBLE INTEGRAL"),
    ("iiint",     "TRIPLE INTEGRAL"),
    ("oint",      "CONTOUR INTEGRAL"),
    ("sum",       "N-ARY SUMMATION"),
    ("prod",      "N-ARY PRODUCT"),
    ("coprod",    "N-ARY COPRODUCT"),
    ("bigcup",    "N-ARY UNION"),
    ("bigcap",    "N-ARY INTERSECTION"),
    ("bigoplus",  "N-ARY CIRCLED PLUS OPERATOR"),
    ("bigotimes", "N-ARY CIRCLED TIMES OPERATOR"),
    ("bigvee",    "N-ARY LOGICAL OR"),
    ("bigwedge",  "N-ARY LOGICAL AND"),
    ("pm",        "PLUS-MINUS SIGN"),
    ("mp",        "MINUS-OR-PLUS SIGN"),
    ("times",     "MULTIPLICATION SIGN"),
    ("div",       "DIVISION SIGN"),
    ("cdot",      "DOT OPERATOR"),
    ("circ",      "RING OPERATOR"),
    ("bullet",    "BULLET OPERATOR"),
    ("ast",       "ASTERISK OPERATOR"),
    ("star",      "STAR OPERATOR"),
    ("oplus",     "CIRCLED PLUS"),
    ("ominus",    "CIRCLED MINUS"),
    ("otimes",    "CIRCLED TIMES"),
    ("oslash",    "CIRCLED DIVISION SLASH"),
    ("odot",      "CIRCLED DOT OPERATOR"),
    ("infty",     "INFINITY"),
    ("partial",   "PARTIAL DIFFERENTIAL"),
    ("nabla",     "NABLA"),
    ("surd",      "SQUARE ROOT"),
    ("prime",     "PRIME"),
    ("degree",    "DEGREE SIGN"),
]

RELATIONS = [
    ("leq",       "LESS-THAN OR EQUAL TO"),
    ("le",        "LESS-THAN OR EQUAL TO"),
    ("geq",       "GREATER-THAN OR EQUAL TO"),
    ("ge",        "GREATER-THAN OR EQUAL TO"),
    ("neq",       "NOT EQUAL TO"),
    ("ne",        "NOT EQUAL TO"),
    ("approx",    "ALMOST EQUAL TO"),
    ("equiv",     "IDENTICAL TO"),
    ("sim",       "TILDE OPERATOR"),
    ("simeq",     "ASYMPTOTICALLY EQUAL TO"),
    ("cong",      "APPROXIMATELY EQUAL TO"),
    ("propto",    "PROPORTIONAL TO"),
    ("ll",        "MUCH LESS-THAN"),
    ("gg",        "MUCH GREATER-THAN"),
    ("prec",      "PRECEDES"),
    ("succ",      "SUCCEEDS"),
    ("preceq",    "PRECEDES OR EQUAL TO"),
    ("succeq",    "SUCCEEDS OR EQUAL TO"),
    ("perp",      "UP TACK"),
    ("bot",       "UP TACK"),
    ("top",       "DOWN TACK"),
    ("parallel",  "PARALLEL TO"),
    ("nparallel", "NOT PARALLEL TO"),
    ("mid",       "DIVIDES"),
    ("nmid",      "DOES NOT DIVIDE"),
    ("nless",     "NOT LESS-THAN"),
    ("ngtr",      "NOT GREATER-THAN"),
    ("nleq",      "NEITHER LESS-THAN NOR EQUAL TO"),
    ("ngeq",      "NEITHER GREATER-THAN NOR EQUAL TO"),
    ("coloneqq",  "COLON EQUALS"),
]

SET_NOTATION = [
    ("in",         "ELEMENT OF"),
    ("notin",      "NOT AN ELEMENT OF"),
    ("ni",         "CONTAINS AS MEMBER"),
    ("subset",     "SUBSET OF"),
    ("supset",     "SUPERSET OF"),
    ("subseteq",   "SUBSET OF OR EQUAL TO"),
    ("supseteq",   "SUPERSET OF OR EQUAL TO"),
    ("nsubseteq",  "NEITHER A SUBSET OF NOR EQUAL TO"),
    ("nsupseteq",  "NEITHER A SUPERSET OF NOR EQUAL TO"),
    ("subsetneq",  "SUBSET OF WITH NOT EQUAL TO"),
    ("supsetneq",  "SUPERSET OF WITH NOT EQUAL TO"),
    ("cup",        "UNION"),
    ("cap",        "INTERSECTION"),
    ("uplus",      "MULTISET UNION"),
    ("sqcup",      "SQUARE CUP"),
    ("sqcap",      "SQUARE CAP"),
    ("setminus",   "SET MINUS"),
    ("emptyset",   "EMPTY SET"),
    ("varnothing", "EMPTY SET"),
    ("forall",     "FOR ALL"),
    ("exists",     "THERE EXISTS"),
    ("nexists",    "THERE DOES NOT EXIST"),
]

LOGIC = [
    ("land",      "LOGICAL AND"),
    ("wedge",     "LOGICAL AND"),
    ("lor",       "LOGICAL OR"),
    ("vee",       "LOGICAL OR"),
    ("neg",       "NOT SIGN"),
    ("lnot",      "NOT SIGN"),
    ("models",    "TRUE"),
    ("vdash",     "RIGHT TACK"),
    ("dashv",     "LEFT TACK"),
    ("therefore", "THEREFORE"),
    ("because",   "BECAUSE"),
]

ARROWS = [
    ("leftarrow",         "LEFTWARDS ARROW"),
    ("gets",              "LEFTWARDS ARROW"),
    ("rightarrow",        "RIGHTWARDS ARROW"),
    ("to",                "RIGHTWARDS ARROW"),
    ("uparrow",           "UPWARDS ARROW"),
    ("downarrow",         "DOWNWARDS ARROW"),
    ("leftrightarrow",    "LEFT RIGHT ARROW"),
    ("updownarrow",       "UP DOWN ARROW"),
    ("nearrow",           "NORTH EAST ARROW"),
    ("searrow",           "SOUTH EAST ARROW"),
    ("swarrow",           "SOUTH WEST ARROW"),
    ("nwarrow",           "NORTH WEST ARROW"),
    ("mapsto",            "RIGHTWARDS ARROW FROM BAR"),
    ("hookleftarrow",     "LEFTWARDS ARROW WITH HOOK"),
    ("hookrightarrow",    "RIGHTWARDS ARROW WITH HOOK"),
    ("rightleftharpoons", "RIGHTWARDS HARPOON OVER LEFTWARDS HARPOON"),
    ("Leftarrow",         "LEFTWARDS DOUBLE ARROW"),
    ("Rightarrow",        "RIGHTWARDS DOUBLE ARROW"),
    ("Uparrow",           "UPWARDS DOUBLE ARROW"),
    ("Downarrow",         "DOWNWARDS DOUBLE ARROW"),
    ("Leftrightarrow",    "LEFT RIGHT DOUBLE ARROW"),
    ("Updownarrow",       "UP DOWN DOUBLE ARROW"),
    ("longleftarrow",     "LONG LEFTWARDS ARROW"),
    ("longrightarrow",    "LONG RIGHTWARDS ARROW"),
    ("longleftrightarrow","LONG LEFT RIGHT ARROW"),
    ("Longleftarrow",     "LONG LEFTWARDS DOUBLE ARROW"),
    ("Longrightarrow",    "LONG RIGHTWARDS DOUBLE ARROW"),
    ("Longleftrightarrow","LONG LEFT RIGHT DOUBLE ARROW"),
    ("implies",           "LONG RIGHTWARDS DOUBLE ARROW"),
    ("impliedby",         "LONG LEFTWARDS DOUBLE ARROW"),
    ("iff",               "LONG LEFT RIGHT DOUBLE ARROW"),
]

# \R \Q \Z ... are user macros rather than base LaTeX, but they are what people
# actually type. \mathbb{R} routes through the same table (see Converter).
BLACKBOARD = [
    ("R", "DOUBLE-STRUCK CAPITAL R"),
    ("Q", "DOUBLE-STRUCK CAPITAL Q"),
    ("Z", "DOUBLE-STRUCK CAPITAL Z"),
    ("N", "DOUBLE-STRUCK CAPITAL N"),
    ("C", "DOUBLE-STRUCK CAPITAL C"),
    ("H", "DOUBLE-STRUCK CAPITAL H"),
    ("E", "MATHEMATICAL DOUBLE-STRUCK CAPITAL E"),
    ("F", "MATHEMATICAL DOUBLE-STRUCK CAPITAL F"),
    ("P", "DOUBLE-STRUCK CAPITAL P"),
]

DELIMITERS = [
    ("langle", "MATHEMATICAL LEFT ANGLE BRACKET"),
    ("rangle", "MATHEMATICAL RIGHT ANGLE BRACKET"),
    ("lfloor", "LEFT FLOOR"),
    ("rfloor", "RIGHT FLOOR"),
    ("lceil",  "LEFT CEILING"),
    ("rceil",  "RIGHT CEILING"),
]

MISC = [
    ("ldots",     "HORIZONTAL ELLIPSIS"),
    ("dots",      "HORIZONTAL ELLIPSIS"),
    ("cdots",     "MIDLINE HORIZONTAL ELLIPSIS"),
    ("vdots",     "VERTICAL ELLIPSIS"),
    ("ddots",     "DOWN RIGHT DIAGONAL ELLIPSIS"),
    ("ell",       "SCRIPT SMALL L"),
    ("hbar",      "PLANCK CONSTANT OVER TWO PI"),
    ("aleph",     "ALEF SYMBOL"),
    ("angle",     "ANGLE"),
    ("triangle",  "WHITE UP-POINTING TRIANGLE"),
    ("square",    "WHITE SQUARE"),
    ("dagger",    "DAGGER"),
    ("ddagger",   "DOUBLE DAGGER"),
    ("checkmark", "CHECK MARK"),
    ("Re",        "BLACK-LETTER CAPITAL R"),
    ("Im",        "BLACK-LETTER CAPITAL I"),
    ("wp",        "SCRIPT CAPITAL P"),
    ("imath",     "LATIN SMALL LETTER DOTLESS I"),
    ("jmath",     "LATIN SMALL LETTER DOTLESS J"),
]

GROUPS = [
    ("Greek, lower case",        GREEK_LOWER),
    ("Greek, upper case",        GREEK_UPPER),
    ("Operators",                OPERATORS),
    ("Relations",                RELATIONS),
    ("Set notation",             SET_NOTATION),
    ("Logic",                    LOGIC),
    ("Arrows",                   ARROWS),
    ("Blackboard bold",          BLACKBOARD),
    ("Delimiters",               DELIMITERS),
    ("Miscellaneous",            MISC),
]

# ---------------------------------------------------------------------------
# Scripts. Coverage is deliberately incomplete and the gaps are load-bearing:
# a missing letter must produce .unsupported, never a silent literal.
# ---------------------------------------------------------------------------

DIGIT_WORDS = ["ZERO","ONE","TWO","THREE","FOUR","FIVE","SIX","SEVEN","EIGHT","NINE"]

SUPERSCRIPT = (
    [(str(i), "SUPERSCRIPT " + w) for i, w in enumerate(DIGIT_WORDS)] +
    [("+", "SUPERSCRIPT PLUS SIGN"),
     ("-", "SUPERSCRIPT MINUS"),
     ("=", "SUPERSCRIPT EQUALS SIGN"),
     ("(", "SUPERSCRIPT LEFT PARENTHESIS"),
     (")", "SUPERSCRIPT RIGHT PARENTHESIS")] +
    # Every lowercase letter except q.
    [("a", "MODIFIER LETTER SMALL A"),
     ("b", "MODIFIER LETTER SMALL B"),
     ("c", "MODIFIER LETTER SMALL C"),
     ("d", "MODIFIER LETTER SMALL D"),
     ("e", "MODIFIER LETTER SMALL E"),
     ("f", "MODIFIER LETTER SMALL F"),
     ("g", "MODIFIER LETTER SMALL G"),
     ("h", "MODIFIER LETTER SMALL H"),
     ("i", "SUPERSCRIPT LATIN SMALL LETTER I"),
     ("j", "MODIFIER LETTER SMALL J"),
     ("k", "MODIFIER LETTER SMALL K"),
     ("l", "MODIFIER LETTER SMALL L"),
     ("m", "MODIFIER LETTER SMALL M"),
     ("n", "SUPERSCRIPT LATIN SMALL LETTER N"),
     ("o", "MODIFIER LETTER SMALL O"),
     ("p", "MODIFIER LETTER SMALL P"),
     # q: no superscript form exists in Unicode.
     ("r", "MODIFIER LETTER SMALL R"),
     ("s", "MODIFIER LETTER SMALL S"),
     ("t", "MODIFIER LETTER SMALL T"),
     ("u", "MODIFIER LETTER SMALL U"),
     ("v", "MODIFIER LETTER SMALL V"),
     ("w", "MODIFIER LETTER SMALL W"),
     ("x", "MODIFIER LETTER SMALL X"),
     ("y", "MODIFIER LETTER SMALL Y"),
     ("z", "MODIFIER LETTER SMALL Z")]
)

SUBSCRIPT = (
    [(str(i), "SUBSCRIPT " + w) for i, w in enumerate(DIGIT_WORDS)] +
    [("+", "SUBSCRIPT PLUS SIGN"),
     ("-", "SUBSCRIPT MINUS"),
     ("=", "SUBSCRIPT EQUALS SIGN"),
     ("(", "SUBSCRIPT LEFT PARENTHESIS"),
     (")", "SUBSCRIPT RIGHT PARENTHESIS")] +
    # Only a e h i j k l m n o p r s t u v x. Missing: b c d f g q w y z.
    [(c, "LATIN SUBSCRIPT SMALL LETTER " + c.upper())
     for c in "aehijklmnoprstuvx"]
)


# Precomposed vulgar fractions. Where one exists it is a true single-character
# representation, not an approximation, so these convert rather than fall back.
VULGAR_FRACTIONS = [
    ("0/3",  "VULGAR FRACTION ZERO THIRDS"),
    ("1/2",  "VULGAR FRACTION ONE HALF"),
    ("1/3",  "VULGAR FRACTION ONE THIRD"),
    ("2/3",  "VULGAR FRACTION TWO THIRDS"),
    ("1/4",  "VULGAR FRACTION ONE QUARTER"),
    ("3/4",  "VULGAR FRACTION THREE QUARTERS"),
    ("1/5",  "VULGAR FRACTION ONE FIFTH"),
    ("2/5",  "VULGAR FRACTION TWO FIFTHS"),
    ("3/5",  "VULGAR FRACTION THREE FIFTHS"),
    ("4/5",  "VULGAR FRACTION FOUR FIFTHS"),
    ("1/6",  "VULGAR FRACTION ONE SIXTH"),
    ("5/6",  "VULGAR FRACTION FIVE SIXTHS"),
    ("1/7",  "VULGAR FRACTION ONE SEVENTH"),
    ("1/8",  "VULGAR FRACTION ONE EIGHTH"),
    ("3/8",  "VULGAR FRACTION THREE EIGHTHS"),
    ("5/8",  "VULGAR FRACTION FIVE EIGHTHS"),
    ("7/8",  "VULGAR FRACTION SEVEN EIGHTHS"),
    ("1/9",  "VULGAR FRACTION ONE NINTH"),
    ("1/10", "VULGAR FRACTION ONE TENTH"),
]

# Joins a superscript numerator to a subscript denominator, which is how any
# other fraction gets written: 10/17 becomes the eight characters of 10, this,
# and 17.
FRACTION_SLASH = [("slash", "FRACTION SLASH")]

ROOTS = [("2", "SQUARE ROOT"), ("3", "CUBE ROOT"), ("4", "FOURTH ROOT")]

# ---------------------------------------------------------------------------

def resolve(pairs, label):
    out = []
    for cmd, name in pairs:
        try:
            ch = unicodedata.lookup(name)
        except KeyError:
            sys.exit("FATAL: %s: no Unicode character named %r (for %r)" % (label, name, cmd))
        out.append((cmd, ch, name))
    return out

def swift_escape(cmd):
    return cmd.replace("\\", "\\\\").replace('"', '\\"')

def codepoint(ch):
    return "U+%04X" % ord(ch)

def entry_line(cmd, ch, name, width):
    key = '"%s":' % swift_escape(cmd)
    return '        %-*s "%s",%s// %s %s' % (
        width + 3, key, ch, " " * 4, codepoint(ch), name)

def emit_dict(title, resolved):
    width = max(len(swift_escape(c)) for c, _, _ in resolved)
    lines = ["        // MARK: %s" % title]
    for cmd, ch, name in resolved:
        lines.append(entry_line(cmd, ch, name, width))
    return "\n".join(lines)

def main():
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

    resolved_groups = [(t, resolve(p, t)) for t, p in GROUPS]

    # A duplicate command would silently shadow in a Swift dictionary literal.
    seen = {}
    for title, res in resolved_groups:
        for cmd, ch, name in res:
            if cmd in seen:
                sys.exit("FATAL: duplicate command \\%s (%s and %s)" % (cmd, seen[cmd], title))
            seen[cmd] = title

    sup = resolve(SUPERSCRIPT, "superscript")
    sub = resolve(SUBSCRIPT, "subscript")
    roots = resolve(ROOTS, "roots")
    fractions = resolve(VULGAR_FRACTIONS, "vulgar fractions")
    slash = resolve(FRACTION_SLASH, "fraction slash")

    header = ("// Generated by Tools/generate_tables.py — do not edit by hand.\n"
              "//\n"
              "// Every character below is resolved from its official Unicode name via\n"
              "// Python's unicodedata.lookup, not transcribed from memory. Re-run the\n"
              "// generator to change this file.\n\n")

    # ---- SymbolTable.swift ----
    # Emits structured entries rather than a bare dictionary: the symbol
    # browser searches on category and Unicode name, not just the command.
    def entry_rows(title, resolved):
        width = max(len(swift_escape(c)) for c, _, _ in resolved)
        rows = ["        // MARK: %s" % title]
        for cmd, ch, name in resolved:
            rows.append(
                '        .init(command: %-*s glyph: "%s", unicodeName: "%s", category: "%s"),'
                % (width + 3, '"%s",' % swift_escape(cmd), ch, name, title))
        return "\n".join(rows)

    body = "\n\n".join(entry_rows(t, r) for t, r in resolved_groups)
    with open(os.path.join(root, "Sources/LaTeXUnicode/SymbolTableData.swift"), "w") as f:
        f.write(header)
        f.write("public extension SymbolTable {\n\n")
        f.write("    /// The coverage table. See SymbolEntry.swift for the derived lookups.\n")
        f.write("    static let entries: [SymbolEntry] = [\n")
        f.write(body)
        f.write("\n    ]\n}\n")

    # ---- ScriptTables.swift ----
    supw = max(len(swift_escape(c)) for c, _, _ in sup)
    subw = max(len(swift_escape(c)) for c, _, _ in sub)
    rw = max(len(c) for c, _, _ in roots)
    with open(os.path.join(root, "Sources/LaTeXUnicode/ScriptTables.swift"), "w") as f:
        f.write(header)
        f.write("public enum ScriptTables {\n\n")
        f.write("    /// Characters that have a Unicode superscript form.\n")
        f.write("    /// Complete for digits; every lowercase letter except `q`.\n")
        f.write("    public static let superscripts: [Character: Character] = [\n")
        f.write("\n".join(entry_line(c, ch, n, supw) for c, ch, n in sup))
        f.write("\n    ]\n\n")
        f.write("    /// Characters that have a Unicode subscript form.\n")
        f.write("    /// Complete for digits; letters only `a e h i j k l m n o p r s t u v x`.\n")
        f.write("    /// Missing: `b c d f g q w y z` — these must return `.unsupported`.\n")
        f.write("    public static let subscripts: [Character: Character] = [\n")
        f.write("\n".join(entry_line(c, ch, n, subw) for c, ch, n in sub))
        f.write("\n    ]\n\n")
        f.write("    /// Radical signs by index. Only these three exist as single characters.\n")
        f.write("    public static let radicals: [Int: Character] = [\n")
        f.write("\n".join('        %-*s "%s",    // %s %s' % (rw + 2, c + ":", ch, codepoint(ch), n)
                          for c, ch, n in roots))
        f.write("\n    ]\n\n")
        f.write("    /// Precomposed fractions, keyed \"numerator/denominator\".\n")
        f.write("    /// A single character here is an exact representation, not an\n")
        f.write("    /// approximation, so it converts rather than falls back.\n")
        f.write("    public static let vulgarFractions: [String: String] = [\n")
        fw = max(len(c) for c, _, _ in fractions)
        f.write("\n".join('        %-*s "%s",    // %s %s' % (fw + 3, '"%s":' % c, ch, codepoint(ch), n)
                          for c, ch, n in fractions))
        f.write("\n    ]\n\n")
        f.write("    /// Joins a superscript numerator to a subscript denominator.\n")
        f.write('    public static let fractionSlash: Character = "%s"    // %s %s\n'
                % (slash[0][1], codepoint(slash[0][1]), slash[0][2]))
        f.write("}\n")

    # ---- GeneratedCodepointChecks.swift ----
    def calls(access, resolved, char_key):
        out = []
        for cmd, ch, name in resolved:
            key = '"%s"' % swift_escape(cmd)
            if char_key:
                key += " as Character"
                val = "0x%04X" % ord(ch)
            else:
                val = "[%s]" % ", ".join("0x%04X" % s for s in map(ord, ch))
            out.append('    scalar(c, %s[%s], %s, "%s")' % (access, key, val, name))
        return "\n".join(out)

    path = os.path.join(root, "Sources/LaTeXUnicodeChecks/GeneratedCodepointChecks.swift")
    with open(path, "w") as f:
        f.write(header)
        f.write("// Asserts the exact scalar value of every table entry, so a hand-edit that\n")
        f.write("// changes a glyph fails loudly.\n\n")
        f.write("import LaTeXUnicode\n\n")

        f.write("func runCodepointChecks(_ c: Checker) {\n")
        for title, res in resolved_groups:
            f.write("    // MARK: %s\n%s\n\n" % (title, calls("SymbolTable.symbols", res, False)))
        f.write("    // MARK: Superscripts\n%s\n\n" % calls("ScriptTables.superscripts", sup, True))
        f.write("    // MARK: Subscripts\n%s\n\n" % calls("ScriptTables.subscripts", sub, True))
        f.write("    // MARK: Vulgar fractions\n%s\n\n"
                % "\n".join('    scalar(c, ScriptTables.vulgarFractions[\"%s\"], [%s], \"%s\")'
                            % (cmd, "0x%04X" % ord(ch), name) for cmd, ch, name in fractions))
        f.write("    // MARK: Radicals\n%s\n\n"
                % "\n".join('    scalar(c, ScriptTables.radicals[%s], %s, "%s")'
                            % (cmd, "0x%04X" % ord(ch), name) for cmd, ch, name in roots))
        f.write("    // MARK: Table sizes — a dropped entry must fail, not pass quietly.\n")
        f.write("    c.equal(SymbolTable.symbols.count, %d, \"symbol count\")\n" % len(seen))
        f.write("    c.equal(ScriptTables.superscripts.count, %d, \"superscript count\")\n" % len(sup))
        f.write("    c.equal(ScriptTables.subscripts.count, %d, \"subscript count\")\n" % len(sub))
        f.write("}\n\n")

        f.write("""private func scalar(_ c: Checker, _ actual: String?, _ expected: [UInt32], _ name: String,
                    file: StaticString = #filePath, line: UInt = #line) {
    guard let actual else { return c.fail("missing entry for \\(name)", file: file, line: line) }
    c.equal(actual.unicodeScalars.map(\\.value), expected, name, file: file, line: line)
}

private func scalar(_ c: Checker, _ actual: Character?, _ expected: UInt32, _ name: String,
                    file: StaticString = #filePath, line: UInt = #line) {
    guard let actual else { return c.fail("missing entry for \\(name)", file: file, line: line) }
    c.equal(actual.unicodeScalars.map(\\.value), [expected], name, file: file, line: line)
}
""")

    print("symbols: %d   superscripts: %d   subscripts: %d"
          % (len(seen), len(sup), len(sub)))

main()
