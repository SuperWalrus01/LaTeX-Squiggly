"""Builds the iPhone user guide, a PDF, from the screenshots that
scripts/make-guide.sh takes.

    python3 guide/make-guide.py <shots folder> <output.pdf>

The pages are HTML, printed to PDF by Chrome, so the layout is CSS and the
maths symbols come out in real fonts.
"""
import html
import os
import subprocess
import sys
from pathlib import Path

from PIL import Image, ImageDraw

SHOTS = Path(sys.argv[1]).resolve()
OUT = Path(sys.argv[2]).resolve()
WORK = SHOTS.parent / "pages"
REPO = Path(__file__).resolve().parents[2]
WORK.mkdir(exist_ok=True)

CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
SQUIGGLE = (226, 102, 15)

# Screenshots are 1170 by 2532 pixels: an iPhone at 3x, 390 by 844 points.
SCALE = 3


def pts(y):
    return int(y * SCALE)


def keyboard_shot(name, top_lines=2):
    """The text being typed and the keyboard, without the empty screen
    between them: the top of the screen, a torn edge, the keyboard."""
    im = Image.open(SHOTS / f"{name}.png").convert("RGB")
    top = im.crop((0, 0, im.width, pts(44 + 26 * top_lines)))
    bottom = im.crop((0, pts(548), im.width, im.height))
    gap = pts(10)
    out = Image.new("RGB", (im.width, top.height + gap + bottom.height), (255, 255, 255))
    out.paste(top, (0, 0))
    out.paste(bottom, (0, top.height + gap))
    # A dotted line where the screen was cut.
    draw = ImageDraw.Draw(out)
    y = top.height + gap // 2
    for x in range(0, im.width, pts(8)):
        draw.line((x, y, x + pts(4), y), fill=(200, 196, 188), width=4)
    path = WORK / f"{name}.png"
    out.save(path)
    return path


def bottom_shot(name, from_y):
    im = Image.open(SHOTS / f"{name}.png").convert("RGB")
    path = WORK / f"{name}.png"
    im.crop((0, pts(from_y), im.width, im.height)).save(path)
    return path


def full_shot(name, to_y=844):
    im = Image.open(SHOTS / f"{name}.png").convert("RGB")
    path = WORK / f"{name}.png"
    im.crop((0, 0, im.width, pts(to_y))).save(path)
    return path


def wordmark():
    """The site's wordmark, ink only, coloured squiggle orange."""
    im = Image.open(REPO / "site/assets/wordmark.png").convert("LA")
    alpha = im.getchannel("A")
    out = Image.new("RGBA", im.size, SQUIGGLE + (0,))
    out.putalpha(alpha)
    path = WORK / "wordmark.png"
    out.save(path)
    return path


def mascot(pose):
    return REPO / f"assets/mascot/{pose}.png"


def shot(path, caption, width="100%"):
    return (f'<figure style="width:{width}"><img class="phone" src="{path.as_uri()}">'
            f"<figcaption>{caption}</figcaption></figure>")


def page(body, number=None, cls=""):
    folio = f'<div class="folio">{number}</div>' if number else ""
    return f'<section class="page {cls}">{body}{folio}</section>'


def code(text):
    return f"<code>{html.escape(text)}</code>"


# MARK: - The pages

# LaTeX shown in the pages, kept out of the f-strings, which cannot hold
# backslashes before Python 3.12.
C0 = code(r'\alpha')
C1 = code(r'\infty')
C2 = code(r'\to')
C3 = code(r'\leq')
C4 = code(r'\sum')
C5 = code(r'\mathbb{R}')
C6 = code(r'\frac{1}{2}')
C7 = code(r'\pm')
C8 = code(r'$x = \frac{-b \pm \sqrt{b^2-4ac}}{2a}$')


pages = []
n = 1

pages.append(page(f"""
<div class="cover">
  <img class="wordmark" src="{wordmark().as_uri()}">
  <h1>The iPhone guide</h1>
  <p class="lede">A keyboard for writing maths anywhere. Type {C0} and get α.
  Write an equation and copy it as a picture.</p>
  <img class="cover-mascot" src="{mascot('hello').as_uri()}">
  <div class="contents">
    <h3>Inside</h3>
    <ol>
      <li><span>Set up the keyboard</span><b>2</b></li>
      <li><span>Switch to it</span><b>3</b></li>
      <li><span>Type symbols: LaTeX to Unicode</span><b>4</b></li>
      <li><span>The ∑ page and held keys</span><b>5</b></li>
      <li><span>Equations as images</span><b>6</b></li>
      <li><span>The big preview</span><b>7</b></li>
      <li><span>LaTeX mode</span><b>8</b></li>
      <li><span>The bar above the keys</span><b>9</b></li>
      <li><span>Render from the share sheet</span><b>10</b></li>
      <li><span>Send equations in Messages</span><b>11</b></li>
      <li><span>The app, tips and help</span><b>12</b></li>
    </ol>
  </div>
</div>
""", cls="cover-page"))

n += 1
pages.append(page(f"""
<h2><span class="num">1</span>Set up the keyboard</h2>
<p>iPhone keyboards are turned on in Settings. You do this once.</p>
<div class="row">
  {shot(full_shot('settings-keyboards', 660), '<b>1.</b> Open <b>Settings</b>, then <b>General</b>, <b>Keyboard</b>, <b>Keyboards</b>. Tap <b>Add New Keyboard</b>.')}
  {shot(full_shot('settings-add', 660), '<b>2.</b> Under Third-Party Keyboards, choose <b>LaTeX Squiggly</b>.')}
  {shot(full_shot('settings-added', 660), '<b>3.</b> Tap <b>LaTeX Squiggly</b> and turn on <b>Allow Full Access</b>.')}
</div>
<div class="note">
  <img src="{mascot('backpack').as_uri()}">
  <p><b>Why Full Access?</b> Only to put equation images on the clipboard, so you can paste
  them. Everything else works without it. Nothing you type leaves your phone: the keyboard
  makes no network connections and stores nothing you write.</p>
</div>
""", n))

n += 1
pages.append(page(f"""
<h2><span class="num">2</span>Switch to it</h2>
<p>In any app, <b>touch and hold the globe</b> <span class="key">🌐</span> below the keys,
then slide to <b>LaTeX Squiggly</b>. A quick tap on the globe moves to the next keyboard.</p>
<div class="row">
  {shot(bottom_shot('globe', 400), 'Hold the globe to pick a keyboard.', '46%')}
  {shot(full_shot('app-try', 520), 'Practise in the app’s <b>Try it</b> tab. The mascot cheers your first symbol.', '46%')}
</div>
<p class="tip">It types like Apple’s keyboard: letters pop up as you press them, a touch
between two keys goes to the one you most likely meant, and you can slide your finger to
the right key before letting go. Hold <span class="key">space</span> and slide to move the
cursor. Hold <span class="key">delete</span> and it speeds up to whole words.</p>
""", n))

n += 1
pages.append(page(f"""
<h2><span class="num">3</span>Type symbols: LaTeX to Unicode</h2>
<p>Type a LaTeX command, then <b>space</b>. It turns into the real symbol, which anyone can
read: in a message, an email, a document.</p>
<div class="row">
  {shot(keyboard_shot('kb-before'), 'Type ' + C0 + '…', '46%')}
  {shot(keyboard_shot('kb-after'), '…press space, and it is α.', '46%')}
</div>
<table class="examples">
  <tr><th>You type</th><th>You get</th><th>You type</th><th>You get</th></tr>
  <tr><td>{C0}</td><td>α</td><td>{C1}</td><td>∞</td></tr>
  <tr><td>{C2}</td><td>→</td><td>{C3}</td><td>≤</td></tr>
  <tr><td>{C4}</td><td>∑</td><td>{C5}</td><td>ℝ</td></tr>
  <tr><td>{C6}</td><td>½</td><td>{C7}</td><td>±</td></tr>
</table>
<p class="tip"><b>Changed your mind?</b> Press <span class="key">delete</span> straight after
a symbol appears and your LaTeX comes back.</p>
""", n))

n += 1
pages.append(page(f"""
<h2><span class="num">4</span>The ∑ page and held keys</h2>
<p>Tap <span class="key">∑</span> for Greek letters and maths symbols, one tap each.
<span class="key">ABC</span> goes back to the letters.</p>
<div class="row">
  {shot(keyboard_shot('kb-math-page', 0), 'The ∑ page.', '46%')}
  {shot(keyboard_shot('accents', 2), 'Hold a key for more: accents on letters.', '46%')}
</div>
<p><b>Hold a key</b> to see related characters, then slide to one and let go. Letters
offer accents (é, ñ, ü). Maths keys offer their relatives:</p>
<table class="examples">
  <tr><th>Hold</th><th>For</th><th>Hold</th><th>For</th></tr>
  <tr><td>=</td><td>≠ ≈ ≡ ≅</td><td>ε</td><td>ϵ</td></tr>
  <tr><td>≤</td><td>≪ ⊆ ≺</td><td>θ</td><td>ϑ Θ</td></tr>
  <tr><td>→</td><td>← ↔ ⇒ ⇔ ↦</td><td>∫</td><td>∬ ∮ ∑ ∏</td></tr>
</table>
""", n))

n += 1
pages.append(page(f"""
<h2><span class="num">5</span>Equations as images</h2>
<p>Some maths can’t be written as plain text: fractions stacked on top of each other,
square roots over long expressions, matrices. For these, make a picture.</p>
<ol class="steps">
  <li>Write your equation <b>between $ signs</b>, like
      {C8}. Inside the $ signs nothing turns
      into symbols, so you can take your time.</li>
  <li>The bar above the keys shows it drawn properly. Tap <b>Copy</b>.</li>
  <li>Touch and hold where you want it, then tap <b>Paste</b>.</li>
</ol>
<div class="row">
  {shot(keyboard_shot('kb-dollar', 3), 'The bar shows your equation. Tap <b>Copy</b>.', '46%')}
  {shot(keyboard_shot('copied', 3), 'Copied. Now paste it into your message.', '46%')}
</div>
<p class="tip">Tap <b>$…$</b> in the bar to get both $ signs with the cursor between them.</p>
""", n))

n += 1
pages.append(page(f"""
<h2><span class="num">6</span>The big preview</h2>
<p><b>Tap the equation in the bar</b> to see it full size, in place of the keys.</p>
<div class="row">
  {shot(keyboard_shot('kb-preview', 3), 'The preview, with its options.', '52%')}
  <div class="aside">
    <p><b>S, M, L</b> choose how big the picture is.</p>
    <p>The <b>sun</b> and <b>moon</b> buttons choose a white or a dark background, to suit a
    light or dark chat.</p>
    <p><b>Copy</b> copies it, just like the bar’s Copy.</p>
    <p><b>Keys</b> brings the keyboard back.</p>
    <p class="small">Your size and background are remembered for next time.</p>
    <img src="{mascot('idea').as_uri()}">
  </div>
</div>
""", n))

n += 1
pages.append(page(f"""
<h2><span class="num">7</span>LaTeX mode</h2>
<p>Writing a LaTeX document, or a long equation? Turn on <b>LaTeX mode</b> and nothing
turns into symbols at all: {C0} stays {C0}.</p>
<div class="row">
  {shot(keyboard_shot('kb-latex-mode', 0), 'Tap <b>LaTeX</b> in the bar. It turns orange, and the space bar says LaTeX.', '46%')}
  {shot(keyboard_shot('kb-latex-long'), 'Your LaTeX stays as typed, and the bar still draws it for you to copy.', '46%')}
</div>
<p>Tap <b>LaTeX</b> again to go back to symbols. The keyboard remembers which you chose.
In LaTeX mode, the keys on the ∑ page type commands like {C0} instead of α.</p>
""", n))

n += 1
pages.append(page(f"""
<h2><span class="num">8</span>The bar above the keys</h2>
<p>The bar changes with what you are doing.</p>
<div class="grid">
  {shot(bottom_shot('kb-quick', 548), '<b>Shortcuts.</b> LaTeX mode, then $…$, braces, x², x₂ and a fraction. Templates leave the cursor inside; press space to jump to the next box.')}
  {shot(bottom_shot('kb-suggest', 548), '<b>Command suggestions.</b> Start a command and tap the one you mean.')}
  {shot(bottom_shot('kb-words', 548), '<b>Spelling.</b> Your word, then suggestions. Tap one to use it; nothing is changed on its own. Never inside maths.')}
  {shot(keyboard_shot('kb-selection', 3), '<b>Select and copy.</b> Select any text with maths in it and tap Copy for a picture of exactly that, words included.')}
</div>
""", n))

n += 1
pages.append(page(f"""
<h2><span class="num">9</span>Render from the share sheet</h2>
<p>Got LaTeX somewhere already, in Notes, a web page or a message? Turn it into a picture
without retyping it.</p>
<ol class="steps">
  <li>Select the text.</li>
  <li>Tap <b>Share</b>, then <b>LaTeX Squiggly</b>. (The first time, scroll the row of apps
      to the end, tap <b>More</b>, then <b>Edit</b>, and add it.)</li>
  <li>It is drawn straight away. Change the size or background, fix the LaTeX if you like,
      then <b>Copy</b> or <b>Share</b>.</li>
</ol>
<div class="row">
  {shot(full_shot('share', 520), 'Words stay words; the maths between $ signs is typeset.', '52%')}
  <div class="aside">
    <p>Plain LaTeX, with no $ signs, becomes one equation.</p>
    <p>Text with {code('$…$')} in it keeps its words, with each piece of maths drawn in its
    line. {code('$$…$$')} goes on a line of its own, in the middle.</p>
    <img src="{mascot('reading').as_uri()}">
  </div>
</div>
""", n))

n += 1
pages.append(page(f"""
<h2><span class="num">10</span>Send equations in Messages</h2>
<p>In Messages, the picture goes straight into your message: no copy and paste.</p>
<ol class="steps">
  <li>In a conversation, tap <b>+</b>, then <b>More</b>, then <b>LaTeX Squiggly</b>.</li>
  <li>Tap <b>New</b> and write your LaTeX. It is drawn as you type.</li>
  <li>Tap <b>Add to message</b>, then send.</li>
</ol>
<div class="row">
  {shot(full_shot('messages-editor', 520), 'Write, see it drawn, add it to your message.', '46%')}
  {shot(bottom_shot('messages-drawer', 560), 'Equations you sent before wait in the drawer. Tap one to send it again.', '46%')}
</div>
""", n))

n += 1
pages.append(page(f"""
<h2><span class="num">11</span>The app, tips and help</h2>
<div class="row">
  {shot(full_shot('app-render', 560), 'The app’s <b>Render</b> tab, for longer pieces.', '40%')}
  <div class="aside wide">
    <h3>Good to know</h3>
    <ul>
      <li><b>Nothing appears in the bar?</b> Check your maths is between $ signs, or that
      LaTeX mode is on.</li>
      <li><b>The bar says “Can’t render this”?</b> It names the command it doesn’t know.
      Check the spelling, or try another way to write it.</li>
      <li><b>Copy asks for Full Access?</b> Turn on Allow Full Access for LaTeX Squiggly in
      Settings (page 2).</li>
      <li><b>The keyboard is missing in a password box?</b> iPhone always uses its own
      keyboard there, for safety.</li>
      <li><b>No automatic capitals.</b> LaTeX cares about capitals, so shift only comes on
      when you tap it. Double-tap for caps lock.</li>
      <li><b>Double space</b> after a word types a full stop.</li>
    </ul>
  </div>
</div>
<div class="closing">
  <img src="{mascot('celebrate').as_uri()}">
  <p>Happy writing. LaTeX Squiggly is free and open source:
  <b>github.com/SuperWalrus01/LaTeX-Squiggly</b></p>
</div>
""", n))

ROUNDED = Path("/System/Library/Fonts/SFCompactRounded.ttf").as_uri()
CSS = f"""
@font-face {{ font-family: Rounded; src: url('{ROUNDED}'); }}
@page {{ size: A4; margin: 0; }}
:root {{ --paper: #FAF7EE; --card: #FFFDF8; --ink: #221A12; --soft: #5C5147;
        --rule: #E4DCCB; --squiggle: #E2660F; }}
* {{ box-sizing: border-box; }}
body {{ margin: 0; font-family: 'Avenir Next', -apple-system, sans-serif; color: var(--ink);
       font-size: 10.5pt; line-height: 1.5; -webkit-print-color-adjust: exact; }}
.page {{ width: 210mm; height: 297mm; padding: 18mm 18mm 16mm; background: var(--paper);
        position: relative; page-break-after: always; overflow: hidden; }}
h1, h2, h3 {{ font-family: Rounded, 'Avenir Next', sans-serif; font-weight: 700; margin: 0; }}
h2 {{ font-size: 21pt; margin-bottom: 4mm; display: flex; align-items: center; gap: 3mm; }}
h3 {{ font-size: 12pt; margin-bottom: 2mm; }}
.num {{ display: inline-flex; width: 10mm; height: 10mm; border-radius: 50%;
        background: var(--squiggle); color: white; font-size: 14pt;
        align-items: center; justify-content: center; }}
p {{ margin: 0 0 3mm; }}
b {{ font-weight: 600; }}
code {{ font-family: Menlo, monospace; font-size: 9pt; background: #F2EDE0;
        border: 1px solid var(--rule); border-radius: 4px; padding: 0.2mm 1.2mm; }}
.key {{ display: inline-block; font-size: 9pt; background: white; border-radius: 5px;
        box-shadow: 0 1px 0 rgba(0,0,0,.18); padding: 0 1.8mm; line-height: 1.6; }}
.row {{ display: flex; gap: 6mm; justify-content: center; align-items: flex-start; margin: 4mm 0; }}
.grid {{ display: grid; grid-template-columns: 1fr 1fr; gap: 5mm 7mm; margin-top: 3mm; }}
figure {{ margin: 0; }}
figure img.phone {{ width: 100%; border-radius: 4mm; border: 1px solid var(--rule);
                    box-shadow: 0 2mm 6mm -3mm rgba(34,26,18,.35); background: white; display: block; }}
.row figure img.phone {{ max-height: 150mm; width: auto; max-width: 100%; margin: 0 auto; }}
figcaption {{ font-size: 9pt; color: var(--soft); margin-top: 2mm; text-align: center; }}
.grid figcaption {{ text-align: left; }}
.note {{ display: flex; gap: 5mm; align-items: center; background: var(--card);
         border: 1px solid var(--rule); border-radius: 4mm; padding: 4mm 5mm; margin-top: 4mm; }}
.note img {{ height: 26mm; }}
.note p {{ margin: 0; }}
.tip {{ background: var(--card); border-left: 1.2mm solid var(--squiggle); border-radius: 2mm;
        padding: 3mm 4mm; }}
.aside {{ width: 40%; padding-top: 4mm; }}
.aside.wide {{ width: 56%; padding-top: 0; }}
.aside img {{ height: 34mm; display: block; margin: 6mm auto 0; }}
.aside ul {{ padding-left: 4mm; margin: 0; }}
.aside li {{ margin-bottom: 2.4mm; }}
.small {{ font-size: 9pt; color: var(--soft); }}
.steps {{ padding-left: 6mm; margin: 0 0 3mm; }}
.steps li {{ margin-bottom: 1.6mm; }}
table.examples {{ border-collapse: collapse; width: 100%; margin: 3mm 0 4mm; background: var(--card);
                  border-radius: 3mm; overflow: hidden; }}
.examples th {{ text-align: left; font-family: Rounded, sans-serif; font-size: 9pt; color: var(--soft);
                padding: 2mm 4mm; border-bottom: 1px solid var(--rule); }}
.examples td {{ padding: 1.6mm 4mm; border-bottom: 1px solid var(--rule); font-size: 11pt; }}
.folio {{ position: absolute; bottom: 8mm; right: 18mm; font-family: Rounded, sans-serif;
          color: var(--soft); font-size: 9pt; }}
.cover {{ height: 100%; display: flex; flex-direction: column; }}
.cover .wordmark {{ width: 105mm; margin-top: 10mm; }}
.cover h1 {{ font-size: 30pt; margin-top: 6mm; }}
.cover .lede {{ font-size: 13pt; color: var(--soft); max-width: 120mm; margin-top: 3mm; }}
.cover-mascot {{ position: absolute; right: 16mm; top: 30mm; height: 78mm; }}
.contents {{ margin-top: auto; background: var(--card); border: 1px solid var(--rule);
             border-radius: 4mm; padding: 6mm 8mm; }}
.contents ol {{ margin: 0; padding-left: 6mm; }}
.contents li {{ padding: 1mm 0; border-bottom: 1px dotted var(--rule); }}
.contents li span {{ display: inline-block; width: 92%; }}
.contents li b {{ color: var(--squiggle); }}
.closing {{ position: absolute; left: 18mm; right: 18mm; bottom: 18mm; display: flex; gap: 5mm;
            align-items: center; background: var(--card); border: 1px solid var(--rule);
            border-radius: 4mm; padding: 4mm 5mm; }}
.closing img {{ height: 24mm; }}
.closing p {{ margin: 0; }}
"""

document = f"""<!doctype html><html><head><meta charset="utf-8">
<title>LaTeX Squiggly: the iPhone guide</title><style>{CSS}</style></head>
<body>{''.join(pages)}</body></html>"""
html_path = WORK / "guide.html"
html_path.write_text(document)
subprocess.run([CHROME, "--headless", "--disable-gpu", "--no-pdf-header-footer",
                "--allow-file-access-from-files", f"--print-to-pdf={OUT}", html_path.as_uri()],
               check=True, capture_output=True)
print("wrote", OUT)
