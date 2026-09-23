#!/usr/bin/env python3
"""
Generates chrome/icons/*.png from the menu bar mark.

Two sets. icon-*.png is the orange mark, for the store and the toolbar while
converting. icon-off-*.png is the toolbar icon while it is not: the mark in
grey with a strike through it, the same as the Windows tray's inactive icon, at
the two sizes a toolbar uses.

The app icon is the full wordmark, which is unreadable at the 16 pixels Chrome
draws in its toolbar, so the extension uses the LS mark the menu bar and the
Windows tray use, in the tray's orange.

Chrome's guidance for the 128 pixel icon is 96 pixels of artwork centred in the
canvas, which leaves room for the shadow the Web Store adds. The toolbar sizes
get less margin, because at 16 pixels every pixel of the mark counts.

Needs Pillow.  Run:  python3 scripts/make-chrome-icons.py
"""

import os, sys

try:
    from PIL import Image, ImageDraw
except ImportError:
    sys.exit("needs Pillow: python3 -m pip install Pillow")

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "chrome", "icons")

# The same orange and grey as scripts/make-windows-icons.py.
ORANGE = (0xF2, 0x7A, 0x1A)
GREY = (0x8C, 0x8C, 0x8C)

# Canvas size to the size of the artwork inside it.
SIZES = {128: 96, 48: 42, 32: 30, 16: 16}
OFF_SIZES = {32: 30, 16: 16}

# The strike is drawn on a large master and reduced with the mark, so the
# reduction antialiases both.
MASTER = 256


def tinted(mark, colour):
    """The mark's shape, which is its alpha, in the given colour."""
    out = Image.new("RGBA", mark.size, colour + (0,))
    out.putalpha(mark.getchannel("A"))
    return out


def placed(art_image, canvas, art):
    """The artwork scaled to fit art pixels, centred on a transparent canvas."""
    scale = art / max(art_image.size)
    size = (max(1, round(art_image.width * scale)), max(1, round(art_image.height * scale)))
    reduced = art_image.resize(size, Image.LANCZOS)
    icon = Image.new("RGBA", (canvas, canvas), (0, 0, 0, 0))
    icon.alpha_composite(reduced, ((canvas - size[0]) // 2, (canvas - size[1]) // 2))
    return icon


def struck(mark):
    """The grey mark with a diagonal strike, as the Windows inactive icon has.

    A gap is cleared around the line first: a strike drawn straight over the
    mark merges with it and reads as a thicker letter, not as a strike.
    """
    master = placed(tinted(mark, GREY), MASTER, MASTER)
    inset = MASTER * 0.11
    line = [(inset, inset), (MASTER - inset, MASTER - inset)]

    gap = Image.new("L", master.size, 0)
    ImageDraw.Draw(gap).line(line, fill=255, width=round(MASTER * 0.14))
    alpha = master.getchannel("A")
    alpha.paste(0, mask=gap)
    master.putalpha(alpha)

    ImageDraw.Draw(master).line(line, fill=GREY + (255,), width=round(MASTER * 0.068))
    return master


def main():
    source = Image.open(os.path.join(ROOT, "assets", "menu-icon.png")).convert("RGBA")
    mark = source.crop(source.getbbox())

    os.makedirs(OUT, exist_ok=True)
    # Reduced in one step from the full-size artwork, so the edges are
    # antialiased by the reduction rather than by hand.
    orange = tinted(mark, ORANGE)
    for canvas, art in SIZES.items():
        placed(orange, canvas, art).save(os.path.join(OUT, f"icon-{canvas}.png"), optimize=True)

    off = struck(mark)
    for canvas, art in OFF_SIZES.items():
        placed(off, canvas, art).save(os.path.join(OUT, f"icon-off-{canvas}.png"), optimize=True)

    print(f"generated {len(SIZES) + len(OFF_SIZES)} icons in chrome/icons")


if __name__ == "__main__":
    main()
