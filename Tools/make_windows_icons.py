#!/usr/bin/env python3
"""
Generates the Windows .ico files from the same artwork the Mac app is built
from.

Why this exists: the source PNG is a mark floating in a large transparent
canvas, and the mark is only 12% of its area. Handing that straight to a 32
pixel tray icon draws a mark about nine pixels wide surrounded by nothing, which
is exactly as small as it sounds. The Mac generator trims to the bounding box
before it does anything else; so does this.

Everything is composed at 256 pixels and reduced from there, so the strike on
the inactive mark is antialiased by the reduction rather than by hand.

Run:  python3 Tools/make_windows_icons.py
"""

import math, os, struct, zlib

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "windows", "LaTeXSquiggly.App", "Assets")

# The mark's own orange, which reads on a light taskbar and a dark one. A
# template image, the way macOS does it, has no Windows equivalent: a tray icon
# is drawn exactly as given.
ORANGE = (0xF2, 0x7A, 0x1A)
GREY = (0x8C, 0x8C, 0x8C)

SIZES = [256, 128, 64, 48, 40, 32, 24, 20, 16]


# --------------------------------------------------------------------------
# A very small PNG reader. Only what this artwork actually uses.
# --------------------------------------------------------------------------

def decode_png(path):
    data = open(path, "rb").read()
    assert data[:8] == b"\x89PNG\r\n\x1a\n", path
    i, idat = 8, b""
    width = height = depth = colour = interlace = None
    while i < len(data):
        length, kind = struct.unpack_from(">I4s", data, i)
        body = data[i + 8:i + 8 + length]
        if kind == b"IHDR":
            width, height, depth, colour, _, _, interlace = struct.unpack(">IIBBBBB", body)
        elif kind == b"IDAT":
            idat += body
        elif kind == b"IEND":
            break
        i += 12 + length

    assert depth == 8 and interlace == 0, f"{path}: unsupported PNG"
    channels = {2: 3, 6: 4}[colour]
    stride = width * channels
    raw = zlib.decompress(idat)

    pixels = bytearray(width * height * 4)
    previous = bytearray(stride)
    position = 0
    for y in range(height):
        filter_type = raw[position]
        position += 1
        line = bytearray(raw[position:position + stride])
        position += stride
        if filter_type == 1:
            for x in range(channels, stride):
                line[x] = (line[x] + line[x - channels]) & 255
        elif filter_type == 2:
            for x in range(stride):
                line[x] = (line[x] + previous[x]) & 255
        elif filter_type == 3:
            for x in range(stride):
                left = line[x - channels] if x >= channels else 0
                line[x] = (line[x] + ((left + previous[x]) >> 1)) & 255
        elif filter_type == 4:
            for x in range(stride):
                a = line[x - channels] if x >= channels else 0
                b = previous[x]
                c = previous[x - channels] if x >= channels else 0
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                nearest = a if (pa <= pb and pa <= pc) else (b if pb <= pc else c)
                line[x] = (line[x] + nearest) & 255
        for x in range(width):
            source = x * channels
            target = (y * width + x) * 4
            pixels[target] = line[source]
            pixels[target + 1] = line[source + 1]
            pixels[target + 2] = line[source + 2]
            pixels[target + 3] = line[source + 3] if channels == 4 else 255
        previous = line
    return width, height, pixels


def alpha_bounds(width, height, pixels):
    min_x, min_y, max_x, max_y = width, height, -1, -1
    for y in range(height):
        for x in range(width):
            if pixels[(y * width + x) * 4 + 3] > 8:
                min_x = min(min_x, x)
                max_x = max(max_x, x)
                min_y = min(min_y, y)
                max_y = max(max_y, y)
    assert max_x >= 0, "the artwork is entirely transparent"
    return min_x, min_y, max_x, max_y


# --------------------------------------------------------------------------
# Compositing
# --------------------------------------------------------------------------

def resample(source, source_width, source_height, target_width, target_height):
    """Area average, on premultiplied alpha so edges do not pick up a halo."""
    result = bytearray(target_width * target_height * 4)
    for y in range(target_height):
        y0 = y * source_height / target_height
        y1 = (y + 1) * source_height / target_height
        for x in range(target_width):
            x0 = x * source_width / target_width
            x1 = (x + 1) * source_width / target_width
            r = g = b = a = weight = 0.0
            for sy in range(int(y0), min(int(math.ceil(y1)), source_height)):
                covery = min(y1, sy + 1) - max(y0, sy)
                if covery <= 0:
                    continue
                for sx in range(int(x0), min(int(math.ceil(x1)), source_width)):
                    coverx = min(x1, sx + 1) - max(x0, sx)
                    if coverx <= 0:
                        continue
                    w = covery * coverx
                    index = (sy * source_width + sx) * 4
                    alpha = source[index + 3] / 255.0
                    r += source[index] * alpha * w
                    g += source[index + 1] * alpha * w
                    b += source[index + 2] * alpha * w
                    a += source[index + 3] * w
                    weight += w
            target = (y * target_width + x) * 4
            if weight <= 0:
                continue
            alpha = a / weight
            if alpha > 0.5:
                scale = 255.0 / alpha
                result[target] = min(255, int(r / weight * scale + 0.5))
                result[target + 1] = min(255, int(g / weight * scale + 0.5))
                result[target + 2] = min(255, int(b / weight * scale + 0.5))
            result[target + 3] = min(255, int(alpha + 0.5))
    return result


def compose(mark, mark_width, mark_height, colour, struck, canvas=256):
    """The mark, tinted, filling the canvas, with an optional strike."""
    # 96% of the canvas: enough margin that the mark is not clipped by a tray
    # that rounds its own bounds, and no more.
    scale = canvas * 0.96 / max(mark_width, mark_height)
    width = max(1, int(round(mark_width * scale)))
    height = max(1, int(round(mark_height * scale)))
    scaled = resample(mark, mark_width, mark_height, width, height)

    out = bytearray(canvas * canvas * 4)
    offset_x = (canvas - width) // 2
    offset_y = (canvas - height) // 2
    for y in range(height):
        for x in range(width):
            alpha = scaled[(y * width + x) * 4 + 3]
            if alpha == 0:
                continue
            target = ((y + offset_y) * canvas + (x + offset_x)) * 4
            out[target] = colour[0]
            out[target + 1] = colour[1]
            out[target + 2] = colour[2]
            out[target + 3] = alpha

    if struck:
        # The gap comes first. A bar laid straight onto a solid mark merges into
        # it and reads as a thicker letter, not as a strike; clearing a little
        # space around the bar is what makes the two shapes separate.
        strike(out, canvas, radius=canvas * 0.070, colour=None)
        strike(out, canvas, radius=canvas * 0.034, colour=colour)
    return out


def strike(pixels, canvas, radius, colour):
    """A diagonal, drawn by distance so the reduction antialiases it."""
    inset = canvas * 0.11
    ax = ay = inset
    bx = by = canvas - inset
    dx, dy = bx - ax, by - ay
    length_squared = dx * dx + dy * dy
    for y in range(canvas):
        for x in range(canvas):
            t = ((x + 0.5 - ax) * dx + (y + 0.5 - ay) * dy) / length_squared
            t = max(0.0, min(1.0, t))
            distance = math.hypot(x + 0.5 - (ax + t * dx), y + 0.5 - (ay + t * dy))
            if distance > radius:
                continue
            index = (y * canvas + x) * 4
            if colour is None:
                pixels[index + 3] = 0
            else:
                pixels[index] = colour[0]
                pixels[index + 1] = colour[1]
                pixels[index + 2] = colour[2]
                pixels[index + 3] = 255


# --------------------------------------------------------------------------
# Writing
# --------------------------------------------------------------------------

def ico(images):
    """
    Packs 32-bit BGRA images as an .ico.

    BMP entries rather than PNG ones: System.Drawing reads these on every
    Windows version without argument, and a tray icon that silently fails to
    load is not a thing that can be noticed from a Mac.
    """
    header = struct.pack("<HHH", 0, 1, len(images))
    directory = b""
    body = b""
    offset = 6 + 16 * len(images)

    for size, pixels in images:
        dib = struct.pack("<IiiHHIIiiII", 40, size, size * 2, 1, 32, 0, size * size * 4,
                          0, 0, 0, 0)
        rows = []
        for y in range(size - 1, -1, -1):          # BMP rows run bottom to top
            row = bytearray()
            for x in range(size):
                index = (y * size + x) * 4
                row += bytes((pixels[index + 2], pixels[index + 1],
                              pixels[index], pixels[index + 3]))
            rows.append(bytes(row))
        xor = b"".join(rows)
        # The AND mask is unused for 32-bit icons but the format still wants it.
        mask_stride = ((size + 31) // 32) * 4
        and_mask = b"\x00" * (mask_stride * size)

        image = dib + xor + and_mask
        directory += struct.pack("<BBBBHHII",
                                 0 if size == 256 else size,
                                 0 if size == 256 else size,
                                 0, 0, 1, 32, len(image), offset)
        body += image
        offset += len(image)
    return header + directory + body


def png(width, height, pixels):
    def chunk(kind, payload):
        return (struct.pack(">I", len(payload)) + kind + payload
                + struct.pack(">I", zlib.crc32(kind + payload) & 0xFFFFFFFF))

    raw = b"".join(b"\x00" + bytes(pixels[y * width * 4:(y + 1) * width * 4])
                   for y in range(height))
    return (b"\x89PNG\r\n\x1a\n"
            + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(raw, 9))
            + chunk(b"IEND", b""))


def main():
    os.makedirs(OUT, exist_ok=True)

    width, height, pixels = decode_png(os.path.join(ROOT, "Assets", "menu-icon.png"))
    min_x, min_y, max_x, max_y = alpha_bounds(width, height, pixels)
    mark_width = max_x - min_x + 1
    mark_height = max_y - min_y + 1
    print(f"mark trimmed from {width}x{height} to {mark_width}x{mark_height} "
          f"({(mark_width * mark_height) / (width * height):.0%} of the canvas was ink)")

    mark = bytearray(mark_width * mark_height * 4)
    for y in range(mark_height):
        source = ((y + min_y) * width + min_x) * 4
        mark[y * mark_width * 4:(y + 1) * mark_width * 4] = \
            pixels[source:source + mark_width * 4]

    for name, colour, struck in [("tray-active", ORANGE, False),
                                 ("tray-inactive", GREY, True)]:
        master = compose(mark, mark_width, mark_height, colour, struck)
        images = [(size, master if size == 256 else resample(master, 256, 256, size, size))
                  for size in SIZES]
        path = os.path.join(OUT, name + ".ico")
        with open(path, "wb") as handle:
            handle.write(ico(images))
        print(f"  {name}.ico  {len(SIZES)} sizes, {os.path.getsize(path) / 1024:.0f} KB")

        # A preview, so the icon can be looked at without a Windows machine.
        os.makedirs(os.path.join(OUT, "preview"), exist_ok=True)
        preview = os.path.join(OUT, "preview", name + ".png")
        with open(preview, "wb") as handle:
            handle.write(png(256, 256, master))

    # The exe's own icon, which already has its background in the artwork.
    width, height, pixels = decode_png(os.path.join(ROOT, "Assets", "app-icon.png"))
    images = [(size, resample(pixels, width, height, size, size)) for size in SIZES]
    path = os.path.join(OUT, "app.ico")
    with open(path, "wb") as handle:
        handle.write(ico(images))
    print(f"  app.ico  {len(SIZES)} sizes, {os.path.getsize(path) / 1024:.0f} KB")


if __name__ == "__main__":
    main()
