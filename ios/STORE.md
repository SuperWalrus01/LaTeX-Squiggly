# Publishing to the App Store

Everything App Store Connect asks for, in the order it asks. Work down the
page: each step says where to click, and the text in the boxes is ready to
paste. The version is **1.0 (build 1)**, set in `project.yml`.

## Open before you submit

Found in a pre-launch check on 9 October 2026. Strike each off when done.

- [ ] **The privacy policy is not live yet.** The iPhone section of
  `site/privacy.html` is only on `github-marketing`; `main`, which deploys the
  site, does not have it (nor any of `ios/`). App Store Connect, the reviewer
  and the app's own About link all open that URL, so merge to `main` first
  and check the page shows **The iPhone app**.
- [ ] **Signing team.** `DEVELOPMENT_TEAM` in `project.yml` is still the free
  Personal Team (`DL65G3N2U3`), which cannot upload to App Store Connect.
- [ ] **Xcode version.** Apple requires uploads to be built with a recent
  SDK (Xcode 26 and the iOS 26 SDK since April 2026). Check
  <https://developer.apple.com/news/upcoming-requirements/> and archive with
  the current Xcode.
- [ ] **The device checklist below is not done.** Landscape has never been
  seen on a real phone, keyboard memory at size L is unmeasured, and a crash
  on opening was fixed only days ago (`ef39fb1`). Use TestFlight for a few
  days before submitting.
- [ ] **Regenerate the screenshots.** `store/make-store.py` now sets the α in
  "Type \alpha, get α" in a maths italic; in the current
  `iphone-1-type.png` it falls back to a face where it reads as "a". Run
  `scripts/make-store-shots.sh` on the Mac.
- [ ] **Support URL.** GitHub Issues needs a GitHub account to reach you.
  Guideline 1.5 asks for an easy way to contact you; a support page on the
  site with an email address is safer.

## Why this should pass review

App Review checks keyboards against guideline 4.4.1, and this one is built to
it:

- **It types.** A full keyboard with letters, numbers, symbols, delete, return
  and spelling, not only a LaTeX tool.
- **It can switch to the next keyboard.** The globe key shows when iOS asks for
  it, and on Face ID iPhones iOS draws its own below the keys.
- **It works without Full Access.** Everything works without it except Copy in
  the bar, which says why it needs Full Access when tapped. Keyboards need Full
  Access for the clipboard, and that is the only thing it is used for.
- **No network, no data.** The keyboard makes no network requests and stores
  nothing typed. The App Privacy answer is Data Not Collected, and every target
  has a privacy manifest saying so.
- **It opens nothing but Settings**, and no standard key does anything
  unusual.

The app around the keyboard has setup steps, a page to try it, a renderer, the
privacy policy link, help and acknowledgements, which is enough for 4.2
(minimum functionality).

The likeliest rejection is a reviewer who cannot find the keyboard and calls
the app broken. The review notes below walk them through it.

## Before you start

1. **Join the Apple Developer Program** at
   <https://developer.apple.com/programs/enroll/>: Individual, US$99 a year.
   Approval can take a day or two. Your legal name is shown as the seller.
2. **Sign with your paid team.** In Xcode, **Settings → Accounts**, add your
   Apple ID and note the new team's ID. Put it in `ios/project.yml` as
   `DEVELOPMENT_TEAM` (it is `DL65G3N2U3`, the free Personal Team, now), then
   run `xcodegen` in `ios/`.
3. **Accept the agreements** in App Store Connect under **Business**. A free
   app needs only the Free Apps Agreement. Charging, now or later, also needs
   the Paid Apps Agreement, bank details and the W-8BEN tax form.
4. **Publish the privacy policy.** The iPhone section of `site/privacy.html`
   goes live when it reaches `main`, which deploys the site. Check that
   <https://superwalrus01.github.io/LaTeX-Squiggly/privacy.html> has a
   section called **The iPhone app**. App Store Connect, the reviewer and the
   app's own Privacy policy link all go there.
5. **Try it on your own iPhone.** Run the `LaTeXSquiggly` scheme on the phone,
   turn the keyboard on, and go through this list. Anything that fails is
   worth fixing before a reviewer finds it.
   - [ ] Notes: `\alpha` then space gives α; delete straight after puts
     `\alpha` back.
   - [ ] Messages: type a sentence at speed. Nothing is dropped, and a thumb sliding on space still types a space.
   - [ ] `$x^2$` shows typeset in the bar. Tap it for the large preview.
   - [ ] Copy with Full Access off says to turn it on. With it on, the image
     pastes into Messages.
   - [ ] Safari's address bar: `/` and `.` sit beside space. A Mail To field:
     `@` and `.`.
   - [ ] Turn the phone sideways in Notes. The keyboard is shorter and every
     key still types. (Not yet seen on a real phone.)
   - [ ] Dark mode: keys and the bar are readable.
   - [ ] Share sheet: select LaTeX in Notes, Share, LaTeX Squiggly. Copy,
     Share and Save Image all work.
   - [ ] Messages app: **+**, then **More**, then LaTeX Squiggly. Write an
     equation and add it to a message.
   - [ ] Memory: with the keyboard open in Notes, Xcode's **Debug navigator**
     shows the Keyboard process's memory. Open the large preview at size L.
     It must stay well under 60 MB, past which iOS ends the keyboard.
6. **Optional, recommended: TestFlight.** After the first upload (below),
   **TestFlight → Internal Testing** sends the build to your own devices and
   up to 100 people on your team, with no review. Give it a few days of real
   use.

## Create the app

App Store Connect (<https://appstoreconnect.apple.com>) → **Apps** → **+** →
**New App**.

| Field | Value |
|---|---|
| Platforms | iOS |
| Name | `LaTeX Squiggly` |
| Primary language | English (U.K.), to match "maths" in the listing |
| Bundle ID | `com.keenanjusak.latex-squiggly.ios`. If it is not in the list, archive once (below): Xcode registers it, and the three extensions' IDs, when it signs. |
| SKU | `latex-squiggly-ios` |
| User access | Full access |

The bundle ID can never change once a build is uploaded.

## Upload the build

```sh
cd ios
xcodegen
open LaTeXSquiggly.xcodeproj
```

1. Choose the **LaTeXSquiggly** scheme and **Any iOS Device (arm64)**.
2. **Product → Archive.** The Organizer opens when it finishes.
3. **Distribute App → App Store Connect → Distribute.** Leave the defaults:
   automatic signing, upload symbols.
4. Wait for the email saying the build has processed, usually 10 to 30
   minutes. It then appears under the version's **Build** section.

Export compliance is already answered: `ITSAppUsesNonExemptEncryption` is NO
in the app's Info.plist, so App Store Connect does not ask.

Each upload needs a higher build number. Raise `CURRENT_PROJECT_VERSION` in
`project.yml` and run `xcodegen` before archiving again.

## App Information

In the app's sidebar, **General → App Information**.

**Subtitle** (30 characters at most)

```
Maths keyboard: \alpha to α
```

**Category:** Primary **Utilities**, where keyboards are browsed. Secondary
**Education**.

**Content Rights:** No, it does not contain, show or access third-party
content.

**Age Rating:** answer **None** or **No** to every question. It has no web
browsing, no chat with other people, no user-generated content, no
advertising and no purchases. The result is 4+.

**Privacy Policy URL**

```
https://superwalrus01.github.io/LaTeX-Squiggly/privacy.html
```

## Pricing and Availability

- **Price:** Free.
- **Availability:** all countries and regions.
- **iPhone and iPad Apps on Apple Silicon Macs:** turn it **off**. A keyboard
  extension does nothing on a Mac, and the Mac has its own app.
- **Apple Vision Pro:** turn it **off**, for the same reason.

**EU Digital Services Act, trader status.** Without an answer, the app is
removed from EU storefronts. A free app made as a personal project is
**not a trader**. If you ever charge for it, you become a trader, and your
address, phone number and email are shown on the EU product page. Use contact
details you are happy to publish, or leave the EU storefronts out at that
point.

## App Privacy

**App Privacy → Get Started.** Answer **No, we do not collect data from this
app**. The label then reads **Data Not Collected**.

That is true as long as nothing is sent off the phone. Adding analytics or a
crash reporter later changes the answer and the privacy policy.

## The 1.0 version page

In the sidebar, **iOS App → 1.0 Prepare for Submission**.

### Screenshots

**iPhone 6.9" Display**, in this order. App Store Connect scales them for
smaller iPhones, so this one set is all it needs.

1. `ios/store/iphone-1-type.png`: Type \alpha, get α
2. `ios/store/iphone-2-see.png`: See your maths as you type
3. `ios/store/iphone-3-copy.png`: Paste it as an image
4. `ios/store/iphone-4-symbols.png`: Every symbol, one key away
5. `ios/store/iphone-5-share.png`: Render LaTeX from any app
6. `ios/store/iphone-6-messages.png`: Send equations in Messages
7. `ios/store/iphone-7-private.png`: Private by design

**iMessage App** (the tab beside iPhone, there because of the Messages
extension): `ios/store/imessage-1-write.png`.

The App Store has no banner image of its own, unlike Google Play or the
Chrome Web Store: a product page opens on the icon, name and subtitle, then
the screenshots, and search results show the first three. So the banner is in
the screenshots: each has the orange banner with its headline across the top,
and the first is the hero, with the wordmark and the mascot. A large header
image only appears if Apple features the app; to ask, use **Featuring
Nominations** in App Store Connect after release.

Every image is 1320×2868, RGB with no transparency, as App Store Connect
requires. They are real screens from the app, made by
`ios/scripts/make-store-shots.sh`, which builds the app, opens each screen in
a 6.9-inch simulator and puts it in an iPhone under the banner with
`ios/store/make-store.py`. Run it again after the keyboard or the app's
screens change.

An **App Preview** video is optional. The demo in `ios/guide/` is 2 minutes
24 seconds and previews must be 15 to 30 seconds, so it would need cutting
down first.

### Promotional Text (170 characters at most)

Shown above the description, and the one field that can change without a new
version.

```
Type \alpha, get α, in any app. Write maths between $ signs to see it typeset, then paste it as an image. Free, and nothing you type leaves your phone.
```

### Description

The first lines are what most people read, so they say what it does. The App
Store shows plain text, so the link is written out in full.

```
A keyboard for maths. Type LaTeX in any app and get the real symbol the moment you press space: \alpha becomes α, \leq becomes ≤, \mathbb{R} becomes ℝ.

For maths plain text can't hold, like fractions and roots, write it between $ signs. The bar above the keys shows it typeset as you type, and Copy turns it into an image to paste into a chat, an email or a document.

TYPING
• Over 200 symbols: Greek letters, operators, relations, arrows and sets
• Suggestions as you type a command: \al offers α
• The ∑ key has Greek letters and maths symbols. Hold a key for more
• Spelling suggestions that never change a word unless you tap one, and double space for a full stop. Hold space to move the cursor
• LaTeX mode keeps everything as LaTeX, for writing LaTeX documents

RENDERING
• Select LaTeX in any app, tap Share, then LaTeX Squiggly to see it typeset, ready to copy, share or save
• In Messages, open LaTeX Squiggly from the app drawer, write an equation and send it as an image
• The app renders longer passages, words and maths together, in three sizes on a light or dark card

PRIVATE
• Nothing you type is stored or sent anywhere. No account, no ads, no tracking
• Full Access is optional, and only used to copy rendered images from the keyboard

FREE AND OPEN SOURCE
Source code and help: https://github.com/SuperWalrus01/LaTeX-Squiggly
```

### Keywords (100 characters at most)

Comma-separated, no spaces. The name and subtitle are searched already, so
these are other words people might type.

```
math,equation,symbols,greek,unicode,tex,formula,calculus,physics,algebra,student,science,render
```

### URLs

| Field | Value |
|---|---|
| Support URL | `https://github.com/SuperWalrus01/LaTeX-Squiggly/issues` |
| Marketing URL | `https://superwalrus01.github.io/LaTeX-Squiggly/` |

### General

| Field | Value |
|---|---|
| Version | 1.0 |
| Copyright | `2026 Damianus Keenan Jusak` |
| Build | the build uploaded above (**+** beside Build) |

### App Review Information

**Sign-in required:** No.

**Contact information:** your name, phone number and email, for the reviewer
only. They are not shown on the store. Use a phone number you will answer:
reviewers sometimes call instead of rejecting.

**Attachment:** upload `ios/guide/LaTeX-Squiggly-iPhone-Demo.mp4`, the demo
video. A reviewer who sees the keyboard working is far less likely to reject
it as "not functioning" when they cannot find it straight away.

**Notes**

```
LaTeX Squiggly is a keyboard that turns LaTeX commands into symbols, with a share sheet extension and a Messages app that render LaTeX as an image. There is no account or sign-in.

To try the keyboard:
1. Open Settings, then General, Keyboard, Keyboards. Tap Add New Keyboard and choose LaTeX Squiggly. (The app's Set up tab lists the same steps.)
2. Open Notes, start a note, and switch to LaTeX Squiggly with the globe key below the keyboard.
3. Type \alpha (the backslash key is beside the space bar) and press space. It becomes α.
4. Type $x^2 + y^2 = z^2$. The bar above the keys shows it typeset, and tapping it shows it large.

Full Access is optional. Everything above works without it. With it on (Settings, General, Keyboard, Keyboards, LaTeX Squiggly, Allow Full Access), the Copy button in the bar also puts the rendered equation on the clipboard as an image, because keyboards need Full Access to use the clipboard. That is all it is used for. The keyboard makes no network requests and stores nothing typed, with or without Full Access.

Share extension: in Notes, select some LaTeX such as \frac{a}{b}, tap Share, then LaTeX Squiggly.

Messages app: in a conversation, tap +, then More, then LaTeX Squiggly. Tap New, write LaTeX, and tap Add to message.
```

### Version Release

Choose **Manually release this version**, so it goes live when you say, not
the moment it is approved.

## Submit

**Add for Review**, then **Submit to App Review**. A first review usually takes
one to two days. The status moves from Waiting for Review to In Review to
Pending Developer Release.

**If it is rejected,** the message in **App Review** says which guideline and
why. Reply there if the reviewer misunderstood, or fix it, upload a new build
with a higher build number, and submit again. The most likely ones:

- **2.1, the app does not work.** The reviewer could not turn the keyboard on.
  Reply with the steps from the notes, and screenshots of each.
- **4.4.1 or 5.1.1, Full Access.** Reply that Full Access is optional, that
  the keyboard works fully without it, and that it is used only for the
  clipboard, as the app's Setup page and the privacy policy both say.
- **2.3, metadata.** Usually a screenshot or a line of the description the
  reviewer did not see in the app. Change the listing to match.

## After approval

1. **Release** it from the version page.
2. Search for LaTeX Squiggly on your phone's App Store and install it, to see
   it as a user will.
3. Tag the release: `git tag ios-v1.0 && git push origin ios-v1.0`.
4. In `CHANGELOG.md`, move the iPhone entry from **Unreleased** to a release
   heading with the date.

## The next version

1. Raise `MARKETING_VERSION` in `project.yml` (1.0 to 1.0.1 for fixes, 1.1
   for new behaviour) and set `CURRENT_PROJECT_VERSION` back to 1, or keep
   raising it. Every target reads both, so they always match.
2. Archive and upload as above.
3. In App Store Connect, **+** beside iOS App for the new version, fill in
   **What's New in This Version**, choose the build and submit.

Do not change the listing while a version is in review. Changing it can
restart the review.
