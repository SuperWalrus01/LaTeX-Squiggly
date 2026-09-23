# LaTeX Squiggly for Chrome

The same engine as the macOS and Windows apps, as a Chrome extension. Type
`\alpha` in a text box on a web page, press space, and it becomes `α` in place.
`$x^2$` gives `x²`. It stays off on Overleaf and the other TeX sites, and in
code editors on any site.

It only reaches the browser, so it is not a replacement for the desktop apps.
It is for Chromebooks, and for computers where you cannot install software.

## Trying it locally

1. Open `chrome://extensions`.
2. Turn on **Developer mode**, top right.
3. Click **Load unpacked** and choose this `chrome/` folder.

Pages that were open before the extension loaded need a reload. After changing
the code, click the reload icon on the extension's card, then reload the page
you are testing in.

- Messages from the page script appear in the page's own DevTools console.
- The popup has its own: right-click the toolbar icon, then **Inspect popup**.
- Errors show up behind a red **Errors** button on the extension's card.

## Tests

```sh
node chrome/test/conformance.mjs
```

This replays the 2,030 fragments the Swift engine was asked about (the same
reference the Windows port is held to) and requires the same answer for each,
down to the delete count. It also checks the site rules. It needs only Node.

```sh
npm install --prefix /tmp/squiggly-test playwright
npx --prefix /tmp/squiggly-test playwright install chromium
NODE_PATH=/tmp/squiggly-test/node_modules node chrome/test/browser.cjs
```

This loads the extension into Chromium and types into real fields: a textarea,
inputs, contenteditable, a controlled field in the React style, a code editor,
editors in iframes and in a shadow root, keys typed with AltGr, Option and dead
keys, Google Docs' hidden input frame, Google Docs mode against a stand-in, an
excluded site, and the off switch. Branded Google Chrome ignores
`--load-extension`, so it has to be Playwright's Chromium.

## How it differs from the desktop apps

The engine is identical: `engine/engine.js` is a port of the Windows engine and
`engine/tables.js` is generated from the Swift tables. Only the part that
touches the text is different.

**It checks before it deletes.** The desktop apps count keystrokes and type
backspaces, trusting that the count is right. A web page lets the extension read
the text itself, so the keystroke buffer only decides *what* was typed, and
nothing changes until the characters in front of the caret are confirmed to be
exactly that. When they are not, because a site rewrote the field or the typing
went to a hidden element, the space goes through untouched.

**The replacement goes through the browser's own editing.** Text is replaced
with `execCommand("insertText")`, which rich editors (ProseMirror, Lexical,
Quill, and the Gmail and Notion kind built on them) treat as ordinary typing.
In a plain text box, undo straight after a conversion brings the command back.
Rich editors keep their own history, so there undo may also take back what you
typed before it.

**Space is the only terminator.** Tab moves focus in a browser, so it cannot be
taken over safely. Return is excluded for the same reason as on the desktop.

**Code editors are recognised by their markup** (CodeMirror, Monaco, Ace),
because on the web they are components inside a page, not apps.

**Every keyboard, not only US English.** A key typed with AltGr (Control and
Alt, to the browser) or with Option on a Mac is typing, not a shortcut: on most
European keyboards that is how `{` and `}` are typed. Only Control and Command
shortcuts end a command. Dead keys and input methods are followed through
their composition, so `^` on a German keyboard works.

**The toolbar icon says whether it is converting.** Orange where it is, grey
with a strike where it is not: paused, or on an excluded site. The tooltip says
which. The page script tells the background worker, which sets the icon for
that tab, the same two states as the desktop apps' icons.

**A shortcut pauses it anywhere:** Alt+Shift+L unless changed at
`chrome://extensions/shortcuts`. The page in front says it has paused or
resumed, even with notices off, because a pause nobody sees looks exactly like
the extension being broken.

**Editors in frames and components.** The script also runs in frames with no
address of their own (`about:blank`), where TinyMCE, CKEditor 4 and the
classic WordPress editor keep their text, and reads the selection from a shadow
root when the editor is inside a web component.

## Google Docs

On by default, with a switch in the settings page. The code is
`content/docs.js`, and it is a different kind of conversion from everywhere
else.

Google Docs draws the document itself and takes typing through a hidden frame,
which it reads and empties, so there is no text in front of the caret for the
extension to check. In Docs it works the way the desktop apps do: it keeps its
own record of the keys pressed, and replaces a command by sending Backspace
key events and then the result as keypress events, trusting that record. The
record is forgotten on any key it cannot follow (arrows, Enter, shortcuts, dead
keys), after four seconds without a key, and on any click in the document,
which the top frame passes to the input frame through the background worker.

Limits, deliberately:

- **Documents only.** Sheets and Slides take input differently and are untested.
- **Characters outside the Basic Multilingual Plane** (𝔼, 𝔽) are left as typed,
  until it is known how Docs takes them from a key event.
- **Docs' own text boxes**, such as comments, are in the top frame and convert
  the ordinary way whether or not the setting is on.

**Capitals.** Docs capitalises the first letter of a sentence, and a Greek
letter is a letter: `\alpha` typed at the start of a sentence can come out as
Α, the capital alpha, which looks exactly like a Latin A. The extension cannot
see where a sentence starts in Docs. Turning off Docs' **Tools → Preferences →
Automatically capitalize words** stops it, and the setting's description says so.

**Testing it.** The browser test runs it against a stand-in built the way Docs
works, which proves the extension's side. Docs' side can only be tested by
hand, signed in. It was first checked on 24 September 2026; run this again after
any change to `content/docs.js`, typing each case after a word or two rather
than at the start of a sentence:

| Do this in a Google Doc | Expected |
|---|---|
| `so \alpha` space | `so α ` |
| `$x^2$` space, and `\frac{1}{2}` space | `x² `, and `½ ` |
| `\frac{x+1}{2}` space | `(x+1)∕2 `, and a notice at the bottom right |
| `\alp`, click elsewhere in the text, `ha` space | nothing converts |
| `\alp`, wait five seconds, `ha` space | nothing converts |
| `\alphx`, Backspace, `a` space | `α ` |
| Type `\alpha` space as fast as you can, several times | every one converts, and no character typed after the space is lost or misplaced |
| Ctrl+Z (Cmd+Z) after a conversion | what comes back, and whether it takes one undo or several (record it) |
| With Tools → Preferences → autocorrect on, type `\alpha` space | converts, and Docs' own substitutions do not interfere |
| A comment box: `\beta` space | `β `, with the setting on or off |
| A Google Sheet and a Google Slide: `\alpha` space | nothing converts |
| Settings → turn Google Docs off, then `\alpha` space | nothing converts, without reloading the doc |

If a Docs update breaks it, it shows in one of two ways. If Docs ignores the
key events, nothing converts and the space is swallowed. If it takes the
Backspaces but not the keypresses, the command is deleted and nothing is typed,
which loses text: tell users to switch Google Docs off until a fix is out.

## What does not work

- **Google Sheets and Slides.** The extension does nothing in any frame inside
  them, so it can never hand them a second copy of what was typed.
- **Chrome's own pages** (`chrome://`, the Web Store, the new tab page). Chrome
  keeps every extension out of these.
- **Password fields**, deliberately.

Running the extension alongside a desktop app should be harmless: the desktop
app takes the space before the page sees it, so the extension never has a
command to act on. This has not been tested.

## Files

| Path | What it is |
|---|---|
| `manifest.json` | The extension's manifest. Its version must match `VERSION`, which `scripts/check-version.py` checks. |
| `engine/tables.js` | Generated by `scripts/generate-js-tables.py`. Do not edit by hand. |
| `engine/engine.js` | Tokenizer, converter and trigger rules. |
| `content/content.js` | Runs in every page: follows typing and replaces text. |
| `content/docs.js` | Google Docs mode: follows the keys, since Docs shows no text. |
| `shared/settings.js` | Settings storage and the site rules. |
| `background/worker.js` | The welcome page on first install, the toolbar icon, the pause shortcut, and the messages between a Google Docs tab's frames. |
| `popup/`, `options/` | The toolbar popup and the settings page. |
| `icons/` | Generated by `scripts/make-chrome-icons.py` from the menu bar mark: `icon-*` orange, `icon-off-*` grey and struck through. |
| `store/` | Screenshots and the promo tile for the Web Store. Not packaged. |
| `STORE.md` | What to fill in on the Web Store, field by field. |

After changing the Swift tables, regenerate: `swift build && python3
scripts/generate-js-tables.py`, then run the conformance test.

## Packaging

```sh
scripts/package-chrome.sh
```

Checks the version, runs the conformance test, and writes
`build/LaTeX-Squiggly-<version>-chrome.zip`, which is what the Web Store takes.
See [STORE.md](STORE.md) for the rest.
