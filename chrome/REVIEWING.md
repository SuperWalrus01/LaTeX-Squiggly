# Notes for reviewers

LaTeX Squiggly turns LaTeX typed in a text box into Unicode when the user
presses space: `\alpha` becomes `α`. To do that it has to see typing, so this
page says where that happens and what becomes of it. Everything runs locally.
The extension makes no network requests and loads no remote code.

## Where typing is read

Only two files read typing. Both are content scripts, and both start with a
list of what they read, keep and send.

| File | What it does with typing |
|---|---|
| `content/content.js` | In ordinary text boxes and rich text editors, keeps the last 64 characters typed, in memory, to recognise a command. It confirms the command is in the field's own text before replacing it. |
| `content/docs.js` | Runs only on `docs.google.com`, and only in a document's hidden input frame. It keeps the same 64-character record, from key events, because Docs has no readable text. |

Neither one reads password fields, email fields or code editors. See `editable`
in `content.js`. Neither does anything while the user has paused the extension
or excluded the site. The shared key rules, such as what counts as a shortcut
and the 64-character limit, are in `content/keyboard.js`.

## What is kept, and where

Nothing typed in a web page is stored. The 64-character record lives in a
variable. It is cleared on every click, arrow key and focus change, and in
Docs mode after 4 seconds without a key.

What is stored, all through `chrome.storage`, never sent anywhere:

| Area | Keys | What |
|---|---|---|
| `sync` | `enabled`, `showNotices`, `googleDocs`, `excludedSites` | The user's settings (`shared/settings.js`). |
| `sync` | `render*` | The renderer's settings (`renderer/settings.js`). |
| `local` | `rendererInput`, `rendererHistory` | What the user typed into the extension's own renderer, and the last 10 equations they copied from it. Never text from a web page. |
| `local` | `popupTab` | Which tab of the popup was open last. |
| `session` | `openRenderer`, `rendererSelection` | Passes text selected with the context menu item to the popup, which then clears it. |

## Messages

All messages stay inside the extension, between its own scripts:

| Message | From → to | Carries |
|---|---|---|
| `state` | page's top frame → worker | Whether the tab is converting, and a tooltip. Nothing typed. |
| `status` | popup → page's top frame | Asks for the site's host name, to show in the popup. |
| `docs-forget` | Docs top frame → worker → Docs frames | Nothing: "the caret moved". |
| `docs-notice` | Docs input frame → worker → Docs top frame | The text of a notice to show the user. |

The worker only passes these along. See `background/worker.js`, the last
listener.

## Things that may look surprising

- **Synthetic key events.** In Google Docs, `typeIntoDocs` in `content/docs.js`
  sends Backspace and character key events to the page. Docs reads keys, not
  text, so this is the only way to replace `\alpha` with `α` there. It fires
  only after the user finishes a command with a space, and it deletes only as
  many characters as that command had.
- **`innerHTML`.** In `content.js`, `buildNotice` fills a closed shadow root
  with a fixed template. Page text is then set with `textContent`. In
  `renderer/mount.js` and `renderer/settings-form.js`, `innerHTML` sets markup
  fetched from the extension's own packaged files.
- **`fetch`.** Only in `renderer/mount.js` and `renderer/settings-form.js`,
  and only for `chrome.runtime.getURL(...)` addresses inside the package.
- **Minified code.** `renderer/mathjax/` is MathJax 3.2.2, unmodified, its
  standard minified release (<https://github.com/mathjax/MathJax-src>).
  `SHA256SUMS` beside it lists each file's checksum. It runs only in the
  extension's popup, to draw LaTeX as an image. `core.js` and `startup.js`
  each contain `new Function("return this")`, a fallback for finding the
  global object that runs only where `globalThis` does not exist. Chrome has
  `globalThis`, so it is never reached.
- **`engine/tables.js`** is generated symbol data: command names and the
  characters they become.
