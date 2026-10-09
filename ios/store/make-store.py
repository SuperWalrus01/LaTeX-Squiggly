"""Builds the App Store screenshots from the screens that
scripts/make-store-shots.sh takes: each screen in a phone frame on paper,
under a headline.

    python3 store/make-store.py <raw screens folder> <output folder>

The pages are HTML, screenshotted by Chrome, so the type is the website's.
Every image is 1320 by 2868, the 6.9-inch iPhone size, as an RGB PNG with no
alpha channel, which App Store Connect requires.
"""
import html
import subprocess
import sys
from pathlib import Path

from PIL import Image

RAW = Path(sys.argv[1]).resolve()
OUT = Path(sys.argv[2]).resolve()
WORK = RAW.parent / "pages"
CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
WIDTH, HEIGHT = 1320, 2868

# Output name, raw screen, headline (with *emphasis* in orange), subline.
SHOTS = [
    ("iphone-1-type", "convert", "Type \\alpha, get *α*",
     "A full keyboard that turns LaTeX into real symbols, in any app."),
    ("iphone-2-see", "dollar", "See your maths *as you type*",
     "Write it between $ signs and the bar above the keys renders it."),
    ("iphone-3-copy", "copy", "Paste it *as an image*",
     "Copy the equation and paste it into a chat, an email or a document."),
    ("iphone-4-symbols", "symbols", "Every symbol, *one key away*",
     "Greek letters and maths symbols on the ∑ key. Hold any key for more."),
    ("iphone-5-share", "share", "Render LaTeX *from any app*",
     "Select it, tap Share, then LaTeX Squiggly."),
    ("iphone-6-messages", "messages-editor", "Send equations *in Messages*",
     "Write it, see it, and add it to your message."),
    ("iphone-7-private", "setup", "Private *by design*",
     "Nothing you type leaves your phone. No account, no ads, no tracking."),
    ("imessage-1-write", "messages-editor", "Write maths, *send an image*",
     "See it rendered as you type, then add it to the conversation."),
]

PAGE = """<!doctype html>
<meta charset="utf-8">
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Bricolage+Grotesque:opsz,wght@12..96,800&family=IBM+Plex+Mono:wght@500&family=Instrument+Sans:wght@500&display=block">
<style>
  html, body {{ margin: 0; width: {w}px; height: {h}px; overflow: hidden; }}
  body {{
    background: #FAF7EE radial-gradient(circle, #E4DCCB 2.4px, transparent 2.6px) 0 0 / 44px 44px;
    font-family: 'Instrument Sans', sans-serif; color: #221A12;
    display: flex; flex-direction: column; align-items: center;
  }}
  h1 {{
    font-family: 'Bricolage Grotesque', sans-serif; font-weight: 800;
    font-size: 116px; line-height: 1.04; letter-spacing: -2px;
    margin: 170px 70px 0; text-align: center; text-wrap: balance;
  }}
  h1 em {{ font-style: normal; color: #E2660F; }}
  h1 code {{ font-family: 'IBM Plex Mono', monospace; font-weight: 500; font-size: 0.86em; letter-spacing: -4px; }}
  p {{ font-size: 50px; line-height: 1.3; color: #5C5147; margin: 44px 110px 0; text-align: center; text-wrap: balance; }}
  .stage {{ position: relative; flex: 1; width: 100%; display: flex; justify-content: center; align-items: flex-end; padding-bottom: 110px; }}
  .phone {{
    border: 22px solid #221A12; border-radius: 132px; overflow: hidden; background: #fff;
    box-shadow: 0 50px 110px rgba(34, 26, 18, 0.22), 0 0 0 4px #3A2E22;
    height: {phone}px;
  }}
  .phone img {{ display: block; height: 100%; }}
</style>
<h1>{title}</h1>
<p>{subtitle}</p>
<div class="stage"><div class="phone"><img src="{screen}"></div></div>
"""


def headline(text):
    """`*word*` in orange and `\\command` in monospace, everything escaped."""
    parts = html.escape(text).split("*")
    out = "".join(f"<em>{part}</em>" if i % 2 else part for i, part in enumerate(parts))
    return out.replace("\\alpha", "<code>\\alpha</code>")


def build(name, screen, title, subtitle):
    page = WORK / f"{name}.html"
    page.write_text(PAGE.format(w=WIDTH, h=HEIGHT, phone=2040, title=headline(title),
                                subtitle=html.escape(subtitle), screen=(RAW / f"{screen}.png").as_uri()))
    shot = WORK / f"{name}.png"
    subprocess.run([CHROME, "--headless=new", "--disable-gpu", "--hide-scrollbars",
                    "--allow-file-access-from-files", "--force-device-scale-factor=1",
                    f"--window-size={WIDTH},{HEIGHT}", "--virtual-time-budget=10000",
                    f"--screenshot={shot}", page.as_uri()],
                   check=True, capture_output=True)
    image = Image.open(shot).convert("RGB")
    assert image.size == (WIDTH, HEIGHT), f"{name} is {image.size}"
    image.save(OUT / f"{name}.png", optimize=True)
    print(name)


if __name__ == "__main__":
    WORK.mkdir(parents=True, exist_ok=True)
    OUT.mkdir(parents=True, exist_ok=True)
    for shot in SHOTS:
        build(*shot)
