# LaTeX-Squigly

An inline LaTeX-to-Unicode menu bar app for macOS. Type `\alpha` or `\int_5^6`
in any app and it becomes `α` or `∫₅⁶` in place — real text, never an image.

- **Phase 0 — conversion engine.** Done. Pure Swift, no system APIs.
- **Phase 1 — text replacement.** Done. Event tap, replacement, permissions.
- **Phase 2 — per-app suppression.** **Not started.** See the warning below.
- **Phase 3 — full UI.** Not started.

## ⚠️ Phase 2 has not landed

There is no per-app exclusion list yet, so the app cannot tell a chat window
from a `.tex` file. **Turn it off before editing LaTeX source or opening
Overleaf**, or it will convert your `\alpha` into `α` and corrupt the document.

That is why conversion **ships disabled** and has to be switched on from the
menu bar each time you install. Do not hand this to a tester without saying so.

## Running the app

```
Scripts/setup-signing.sh    once, BEFORE the first install
Scripts/install.sh          build from source, install to /Applications
open /Applications/LaTeX-Squigly.app
```

Order matters. macOS ties the Accessibility grant to the code signature, so
signing after you have granted permission invalidates the grant. If the app
ever stops responding to what you type, ask it why:

```
/Applications/LaTeX-Squigly.app/Contents/MacOS/LaTeX-Squigly --diagnose
```

Then grant **Accessibility** (to replace text) and **Input Monitoring** (to
notice you typing) when the menu bar item asks, and tick *Enable conversion*.

Nothing typed is stored or transmitted. The rolling buffer is 64 characters,
in memory only, and is discarded on every command, Return, arrow key, click,
app switch and shortcut.

## Running the tests

```
swift run latex-squigly-check     # works with Command Line Tools alone
swift test                        # requires Xcode
```

Both run the same suite. On macOS, XCTest *and* swift-testing ship inside
`Xcode.app`, so `swift test` cannot work on a machine with only the Command
Line Tools installed. The expectations therefore live in a plain-Swift target,
`Sources/LaTeXUnicodeChecks`, with two thin front ends: the
`latex-squigly-check` executable and a `Tests/LaTeXUnicodeTests` wrapper. There
is exactly one copy of every expectation.

Xcode is on the critical path for Phase 1 anyway (AppKit app bundle, code
signing), so this is a stopgap, not a permanent shape.

Current status: **1479 checks passing.**

## Trying conversions by hand

```
swift run latex-squigly '\int_5^6'          # one-shot
swift run latex-squigly                      # interactive, one fragment per line
echo '\alpha' | swift run latex-squigly      # pipe
swift run latex-squigly -c '\R'              # also print U+ values
```

Replacement text goes to stdout and explanations to stderr, so the tool
composes. Exit status is 0 for converted and fallback, 1 for unsupported.

## API

```swift
public enum ConversionResult: Equatable {
    case converted(String)                 // faithful Unicode
    case fallback(String, reason: String)  // linear approximation; tell the user
    case unsupported(reason: String)       // leave the input alone; tell the user why
}

public func convert(_ latex: String) -> ConversionResult
```

`ConversionResult` also exposes `.text`, `.reason`, and `.requiresUserNotice`
for the Phase 1 call site.

`convert` takes a whole fragment, not just one command. Literal text passes
through:

```swift
convert("\\alpha")             // .converted("α")
convert("\\int_5^6")           // .converted("∫₅⁶")
convert("\\alpha + \\beta \\leq x^2")
                               // .converted("α + β ≤ x²")
convert("\\frac{x+1}{y-2}")    // .fallback("(x+1)/(y-2)", reason: …)
convert("x_b")                 // .unsupported("There is no Unicode subscript for “b”.")
convert("\\begin{matrix}")     // .unsupported("The matrix environment needs …")
```

## Decisions

**All or nothing.** If any part of the input has no faithful Unicode form, the
whole call returns `.unsupported`. A half-converted string is never produced —
this is the failure mode the app exists to avoid. `.unsupported` beats
`.fallback`, which beats `.converted`.

**Longest match on command names.** A command name is a backslash followed by
the longest run of ASCII letters, so the `\in` / `\inf` / `\infty` / `\int`
family resolves without ambiguity. `\int` can never be read as `\in` + `t`, and
a longer unknown command (`\ints`) never decays into a shorter known one.

**Terminators are preserved.** The space or tab that ends a command name is
*not* consumed; it is emitted as ordinary text, so `\alpha ` becomes `α `. This
diverges from TeX, which swallows it. In running prose, eating the space is the
wrong default: `\alpha + \beta ` should read `α + β`, not `α+ β`.

**…except before an argument.** A command that takes an argument skips
whitespace first, so `\mathbb R`, `\frac 1 2` and `\sqrt 2` work as in LaTeX.
This doesn't conflict with the rule above: symbol commands take no argument and
so never hit this path.

**Fallbacks parenthesise only when needed.** `\frac{1}{2}` → `1/2`;
`\frac{x+1}{y-2}` → `(x+1)/(y-2)`. Single characters are left bare.

**Refused commands are recognised, not unknown.** `\vec` returns "An accent
cannot be drawn over other characters in plain text", not "Unknown command
\vec". The first tells the user the truth about the constraint; the second
suggests a typo.

## Coverage

202 symbols: Greek (both cases, plus `\var…` forms), operators, relations, set
notation, logic, arrows, blackboard bold (`\R \Q \Z \N \C \H \E \F \P` and
`\mathbb{…}`), delimiters, ellipses. 32 named operators (`\sin`, `\log`,
`\lim`, …) convert to their upright roman text.

Superscripts: all ten digits, `+ - = ( )`, and every lowercase letter **except
`q`**. Subscripts: all ten digits, `+ - = ( )`, and only
`a e h i j k l m n o p r s t u v x` — **missing `b c d f g q w y z`**. Requesting
a missing letter returns `.unsupported`. Uppercase has no script forms in
Unicode at all.

Fallbacks: `\frac`, `\sqrt` (including `\sqrt[n]`), `\binom`.

Unsupported: environments, stacked constructions, accents, alternate alphabets,
spacing commands, line breaks, nested scripts.

### Variant letters

Following `unicode-math`, `\epsilon` → ϵ (U+03F5, lunate) and `\varepsilon` → ε
(U+03B5); `\phi` → ϕ (U+03D5) and `\varphi` → φ (U+03C6). If you'd rather
`\epsilon` gave the familiar ε, swap the two names in
`Tools/generate_tables.py` and regenerate — it's a one-line change.

## The coverage table is generated, not typed

`Sources/LaTeXUnicode/SymbolTable.swift` and `ScriptTables.swift` are produced
by `Tools/generate_tables.py`. Each entry is specified by its **Unicode
character name**, and the character is resolved by `unicodedata.lookup` against
the Unicode database shipped with Python:

```python
("alpha", "GREEK SMALL LETTER ALPHA"),
```

A wrong name is a hard error at generation time rather than a wrong glyph at
runtime. This is deliberate: hand-written LaTeX→Unicode tables get codepoints
wrong in ways that look right. The generator also rejects duplicate commands,
which would silently shadow in a Swift dictionary literal.

`Sources/LaTeXUnicodeChecks/GeneratedCodepointChecks.swift` is generated
alongside and asserts the exact scalar value of all 277 table entries, so a later
hand-edit to a table fails loudly.

To change a table: edit the generator, run `python3 Tools/generate_tables.py`,
re-run the checks.

## Deliberately left out — tell me which you want

None of these were omitted from uncertainty; they're scope calls for you to
overrule.

- **Combining accents.** `\hat{x}` → `x` + U+0302 is real inline Unicode, but
  renders inconsistently across the apps this types into. Currently
  `.unsupported` with an honest reason.
- **Bold / script / fraktur alphabets.** 𝐀 𝒜 𝔄 exist (U+1D400 onward).
  Currently `.unsupported`.
- **Greek super- and subscripts.** ᵅ ᵝ ᵞ and ᵦ ᵧ ᵨ exist for a handful of
  letters. Partial coverage, so left out entirely.
- **Vulgar fractions.** `\frac{1}{2}` → ½ would make that case `.converted`
  rather than `.fallback`. Better output, but the spec treats fractions as a
  fallback case throughout, so I didn't add it unasked.
- **Spacing commands.** `\,` `\;` `\quad` currently `.unsupported`. U+2009 and
  friends exist if you want them.
- **`\pmod`, `\overset`, `\underset`.**

## How replacement works

`InputTracking` holds the typing logic with no system APIs in it, so the part
most likely to be wrong is unit-tested rather than only observable by typing
into Slack. The app target is a thin shell over it.

**Two things fire.** A `$...$` span converts whatever is inside it, and a
candidate starting with a backslash converts itself:

```
\alpha          ->  α
\int_5^6        ->  ∫₅⁶
$x^2$           ->  x²
$\alpha + x^2$  ->  α + x²
```

**Bare `x^2` deliberately does not fire.** Otherwise `2^3` in prose, or `a_b` in
an identifier, would rewrite itself. Write `$x^2$` when you mean maths —
nobody types that by accident. `\alpha_b` still reports its missing subscript,
because it opens with a command.

**A `$...$` span must contain a `\`, `^` or `_` to count as maths**, so `$5$`
stays money. Failures inside a span are always reported, unlike the backslash
path: wrapping something in delimiters is a clear statement of intent, so
silence would be the wrong answer.

**Unknown commands stay silent.** `C:\Users ` contains a backslash but `Users`
is nobody's command, so nothing happens and nothing is reported. You are only
told about failures you plausibly meant to cause.

**Space and tab terminate; Return does not.** In a chat app Return sends the
message, and racing a replacement against a send is how you post half a symbol.

**The terminator is suppressed and retyped.** The tap is `.defaultTap` rather
than `.listenOnly` for exactly this reason, and the replacement is posted
synchronously inside the callback — dispatching it leaves a window in which the
next keystroke lands first and the delete count eats a character the user meant
to keep.

**Synthetic events are stamped** via `CGEventSource.userData` so the tap ignores
its own output instead of feeding on it.

## Signing and distribution

```
Scripts/setup-signing.sh    one-time: a stable self-signed identity
Scripts/make-app.sh         assemble and sign the .app from SwiftPM output
Scripts/install.sh          build from source and install to /Applications
```

**Signing is a development need before it is a distribution one.** macOS TCC
identifies an app by its code signature, and ad-hoc signatures key on the code
directory hash, which changes on every build — so without a stable identity you
re-grant Accessibility and Input Monitoring on every single rebuild.
`setup-signing.sh` creates one. Verified: codesign accepts an untrusted
self-signed certificate as long as its keychain is in the search list, so this
does not touch the trust store.

**Building from source is the distribution path.** Not a fallback — the only
free one that is actually clean. Tested on macOS 15.6:

| How the app arrives | Quarantined? |
|---|---|
| Built locally (`Scripts/install.sh`) | No — opens normally |
| Downloaded `.tar.gz`, extracted with `tar -xzf` | **Yes** |
| Downloaded `.dmg`, dragged from Finder | Yes |

Command-line `tar` is widely believed to sidestep quarantine. It does for plain
files, but **not** for `.app` bundles: macOS writes a fresh quarantine attribute
(flag `0281`, not the archive's own) onto the extracted bundle's contents. A
downloaded build therefore still costs the user a trip through System Settings →
Privacy & Security, which on macOS 15 no longer has the old Control-click → Open
shortcut.

Notarization is the only thing that removes that step, and it requires a
Developer ID certificate, which requires the paid Apple Developer Program.
Until then: ship source, and `make-app.sh TARBALL=1` for anyone who won't build
it — with honest instructions about what they'll see.

## Non-goals

No image rendering, cloud sync, accounts, text editor, note-taking, iOS,
Windows, Linux, web version, telemetry, or auto-update. Not now, not later.

## Layout

```
Sources/LaTeXUnicode/          engine
  ConversionResult.swift       the result type
  Tokenizer.swift              string → tokens; longest match, terminator rules
  Converter.swift              public convert(); assembly and strictness
  SymbolTable.swift            generated
  ScriptTables.swift           generated
  TextOperators.swift          \sin, \log, … → upright roman text
  UnsupportedCommands.swift    recognised-but-refused, with user-facing reasons
Sources/LaTeXUnicodeChecks/    the test suite (no XCTest)
Sources/latex-squigly-check/   CLI runner
Tests/LaTeXUnicodeTests/       swift test wrapper
Tools/generate_tables.py       table generator
Sources/latex-squigly/         convert CLI for trying things by hand
Scripts/                       signing, bundling, install
```
