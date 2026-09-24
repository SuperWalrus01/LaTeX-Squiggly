# Changelog

Every release, newest first. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/). Changes are added under
**Unreleased** as they are merged; see
[docs/releasing.md](docs/releasing.md).

## Unreleased

To be released as 0.3.0. The Chrome extension goes to the store first; the
Windows fixes ship once they have been tested on Windows.

### Added

- **Renderer** in the Chrome extension's popup: type maths-mode LaTeX, see it
  drawn by MathJax as you type, and copy or save it as a PNG or SVG, for
  pasting where LaTeX is not understood. White or transparent background,
  scale 1× to 4×, text colour, your own `\newcommand` definitions,
  autocomplete, closing braces, colour swatches that write `\textcolor`, and
  Overbrace and Underbrace helpers. Alt+Shift+E opens it; Ctrl+Enter copies
  and closes. MathJax 3.2.2 is included in the extension, which fetches
  nothing.
- **Renderer in the macOS app**: Render LaTeX as Image… in the menu, or
  ⌃⌥⌘L from any app, opens the extension's renderer in a window. Copy PNG
  puts the image on the clipboard at the size it was previewed, which Chrome
  cannot do, and ⌘Enter copies and hands the focus back to the app you were
  in.
- **Render selection as image**, on the right-click menu for selected text,
  opens the renderer with that text, less its `$` or `\[` delimiters. It adds
  the `contextMenus` permission, which shows no warning.
- A **history** in the renderer of the last 10 equations copied or saved,
  closed until opened, with thumbnails drawn only then.

- **Google Docs** in the Chrome extension, on by default with a switch in the
  settings. Docs gives the extension no text to check, so it follows the keys
  pressed instead, forgets them after four seconds or on any click, and
  replaces a command with Backspace and key events. Documents only; Sheets and
  Slides are untouched. The popup offers the switch when a Google Doc is open.
- The extension's toolbar icon turns grey with a strike wherever it is not
  converting, paused or on an excluded site, and its tooltip says which.
- Alt+Shift+L pauses and resumes the extension from any page, and the page
  says so. The shortcut can be changed at `chrome://extensions/shortcuts`.

- **Chrome extension**, in `chrome/`. Converts LaTeX in text boxes and rich
  editors on web pages, with the same engine and the same 2,030-fragment
  conformance reference as the desktop apps. It confirms the text in front of
  the caret before replacing anything, stays off on Overleaf and other LaTeX
  sites and in code editors, and has a toolbar popup, a settings page with a
  symbol search, and a first-install page saying what it reads. Submitted to
  the Chrome Web Store.
- A privacy policy page on the website, covering all three platforms.
- `scripts/check-all.sh`, which runs every check in the repository, including
  one that fails if a generated file has been edited by hand.
- Continuous integration on every push and pull request.
- `CONTRIBUTING.md`, this changelog, issue and pull request templates, and the
  `docs/` folder.

### Changed

- The repository is organised by role: `assets/`, `scripts/` (the former
  `Scripts/` and `Tools/`), `conformance/`, `site/` (the former `docs/`) and
  `docs/`. Every file kept its history.
- The website's favicon is the LS mark alone, without its paper tile, so it
  reads on dark browser tabs. Home-screen icons keep the tile.
- The README is a short front page; the design writing moved to `docs/`.

### Fixed

- The Windows app's source now matches the build that shipped. The 0.2.0
  executable was rebuilt on 8 September with a fix for the hang, but the
  source of that fix never reached the repository, so building from it gave
  the version that could freeze the keyboard. The keyboard hook now runs on a
  thread of its own again, with no mouse hook, a keyboard layout table built
  off the hook, and a diagnostics log, and the source compiles to the same
  code as the published executable.
- The extension's icons were missing from the repository, because the rule
  ignoring the macOS `Icon` file also matched `chrome/icons/`.
- In the Chrome extension: commands with braces, such as `\frac{1}{2}`, never
  converted on keyboards that type braces with AltGr or Option, which is most
  European ones, because any modified key ended the command; dead keys such
  as `^` on a German keyboard did the same. Editors inside an `about:blank`
  frame (TinyMCE, CKEditor 4, classic WordPress) or a shadow root were never
  reached, and an editor filled with `document.open` after the page loaded,
  as TinyMCE does, erased the extension's listeners, so it worked on some
  loads and not others. The extension now also stays out of every frame inside Google
  Docs, rather than relying on how Docs builds its hidden input frame, and an
  editor that refuses a replacement no longer leaves the command selected
  with the space lost.

## [0.2.1] - 2026-09-08

macOS only. Windows stays on 0.2.0.

### Added

- **Keep scripts Unicode cannot make**, a setting that is off by default. On,
  `\Sigma_{i=1}^\infty{a_i}` becomes `Σᵢ₌₁^∞aᵢ` instead of being refused: every
  part with a Unicode form gets one, and only the script without one keeps the
  way it was typed. It reports itself as a fallback, so the notice still fires.
  `latex-squiggly -k` on the command line.
- The disk image opens as a fixed window with the app, an arrow and the
  Applications folder, and the mounted volume has its own icon and is named
  **LaTeX Squiggly Installer**.

### Changed

- Excluded apps and sites are edited in Settings only. **Do not convert in
  ‹app›** stays in the menu.

### Known issue

- With the new setting off, a long expression that cannot convert can still
  have a fragment of its tail replaced: `\Sigma_{i=1}^\infty{a_i}` becomes
  `\Sigma_{i=1}^∞aᵢ`, with no message.

## [0.2.0] - 2026-09-07

### Added

- **Windows**, as a beta: a tray app for Windows 10 and later, one executable
  with no installer. The engine is the Mac app's, with its tables generated
  from the Swift engine and checked against it over 2,030 fragments.
- The version is kept in one file, `VERSION`, and checked everywhere else.

### Fixed

Four bugs that could damage the text being typed:

- Commands inside commands were mangled: `\frac{\alpha}{2}` was read from its
  last backslash and reported a stray brace, `\alpha\beta` became `\alphaβ`,
  and `\left(\alpha\right)` became `\left(\alpha)`. A fragment now starts at
  the first backslash typed since the last space.
- Clicking elsewhere did not clear the typing buffer, so pressing space could
  delete text at the new cursor position.
- Option-Backspace deleted a word while the buffer dropped one character,
  leaving the delete count too large.
- `\sqrt[]{8}` produced `8^(1/)` and `\sqrt[0]{8}` produced `8^(1/0)`. Both are
  refused now, with a reason.

And three that could not damage text: a notification observer leaked on every
enable and disable, an exclusion list that a future field would have wiped, and
notices appearing on the wrong display.

## [0.1.0] - 2026-09-07

The first release, for macOS 13 and later.

### Added

- Type LaTeX in any app and it becomes Unicode when you press space: 202
  symbols, named operators, superscripts, subscripts, fractions, roots and
  binomials, as real text.
- `$...$` inline maths, so `$x^2$` converts while `x^2` in prose does not.
- Honest results: a flagged approximation when there is no exact form, and the
  text left alone, with the reason, when there is none at all.
- Per-app suppression for TeX editors, code editors and terminals, and per-site
  suppression for Overleaf and other LaTeX websites, read from the browser.
- A menu bar item, a settings window with the permission state, and a symbol
  browser.
- A signed disk image, and a website with a live demo.

[0.2.1]: https://github.com/SuperWalrus01/LaTeX-Squiggly/releases/tag/v0.2.1
[0.2.0]: https://github.com/SuperWalrus01/LaTeX-Squiggly/releases/tag/v0.2.0
[0.1.0]: https://github.com/SuperWalrus01/LaTeX-Squiggly/releases/tag/v0.1.0
