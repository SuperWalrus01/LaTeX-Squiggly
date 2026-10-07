# iPhone demo video

`latex-squiggly-iphone-portrait.mp4` (1080×1920) and
`latex-squiggly-iphone-landscape.mp4` (1920×1080) are a recreation of the iOS
app on the `github-marketing` branch, not a screen recording. Conversions come
from the real engine (`chrome/engine`), and the keyboard's suggestion and
rendering rules are ported from `ios/KeyboardUI`. Fonts and the equation
renderer (MathJax instead of SwiftMath) differ from the device.

## Re-render

`source/index.html` draws any frame with `render(t)`. Next to it, it expects:
`tables.js` and `engine.js` from `chrome/engine/`, `mathjax/` from
`chrome/renderer/`, `mark.png` and `wordmark.png` from `site/assets/`,
`appicon.png` from `ios/App/Assets.xcassets/AppIcon.appiconset/`, and the
site's Google Fonts saved locally as `fonts-local.css`.

```sh
node capture.mjs portrait video      # out/portrait-silent.mp4, out/events.json
node capture.mjs landscape video
python3 audio.py out/events.json out/audio.wav
ffmpeg -i out/portrait-silent.mp4 -i out/audio.wav -c:v copy -c:a aac -shortest out.mp4
```
