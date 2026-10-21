# The LaTeX Squiggly site

A plain static site: no build step, no framework, no dependencies. Serve the
folder (`python3 -m http.server` inside `site/`) and open it. From the file
system most of it works, but Chrome will not draw the logo and wordmark masks.

```
site/
  index.html            the home page
  privacy.html          the privacy policy, for every platform
  guide.html            how to use it, on each platform
  assets/site.css       one stylesheet for all three pages, tokens for light and dark
  assets/app.js         the live demo and the symbol browser
  assets/data.js        generated: the app's own tables
  assets/*.png          the artwork, the icons, the link cards
  assets/guide.js       the guide's video carousels and its sidebar
  assets/videos/        the guide's tutorial videos (720p MP4) and their posters
  assets/mascot/        mascot poses, copied from assets/mascot at the root
  assets/shots/         store screenshots, scaled down: the iPhone ones from
                        ios/store/v2, the Chrome ones from chrome/store/chrome-v2
```

## Publishing it

`.github/workflows/pages.yml` deploys this folder to GitHub Pages whenever a
change to it reaches `main`, and can be run by hand from the **Actions** tab.
The repository's **Settings → Pages → Source** is set to *GitHub Actions*.

The site is at `https://superwalrus01.github.io/LaTeX-Squiggly/`. If the
repository moves, change the `<link rel="canonical">` in both pages and
`og:image` in `index.html`, which some scrapers insist on reading as an
absolute URL. The Chrome extension's store listing and settings page link to
`privacy.html`, so that address must keep working.

## What is generated, and what is not

`index.html`, `privacy.html`, `guide.html`, `styles.css` and `app.js` are
written by hand. `assets/guide-renderer.png` is a screenshot of the
extension's Renderer tab. The videos in `assets/videos/` are rendered from the
real extension, engine and renderer; their music is "Voxel Revolution" by Kevin
MacLeod (incompetech.com), CC BY 4.0, credited in the guide's footer.
Edit them.

`assets/data.js` and the worked examples inside `index.html` are not:

```
python3 scripts/make-site.py
```

That reads the tables out of `Sources/LaTeXUnicode` and runs every example
through the real `latex-squiggly` binary, so the page cannot drift away from
the app it describes. The examples live between `<!-- BEGIN generated: … -->`
markers; everything outside them is left alone.

The images come out of the artwork in `assets/`:

```
swift scripts/make-site-images.swift
```

`favicon.png` is the LS mark on a transparent ground, for browser tabs.
`touch-icon.png` is the same mark on a paper tile, because iOS puts a
transparent home-screen icon on black.

`github-card.png` is not used by the site. It is the 1280x640 image GitHub
wants for a repository's social preview, uploaded by hand in **Settings →
General → Social preview**, and it is generated here so it stays in step with
the artwork.

`wordmark.png` and `mark.png` are alpha masks, not pictures: the page inks them
from a CSS custom property, so one file serves both themes. Their grey plane is
white on purpose. A browser may resolve a mask by luminance instead of alpha,
and black ink at full coverage is luminance zero, which would mask the element
away entirely.

The demo in the page is a working mirror of the converter, with the same tables
and the same rules for the paths the page shows, not a recording. It runs
entirely in the browser and talks to nothing.
