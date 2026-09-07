# LaTeX Squiggly

An inline LaTeX-to-Unicode menu bar app for macOS. Type `\alpha` or `\int_5^6`
in any app and it becomes `α` or `∫₅⁶` in place — real text, never an image.

- **Phase 0 — conversion engine.** Done. Pure Swift, no system APIs.
- **Phase 1 — text replacement.** Done. Event tap, replacement, permissions.
- **Phase 2 — per-app suppression.** Done. Exclusion list, per-site rules.
- **Phase 3 — menu bar UI.** Done. Symbol browser and exclusion editor.

## Per-app suppression

In a `.tex` file or on Overleaf, `\alpha` has to stay `\alpha`. An app that
corrupts LaTeX source is worse than no app, so this is core behaviour rather
than a preference, and it is why conversion can now be on by default.

**Applications** are matched by bundle identifier. The shipped defaults cover
terminals, code editors and the TeX editors, but only produce a rule for
software you actually have — the list in the editor is short and true rather
than a wall of apps you have never installed. Identifiers are never written
from memory: the well-known ones are checked against LaunchServices, and the
TeX editors are found by name in `/Applications` and have their real identifier
read off the bundle. Anything missed is one click to fix, from **Do not convert
in ‹app›** in the menu.

**Websites** are the case the phase exists for: Overleaf is not an app, it is a
tab in the same browser you chat in. The frontmost browser's page is read
through the Accessibility API — the permission the app already needs in order
to type, so there is no extra prompt — and matched against a host list that
ships with `overleaf.com` and its cousins. A host rule matches subdomains, so
`www.` and `fr.` are covered; `notoverleaf.com` is not.

The URL is compared and dropped. It is never stored, logged or transmitted, and
page contents are never read. Pages are only read while conversion is actually
running.

### What browsers actually expose

Measured on macOS 15.6, against Safari 26 and Chrome 152 — not assumed, because
the received wisdom here is wrong in both directions:

| | Page URL | Cost | How |
|---|---|---|---|
| Chrome, Chromium family | Yes | 2.8 ms avg | `AXDocument` on the focused window, and an `AXWebArea` under the caret |
| Safari | Yes | 12 ms avg, 109 ms worst | `AXWebArea` six levels down; it does **not** answer `AXDocument`, contrary to the usual claim |
| Firefox family | No | — | Window title only |

Two consequences are baked into the code. Safari's descent is skipped on the
path that runs inside the event tap callback, where 109 ms would be felt as a
stuck keystroke — that path relies on the caret being inside the page, which it
is whenever there is something to convert. And `AXManualAccessibility`, the
supposed Chromium opt-in, returns `kAXErrorAttributeUnsupported` on both
browsers; it is not set, because neither needs it.

Where only the title can be read, site rules fall back to matching it — an
Overleaf tab is titled "Overleaf" whatever the browser. A browser that will say
nothing at all is suppressed, and that is a setting you can turn off if you
never open Overleaf. The reasoning is the same one that runs through the whole
app: a missed conversion costs a keystroke, a wrong one costs a document.

Ask the app what it currently sees:

```
"/Applications/LaTeX Squiggly.app/Contents/MacOS/LaTeX Squiggly" --diagnose
```

It lists every rule and, for each running browser, what it can read and what it
would do. Hosts are printed rather than whole URLs — an Overleaf link carries a
share token, and a diagnostic people paste into a bug report should not carry
it too.

## Running the app

```
xcode-select --install                  # Apple's Command Line Tools, not Xcode
git clone https://github.com/SuperWalrus01/LaTeX-Squiggly.git
cd LaTeX-Squiggly
Scripts/setup-signing.sh                # once, BEFORE the first install
Scripts/install.sh                      # build from source, install to /Applications
open "/Applications/LaTeX Squiggly.app"
```

Order matters. macOS ties the Accessibility grant to the code signature, so
signing after you have granted permission invalidates the grant. (The app was
called LaTeX-Squiggly before; `install.sh` quits and removes that bundle on its
way past. The signing identity keeps the old hyphenated name on purpose —
renaming the certificate is what would reset the permissions.) If the app
ever stops responding to what you type, ask it why:

```
"/Applications/LaTeX Squiggly.app/Contents/MacOS/LaTeX Squiggly" --diagnose
```

Then grant **Accessibility** (to replace text) and **Input Monitoring** (to
notice you typing) when the menu bar item asks.

Nothing typed is stored or transmitted. The rolling buffer is 64 characters,
in memory only, and is discarded on every command, Return, arrow key, click,
app switch and shortcut.

## Running the tests

```
swift run latex-squiggly-check     # works with Command Line Tools alone
swift test                        # requires Xcode
```

Both run the same suite. On macOS, XCTest *and* swift-testing ship inside
`Xcode.app`, so `swift test` cannot work on a machine with only the Command
Line Tools installed. The expectations therefore live in a plain-Swift target,
`Sources/LaTeXUnicodeChecks`, with two thin front ends: the
`latex-squiggly-check` executable and a `Tests/LaTeXUnicodeTests` wrapper. There
is exactly one copy of every expectation.

Xcode is on the critical path for Phase 1 anyway (AppKit app bundle, code
signing), so this is a stopgap, not a permanent shape.

Current status: **1674 checks passing.**

## Trying conversions by hand

```
swift run latex-squiggly '\int_5^6'          # one-shot
swift run latex-squiggly                      # interactive, one fragment per line
echo '\alpha' | swift run latex-squiggly      # pipe
swift run latex-squiggly -c '\R'              # also print U+ values
```

Replacement text goes to stdout and explanations to stderr, so the tool
composes. Exit status is 0 for converted and fallback, 1 for unsupported.

It reports what the *app* would do, not just what the engine would do, so
`$x^2$` shows `x²` rather than `$x²$`. Input the app would not fire on falls
through to the raw engine result, which keeps the engine directly testable.

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

Fractions convert properly rather than falling back. Unicode has no stacked
fraction — there is no vinculum and no way to put one expression above another —
so the choice is between compact and legible, and the rule picks whichever suits
the content:

```
\frac{1}{2}       ->  ½             precomposed character
\frac{5}{8}       ->  ⅝             precomposed character
\frac{10}{17}     ->  ¹⁰⁄₁₇         composed: superscript ⁄ subscript
\frac{n}{2}       ->  ⁿ⁄₂           composed
\frac{x+1}{2}     ->  (x+1)∕2       linear
\frac{x-2}{x-4}   ->  (x−2)∕(x−4)   linear
\frac{a}{b}       ->  a∕b           linear — no subscript b exists
```

Composition is capped at what stays readable: both sides all digits (legible at
any length), or both sides at most two characters. Superscript `x` against
subscript `x` is near-indistinguishable at text size, so longer alphabetic
fractions read better on one line.

Linear maths uses real mathematical characters — U+2212 MINUS SIGN and U+2215
DIVISION SLASH, not the ASCII hyphen and solidus. A hyphen is shorter, sits
lower, and reads as a word break. `\text{}` keeps its hyphens, so "well-known"
is not mangled. One trade-off: the output is not ASCII, so it will not paste
into a calculator or source code as-is.

Remaining fallbacks: `\sqrt` (including `\sqrt[n]`) and `\binom`.

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

## The menu

The status item shows state at a glance — the LS mark when converting, a
faded and struck-through one when not — and carries the enable toggle,
permission shortcuts when something is missing, **Do not convert in ‹app›**,
**Excluded Apps and Sites…**, **Settings…** and **Symbols…**.

Two icon states, not three. The icon answers "is it converting right now",
which has the same answer whether the app is switched off or merely staying
quiet in Cursor; the menu answers "why not", naming the rule it is obeying. A
third glyph meaning "off, but for another reason" would be read as neither.

The mark is drawn as a **template image**: macOS keeps its alpha and supplies
the colour itself, which is the only way one file reads correctly on a light
menu bar, a dark one and a highlighted status item. Its orange survives in the
app icon, where the background is ours to choose. Both are generated from the
artwork in `Assets/` by `Scripts/make-icons.sh` — the app icon into
`Assets/AppIcon.icns`, and the menu bar mark into a base64 literal in
`Sources/LaTeXSquigglyApp/MenuBarIconData.swift`.

Embedded in source, not bundled as a resource, because `swift run
LaTeXSquigglyApp` has no `Resources` directory to read from: a project that
promises to build with only the Command Line Tools should look the same however
it was started.

## Settings

`Settings…` (⌘,) from the menu, or:

```
open -a "LaTeX Squiggly" --args --settings
```

Two panes, in the shape macOS has used for preferences since long before
System Settings — `NSTabViewController` in `.toolbar` mode, which supplies the
toolbar, the selection and the resize between panes.

**General** carries the three switches and, unusually for a settings window,
the permission state:

| | |
|---|---|
| Convert LaTeX as you type | The same switch as the menu's, reading the same value. Off, the app keeps running and stops touching your typing. |
| Open at login | `SMAppService.mainApp`. Disabled, with the reason shown, when the app is not running from a bundle — under `swift run` there is nothing to register, and registering would record a path that stops existing at the next build. |
| Show a notice when a command is refused or falls back | Covers the notices a *conversion* produces. The app's own state messages are never silenced: "conversion stopped, permission was turned off" is the difference between quiet and broken. |
| Accessibility / Input Monitoring | Granted or not, live, with a button to the only place either can be changed. |

The permissions are here rather than only in the menu because the menu can only
offer them while they are *missing* — it has nowhere to say "granted". An app
that reads your keystrokes should be able to show you exactly what it currently
holds, at any time, rather than asking you to read its silence correctly.

**Exclusions** is the Phase 2 list editor, which used to be a window of its own.
Where the app stays quiet is a setting, and having it open separately meant the
answer to "what is this app configured to do" lived in two places.

The window reads the app's state through a `SettingsHost` protocol instead of
copying it, so the menu and the window cannot disagree about whether conversion
is on: both ask the same object at the moment they draw. The permission poll
that already runs every two seconds refreshes the pane when the answer actually
changes, so a grant made in System Settings appears without reopening
anything — and does nothing at all while the window is closed.

The symbol browser searches all 202 symbols by command, Unicode name and
category at once, so "greek capital" narrows to eleven rows and "double-struck"
finds the blackboard bold letters without knowing they are called that. Double-
click copies the glyph; there is a button for the command.

```
open -a "LaTeX Squiggly" --args --symbols   # opens the browser directly
```

## Signing and distribution

```
Scripts/setup-signing.sh    one-time: a stable self-signed identity
Scripts/make-app.sh         assemble and sign the .app from SwiftPM output
Scripts/install.sh          build from source and install to /Applications
Scripts/make-icons.sh       regenerate the icons after changing Assets/
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
Until then: ship source, and `DMG=1 Scripts/make-app.sh` for anyone who won't
build it — with honest instructions about what they'll see.

The disk image carries an `Applications` symlink, so installing is a drag
rather than a question, and is itself signed: an unsigned image makes the first
thing macOS says about the download "damaged", which is both alarming and
untrue. It buys no Gatekeeper relief — see the table above. `TARBALL=1` still
produces a `.tar.gz` for anyone who prefers one.

## The site

`docs/` is a plain static site — no build step, no framework, no dependencies —
ready for GitHub Pages (**Settings -> Pages -> Deploy from a branch**, `main`,
`/docs`). It carries a live demo of the converter that runs in the browser.

The demo is not a recording and not a second implementation typed out by hand.
`Tools/make_site.py` reads the tables straight out of `Sources/LaTeXUnicode`
into `docs/assets/data.js`, and runs every worked example on the page through
the real `latex-squiggly` binary, capturing what it actually printed:

```
python3 Tools/make_site.py
```

So the page cannot claim a conversion the app does not make. The examples sit
between `<!-- BEGIN generated: ... -->` markers in `docs/index.html`; the rest
of that file, the stylesheet and the demo's own code are written by hand.

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
Sources/AppSuppression/        Phase 2 rules, pure
  AppContext.swift             what is frontmost, and which page if a browser
  ExclusionList.swift          the rules, the decision, host matching
  DefaultExclusions.swift      what ships excluded, and what is found on disk
  KnownBrowsers.swift          which apps get asked about their page
Sources/InputTracking/         Phase 1 typing logic, pure
Sources/LaTeXSquigglyApp/       the menu bar app
  EventTapController.swift     the tap; buffering, terminators, suppression
  FrontmostAppMonitor.swift    which app is in front, and which page
  BrowserPageReader.swift      the Accessibility reads; see the table above
  SuppressionGate.swift        cached per keystroke, verified before typing
  ExclusionStore.swift         persistence, defaults, on-disk discovery
  SettingsWindow.swift         the settings window, and what it may ask the app
  GeneralPane.swift            switches, and the permissions stated plainly
  ExclusionsPane.swift         the list editor
  Preferences.swift            every switch's defaults key, in one place
  LoginItem.swift              open at login, and when it cannot be offered
Sources/LaTeXUnicodeChecks/    the test suite (no XCTest)
Sources/latex-squiggly-check/   CLI runner
Tests/LaTeXUnicodeTests/       swift test wrapper
Tools/generate_tables.py       table generator
Tools/make_icons.swift         icon generator, from Assets/ artwork
Tools/make_site.py             regenerates the site's tables and examples
Tools/make_site_images.swift   regenerates the site's images
Assets/                        the artwork, and the generated .icns
docs/                          the site; see docs/README.md
Sources/latex-squiggly/         convert CLI for trying things by hand
Scripts/                       signing, bundling, install, icons
```
