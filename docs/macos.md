# The macOS app

A menu bar app for macOS 13 and later. The code is in
`Sources/LaTeXSquigglyApp`, a thin shell over the engine in
`Sources/LaTeXUnicode` and `Sources/InputTracking` and the suppression rules in
`Sources/AppSuppression`.

## Installing

Download the disk image from the
[latest release](https://github.com/SuperWalrus01/LaTeX-Squiggly/releases/latest),
open it, and drag **LaTeX Squiggly** onto **Applications**. It is signed but not
notarized, which needs a paid Apple Developer account, so macOS refuses to open
it the first time: go to **System Settings → Privacy & Security**, scroll down,
and click **Open Anyway**.

Or build it yourself, which avoids that warning entirely:

```
xcode-select --install                # Apple's Command Line Tools, not Xcode
git clone https://github.com/SuperWalrus01/LaTeX-Squiggly.git
cd LaTeX-Squiggly
scripts/setup-mac-signing.sh          # once, BEFORE the first install
scripts/install-mac-app.sh            # build from source, install to /Applications
open "/Applications/LaTeX Squiggly.app"
```

Order matters. macOS ties the Accessibility grant to the code signature, so
signing after you have granted permission invalidates the grant. (The app was
called LaTeX-Squiggly before; `install-mac-app.sh` quits and removes that
bundle on its way past. The signing identity keeps the old hyphenated name on
purpose, because renaming the certificate is what would reset the
permissions.)

Then grant **Accessibility** (to replace text) and **Input Monitoring** (to
notice you typing) when the menu bar item asks.

Nothing typed is stored or transmitted. The rolling buffer is 64 characters,
in memory only, and is discarded on every command, Return, arrow key, click,
app switch and shortcut.

## Updating

Quit from the menu bar item, drag `/Applications/LaTeX Squiggly.app` to the
Trash, then install the new one. `scripts/install-mac-app.sh` does this for you.

One trap is worth knowing about, because the symptom is that the new build
silently does nothing. macOS ties the Accessibility and Input Monitoring grants
to the app's **code signature**, and a build signed by a different identity is,
as far as the system is concerned, a different app that happens to be at the
same path. The old entry stays in the list, still ticked, and grants nothing:

```
System Settings -> Privacy & Security -> Accessibility
                                      -> Input Monitoring
```

Remove **LaTeX Squiggly** from both lists with the minus button *before*
installing the new build, then let the new one ask again. If you build from
source with `scripts/setup-mac-signing.sh`'s stable identity, the signature
does not change between builds and none of this applies.

Settings live in `UserDefaults` under `com.keenanjusak.latex-squiggly`, so they
survive a reinstall. To wipe them:

```
defaults delete com.keenanjusak.latex-squiggly
```

## When it is not responding

Ask the app what it currently sees:

```
"/Applications/LaTeX Squiggly.app/Contents/MacOS/LaTeX Squiggly" --diagnose
```

It lists every rule and, for each running browser, what it can read and what it
would do. Hosts are printed rather than whole URLs: an Overleaf link carries a
share token, and a diagnostic people paste into a bug report should not carry
it too.

## Per-app suppression

In a `.tex` file or on Overleaf, `\alpha` has to stay `\alpha`. An app that
corrupts LaTeX source is worse than no app, so this is core behaviour rather
than a preference, and it is why conversion can be on by default.

**Applications** are matched by bundle identifier. The shipped defaults cover
terminals, code editors and the TeX editors, but only produce a rule for
software you actually have, so the list is short and true rather than a wall of
apps you have never installed. Identifiers are never written from memory: the
well-known ones are checked against LaunchServices, and the TeX editors are
found by name in `/Applications` and have their real identifier read off the
bundle. Anything missed is one click to fix, from **Do not convert in ‹app›**
in the menu.

**Websites** are the case suppression exists for: Overleaf is not an app, it is
a tab in the same browser you chat in. The frontmost browser's page is read
through the Accessibility API, which the app already needs in order to type, so
there is no extra prompt, and matched against a host list that ships with
`overleaf.com` and its relatives. A host rule matches subdomains, so `www.` and
`fr.` are covered; `notoverleaf.com` is not.

The URL is compared and dropped. It is never stored, logged or transmitted, and
page contents are never read. Pages are only read while conversion is actually
running.

### What browsers actually expose

Measured on macOS 15.6, against Safari 26 and Chrome 152, not assumed, because
the received wisdom here is wrong in both directions:

| | Page URL | Cost | How |
|---|---|---|---|
| Chrome, Chromium family | Yes | 2.8 ms avg | `AXDocument` on the focused window, and an `AXWebArea` under the caret |
| Safari | Yes | 12 ms avg, 109 ms worst | `AXWebArea` six levels down; it does **not** answer `AXDocument`, contrary to the usual claim |
| Firefox family | No | n/a | Window title only |

Two consequences are built into the code. Safari's descent is skipped on the
path that runs inside the event tap callback, where 109 ms would be felt as a
stuck keystroke; that path relies on the caret being inside the page, which it
is whenever there is something to convert. And `AXManualAccessibility`, the
supposed Chromium opt-in, returns `kAXErrorAttributeUnsupported` on both
browsers, so it is not set, because neither needs it.

Where only the title can be read, site rules fall back to matching it: an
Overleaf tab is titled "Overleaf" whatever the browser. A browser that will say
nothing at all is suppressed, and that is a setting you can turn off if you
never open Overleaf. The reasoning is the same one that runs through the whole
app: a missed conversion costs a keystroke, a wrong one costs a document.

## How the text is replaced

The typing rules themselves are shared with every platform; see
[engine.md](engine.md#when-typing-becomes-a-conversion). What is specific to
macOS is how the keystrokes are caught and the replacement typed.

**The terminator is suppressed and retyped.** The event tap is `.defaultTap`
rather than `.listenOnly` for exactly this reason, and the replacement is
posted synchronously inside the callback. Dispatching it instead leaves a
window in which the next keystroke lands first and the delete count eats a
character the user meant to keep.

**Synthetic events are stamped** via `CGEventSource.userData`, so the tap
ignores its own output instead of feeding on it.

## The menu

The status item shows state at a glance, the LS mark when converting and a
faded, struck-through one when not, and carries the enable toggle, permission
shortcuts when something is missing, **Do not convert in ‹app›**,
**Settings…**, **Symbols…** and **Render LaTeX as Image…**.

**Do not convert in ‹app›** is the only exclusion the menu carries, because it
is the only one that needs the app in front of you to mean anything: a default
list cannot know about every TeX editor, and the moment you notice a miss is the
moment you are looking at the wrong app. The list itself lives in Settings and
nowhere else.

Two icon states, not three. The icon answers "is it converting right now",
which has the same answer whether the app is switched off or merely staying
quiet in Cursor; the menu answers "why not", naming the rule it is obeying. A
third glyph meaning "off, but for another reason" would be read as neither.

The mark is drawn as a **template image**: macOS keeps its alpha and supplies
the colour itself, which is the only way one file reads correctly on a light
menu bar, a dark one and a highlighted status item. Its orange survives in the
app icon, where the background is ours to choose. Both are generated from the
artwork in `assets/` by `scripts/make-mac-icons.sh`: the app icon into
`assets/app-icon.icns`, and the menu bar mark into a base64 literal in
`Sources/LaTeXSquigglyApp/MenuBarIconData.swift`. It is embedded in source
rather than bundled as a resource because `swift run LaTeXSquigglyApp` has no
`Resources` directory to read from, and a project that builds with only the
Command Line Tools should look the same however it was started.

## The renderer

**Render LaTeX as Image…** from the menu, or ⌃⌥⌘L from any app, opens a window
that turns maths-mode LaTeX into an image, for pasting where LaTeX is not
understood and Unicode cannot draw it. It is the Chrome extension's renderer,
the same files, in a web view: live preview, autocomplete, colours, braces,
history and settings all behave as
[the extension's](../chrome/README.md#the-renderer) do. The app adds what a
page cannot do for itself:

- **The clipboard.** Copy PNG puts the PNG on the pasteboard with its size in
  points, and a TIFF beside it. Chrome cannot do this, so there a 3× image
  pastes three times too large; on the Mac, apps that read the size, which is
  most of them, paste it at the size it was previewed, and sharp.
- **Saving,** through the standard save panel.
- **Settings,** kept in the app's own defaults: `rendererSettings` for the
  image settings and `rendererLocal` for the last input and the history, each
  a JSON object, because the page's values can include null.
- **The shortcut,** a Carbon hot key, which needs no permission and works with
  conversion off. It takes three modifiers because a hot key is taken from
  every app on the Mac, and Option-Shift with a letter types a character.
  When another app already holds it, the menu item still works.

⌘Enter copies the PNG, closes the window and hands the focus back to the app
that was in front, so ⌘V pastes where you were. Esc closes without copying.
The window is hidden rather than closed, so MathJax loads once per launch, the
first time it opens, and after that it appears at once.

A web view will not load modules or fetch files from `file://` pages, so the
files are served at `squiggly://app/` by `RendererFiles.swift`.
`Sources/LaTeXSquigglyApp/Web/files.json` says where each comes from: the
page and its script from `Web/`, everything else from `chrome/`.
`scripts/build-mac-app.sh` copies them into the bundle's `Resources/web/`, and
`swift run LaTeXSquigglyApp` reads them from the repository by the same map.
`LaTeXSquigglyApp --renderer` opens the window at launch.

`chrome/test/mac-window.cjs` runs the page in Chromium against a stand-in for
the app's side of the bridge. The app's side itself, the window, clipboard,
save panel and hot key, can only be tried on a Mac.

## Settings

**Settings…** (⌘,) from the menu, or:

```
open -a "LaTeX Squiggly" --args --settings
```

Two panes, in the shape macOS has used for preferences since long before
System Settings: `NSTabViewController` in `.toolbar` mode, which supplies the
toolbar, the selection and the resize between panes.

**General** carries the switches and, unusually for a settings window, the
permission state:

| | |
|---|---|
| Convert LaTeX as you type | The same switch as the menu's, reading the same value. Off, the app keeps running and stops touching your typing. |
| Open at login | `SMAppService.mainApp`. Disabled, with the reason shown, when the app is not running from a bundle: under `swift run` there is nothing to register, and registering would record a path that stops existing at the next build. |
| Show a notice when a command is refused or falls back | Covers the notices a conversion produces. The app's own state messages are never silenced: "conversion stopped, permission was turned off" is the difference between quiet and broken. |
| Keep superscripts and subscripts that have no Unicode form | Off by default. See [engine.md](engine.md#scripts-unicode-cannot-make). |
| Accessibility / Input Monitoring | Granted or not, live, with a button to the only place either can be changed. |

The permissions are here rather than only in the menu because the menu can only
offer them while they are missing; it has nowhere to say "granted". An app that
reads your keystrokes should be able to show you exactly what it currently
holds, at any time.

**Exclusions** is the list editor for apps and sites.

The window reads the app's state through a `SettingsHost` protocol instead of
copying it, so the menu and the window cannot disagree about whether conversion
is on: both ask the same object at the moment they draw. The permission poll
that already runs every two seconds refreshes the pane when the answer actually
changes, so a grant made in System Settings appears without reopening anything,
and does nothing at all while the window is closed.

The symbol browser searches all 202 symbols by command, Unicode name and
category at once, so "greek capital" narrows to eleven rows and "double-struck"
finds the blackboard bold letters without knowing they are called that.
Double-click copies the glyph; there is a button for the command.

```
open -a "LaTeX Squiggly" --args --symbols   # opens the browser directly
```

## Signing and distribution

```
scripts/setup-mac-signing.sh    one-time: a stable self-signed identity
scripts/build-mac-app.sh        assemble and sign the .app from SwiftPM output
scripts/install-mac-app.sh      build from source and install to /Applications
scripts/make-mac-icons.sh       regenerate the icons after changing assets/
```

**Signing is a development need before it is a distribution one.** macOS TCC
identifies an app by its code signature, and ad-hoc signatures key on the code
directory hash, which changes on every build, so without a stable identity you
re-grant Accessibility and Input Monitoring on every rebuild.
`setup-mac-signing.sh` creates one. Verified: codesign accepts an untrusted
self-signed certificate as long as its keychain is in the search list, so this
does not touch the trust store.

**Building from source is the cleanest install.** Tested on macOS 15.6:

| How the app arrives | Quarantined? |
|---|---|
| Built locally (`scripts/install-mac-app.sh`) | No, opens normally |
| Downloaded `.tar.gz`, extracted with `tar -xzf` | **Yes** |
| Downloaded `.dmg`, dragged from Finder | Yes |

Command-line `tar` is widely believed to sidestep quarantine. It does for plain
files, but **not** for `.app` bundles: macOS writes a fresh quarantine attribute
onto the extracted bundle's contents. A downloaded build therefore still costs
the user a trip through System Settings → Privacy & Security, which on macOS 15
no longer has the old Control-click → Open shortcut.

Notarization is the only thing that removes that step, and it requires a
Developer ID certificate, which requires the paid Apple Developer Program.
Until then: ship source, and `DMG=1 scripts/build-mac-app.sh` for anyone who
will not build it, with honest instructions about what they will see.

The disk image carries an `Applications` symlink, so installing is a drag
rather than a question, and is itself signed: an unsigned image makes the first
thing macOS says about the download "damaged", which is both alarming and
untrue. `TARBALL=1` still produces a `.tar.gz` for anyone who prefers one.
