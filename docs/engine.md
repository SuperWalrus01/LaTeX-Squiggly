# The engine

The conversion engine is the Swift module in `Sources/LaTeXUnicode`, with the
typing rules in `Sources/InputTracking`. Neither uses a system API, so both are
fully testable, and together they are the source of truth for every platform:
the Windows and Chrome versions are ports whose tables are generated from this
engine and whose answers are checked against it. See
[architecture.md](architecture.md) for how that works.

## The API

```swift
public enum ConversionResult: Equatable {
    case converted(String)                 // faithful Unicode
    case fallback(String, reason: String)  // linear approximation; tell the user
    case unsupported(reason: String)       // leave the input alone; tell the user why
}

public func convert(_ latex: String,
                    options: ConversionOptions = .default) -> ConversionResult

public struct ConversionOptions: Equatable, Sendable {
    public var keepUnrenderableScripts: Bool   // default false
}
```

`ConversionResult` also exposes `.text`, `.reason` and `.requiresUserNotice`
for the call site in the app.

`convert` takes a whole fragment, not just one command. Literal text passes
through:

```swift
convert("\\alpha")             // .converted("α")
convert("\\int_5^6")           // .converted("∫₅⁶")
convert("\\alpha + \\beta \\leq x^2")
                               // .converted("α + β ≤ x²")
convert("\\frac{x+1}{y-2}")    // .fallback("(x+1)∕(y−2)", reason: …)
convert("x_b")                 // .unsupported("There is no Unicode subscript for “b”.")
convert("\\begin{matrix}")     // .unsupported("The matrix environment needs …")
```

## Trying conversions by hand

```
swift run latex-squiggly '\int_5^6'          # one-shot
swift run latex-squiggly                      # interactive, one fragment per line
echo '\alpha' | swift run latex-squiggly      # pipe
swift run latex-squiggly -c '\R'              # also print U+ values
swift run latex-squiggly -k '\int_0^\infty'   # keep a script Unicode cannot make
```

Replacement text goes to stdout and explanations to stderr, so the tool
composes. Exit status is 0 for converted and fallback, 1 for unsupported.

It reports what the *app* would do, not just what the engine would do, so
`$x^2$` shows `x²` rather than `$x²$`. Input the app would not fire on falls
through to the raw engine result, which keeps the engine directly testable.
`--app-only` turns that fall-through off; the site's examples are generated
with it, so the page cannot advertise a conversion the app never makes.

## Tests

```
swift run latex-squiggly-check     # works with the Command Line Tools alone
swift test                         # requires Xcode
```

Both run the same suite. On macOS, XCTest and swift-testing ship inside
`Xcode.app`, so `swift test` cannot work on a machine with only the Command
Line Tools installed. The expectations therefore live in a plain Swift target,
`Sources/LaTeXUnicodeChecks`, with two thin front ends: the
`latex-squiggly-check` executable and the `Tests/LaTeXUnicodeTests` wrapper.
There is exactly one copy of every expectation.

To run everything the repository checks, across all platforms, use
`scripts/check-all.sh`.

## Decisions

**All or nothing.** If any part of the input has no faithful Unicode form, the
whole call returns `.unsupported`. A half-converted string is never produced:
that is the failure the app exists to avoid. `.unsupported` beats `.fallback`,
which beats `.converted`. The single exception is opt-in and reports itself as
a fallback; see [Scripts Unicode cannot make](#scripts-unicode-cannot-make).

**Longest match on command names.** A command name is a backslash followed by
the longest run of ASCII letters, so the `\in` / `\inf` / `\infty` / `\int`
family resolves without ambiguity. `\int` can never be read as `\in` + `t`, and
a longer unknown command (`\ints`) never decays into a shorter known one.

**Terminators are preserved.** The space or tab that ends a command name is
not consumed; it is emitted as ordinary text, so `\alpha ` becomes `α `. This
diverges from TeX, which swallows it. In running prose, eating the space is the
wrong default: `\alpha + \beta ` should read `α + β`, not `α+ β`.

**…except before an argument.** A command that takes an argument skips
whitespace first, so `\mathbb R`, `\frac 1 2` and `\sqrt 2` work as in LaTeX.
This does not conflict with the rule above: symbol commands take no argument
and so never reach this path.

**Fallbacks parenthesise only when needed.** `\frac{x+1}{y-2}` gives
`(x+1)∕(y−2)`, while single characters are left bare.

**Refused commands are recognised, not unknown.** `\vec` returns "An accent
cannot be drawn over other characters in plain text", not "Unknown command
\vec". The first tells the user the truth about the constraint; the second
suggests a typo.

## When typing becomes a conversion

These rules live in `Sources/InputTracking` and are shared by every platform.

**Two things fire.** A `$...$` span converts whatever is inside it, and a
candidate starting with a backslash converts itself:

```
\alpha             ->  α
\int_5^6           ->  ∫₅⁶
\frac{\alpha}{2}   ->  α∕2
$x^2$              ->  x²
$\alpha + x^2$     ->  α + x²
```

**A candidate starts at the first backslash, not the last.** Everything typed
since the last space is one fragment, so `\frac{\alpha}{2}` is replaced whole
rather than having `\alpha` picked out of the middle of it. Reading from the
last backslash left `\alpha}{2}`, which really is unbalanced, and said so about
LaTeX that was written correctly.

**Bare `x^2` deliberately does not fire.** Otherwise `2^3` in prose, or `a_b`
in an identifier, would rewrite itself. Write `$x^2$` when you mean maths;
nobody types that by accident. `\alpha_b` still reports its missing subscript,
because it opens with a command.

**A `$...$` span must contain a `\`, `^` or `_` to count as maths**, so `$5$`
stays money. Failures inside a span are always reported, unlike the backslash
path: wrapping something in delimiters is a clear statement of intent, so
silence would be the wrong answer.

**Unknown commands stay silent.** `C:\Users ` contains a backslash but `Users`
is nobody's command, so nothing happens and nothing is reported. You are only
told about failures you plausibly meant to cause. A refusal needs every
command in the fragment to be one the converter knows, which is what keeps
`C:\path\to\file ` quiet even though `\to` is real.

**Space and tab terminate; Return does not.** In a chat app Return sends the
message, and racing a replacement against a send is how you post half a
symbol. (The Chrome extension uses space only, because Tab moves focus in a
browser.)

## Coverage

202 symbols: Greek (both cases, plus `\var…` forms), operators, relations, set
notation, logic, arrows, blackboard bold (`\R \Q \Z \N \C \H \E \F \P` and
`\mathbb{…}`), delimiters and ellipses. 33 named operators (`\sin`, `\log`,
`\lim`, …) convert to their upright roman text.

Superscripts: all ten digits, `+ - = ( )`, and every lowercase letter except
`q`. Subscripts: all ten digits, `+ - = ( )`, and only
`a e h i j k l m n o p r s t u v x`; `b c d f g q w y z` have no subscript form.
Requesting a missing letter returns `.unsupported`. Uppercase has no script
forms in Unicode at all.

Fractions convert rather than falling back where Unicode allows it. There is no
stacked fraction in Unicode, so the choice is between compact and legible, and
the rule picks whichever suits the content:

```
\frac{1}{2}       ->  ½             precomposed character
\frac{5}{8}       ->  ⅝             precomposed character
\frac{10}{17}     ->  ¹⁰⁄₁₇         composed: superscript ⁄ subscript
\frac{n}{2}       ->  ⁿ⁄₂           composed
\frac{x+1}{2}     ->  (x+1)∕2       linear
\frac{x-2}{x-4}   ->  (x−2)∕(x−4)   linear
\frac{a}{b}       ->  a∕b           linear: no subscript b exists
```

Composition is capped at what stays readable: both sides all digits (legible at
any length), or both sides at most two characters. Superscript `x` against
subscript `x` is nearly indistinguishable at text size, so longer alphabetic
fractions read better on one line.

Linear maths uses real mathematical characters, U+2212 MINUS SIGN and U+2215
DIVISION SLASH, not the ASCII hyphen and solidus. A hyphen is shorter, sits
lower, and reads as a word break. `\text{}` keeps its hyphens, so "well-known"
is not mangled. One trade-off: the output is not ASCII, so it will not paste
into a calculator or source code as-is.

Remaining fallbacks: `\sqrt` (including `\sqrt[n]`) and `\binom`.

Unsupported: environments, stacked constructions, accents, alternate alphabets,
spacing commands, line breaks and nested scripts.

### Variant letters

Following `unicode-math`, `\epsilon` gives ϵ (U+03F5, lunate) and `\varepsilon`
gives ε (U+03B5); `\phi` gives ϕ (U+03D5) and `\varphi` gives φ (U+03C6).
Swapping either pair is a one-line change in `scripts/generate-swift-tables.py`.

## Scripts Unicode cannot make

Unicode has raised forms for some characters and not others. There is a
superscript `n` and a superscript `2`; there is no superscript `∞`, no
superscript `α`, and no way to nest one raised character inside another. So
`\Sigma_{i=1}^\infty{a_i}` is correct LaTeX that has no honest inline form, and
by default it is refused whole, with the reason.

`ConversionOptions.keepUnrenderableScripts` (the **Scripts** switch in the Mac
app's settings, `-k` on the command line) offers the other answer. On, every
part that has a Unicode form gets one, and only the script that has none keeps
the way it was typed:

```
\Sigma_{i=1}^\infty{a_i}   off ->  refused: "There is no Unicode superscript for ∞."
                            on ->  Σᵢ₌₁^∞aᵢ
\int_0^\infty               on ->  ∫₀^∞
x^{a^b}                     on ->  x^(aᵇ)
```

It reports itself as a `.fallback`, so the notice still fires and nothing is
substituted silently. The rules it keeps:

- **All or nothing within one script.** `x^{1q}` gives `x^(1q)`, not `x¹q`.
  Half a script raised and half not reads as a typo.
- **Parenthesised past one character**, for the reason `\frac` parenthesises:
  `x^(n+1)` says something `x^n+1` does not.
- **Scripts only.** `\vec{v}` and `\begin{matrix}` are still refused. A script
  can be written back in the notation it was typed in; an accent over a letter
  and a two-dimensional layout cannot.

It is off by default because its output puts converted characters and raw LaTeX
on the same line. Text left alone is always honest about what happened. Mixed
text is only sometimes what was wanted.

## The tables are generated, not typed

`Sources/LaTeXUnicode/SymbolTableData.swift` and `ScriptTables.swift` are
produced by `scripts/generate-swift-tables.py`. Each entry is specified by its
**Unicode character name**, and the character is resolved by
`unicodedata.lookup` against the Unicode database shipped with Python:

```python
("alpha", "GREEK SMALL LETTER ALPHA"),
```

A wrong name is a hard error at generation time rather than a wrong glyph at
runtime. This is deliberate: hand-written LaTeX-to-Unicode tables get codepoints
wrong in ways that look right. The generator also rejects duplicate commands,
which would silently shadow each other in a Swift dictionary literal.

`Sources/LaTeXUnicodeChecks/GeneratedCodepointChecks.swift` is generated
alongside and asserts the exact scalar value of every table entry, so a later
hand edit to a table fails loudly.

To change a table, edit the generator and follow
[Changing the engine](../CONTRIBUTING.md#changing-the-engine).

## Not supported, on purpose

None of these were left out from uncertainty. Each is a scope decision, and an
issue asking for one is welcome.

- **Combining accents.** `\hat{x}` as `x` + U+0302 is real inline Unicode, but
  it renders inconsistently across the apps this types into. Currently refused
  with a reason.
- **Bold, script and fraktur alphabets.** 𝐀 𝒜 𝔄 exist (U+1D400 onward).
  Currently refused.
- **Greek superscripts and subscripts.** ᵅ ᵝ ᵞ and ᵦ ᵧ ᵨ exist for a handful of
  letters only, so they are left out entirely rather than half supported.
- **Spacing commands.** `\,` `\;` `\quad` are refused. U+2009 and its relatives
  exist if they are wanted.
- **`\pmod`, `\overset`, `\underset`.**
