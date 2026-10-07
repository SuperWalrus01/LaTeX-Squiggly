# LaTeX Squiggly for iPhone

A keyboard that types normally, converts LaTeX to Unicode on space, and
renders LaTeX to an image you can paste. Selected LaTeX renders from the
share sheet, and Messages has its own app for sending equations. It reuses
the Mac app's engine (`LaTeXUnicode`, `InputTracking`) unchanged.

```
ios/
  project.yml      XcodeGen spec: the app, its extensions, their packages
  App/             the container app: setup steps, a test pad, a renderer
  Keyboard/        the keyboard extension, which shows KeyboardUI/
  KeyboardUI/      keys, touch handling, spelling and the bar above the keys
  Share/           the share sheet extension: render selected LaTeX
  Messages/        the Messages app: write LaTeX, send it as an image
  Render/          the render screen the app, Share and Messages all use
  Shared/          the renderer, which every target compiles
  scripts/         letter-odds.py, which counts the keyboard's letter odds
```

## How the keyboard feels like the system's

- One touch surface over all the keys (`KeyTouches.swift`), not a gesture per
  key: a touch in a gap goes to the nearest key, a deliberate slide changes
  the key but a finger rolling as it lifts does not, and a second finger
  types the first finger's key at once, so fast typing keeps its order.
- Near the edge of two letters, the likelier letter in English wins
  (`LetterOdds.swift`), as the system keyboard quietly grows the key you
  probably meant.
- Spelling from the system dictionary (`WordCorrector.swift`): suggestions
  in the bar, corrections on space, delete straight after a correction puts
  the word back. Never inside math, and off where the text field turns it off.
- Hold a key for accents or related symbols (`Alternates.swift`).

## Build

Needs full Xcode (the Command Line Tools cannot build for iOS) and XcodeGen.

```sh
brew install xcodegen
cd ios && xcodegen && open LaTeXSquiggly.xcodeproj
```

Pick your team under Signing & Capabilities for both targets, or set
`DEVELOPMENT_TEAM` in `project.yml`.

## Test

- **Engine:** `swift run latex-squiggly-check` from the repository root.
  Conversion is the same code as on the Mac, so its suite covers the keyboard.
- **Simulator:** run the `Keyboard` scheme and choose the LaTeX Squiggly app
  as the host. In the simulator's Settings, add the keyboard under General,
  Keyboard, Keyboards. Press ⌘K if the software keyboard is hidden.
- **Your own iPhone:** a free Apple ID can sign and install for 7 days at a
  time. Turn on Developer Mode on the phone (Settings, Privacy & Security).
- **Testers:** TestFlight, which needs the paid developer account.

## Things a keyboard cannot do

- Insert an image. Only text goes through `textDocumentProxy`, which is why
  rendering copies to the clipboard instead, and why the share sheet and
  Messages extensions exist.
- Use the clipboard or network without Full Access. The keyboard must still
  work without it, which App Review checks.
- Appear in password or phone-number fields. iOS swaps in the system keyboard.
- Use much memory. iOS kills keyboards past a few tens of megabytes, which is
  why rendering uses SwiftMath rather than MathJax in a web view.
