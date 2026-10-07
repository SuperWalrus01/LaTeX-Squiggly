# The mascot

Nine poses, each a PNG on a transparent background, cut from the sheet
`mascot.png` at the repository root.

| File | Pose | Used in |
|---|---|---|
| `hello.png` | Waving hello, holding an LS book | Small promo tile, GitHub social preview, video end cards |
| `reading.png` | Sitting, reading an LS book | Not yet used |
| `idea.png` | Thinking, with a lightbulb | Store screenshot 2, the renderer |
| `walking.png` | Walking along with a book | Not yet used |
| `peeking.png` | Peeking up over an edge (flat bottom) | Store screenshot 3, over the renderer; marquee tile |
| `backpack.png` | Seen from behind, the LS logo on its backpack | Store screenshot 5, privacy |
| `laptop.png` | Typing on an LS laptop | Store screenshot 1, typing |
| `celebrate.png` | Arms up, celebrating | Store screenshot 4, paste anywhere; video end cards |
| `books.png` | Carrying a stack of books | Not yet used |

In the store images the mascot stays small and at the edges: the demo is the
point of each image, so it never stands in front of it. In the holiday sets
(`chrome/store/holidays/`) it wears the holiday's hat.

`poses.json` gives each pose's size in pixels and the top of its head
(`head`, as x and y, and `headWidth`), which is where a hat goes.

The sheet's background is black, not transparent. Each pose was lifted out
with macOS's subject lifting (Vision's foreground instance mask, as Photos'
"Copy Subject"), which keeps the dark backpack and books whole. The sparks and
the lightbulb, which the lifting leaves out, were put back by their
brightness, and the soft edges had the black divided back out, so the poses
sit cleanly on light backgrounds too.
