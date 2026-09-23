# Publishing to the Chrome Web Store

Everything the Developer Dashboard asks for, in the order it asks. The text in
the boxes is ready to paste.

The text here is for the next upload, 0.2.2, which adds Google Docs. Version
0.2.1's listing said the extension does not work in Google Docs, so when
uploading 0.2.2, paste the description and the host permission justification
again: both changed. The steps are under
[Uploading the next version](#uploading-the-next-version).

## Why this should pass review

The extension is built to what the review checks for:

- **One permission**, `storage`, for the settings. No `tabs`, no `scripting`,
  no `activeTab`, no `<all_urls>`.
- **Page access is the content script only**, on `http://*/*` and
  `https://*/*`. It has to run everywhere because typing happens everywhere.
  This is the one thing that triggers a closer manual review, and the
  justification below answers it.
- **No remote code.** Every script is in the package. Nothing is fetched,
  nothing is evaluated, and the extension makes no network requests at all.
- **Readable code.** Nothing is minified or obfuscated, which the policy
  requires.
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

• 202 symbols: Greek letters, operators, relations, arrows, set theory, logic
• Superscripts and subscripts inside dollars: $x^2$, $a_1$, $\int_0^1$
• Fractions, roots, binomials and \mathbb{R}
• Honest when it has to approximate: if something cannot be written exactly in plain text, a short note says what it did, and if it cannot be written at all, your text is left as typed
• Stays quiet on Overleaf and other LaTeX editors, in code editors, and in password fields, and anywhere you switch it off
• In ordinary text boxes, undo brings the command back

Where it works: text boxes, search boxes, comment fields and rich text editors on web pages. Google Docs documents work too. Not in Google Sheets or Slides, and not in Chrome's address bar or on Chrome's own pages, which no extension can reach.

Privacy: to recognise a command, the extension keeps the last few characters you typed in a text box, in memory only, and forgets them when you click or change fields. Nothing you type is saved or sent anywhere, and the extension makes no network requests. Your settings are stored with Chrome.

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
Converts LaTeX commands the user types into web page text fields into the matching Unicode characters, in place, when the user presses space.
```

**Permission justification: storage**

```
Saves the user's settings: whether conversion is on, whether notices are shown, and the list of sites where the extension stays off. Nothing else is stored.
```

**Host permission justification** (the content script's `http://*/*` and `https://*/*`)

```
The extension converts LaTeX wherever the user types, which can be any site, so its content script has to run on every page. It only reacts to typing in text fields: it keeps the last 64 typed characters in memory to recognise a command, reads the characters just before the cursor to confirm them, and replaces them. In Google Docs, whose text it cannot read, it replaces a command by sending Backspace and key events instead, and the user can switch this off. It compares the page's host with the user's list of excluded sites and discards it. It does not read the rest of the page, store anything typed, or make any network request.
```

**Are you using remote code?** No.

```
All JavaScript is included in the package. The extension loads no external scripts, uses no eval, and makes no network requests.
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

## Releasing an update

1. Bump `VERSION`, and the version in `chrome/manifest.json` to match.
   `scripts/check-version.py` fails until they agree. The store refuses a version
   that is not higher than the last one it accepted.
2. Run `scripts/package-chrome.sh`.
3. In the dashboard: **Package → Upload new package**, then **Submit for
   review**.

Adding a permission later shows existing users a warning and disables the
extension until they accept it, so keep the permission list as it is unless a
feature cannot work without the change.
