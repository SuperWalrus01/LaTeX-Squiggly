#!/usr/bin/env python3
"""
Generates chrome/icons/*.png from the menu bar mark.

The app icon is the full wordmark, which is unreadable at the 16 pixels Chrome
draws in its toolbar, so the extension uses the LS mark the menu bar and the
Windows tray use, in the tray's orange.

Chrome's guidance for the 128 pixel icon is 96 pixels of artwork centred in the
canvas, which leaves room for the shadow the Web Store adds. The toolbar sizes
get less margin, because at 16 pixels every pixel of the mark counts.

Needs Pillow.  Run:  python3 Tools/make_chrome_icons.py
"""

import os, sys

try:
    from PIL import Image
except ImportError:
    sys.exit("needs Pillow: python3 -m pip install Pillow")

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "chrome", "icons")

# The same orange as Tools/make_windows_icons.py.
ORANGE = (0xF2, 0x7A, 0x1A)

# Canvas size to the size of the artwork inside it.
SIZES = {128: 96, 48: 42, 32: 30, 16: 16}


def main():
    source = Image.open(os.path.join(ROOT, "Assets", "menu-icon.png")).convert("RGBA")
    mark = source.crop(source.getbbox())

    # The mark's shape is its alpha; the colour is replaced outright.
    alpha = mark.getchannel("A")
    tinted = Image.new("RGBA", mark.size, ORANGE + (0,))
    tinted.putalpha(alpha)

    os.makedirs(OUT, exist_ok=True)
    for canvas, art in SIZES.items():
        scale = art / max(tinted.size)
        # Reduced in one step from the full-size artwork, so the edges are
        # antialiased by the reduction rather than by hand.
        size = (max(1, round(tinted.width * scale)), max(1, round(tinted.height * scale)))
        reduced = tinted.resize(size, Image.LANCZOS)
        icon = Image.new("RGBA", (canvas, canvas), (0, 0, 0, 0))
        icon.alpha_composite(reduced, ((canvas - size[0]) // 2, (canvas - size[1]) // 2))
        icon.save(os.path.join(OUT, f"icon-{canvas}.png"), optimize=True)

    print(f"generated {len(SIZES)} icons in chrome/icons")


if __name__ == "__main__":
    main()
