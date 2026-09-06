# Build prompt — inline LaTeX-to-Unicode menu bar app (macOS)

Paste the section below into your AI coding tool. Everything above the line is note-to-self.

**How to use it:** don't paste this and say "build it all." Paste the whole thing as context, then instruct the tool to do **Phase 0 only**. Review, test, commit. Then Phase 1. AI coding tools degrade badly when given four phases at once — you get plausible code for all of them and working code for none.

---

## PROMPT STARTS HERE

You are helping me build a macOS menu bar utility. Read this entire spec before writing any code. At the end, ask me any clarifying questions you have, then implement **only the phase I name**. Do not implement later phases ahead of time.

### What the app is

A menu bar utility that replaces LaTeX commands with Unicode characters inline, in any application. I type `\alpha` or `\int_5^6` in WhatsApp, Slack, Notion, or an email, and it becomes `α` or `∫₅⁶` in place — real text characters, not an image.

### The hard constraint

**Everything is Unicode and everything is inline. The app never produces an image, ever.**

This is a deliberate product constraint, not a limitation to work around. Do not propose rendering to PNG, clipboard image formats, KaTeX, MathJax, or SVG. If you think a feature requires image rendering, the answer is that the feature is out of scope.

Consequence: fractions, radicals over multiple characters, matrices, cases, and aligned environments cannot be represented. The app must handle this honestly (see "Failure behaviour").

### Stack

- Swift + AppKit, native macOS app. Menu bar only — `LSUIElement`, no dock icon.
- Minimum target: macOS 13.
- No backend, no network calls, no account, no analytics, no sync. The app must work fully offline and must never transmit keystrokes anywhere.

### Phase 0 — conversion engine (do this first, standalone)

Build the conversion logic as a self-contained Swift module with **no UI and no system APIs**. It must be testable in isolation via `swift test`.

Public interface, roughly:

```swift
enum ConversionResult {
    case converted(String)           // full Unicode representation
    case fallback(String, reason: String)  // linear approximation, user must be told
    case unsupported(reason: String) // nothing sensible exists; leave input alone
}

func convert(_ latex: String) -> ConversionResult
```

Requirements:

1. **Coverage table.** A data file (JSON or Swift literal) mapping LaTeX commands to Unicode. Cover: Greek lower and upper case, common operators (`\int \sum \prod \pm \times \cdot \infty \partial \nabla`), relations (`\leq \geq \neq \approx \equiv \sim \propto`), set notation (`\in \notin \subset \subseteq \cup \cap \emptyset \forall \exists`), arrows, and blackboard bold (`\R \Q \Z \N \C` → ℝ ℚ ℤ ℕ ℂ).

2. **Verify every codepoint.** Do not write mappings from memory — LLMs hallucinate codepoints confidently. For each entry, include the codepoint in a comment (e.g. `"\\alpha": "α" // U+03B1`) and write a test asserting the scalar value. If you are not certain of a codepoint, leave the entry out and list it for me to add.

3. **Sub- and superscripts.** All ten digits exist in both forms, so `x^2` → `x²` and `\int_5^6` → `∫₅⁶` work. Letter coverage is incomplete and this must be encoded explicitly, not assumed:
   - Superscript letters: all except `q`.
   - Subscript letters: only `a e h i j k l m n o p r s t u v x`. Missing: `b c d f g q w y z`.
   - Requesting a missing letter returns `.unsupported`, never a silent literal.

4. **Prefix collisions.** `\in` is a prefix of `\int` and `\infty`. Resolve with an explicit terminator (space or tab) and longest-match. Decide whether the terminator is consumed or preserved, document the choice, and test it.

5. **Fallbacks.** Where a linear form is honest, return `.fallback` with a reason: `\frac{x+1}{y-2}` → `(x+1)/(y-2)`. Anything requiring two-dimensional layout that has no honest linear form returns `.unsupported`.

Deliverable for this phase: the module, the coverage table, and a test suite covering every mapping, every prefix collision, both fallback paths, and malformed input. Nothing else.

### Phase 1 — text replacement

- `CGEventTap` keystroke listener maintaining a short rolling buffer of recent input.
- On a completed trigger, delete the typed source and insert the replacement.
- Insert via `CGEvent.keyboardSetUnicodeString`, **not** via the clipboard. Clipboard swapping destroys the user's copied content and is racy.
- Requires Accessibility and Input Monitoring permissions. Detect whether they are granted, and show a clear explanation with a button that opens the correct System Settings pane. Handle the case where permission is revoked while running.

### Phase 2 — per-app suppression (core behaviour, not a preference)

In a `.tex` file or Overleaf, `\alpha` must stay `\alpha`. The app must detect the frontmost application and suppress itself in an exclusion list. Ship with sensible defaults (Overleaf in any browser is the hard case — discuss options with me before implementing that one) and let the user add apps.

Treat this as required behaviour. An app that corrupts LaTeX source is worse than no app.

### Phase 3 — UI

- Menu bar icon, enable/disable toggle, exclusion list editor.
- A searchable symbol browser for when the user doesn't remember the command name.
- Nothing else. No editor, no history, no notes, no snippets.

### Failure behaviour (the most important UX in the app)

Silent partial conversion is the failure mode to avoid at all costs. If a user pastes something that renders as broken text on someone else's phone and they don't know why, they stop trusting the app.

- `.fallback` must tell the user a fallback happened and what it produced.
- `.unsupported` must leave the input untouched and say why.
- Never emit a half-converted string.

### Non-goals

Do not build, suggest, or scaffold: image rendering, cloud sync, accounts, a text editor, note-taking, iOS, Windows, Linux, a web version, telemetry, or auto-update. If I ask for one of these, remind me of this list.

### Working style

- Ask clarifying questions before writing code.
- Do not add dependencies without telling me why.
- Write tests alongside code, not after.
- When you are uncertain about a macOS API's behaviour, say so instead of guessing — event taps and Accessibility permissions are areas where plausible-looking wrong code is common.
- Keep files small and single-purpose.

Start by asking your questions, then implement **Phase 0 only**.

## PROMPT ENDS HERE

---

## Notes for you, not for the AI

**Distribution.** Unsigned apps using Accessibility permissions are effectively undistributable — Gatekeeper often reports them as damaged on Apple Silicon. Signing and notarising means the Apple Developer Program at $99/year. Decide before you build, not after.

**Prior art to check first.** Espanso does system-wide text expansion and has maths symbol packages. `unicodeit` does LaTeX-to-Unicode conversion. Julia's REPL has this built in. None of them do per-app suppression well, which is your angle — but confirm that yourself rather than taking my word for it.
