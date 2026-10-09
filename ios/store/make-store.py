"""Builds the App Store screenshots from the screens that
scripts/make-store-shots.sh takes: an orange banner across the top with the
headline, and the screen in an iPhone that overlaps it. The first is the
hero, with the wordmark and the mascot, since the App Store has no banner of
its own: the first screenshots are what a product page opens on.

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
REPO = Path(__file__).resolve().parents[2]
WORDMARK = REPO / "chrome" / "store" / "image-kit" / "wordmark-transparent.png"
MASCOT = REPO / "assets" / "mascot" / "laptop.png"
CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
WIDTH, HEIGHT = 1320, 2868

# Output name, raw screen, headline (with *emphasis* in ink), subline, hero.
SHOTS = [
    ("iphone-1-type", "convert", "Type \\alpha, get *α*",
     "A full keyboard that turns LaTeX into real symbols, in any app.", True),
    ("iphone-2-see", "dollar", "See your maths *as you type*",
     "Write it between $ signs and the bar above the keys renders it.", False),
    ("iphone-3-copy", "copy", "Paste it *as an image*",
     "Copy the equation and paste it into a chat, an email or a document.", False),
    ("iphone-4-symbols", "symbols", "Every symbol, *one key away*",
     "Greek letters and maths symbols on the ∑ key. Hold any key for more.", False),
    ("iphone-5-share", "share", "Render LaTeX *from any app*",
     "Select it, tap Share, then LaTeX Squiggly.", False),
    ("iphone-6-messages", "messages-editor", "Send equations *in Messages*",
     "Write it, see it, and add it to your message.", False),
    ("iphone-7-private", "setup", "Private *by design*",
     "Nothing you type leaves your phone. No account, no ads, no tracking.", False),
    ("imessage-1-write", "messages-editor", "Write maths, *send an image*",
     "See it rendered as you type, then add it to the conversation.", False),
]

PAGE = """<!doctype html>
<meta charset="utf-8">
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Bricolage+Grotesque:opsz,wght@12..96,800&family=IBM+Plex+Mono:wght@500&family=Instrument+Sans:wght@500;600&display=block">
<style>
  html, body {{ margin: 0; width: {w}px; height: {h}px; overflow: hidden; }}
  body {{
    position: relative;
    background: #FAF7EE radial-gradient(circle, #E4DCCB 2.4px, transparent 2.6px) 0 0 / 44px 44px;
    font-family: 'Instrument Sans', sans-serif;
  }}

  /* The banner: squiggle orange, lit from the top left, with a wavy foot. */
  .banner {{
    position: absolute; left: 0; top: 0; width: {w}px; height: 900px;
    background: radial-gradient(130% 80% at 15% 0%, #F7943F 0%, #E2660F 60%);
  }}
  .banner svg {{ position: absolute; left: 0; bottom: -59px; width: {w}px; height: 60px; }}
  .text {{
    position: relative; z-index: 2;
    display: flex; flex-direction: column; align-items: center;
    padding: 150px 80px 0; text-align: center;
  }}
  .hero {{ display: flex; align-items: center; gap: 40px; margin-bottom: 46px; }}
  .wordmark {{
    width: 440px; height: 279px; background: #FFF8EE;
    -webkit-mask: url("{wordmark}") center / contain no-repeat;
  }}
  /* A cream outline, like a sticker, so the orange mascot shows on orange. */
  .mascot {{
    height: 270px;
    filter: drop-shadow(5px 0 0 #FFF8EE) drop-shadow(-5px 0 0 #FFF8EE)
            drop-shadow(0 5px 0 #FFF8EE) drop-shadow(0 -5px 0 #FFF8EE)
            drop-shadow(0 18px 24px rgba(80, 30, 0, 0.25));
  }}
  h1 {{
    margin: 0; color: #FFF8EE;
    font-family: 'Bricolage Grotesque', sans-serif; font-weight: 800;
    font-size: 116px; line-height: 1.04; letter-spacing: -2px;
    text-wrap: balance;
  }}
  h1 em {{ font-style: normal; color: #2B1407; }}
  h1 code {{
    font-family: 'IBM Plex Mono', monospace; font-weight: 500; font-size: 0.82em;
    letter-spacing: -4px; background: rgba(255, 248, 238, 0.18);
    border-radius: 22px; padding: 0 18px;
  }}
  p {{
    margin: 40px 0 0; color: rgba(255, 248, 238, 0.92);
    font-size: 50px; line-height: 1.3; font-weight: 500; text-wrap: balance;
  }}

  /* An iPhone: the screen, a black bezel, a metal band, and its buttons. */
  .phone {{
    position: absolute; left: 50%; transform: translateX(-50%); z-index: 1;
    padding: 18px; box-sizing: border-box; border-radius: 156px; background: #0D0D0F;
    box-shadow: 0 0 0 6px #73777E, 0 0 0 9px #2E3035,
                0 70px 140px rgba(34, 26, 18, 0.32), 0 24px 48px rgba(34, 26, 18, 0.18);
  }}
  .phone img {{ display: block; width: 100%; height: 100%; border-radius: 138px; }}
  .button {{ position: absolute; width: 10px; border-radius: 5px; background: #5F636A; }}
  .left {{ left: -18px; }}
  .right {{ right: -18px; }}
</style>
<div class="banner">
  <svg viewBox="0 0 1320 60" preserveAspectRatio="none"><path fill="#E2660F" d="{wave}"/></svg>
</div>
<div class="text">
  {hero}
  <h1>{title}</h1>
  <p>{subtitle}</p>
</div>
<div class="phone">
  <img src="{screen}">
  <div class="button left" style="top: 15%; height: 4.5%"></div>
  <div class="button left" style="top: 22%; height: 8%"></div>
  <div class="button left" style="top: 32%; height: 8%"></div>
  <div class="button right" style="top: 26%; height: 12%"></div>
</div>
<script>
  // The phone goes as far below the headline as there is room for, as big
  // as fits, and the banner reaches a quarter of the way down it.
  document.fonts.ready.then(() => {{
    const top = document.querySelector('.text').getBoundingClientRect().bottom + 70;
    const height = {h} - 80 - top;
    const phone = document.querySelector('.phone');
    phone.style.top = top + 'px';
    phone.style.height = height + 'px';
    phone.style.width = ((height - 36) * {aspect} + 36) + 'px';
    document.querySelector('.banner').style.height = (top + height * 0.22) + 'px';
  }});
</script>
"""


def wave():
    """A squiggle along the banner's foot: a row of smooth bumps."""
    path, x, step = "M0,0 L0,24", 0, 110
    while x < WIDTH:
        path += f" Q{x + step / 4},50 {x + step / 2},24 T{x + step},24"
        x += step
    return path + f" L{WIDTH},0 Z"


def headline(text):
    """`*word*` in ink and `\\command` in monospace, everything escaped."""
    parts = html.escape(text).split("*")
    out = "".join(f"<em>{part}</em>" if i % 2 else part for i, part in enumerate(parts))
    return out.replace("\\alpha", "<code>\\alpha</code>")


def build(name, screen, title, subtitle, hero):
    art = ""
    if hero:
        art = (f'<div class="hero"><div class="wordmark"></div>'
               f'<img class="mascot" src="{MASCOT.as_uri()}"></div>')
    page = WORK / f"{name}.html"
    page.write_text(PAGE.format(w=WIDTH, h=HEIGHT, aspect=1320 / 2868, wave=wave(),
                                wordmark=WORDMARK.as_uri(), hero=art, title=headline(title),
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
