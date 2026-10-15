# Holiday store images

A set of Chrome Web Store images for each holiday, to swap in for a few weeks
and then swap back. Each set is the everyday set (`chrome/store/chrome-v2/`)
in costume: the same five screenshots and two promo tiles, with a holiday
backdrop, holiday headlines and holiday maths, plus a themed logo. The mascot
(`assets/mascot/`) is in each image too, small and at the edge, in the
holiday's hat.

The screenshots are still real. The extension's popup, renderer and menu item
are drawn by the extension's own code, unthemed; only the page around them
changes. That matters, because the Web Store treats screenshots of things the
extension does not do as misleading.

## The sets

| Folder | When | The maths on show |
|---|---|---|
| `back-to-school/` | Mid September to mid October | The quadratic formula |
| `halloween/` | 10 to 31 October | The witch of Agnesi, a curve with a spooky name |
| `christmas/` | 1 to 26 December | The twelve days of Christmas: 364 gifts |
| `new-year/` | 27 December to 7 January | Why fireworks trace parabolas (and 2027 is prime) |
| `valentines/` | 1 to 14 February | A heart-shaped curve |
| `pi-day/` | 7 to 14 March | Leibniz's series for π |

Every folder has the same files, named as in `chrome-v2/`:

| File | Dashboard field |
|---|---|
| `screenshot-1-type-anywhere.png` to `screenshot-5-control-privacy.png` | Screenshots (1280×800), in that order, except that `screenshot-3-right-click.png` goes second, as in `chrome/STORE.md` |
| `promo-small-440x280.png` | Small promo tile |
| `promo-marquee-1400x560.png` | Marquee promo tile |
| `logo/icon-128.png` | Store icon |
| `logo/icon-16.png`, `icon-32.png`, `icon-48.png` | Not uploaded: the extension's own icons, below |
| `logo/wordmark.png` | Not uploaded: the themed wordmark on a transparent background, for social posts or the website |

The screenshots and tiles are 24-bit PNGs with no alpha channel, which the
store requires. The logo files keep their transparency.

## Putting a set up

1. In the [dashboard](https://chrome.google.com/webstore/devconsole), open
   LaTeX Squiggly, then **Store listing**.
2. Replace the screenshots, both promo tiles and the store icon with the
   holiday folder's.
3. **Submit for review.** Listing changes are reviewed too, so submit about a
   week before the date in the table.

To take it down, upload the everyday images the same way: the screenshots and
tiles in `chrome/store/chrome-v2/`, and the icon `chrome/icons/icon-128.png`.

## The logo in the extension itself

The store icon above changes only the listing. To give the extension's own
icon, in the toolbar, the popup and the settings page, the holiday look:

```
scripts/use-icon-theme.sh halloween
```

This copies the theme's icons into `chrome/icons/`. Reload the unpacked
extension to see it. Users get it only with the next package uploaded to the
store, so plan it into a release. Put the everyday icons back with:

```
scripts/use-icon-theme.sh default
```

At 16 and 32 pixels, the toolbar's sizes, a hat or a heart would be a smudge,
so those sizes are the mark in the holiday's colour only. The accessory shows
at 48 and 128.
