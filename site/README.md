# The LaTeX Squiggly site

A plain static site: no build step, no framework, no dependencies. Open
`index.html` in a browser and it works, from the file system or from a server.

```
docs/
  index.html          the page
  assets/styles.css   one stylesheet, tokens for light and dark
  assets/app.js       the live demo and the symbol browser
  assets/data.js      generated — the app's own tables
  assets/*.png        the artwork, the favicon, the link cards
```

## Publishing it

GitHub Pages serves this folder directly. In the repository's
**Settings → Pages**, set **Source** to *Deploy from a branch*, then pick
`main` and the `/docs` folder. The site appears at
`https://<user>.github.io/<repository>/` within a minute or so.

Two things to change if the repository is not at that address: the
`<link rel="canonical">` in `index.html`, and `og:image`, which some scrapers
insist on reading as an absolute URL.

## What is generated, and what is not

`index.html`, `styles.css` and `app.js` are written by hand. Edit them.

`assets/data.js` and the worked examples inside `index.html` are not:

```
python3 Tools/make_site.py
```

Nor are the four images, which come out of the artwork in `Assets/`:

```
Scripts/make-icons.sh                  # for the iconset the favicon is cut from
swift Tools/make_site_images.swift
```

`github-card.png` is not used by the site. It is the 1280x640 image GitHub
wants for a repository's social preview, uploaded by hand in **Settings ->
General -> Social preview**, and it is generated here so it stays in step with
the artwork.

`wordmark.png` and `mark.png` are alpha masks, not pictures — the page inks
them from a CSS custom property, so one file serves both themes. Their grey
plane is white on purpose: a browser may resolve a mask by luminance instead of
alpha, and black ink at full coverage is luminance zero, which would mask the
element away entirely.

That reads the tables out of `Sources/LaTeXUnicode` and runs every example
through the real `latex-squiggly` binary, so the page cannot drift away from
the app it describes. The examples live between `<!-- BEGIN generated: … -->`
markers; everything outside them is left alone.

The demo in the page is a working mirror of the converter — the same tables and
the same rules for the paths the page shows — not a recording. It runs entirely
in the browser and talks to nothing.
