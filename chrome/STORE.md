# Publishing to the Chrome Web Store

Everything the Developer Dashboard asks for, in the order it asks. The text in
the boxes is ready to paste.

The text here is for the next upload, 0.3.0, which adds Google Docs and the
renderer. Much of what the dashboard holds from 0.2.1 has changed: the
description, the single purpose, the storage and host permission
justifications, the remote code answer, and a new justification for
`contextMenus`. The steps are under
[Uploading the next version](#uploading-the-next-version).

## Why this should pass review

The extension is built to what the review checks for:

- **Two permissions**, `storage` for the settings and `contextMenus` for the
  Render selection as image item, neither of which shows the user a warning.
  No `tabs`, no `scripting`, no `activeTab`, no `<all_urls>`.
- **Page access is the content script only**, on `http://*/*` and
  `https://*/*`. It has to run everywhere because typing happens everywhere.
  This is the one thing that triggers a closer manual review, and the
  justification below answers it.
- **No remote code.** Every script is in the package, MathJax included.
  Nothing is fetched, and the extension makes no network requests at all.
  MathJax's bundle contains one `eval("require")`, reached only when it runs
  under Node, never in Chrome.
- **Readable code.** The extension's own code is neither minified nor
  obfuscated. MathJax, in `renderer/mathjax/`, is its standard minified
  release, byte for byte; the policy allows minification and forbids only
  obfuscation. Its source is public at <https://github.com/mathjax/MathJax-src>.
- **Disclosure before and after install.** The store description, the privacy
  policy and a welcome page on first install all say what is read and that it
  never leaves the computer. The 2026 policy update requires this even for
  data that is only handled locally, and enforcement started on 1 August 2026.

Expect the first review to take longer than a few days, because of the page
access. Updates that do not add permissions are usually faster.

## Before you start

1. **Push `site/privacy.html`** so the privacy policy is live at
   <https://superwalrus01.github.io/LaTeX-Squiggly/privacy.html>. The dashboard
   will not accept a policy URL that does not load, and the welcome page links
   to it.
2. **Build the package:** `scripts/package-chrome.sh` writes
   `build/LaTeX-Squiggly-<version>-chrome.zip`.
3. **Register as a developer** at
   <https://chrome.google.com/webstore/devconsole> (a one-time US$5 fee) and
   verify the contact email.

## Package

**Items → New item**, then upload the zip.

## Store listing

**Description**

```
Type LaTeX in any text box on the web and get real characters. \alpha becomes α, \Rightarrow becomes ⇒, and $x^2$ becomes x², right where you typed it, as soon as you press space.

The result is ordinary Unicode text, not an image, so it survives copying and pasting into chat messages, emails, comments and forms.

For what Unicode cannot write, such as fractions, matrices and braces, the popup's renderer turns LaTeX into an image: type it, see it drawn as you type, and copy it as a PNG to paste into Google Docs, Slack or an email.

• 202 symbols: Greek letters, operators, relations, arrows, set theory, logic
• Superscripts and subscripts inside dollars: $x^2$, $a_1$, $\int_0^1$
• Fractions, roots, binomials and \mathbb{R}
• Honest when it has to approximate: if something cannot be written exactly in plain text, a short note says what it did, and if it cannot be written at all, your text is left as typed
• Stays quiet on Overleaf and other LaTeX editors, in code editors, and in password fields, and anywhere you switch it off
• In ordinary text boxes, undo brings the command back
• The toolbar icon turns grey wherever it is not converting, and Alt+Shift+L pauses it anywhere
• Renderer: maths-mode LaTeX to PNG or SVG, drawn by MathJax inside the extension, with a white or transparent background, colours, your own \newcommand definitions, command autocomplete and a history. Alt+Shift+R opens it, or right-click selected LaTeX and choose Render selection as image; Ctrl+Enter copies

Where it works: text boxes, search boxes, comment fields and rich text editors on web pages. Google Docs documents work too. Not in Google Sheets or Slides, and not in Chrome's address bar or on Chrome's own pages, which no extension can reach.

Privacy: to recognise a command, the extension keeps the last few characters you typed in a text box, in memory only, and forgets them when you click or change fields. Nothing you type in a web page is saved or sent anywhere, and the extension makes no network requests. Your settings, and the last LaTeX you typed into the renderer, are stored with Chrome.

Also available as a menu bar app for macOS and a tray app for Windows, which work in every app, not only the browser.
```

**Category:** Productivity (or Tools, whichever the dashboard offers).

**Language:** English.

**Graphics**

| Field | File |
|---|---|
| Store icon (128×128) | `chrome/icons/icon-128.png` |
| Screenshots (1280×800) | `chrome/store/screenshot-1-typing.png`, `screenshot-2-notice.png`, `screenshot-3-welcome.png` |
| Small promo tile (440×280) | `chrome/store/promo-440x280.png` |
| Marquee promo tile (1400×560), optional | `chrome/store/marquee-1400x560.png` |

The screenshots are real: the extension typing into a page, not a mock-up.
Every image is a 24-bit PNG with no alpha channel, which the store requires.

**Homepage URL:** `https://superwalrus01.github.io/LaTeX-Squiggly/`

**Support URL:** `https://github.com/SuperWalrus01/LaTeX-Squiggly/issues`

## Privacy practices

**Single purpose**

```
Write maths anywhere on the web: LaTeX commands typed into web page text fields become the matching Unicode characters when the user presses space, and the popup's renderer turns LaTeX into an image to paste where Unicode cannot show it.
```

**Permission justification: storage**

```
Saves the user's settings: whether conversion is on, whether notices are shown, the list of sites where the extension stays off, and the renderer's image settings. Also keeps, locally, the last LaTeX typed into the popup's renderer, so it is there when the popup reopens, and the LaTeX of the last 10 images the user copied or saved, as a history they can clear. Nothing typed into web pages is stored.
```

**Permission justification: contextMenus**

```
Adds one item, "Render selection as image", to the menu for selected text. It opens the extension's LaTeX renderer with the selected text in it. The text comes from Chrome with the click; no page is read.
```

**Host permission justification** (the content script's `http://*/*` and `https://*/*`)

```
The extension converts LaTeX wherever the user types, which can be any site, so its content script has to run on every page. It only reacts to typing in text fields: it keeps the last 64 typed characters in memory to recognise a command, reads the characters just before the cursor to confirm them, and replaces them. In Google Docs, whose text it cannot read, it replaces a command by sending Backspace and key events instead, and the user can switch this off. It compares the page's host with the user's list of excluded sites and discards it. It does not read the rest of the page, store anything typed, or make any network request.
```

**Are you using remote code?** No.

```
All JavaScript is included in the package, including MathJax 3.2.2 for the popup's LaTeX renderer, which runs only in the extension's own popup. The extension loads no external scripts and makes no network requests.
```

**Data usage.** Tick these two. The data never leaves the computer, but the
2026 policy asks for local handling to be disclosed too, and declaring it is
what matches the privacy policy.

- [x] **User activity** (keystrokes typed into text fields, used locally to
  recognise LaTeX commands)
- [x] **Website content** (the characters just before the cursor, read locally
  to confirm the command before replacing it)

Leave everything else unticked: no personally identifiable information, health,
financial, authentication, personal communications, location or web history.

Then tick all three certifications:

- [x] I do not sell or transfer user data to third parties, outside of the approved use cases
- [x] I do not use or transfer user data for purposes that are unrelated to my item's single purpose
- [x] I do not use or transfer user data to determine creditworthiness or for lending purposes

**Privacy policy URL:** `https://superwalrus01.github.io/LaTeX-Squiggly/privacy.html`

## Distribution

**Visibility:** Public, or Unlisted to try the store install with a few people
first. Unlisted items go through the same review.

**Regions:** All regions.

## Uploading the next version

The next version is **0.3.0**: Google Docs mode and the renderer. It goes
straight from 0.2.1 to 0.3.0, a minor version for new behaviour, as
`docs/releasing.md` says; there is no 0.2.2. The version
is set everywhere, and the file to upload is
`build/LaTeX-Squiggly-0.3.0-chrome.zip`. The renderer is on the branch
`claude/chrome-extension-feasibility-6kahfo` until it is merged into `main`,
which has to happen first: the privacy policy is published from `main`.

**Before uploading**

1. 0.2.1 has been approved. Uploading while a review is pending can restart it.
2. Rebuild the zip, so it has every change made since it was last built:

   ```
   scripts/package-chrome.sh
   ```

   It checks the version and runs the tests before it packages anything.
3. The privacy policy has its Google Docs and renderer paragraphs live at
   <https://superwalrus01.github.io/LaTeX-Squiggly/privacy.html>. It deploys
   when `main` is pushed. The reviewer compares it with what the extension
   does, and the renderer keeps its input and history on the computer, which
   the old policy said nothing typed ever is.
4. Load the unpacked extension and try by hand what the browser test cannot:
   the renderer from the toolbar popup, Alt+Shift+R, right-click → Render
   selection as image, and a copied PNG pasted into Google Docs, Slack and
   Gmail.

**In the dashboard** (<https://chrome.google.com/webstore/devconsole>, then
LaTeX Squiggly)

1. **Package → Upload new package**, and choose the 0.3.0 zip.
2. **Store listing**: paste the description above; it now mentions Google Docs
   and the renderer. A screenshot of the Renderer tab helps the reviewer match
   the listing to the extension; the current three show only typing.
3. **Privacy**: paste, from above, the single purpose, the storage and host
   permission justifications, the new contextMenus justification, and the
   remote code answer. The data usage ticks stay as they are: text selected
   and sent to the renderer is website content, already declared.
4. **Submit for review**. 0.2.1 stays live until 0.3.0 is approved.

Expect this review to take longer than an ordinary update: it adds a
permission and about 1.9 MB of minified code (MathJax), on top of the page
access that already brings a manual review. If the reviewer asks about the
minified files or the `eval` in them, the answers are under
[Why this should pass review](#why-this-should-pass-review).

**After uploading**

1. In `CHANGELOG.md`, rename **Unreleased** to `[0.3.0]` with the date.
2. Tag it: `git tag v0.3.0 && git push origin v0.3.0`.
3. From then on, 0.3.0 is fixed. The next change goes into 0.3.1: set it in
   `VERSION`, `chrome/manifest.json` and `windows/LaTeXSquiggly.App/app.manifest`
   (as `0.3.1.0`), and `scripts/check-version.py` checks that all three agree.

**Changing something before 0.3.0 is uploaded** needs none of that: make the
change, run `scripts/check-all.sh`, commit, and rebuild the zip. The version
stays 0.3.0 until it is uploaded.

A permission that Chrome shows a warning for disables the extension for every
existing user until they accept it, so add one only if a feature cannot work
without it. 0.3.0 adds `contextMenus`, which Chrome shows no warning for, so
existing users update without being asked. That is worth confirming before
uploading: install 0.2.1 unpacked, replace its files with 0.3.0's, reload it
at `chrome://extensions`, and check that nothing is asked for.
