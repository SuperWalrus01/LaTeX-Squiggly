# Plan: bring the Android app up to the iPhone app

Written 16 October 2026. The draft on this branch (`android-app`, commit
`7c66608`) is a maths keyboard you switch to and away from, plus Convert and
Render in the selection menu. The iPhone app (branch
`claude/ios-appstore-prep`, under `ios/`) is a keyboard for all your typing,
with a guide, a tour and a richer renderer. This plan closes that gap in
phases, each one usable on its own.

## Where things stand

- CI passes on this branch: the engine's 2,030 conformance fragments, the
  renderer page in Chromium, `assembleDebug` and `lintDebug`
  ([run 38889146627](https://github.com/SuperWalrus01/LaTeX-Squiggly/actions/runs/38889146627),
  started by hand, since `checks.yml` only runs on `main` and pull requests).
- Nothing has run on a phone or emulator. See README.md, *What is untested*.
- This branch is based on `main`, which does not have `ios/`. Read the iPhone
  code from `claude/ios-appstore-prep` (for example with
  `git show claude/ios-appstore-prep:ios/KeyboardUI/KeyboardModel.swift`).

## Decisions to confirm before starting

| Decision | Default in this plan |
|---|---|
| Everyday keyboard like the iPhone's, or a maths pad you switch to | **Everyday keyboard.** Phases 2 and 3 are only needed for this. |
| Where to test | **Install the Android SDK and an emulator locally** (see Phase 0), and try a real phone before release. |
| Branch | **Keep working on `android-app`.** Merge with the iPhone branch later, once both are ready for `main`. |
| Libraries | **Keep "no libraries, no permissions".** Every phase below fits within it. |

## Phase 0: get it running (half a day)

1. Install JDK 17 (`brew install --cask temurin@17`). The local JDK is 26,
   which Gradle 8.14 cannot run on. Use it with
   `JAVA_HOME=$(/usr/libexec/java_home -v 17)`.
2. Install the Android command line tools (`brew install --cask android-commandlinetools`),
   then `sdkmanager "platform-tools" "platforms;android-36" "build-tools;36.0.0" "emulator" "system-images;android-36;google_apis;arm64-v8a"`,
   and create an emulator with `avdmanager`.
3. `android/gradlew -p android :engine:conformance :app:assembleDebug`, then
   install with `adb install`.
4. Work through README.md's *What is untested* list on the emulator. Fix what
   breaks before adding anything: this draft is the base for everything else.
5. Make `checks.yml` run on pushes to `android-app` too, or open a draft pull
   request, so CI runs on every push.

**Done when:** the keyboard types, converts and renders in Messages, Chrome
and Google Docs on the emulator.

## Phase 1: the maths features (2 to 3 days)

These matter whichever way the keyboard decision goes.

| Feature | iPhone source to port | Android target |
|---|---|---|
| The bar above the keys: `$…$`, braces and script buttons when idle; command completions after `\`; a typeset preview of the LaTeX at the cursor | `KeyboardUI/KeyboardModel.swift` (the `Bar` cases), `KeyboardUI/CommandSuggestions.swift` | Replace the preview strip in `keyboard/KeyboardView.kt`; new `keyboard/CommandSuggestions.kt`, with the ranking in `engine/` so it can be tested on the JVM |
| x² and x₂ keys that type braced scripts, and space converting `x^{2}` typed from them as if between `$` signs | `KeyboardUI/Layouts.swift`, commit `3d9af15` | `keyboard/Layouts.kt`, `KeyboardService.onSpace`; add the rule to the engine and its conformance checks |
| Keep LaTeX: one switch in the bar. On, nothing converts and maths keys type `\alpha`. Off, space converts and maths keys type `α` | `KeyboardModel.swift` (mode) | Replaces the *Convert on space* setting; remembered by the keyboard |
| Hold a key for accents, or for related symbols on maths keys | `KeyboardUI/Alternates.swift` (data ports as is) | `keyboard/Alternates.kt`, a popup in `KeyboardView.kt` |
| An enlarged key while pressed | `KeyboardUI/KeyboardView.swift` | `KeyboardView.kt` (a `PopupWindow` above the key) |
| The ∑ symbols page opened from the bar | `Layouts.swift` | The symbols grid exists; move how it opens |

**Done when:** each feature has a check in `:engine:conformance` where it is
logic, and has been tried on the emulator where it is touch.

## Phase 2: typing that feels like a phone keyboard (4 to 6 days)

Only for the everyday keyboard. This is where the iPhone work spent most of
its effort, so port the behaviour carefully rather than approximately.

| Feature | iPhone source | Notes for Android |
|---|---|---|
| One touch surface over all the keys: a tap in a gap goes to the nearest key, a deliberate slide changes key but a roll as the finger lifts does not, a second finger types the first finger's key at once | `KeyboardUI/KeyTouches.swift` | Replace the per-key `TextView` listeners with one `onTouchEvent` over the whole keyboard, handling `ACTION_POINTER_DOWN` |
| Between two letters or on a key's edge, the likelier English letter wins; never inside maths or a command | `KeyboardUI/LetterOdds.swift`, `ios/scripts/letter-odds.py` | Generate the table into Kotlin, as `generate-kotlin-tables.py` does for the engine |
| Hold space to move the cursor like a trackpad | `KeyTouches.swift`, `KeyboardModel.swift` | Move the selection with `InputConnection.setSelection` |
| Spelling suggestions in the bar, only ever applied on tap | `KeyboardUI/WordCorrector.swift` | Android's `SpellCheckerSession` (`TextServicesManager`) needs no library or permission. Suggestions wait for the second letter, so a lone `x` keeps the quick keys |
| Double space types a full stop; punctuation after an accepted word takes back its space; space after numbers goes back to letters | `KeyboardModel.swift` | Port as is |
| Delete held: repeats, then deletes words | `KeyboardModel.swift` | Key repeat exists; add the word step |
| `@`, `/` and `.` beside space in email and web fields | `Layouts.swift` (`FieldKind`) | Read `EditorInfo.inputType` |
| A shorter keyboard in landscape | `KeyboardView.swift` | Check `Configuration.orientation` |
| Emoji page: categories, recent first, delete that repeats | `KeyboardUI/EmojiPanel.swift`, `EmojiData.swift` | A scrolling grid in place of the keys; reuse the emoji data |
| Settings: Words, Space space ., Haptics, automatic capitals (off by default) | `Shared/SharedSettings.swift` | Extend `Settings.kt`. Android has no Full Access step: the keyboard and app share preferences directly |

**Done when:** a typing test on the emulator, in the spirit of
`ios/LookTests/TypingTests.swift`, types sentences and LaTeX and checks the
text. Android's `UiAutomator` can do this without adding a library to the app
(it is a test dependency only).

## Phase 3: rendering (1 to 2 days)

| Feature | iPhone source | Android target |
|---|---|---|
| Size and a light or dark card for rendered images, remembered | `Render/RenderControls.swift` | The renderer page already has options; expose them in `RendererActivity.kt` and the keyboard |
| **Share** as a JPEG, so apps receive a photo rather than a sticker | `RenderControls.swift` (`ShareImage`) | `Intent.ACTION_SEND` with the existing `RenderedImages` provider |
| A large preview of the rendering, in place of the keys | `KeyboardModel.swift` (`preview`) | `KeyboardView.kt` |
| Render from the share sheet (the iPhone's Share extension) | `Share/ShareViewController.swift` | An `ACTION_SEND` `text/plain` intent filter on `RendererActivity`, beside the selection menu entry |
| The Messages app | `Messages/MessagesViewController.swift` | No Android equivalent. Inserting the image from the keyboard (`commitContent`) covers it; add recent equations to the bar if it is missed |

## Phase 4: the app around the keyboard (3 to 4 days)

| Feature | iPhone source | Notes |
|---|---|---|
| Tabs: Guide, Render, Settings | `App/LaTeXSquigglyApp.swift` | Plain views, no Compose, to keep "no libraries" |
| Guided lessons with practice boxes, done when the box shows the user did it, progress kept | `App/GuideView.swift` | Reuse the lesson text and checks |
| First-launch tour: dims the screen and lights one thing at a time; skippable, repeatable from Settings | `App/Tour.swift` | An overlay view over the activity |
| Keyboard tricks, a searchable list of every command, Questions | `App/HelpViews.swift` | The command list comes from the engine's tables |
| Setup steps for turning the keyboard on, which differ on Android | `App/Components.swift` | The current `MainActivity.kt` setup card is the start of this |
| About, privacy policy and acknowledgements | `App/AboutView.swift` | Same text, with Android's permissions story |
| Brand: colours, wordmark, mascot | `Render/Brand.swift` | Colours into `values/` and `values-night/` |

## Phase 5: release (1 to 2 days, plus Google's waiting time)

1. A release signing key, kept out of git, and a signed `assembleRelease`
   in CI.
2. A Play Console account. New personal accounts must run a closed test with
   12 testers for 14 days before publishing; check Google's current rules.
3. A store listing and screenshots. Adapt `ios/STORE.md` and the screenshot
   pipeline from commit `1a85a19` (simulator captures and phone mockups) to
   emulator captures.
4. The Data safety form: no data collected, and no network permission.
5. The keyboard warning Android shows when a keyboard is turned on should be
   answered in the setup screen: the app cannot reach the network.

## Order and size

Phase 0, then 1, then 3 give a useful maths keyboard in about a week. Phases 2
and 4 make it the iPhone app's equal, roughly another one and a half to two
weeks. Phase 5 can start alongside Phase 4, since the 14 day closed test is the
longest wait.

## Keeping the platforms together

- New conversion rules (like the x² rule) go in the engine first, with
  conformance fragments, so every platform agrees.
- Each phase updates README.md: what it does, and what is still untested.
- When both branches are ready, merge `android-app` and the iPhone branch into
  `main` one at a time. They overlap in `scripts/check-all.sh`,
  `CONTRIBUTING.md` and `docs/architecture.md`.
