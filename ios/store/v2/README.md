# Store screenshots, version 2

The keyboard shown inside Messages and Notes, with the result each headline
promises on screen. Same banner and type as `../make-store.py`.

**These are recreations, not simulator captures.** The keyboard, the share
sheet and the Messages app are drawn in HTML from the app's own layouts and
colours (`ios/KeyboardUI/Layouts.swift`, `Render/Brand.swift`); equations are
typeset by MathJax rather than SwiftMath, and the iOS type is Inter, not SF.
App Review checks that screenshots match the app (guideline 2.3), so compare
each one against the app on a phone before uploading.
`iphone-7-private.png` is the real setup screen, copied from `..`.

## Remake

`source/store.html?shot=<name>` draws one. Next to it, it needs `tables.js`
and `engine.js` from `chrome/engine/`, `mathjax/` from `chrome/renderer/`,
`fonts-local.css` (the site's Google Fonts saved locally), and these images:
`wordmark-t.png` (`chrome/store/image-kit/wordmark-transparent.png`),
`mascot-laptop.png` (`assets/mascot/laptop.png`), `wordmark-app.png`
(`ios/Render/Brand.xcassets/Wordmark.imageset`) and `appicon.png`.

    node store-shots.mjs <out dir> [name ...]
