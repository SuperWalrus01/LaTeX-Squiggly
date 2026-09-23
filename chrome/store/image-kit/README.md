# Store image kit

Prompts and reference images for making better Chrome Web Store graphics with
an image generator (ChatGPT, Gemini or Midjourney).

The brand already has a strong look: the hand-drawn orange squiggly wordmark on
warm cream paper. Everything here builds on that.

## What is in this folder

| File | Contents |
|---|---|
| `generated/` | What the generator made, kept as the source of the finished images |
| `wordmark-transparent.png` | The wordmark on a transparent background, 867 pixels wide, to place on finished images. Not for the generator. |

The store images in use now are in `chrome/store/`, one folder up.

**References to attach to the generator**

These are the originals elsewhere in the repository, not copies, so they cannot
drift from what the app actually uses. Paths are from the repository root.

| File | Attach it for |
|---|---|
| `docs/assets/og-card.png` | The squiggly letter style and the paper colour. Attach to every prompt. |
| `Assets/app-icon.png` | The same style, square |
| `chrome/icons/icon-128.png` | The orange "LS" mark |
| `chrome/store/screenshot-1-typing.png` | What the product looks like, for the screenshot backgrounds |

## Rules

- **No text in generated images.** Generators garble lettering, and a wrong
  `x²` or `\alpha` on a maths tool looks careless. Leave empty space, and add
  the words afterwards.
- **Screenshots stay real.** The Web Store treats screenshots of features the
  extension does not have as misleading. Use the generator for backgrounds and
  promo tiles only, then place the real screenshots on top.
- **No other companies' apps.** No Gmail, Slack or ChatGPT windows or logos.
  Using other brands can get the listing rejected. Generic windows only.
- **Final files** must be the exact size, as 24-bit PNG or JPEG with no
  transparency.
- **Do not change the listing while the extension is in review.** Changing it
  can restart the review. Swap the new images in after approval.

## Style block

Paste this at the start of every prompt.

```
Style: warm, friendly, hand-made. Background is flat cream paper, hex #FAF7EE, with a very faint paper grain. The only accent colour is a warm squiggle orange, hex #E2660F, with a darker shade #C2560B for depth and deep brown-black #221A12 for any dark detail. Shapes are soft, rounded, wobbly and blobby, like thick orange ink drawn with a rounded marker, matching the letterforms in the attached reference image. Flat 2D illustration, no gradients except very soft shadows, no 3D render, no glossy effects, no neon. Absolutely no text, letters, numbers, logos or watermarks anywhere in the image.
```

## 1. Marquee promo tile (1400×560)

Attach: `docs/assets/og-card.png`, `chrome/icons/icon-128.png`

```
A wide banner, 5:2 aspect ratio. The left 55% is completely empty cream paper, reserved for a title to be added later. On the right side, a playful illustration of transformation: a thick orange squiggly line enters from the left edge, loops once like a ribbon, and flows into a scatter of soft rounded orange blobs of varying sizes, as if ink is wriggling into new shapes. A few tiny orange sparkle marks and dots float around it. Generous margins on all sides, composition balanced toward the right, calm and uncluttered.
```

Afterwards: the wordmark in the empty left side, and "Type LaTeX anywhere on
the web" under it.

## 2. Small promo tile (440×280)

Attach: `docs/assets/og-card.png`, `chrome/icons/icon-128.png`

```
A small, simple tile, 11:7 aspect ratio, that must stay readable when shown tiny. Centre-left: a large empty rounded area for a logo to be added later. Around the edges: three or four chunky orange squiggles and blobs, bold and simple, nothing thin or detailed. Lots of empty cream space. Minimal and bold.
```

Afterwards: the wordmark, or the LS mark with the name. Keep it to the name
only; anything more is unreadable at this size.

## 3. Screenshot backgrounds (1280×800, make three)

Attach: `docs/assets/og-card.png`, `chrome/store/screenshot-1-typing.png`

```
A 16:10 background for a product screenshot. The centre 70% of the image is a clean, empty, slightly lighter cream rectangle with softly rounded corners and a very soft shadow, where a screenshot will be placed later; leave it completely blank. Around it, in the margins only, loose orange squiggly doodles: wavy lines, small loops, rounded blobs and dots, as if drawn in the margin of a notebook. Keep the doodles light and sparse so they frame the centre without competing with it. Leave a clear empty band across the top 15% for a headline.
```

For the other two, change the doodle wording to one of:

- "doodles concentrated in the bottom-left and top-right corners"
- "a single long squiggle running along the bottom edge"
- "small scattered dots and loops evenly around the border"

Afterwards: a headline in the top band, and the real screenshot in the centre.

| Screenshot | Headline |
|---|---|
| `screenshot-1-typing.png` | Type LaTeX. Get real characters. |
| `screenshot-2-notice.png` | Honest when it has to approximate |
| `screenshot-3-welcome.png` | Nothing you type leaves your computer |

## 4. Squiggly symbols (optional)

Attach: `docs/assets/og-card.png`

Use the style block, but replace its last sentence with "Only the single shape
described below, nothing else."

```
One single symbol drawn in the exact wobbly, blobby, thick orange marker style of the letters in the attached reference: the Greek letter alpha (α). Centred on plain cream paper, lots of empty space around it.
```

One symbol per image. Swap alpha for sigma (Σ), integral (∫), infinity (∞) or
right arrow (⇒). Asking for several at once makes the generator garble them, and
check each one really is the right symbol. They work as accents on the tiles and
in screenshot margins.

## 5. Social sharing card (1200×630, optional)

Attach: `docs/assets/og-card.png`

```
A 1.91:1 social sharing card. Centre: a large empty area for a logo. Below it, a thin empty band for one line of text. Framing it, a few bold orange squiggles curling in from the corners. Calm, lots of cream space.
```

## Finishing

Put the backgrounds you like in `generated/`, then ask Claude to compose the
final images: wordmark, headlines and real screenshots placed on top, exported
at the exact store sizes as 24-bit PNGs with no transparency, and copied into
`chrome/store/`.
