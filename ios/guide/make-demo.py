"""Turns the simulator recording into the demo video: the phone in a
1080 by 1920 frame in LaTeX Squiggly's colours, each scene's caption above
it, and title cards at both ends.

    python3 guide/make-demo.py <folder from make-demo.sh> <output.mp4>
"""
import subprocess
import sys
from pathlib import Path

import imageio_ffmpeg
from PIL import Image, ImageDraw, ImageFont

WORK = Path(sys.argv[1]).resolve()
OUT = Path(sys.argv[2]).resolve()
REPO = Path(__file__).resolve().parents[2]
FFMPEG = imageio_ffmpeg.get_ffmpeg_exe()

W, H = 1080, 1920
PAPER, INK, SOFT, SQUIGGLE = (250, 247, 238), (34, 26, 18), (92, 81, 71), (226, 102, 15)
PHONE_H = 1440
PHONE_W = round(PHONE_H * 1170 / 2532)
PHONE_X, PHONE_Y = (W - PHONE_W) // 2, 420
FPS = 30


def font(size, weight="Semibold"):
    f = ImageFont.truetype("/System/Library/Fonts/SFCompactRounded.ttf", size)
    try:
        f.set_variation_by_name(weight)
    except (OSError, ValueError):
        pass
    return f


def wordmark(height):
    im = Image.open(REPO / "site/assets/wordmark.png").convert("LA")
    mark = Image.new("RGBA", im.size, SQUIGGLE + (0,))
    mark.putalpha(im.getchannel("A"))
    return mark.resize((round(im.width * height / im.height), height), Image.LANCZOS)


def mascot(pose, height):
    im = Image.open(REPO / f"assets/mascot/{pose}.png").convert("RGBA")
    return im.resize((round(im.width * height / im.height), height), Image.LANCZOS)


def centred_text(draw, text, y, size, fill, width=W - 140, weight="Semibold"):
    """Wrapped to `width`, each line centred. Returns the y below it."""
    f = font(size, weight)
    words, lines, line = text.split(), [], ""
    for word in words:
        trial = (line + " " + word).strip()
        if draw.textlength(trial, font=f) > width and line:
            lines.append(line)
            line = word
        else:
            line = trial
    lines.append(line)
    for line in lines:
        draw.text(((W - draw.textlength(line, font=f)) / 2, y), line, font=f, fill=fill)
        y += round(size * 1.25)
    return y


# The frame behind the phone, the mask that rounds its corners, captions.
background = Image.new("RGB", (W, H), PAPER)
mark = wordmark(76)
background.paste(mark, ((W - mark.width) // 2, 56), mark)
background.save(WORK / "background.png")

mask = Image.new("RGBA", (W, H), PAPER + (255,))
hole = Image.new("L", (W, H), 255)
ImageDraw.Draw(hole).rounded_rectangle((PHONE_X, PHONE_Y, PHONE_X + PHONE_W, PHONE_Y + PHONE_H),
                                       radius=64, fill=0)
mask.putalpha(hole)
ImageDraw.Draw(mask).rounded_rectangle((PHONE_X - 3, PHONE_Y - 3, PHONE_X + PHONE_W + 3, PHONE_Y + PHONE_H + 3),
                                       radius=66, outline=(207, 196, 173), width=3)
mask.save(WORK / "mask.png")

start = float((WORK / "start.txt").read_text())
scenes = []
for line in (WORK / "scenes.txt").read_text().splitlines():
    _, time, caption = line.split(" ", 2)
    scenes.append((float(time) - start, caption))
lead_in = max(scenes[0][0] - 0.8, 0)
end = scenes[-1][0] + 0.3

captions = []
for i, (time, caption) in enumerate(scenes[:-1]):
    image = Image.new("RGBA", (W, 260), (0, 0, 0, 0))
    centred_text(ImageDraw.Draw(image), caption, 20, 58, INK)
    path = WORK / f"caption-{i}.png"
    image.save(path)
    captions.append((path, time - lead_in, scenes[i + 1][0] - lead_in))

# Title cards.
intro = Image.new("RGB", (W, H), PAPER)
big = wordmark(330)
intro.paste(big, ((W - big.width) // 2, 360), big)
d = ImageDraw.Draw(intro)
y = centred_text(d, "on iPhone", 760, 76, INK)
centred_text(d, "Write maths anywhere. Type \\alpha, get α. Copy any equation as a picture.",
             y + 30, 46, SOFT, weight="Regular")
hello = mascot("hello", 560)
intro.paste(hello, ((W - hello.width) // 2, 1200), hello)
intro.save(WORK / "intro.png")

outro = Image.new("RGB", (W, H), PAPER)
cheer = mascot("celebrate", 620)
outro.paste(cheer, ((W - cheer.width) // 2, 330), cheer)
d = ImageDraw.Draw(outro)
small = wordmark(150)
outro.paste(small, ((W - small.width) // 2, 1040), small)
y = centred_text(d, "Free and open source", 1250, 64, INK)
centred_text(d, "github.com/SuperWalrus01/LaTeX-Squiggly", y + 20, 42, SQUIGGLE, weight="Regular")
outro.save(WORK / "outro.png")


def run(*args):
    subprocess.run([FFMPEG, "-y", "-loglevel", "error", *args], check=True)


encode = ["-c:v", "libx264", "-pix_fmt", "yuv420p", "-r", str(FPS), "-crf", "18", "-preset", "medium"]

# The demo itself: background, phone, rounded corners, then each caption.
inputs = ["-loop", "1", "-i", str(WORK / "background.png"),
          "-ss", f"{lead_in:.2f}", "-to", f"{end:.2f}", "-i", str(WORK / "raw.mp4"),
          "-loop", "1", "-i", str(WORK / "mask.png")]
graph = [f"[1:v]setpts=PTS-STARTPTS,fps={FPS},scale={PHONE_W}:{PHONE_H}[phone]",
         f"[0:v][phone]overlay={PHONE_X}:{PHONE_Y}:shortest=1[v0]",
         "[v0][2:v]overlay=0:0[v1]"]
for i, (path, a, b) in enumerate(captions):
    inputs += ["-loop", "1", "-i", str(path)]
    graph.append(f"[v{i + 1}][{i + 3}:v]overlay=0:230:enable='between(t,{a:.2f},{b:.2f})'[v{i + 2}]")
# The still images loop for ever, so the length is given outright.
run(*inputs, "-filter_complex", ";".join(graph), "-map", f"[v{len(captions) + 1}]",
    "-t", f"{end - lead_in:.2f}", *encode, str(WORK / "main.mp4"))

for card in ["intro", "outro"]:
    run("-loop", "1", "-t", "3", "-i", str(WORK / f"{card}.png"),
        "-vf", "fade=in:0:12,fade=out:st=2.6:d=0.4", *encode, str(WORK / f"{card}.mp4"))

(WORK / "parts.txt").write_text("".join(f"file '{WORK / p}.mp4'\n" for p in ["intro", "main", "outro"]))
run("-f", "concat", "-safe", "0", "-i", str(WORK / "parts.txt"), "-c", "copy",
    "-movflags", "+faststart", str(OUT))
print("wrote", OUT)
