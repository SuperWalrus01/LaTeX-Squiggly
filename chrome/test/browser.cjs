// Loads the unpacked extension into Chromium and types into real fields: a
// textarea, inputs, contenteditable, a controlled field, a code editor, an
// editor in an about:blank iframe and one in a shadow root, keys typed with
// AltGr, Option and dead keys, and an excluded site. Pages are served by route
// interception, so nothing touches the network.
//
// Needs Playwright, which is not a dependency of the extension:
//   npm install --prefix /tmp/squiggly-test playwright
//   npx --prefix /tmp/squiggly-test playwright install chromium
//   NODE_PATH=/tmp/squiggly-test/node_modules node chrome/test/browser.cjs
//
// CHROMIUM_PATH points it at a different Chromium build. Branded Google Chrome
// will not do: it ignores --load-extension.

const { chromium } = require('playwright');
const path = require('path');

const ext = path.join(__dirname, '..');
const mod = process.platform === 'darwin' ? 'Meta' : 'Control';

const PAGE = `<!doctype html><meta charset=utf-8><body>
<textarea id=ta></textarea><input id=inp><input id=pw type=password>
<div id=ce contenteditable style="min-height:2em;border:1px solid"></div>
<div class=cm-editor><textarea id=code></textarea></div>
<input id=react><p id=log></p>
<iframe id=frame style="width:300px;height:80px"></iframe>
<iframe id=blank style="width:300px;height:80px"></iframe>
<shadow-editor></shadow-editor>
<script>
  // A controlled field in the React style: it keeps its own copy of the value
  // and only knows about changes that arrive as input events.
  let model = ''; const r = document.getElementById('react');
  r.addEventListener('input', () => { model = r.value; document.getElementById('log').textContent = model; });

  // A TinyMCE-style editor: an editable body written into an iframe with
  // document.open. Written after a pause, as editors do once the page has
  // loaded, so the extension is already in the frame when document.open
  // erases every listener on it.
  setTimeout(() => {
    const doc = document.getElementById('frame').contentDocument;
    doc.open(); doc.write('<body contenteditable style="min-height:40px"></body>'); doc.close();
  }, 300);

  // The same, made editable without document.open, so the frame keeps the
  // address about:blank and only match_origin_as_fallback reaches it.
  const blank = document.getElementById('blank').contentDocument;
  blank.body.contentEditable = 'true';
  blank.body.style.minHeight = '40px';

  // A web component with its editor inside a shadow root.
  customElements.define('shadow-editor', class extends HTMLElement {
    constructor() {
      super();
      this.attachShadow({ mode: 'open' }).innerHTML =
        '<div id=ed contenteditable style="min-height:2em;border:1px solid"></div>';
    }
  });
</script>`;

// A stand-in for Google Docs, built the way Docs is understood to work: the
// document is drawn from a model, and typing reaches it only as key events in a
// hidden frame, read by keyCode and charCode. It proves the extension's side of
// Google Docs mode; only a test by hand in Docs itself proves Docs' side.
const DOCS_STAND_IN = `<!doctype html><meta charset=utf-8><body>
<div id=doc style="min-height:2em;border:1px solid"></div>
<iframe id=input style="width:200px;height:40px"></iframe>
<script>
  let model = '';
  const draw = () => { document.getElementById('doc').textContent = model; };
  const input = document.getElementById('input').contentDocument;
  input.body.contentEditable = 'true';
  input.addEventListener('keypress', (e) => { model += String.fromCharCode(e.charCode); draw(); e.preventDefault(); });
  input.addEventListener('keydown', (e) => {
    if (e.keyCode === 8) { model = model.slice(0, -1); draw(); e.preventDefault(); }
  });
</script>`;

(async () => {
  // Playwright's default headless browser is a stripped-down shell that cannot
  // load extensions, so ask for its full Chromium unless a build is named.
  const context = await chromium.launchPersistentContext('', {
    executablePath: process.env.CHROMIUM_PATH || undefined,
    channel: process.env.CHROMIUM_PATH ? undefined : 'chromium',
    headless: true,
    args: [`--disable-extensions-except=${ext}`, `--load-extension=${ext}`],
  });
  let [sw] = context.serviceWorkers();
  if (!sw) sw = await context.waitForEvent('serviceworker');
  const id = sw.url().split('/')[2];

  await context.route('https://**/*', (route) => {
    const u = new URL(route.request().url());
    if (u.hostname === 'docs.google.com' && u.pathname.includes('/stand-in/')) {
      return route.fulfill({ contentType: 'text/html', body: DOCS_STAND_IN });
    }
    if (u.hostname.endsWith('example.test') || u.hostname.endsWith('overleaf.com')
        || u.hostname === 'docs.google.com') {
      return route.fulfill({ contentType: 'text/html', body: PAGE });
    }
    return route.continue();
  });

  const results = [];
  // The first-install page opens by itself; give it a moment to arrive.
  await new Promise((r) => setTimeout(r, 1000));
  const welcomed = context.pages().some((p) => p.url().endsWith('/options/options.html#welcome'));

  const page = await context.newPage();
  const check = (name, got, want) => {
    // Arrays compare by their contents, for checks of several things at once.
    const ok = Array.isArray(want) ? JSON.stringify(got) === JSON.stringify(want) : got === want;
    results.push(ok);
    console.log(`${ok ? 'PASS' : 'FAIL'}  ${name}${ok ? '' : `\n      want ${JSON.stringify(want)}\n      got  ${JSON.stringify(got)}`}`);
  };
  const value = (sel) => page.$eval(sel, (e) => e.value);
  const text = (sel) => page.$eval(sel, (e) => e.textContent.replace(/\u00a0/g, ' '));
  const fresh = async (sel) => { await page.$eval(sel, (e) => { if ('value' in e) e.value = ''; else e.textContent = ''; }); await page.click(sel); };
  const notice = () => page.evaluate(() => !!document.querySelector('latex-squiggly-notice'));

  check('first install opens the welcome page', welcomed, true);

  await page.goto('https://www.example.test/');
  await page.waitForTimeout(500);

  await fresh('#ta'); await page.keyboard.type('\\alpha ');
  check('textarea: \\alpha', await value('#ta'), 'α ');

  await fresh('#ta'); await page.keyboard.type('x \\int_5^6 dx');
  check('textarea: \\int_5^6 with scripts', await value('#ta'), 'x ∫₅⁶ dx');

  await fresh('#inp'); await page.keyboard.type('so $x^2 + y_1$ ok');
  check('input: $...$ span with spaces', await value('#inp'), 'so x² + y₁ ok');

  await fresh('#inp'); await page.keyboard.type('\\frac{\\alpha}{2} ');
  check('input: nested \\frac{\\alpha}{2}', await value('#inp'), 'α∕2 ');
  check('fallback shows a notice', await notice(), true);

  await fresh('#ta'); await page.keyboard.type('\\vec{v} ');
  check('refusal leaves text alone', await value('#ta'), '\\vec{v} ');

  await fresh('#ta'); await page.keyboard.type('C:\\path\\to\\file and \\Users ');
  check('Windows path stays quiet', await value('#ta'), 'C:\\path\\to\\file and \\Users ');

  await fresh('#ta'); await page.keyboard.type('I have $5$ left ');
  check('$5$ is not maths', await value('#ta'), 'I have $5$ left ');

  await fresh('#ta'); await page.keyboard.type('x^2 ');
  check('bare x^2 stays', await value('#ta'), 'x^2 ');

  await fresh('#ta'); await page.keyboard.type('\\alpha ');
  await page.keyboard.press(`${mod}+z`);
  check('undo restores the source', await value('#ta'), '\\alpha');

  await fresh('#ta'); await page.keyboard.type('\\alp');
  await page.mouse.click(5, 5); await page.click('#ta');
  await page.keyboard.type('ha ');
  check('a click ends the run', await value('#ta'), '\\alpha ');

  await fresh('#ta'); await page.keyboard.type('\\alphx');
  await page.keyboard.press('Backspace'); await page.keyboard.type('a ');
  check('backspace is followed', await value('#ta'), 'α ');

  await fresh('#pw'); await page.keyboard.type('\\alpha ');
  check('password field untouched', await value('#pw'), '\\alpha ');

  await fresh('#code'); await page.keyboard.type('\\alpha ');
  check('code editor untouched', await value('#code'), '\\alpha ');

  await fresh('#react'); await page.keyboard.type('\\beta ');
  check('controlled field sees the change', await text('#log'), 'β ');

  await fresh('#ce'); await page.keyboard.type('hello \\beta world');
  check('contenteditable: \\beta', await text('#ce'), 'hello β world');

  await fresh('#ce'); await page.keyboard.type('so $a + b^2$ ok');
  check('contenteditable: $...$ across typed spaces', await text('#ce'), 'so a + b² ok');

  await fresh('#ce'); await page.keyboard.type('\\sum_{i=1}^{n} ');
  check('contenteditable: \\sum_{i=1}^{n}', await text('#ce'), '∑ᵢ₌₁ⁿ ');

  // Keyboards other than US English. A key typed with AltGr reaches the page
  // as Control and Alt together, and one typed with Option on a Mac as Alt;
  // on most European keyboards that is how { and } are typed.
  const modifiedKey = (key, modifiers) => page.evaluate(([k, m]) =>
    document.activeElement.dispatchEvent(new KeyboardEvent('keydown', { key: k, bubbles: true, ...m })), [key, modifiers]);
  const typeWith = async (modifiers, sequence) => {
    for (const ch of sequence) {
      if ('{}'.includes(ch)) { await modifiedKey(ch, modifiers); await page.keyboard.insertText(ch); }
      else await page.keyboard.type(ch);
    }
  };
  await fresh('#ta'); await typeWith({ ctrlKey: true, altKey: true }, '\\frac{1}{2} ');
  check('braces typed with AltGr', await value('#ta'), '½ ');
  await fresh('#ta'); await typeWith({ altKey: true }, '\\frac{1}{2} ');
  check('braces typed with Option', await value('#ta'), '½ ');

  await fresh('#ta'); await page.keyboard.type('\\alp');
  await modifiedKey('b', { ctrlKey: true });
  await page.keyboard.type('ha ');
  check('a Control shortcut still ends the run', await value('#ta'), '\\alpha ');

  // A dead key: ^ built by composition, as on a German Mac.
  const cdp = await context.newCDPSession(page);
  await fresh('#ta'); await page.keyboard.type('$x');
  await cdp.send('Input.imeSetComposition', { text: '^', selectionStart: 1, selectionEnd: 1 });
  await cdp.send('Input.insertText', { text: '^' });
  await page.keyboard.type('2$ ');
  check('a caret typed with a dead key', await value('#ta'), 'x² ');

  const frameBody = (f) => f.$eval('body', (b) => b.textContent.replace(/\u00a0/g, ' '));
  // Frames come in page order: #frame, written with document.open, then #blank.
  const [, written, blankFrame] = page.frames();
  await written.click('body'); await page.keyboard.type('\\alpha ');
  check('an editor in an iframe written with document.open', await frameBody(written), 'α ');
  await blankFrame.click('body'); await page.keyboard.type('\\gamma ');
  check('an editor in an about:blank iframe', await frameBody(blankFrame), 'γ ');

  await page.click('shadow-editor >> #ed'); await page.keyboard.type('\\beta ');
  check('an editor inside a shadow root', (await page.$eval('shadow-editor >> #ed', (e) => e.textContent)).replace(/\u00a0/g, ' '), 'β ');

  // Google Docs, Sheets and Slides take typing through a hidden frame, which
  // content.js must leave alone even though it runs in such frames elsewhere.
  // Slides here, because in Docs documents docs.js takes over; see below.
  await page.goto('https://docs.google.com/presentation/d/test/edit');
  await page.waitForTimeout(500);
  for (const [index, kind] of [[1, 'written with document.open'], [2, 'about:blank']]) {
    const docsFrame = page.frames()[index];
    await docsFrame.click('body'); await page.keyboard.type('\\alpha ');
    check(`Google Slides' hidden frame (${kind}) untouched`, await frameBody(docsFrame), '\\alpha ');
  }

  // Excluded site
  await page.goto('https://fr.overleaf.com/project');
  await page.waitForTimeout(500);
  await fresh('#ta'); await page.keyboard.type('\\alpha ');
  check('overleaf subdomain untouched', await value('#ta'), '\\alpha ');

  // The toolbar icon's tooltip, read back from Chrome for the tab. The worker
  // can stop and restart between checks, so it is looked up each time.
  const worker = async () => context.serviceWorkers()[0] ?? context.waitForEvent('serviceworker');
  // The tab is found as the active one, because without the tabs permission,
  // which the extension does not ask for, Chrome will not match tabs by URL.
  const toolbarTitle = async () => {
    await page.bringToFront();
    await page.waitForTimeout(300);
    return (await worker()).evaluate(async () => {
      const [tab] = await chrome.tabs.query({ active: true, lastFocusedWindow: true });
      return chrome.action.getTitle({ tabId: tab.id });
    });
  };
  check('toolbar icon says it is off on an excluded site',
    await toolbarTitle(), 'LaTeX Squiggly: off on overleaf.com');

  await page.goto('https://www.example.test/');
  check('toolbar icon says it is converting elsewhere',
    await toolbarTitle(), 'LaTeX Squiggly');

  // The pause shortcut, through the same function the command calls. The
  // notice shows even with notices off: it is about the extension, not a
  // conversion.
  await page.waitForTimeout(300);
  await page.bringToFront(); await page.click('#ta');
  await (await worker()).evaluate(() => chrome.storage.sync.set({ showNotices: false }));
  await (await worker()).evaluate(() => toggleConversion());
  check('the shortcut pauses: the toolbar icon says so',
    await toolbarTitle(), 'LaTeX Squiggly: paused');
  check('the shortcut pauses: the page in front says so, notices off or not', await notice(), true);
  await fresh('#ta'); await page.keyboard.type('\\alpha ');
  check('the shortcut pauses: nothing converts', await value('#ta'), '\\alpha ');
  await (await worker()).evaluate(() => toggleConversion());
  await page.waitForTimeout(300);
  await fresh('#ta'); await page.keyboard.type('\\alpha ');
  check('the shortcut resumes', await value('#ta'), 'α ');
  await (await worker()).evaluate(() => chrome.storage.sync.set({ showNotices: true }));

  // Settings: turning it off
  const options = await context.newPage();
  await options.goto(`chrome-extension://${id}/options/options.html`);
  await options.waitForTimeout(300);
  await options.click('label:has(#enabled)');
  await page.goto('https://www.example.test/');
  await page.waitForTimeout(500);
  await fresh('#ta'); await page.keyboard.type('\\alpha ');
  check('off switch is respected', await value('#ta'), '\\alpha ');
  await options.click('label:has(#enabled)');

  // Google Docs mode, against the stand-in.
  const docs = async (path = '/document/d/stand-in/edit') => {
    await page.goto('https://docs.google.com' + path);
    await page.waitForTimeout(500);
    const frame = page.frames()[1];
    await frame.click('body');
    return frame;
  };
  const drawn = () => page.$eval('#doc', (e) => e.textContent);

  await docs(); await page.keyboard.type('x \\alpha y');
  check('Google Docs mode is on by default: \\alpha', await drawn(), 'x α y');

  await docs(); await page.keyboard.type('$x^2$ and \\frac{1}{2} ');
  check('Google Docs mode: scripts and fractions', await drawn(), 'x² and ½ ');

  await docs(); await page.keyboard.type('\\alphx');
  await page.keyboard.press('Backspace'); await page.keyboard.type('a ');
  check('Google Docs mode follows Backspace', await drawn(), 'α ');

  const docsFrame = await docs(); await page.keyboard.type('\\alp');
  await page.click('#doc'); await page.waitForTimeout(200); await docsFrame.click('body');
  await page.keyboard.type('ha ');
  check('Google Docs mode: a click on the document ends the command', await drawn(), '\\alpha ');

  await docs(); await page.keyboard.type('\\alp');
  await page.waitForTimeout(4500);
  await page.keyboard.type('ha ');
  check('Google Docs mode: a pause of over four seconds ends the command', await drawn(), '\\alpha ');

  await docs(); await page.keyboard.type('\\frac{x+1}{2} ');
  check('Google Docs mode: an approximation', await drawn(), '(x+1)∕2 ');
  check('Google Docs mode: its notice appears in the top frame', await notice(), true);

  await docs(); await page.keyboard.type('\\E ');
  check('Google Docs mode leaves 𝔼 as typed, for now', await drawn(), '\\E ');

  await docs('/spreadsheets/d/stand-in/edit'); await page.keyboard.type('\\alpha ');
  check('Google Docs mode stays out of Sheets', await drawn(), '\\alpha ');

  // Switched off, it stops at once, without reloading the document.
  await docs();
  await options.click('label:has(#google-docs)');
  await options.waitForTimeout(300);
  await page.frames()[1].click('body'); await page.keyboard.type('\\alpha ');
  check('Google Docs mode switched off stops without a reload', await drawn(), '\\alpha ');
  await options.click('label:has(#google-docs)');

  // Popup, as a page
  const popup = await context.newPage();
  await popup.setViewportSize({ width: 300, height: 320 });
  await popup.goto(`chrome-extension://${id}/popup/popup.html`);
  await popup.waitForTimeout(300);
  check('popup shows its switch', await popup.isVisible('#enabled'), true);
  // Chrome writes it as Alt+Shift+L, or as ⌥⇧L on a Mac.
  const keys = await popup.textContent('#shortcut-keys');
  check('popup shows the pause shortcut', ['Alt+Shift+L', '⌥⇧L'].includes(keys), true);
  check('popup opens on the Typing tab at first', await popup.isVisible('#latex'), false);

  // MARK: Renderer

  // MathJax must reach only extension pages. The page script's world is its
  // own, so this checks the page's: nothing named MathJax, no script loaded.
  await page.goto('https://www.example.test/');
  await page.waitForTimeout(300);
  check('MathJax is not in web pages',
    await page.evaluate(() => typeof window.MathJax === 'undefined' &&
      !document.querySelector('script[src*="mathjax"]')), true);

  // Chrome will not grant clipboard permissions to an extension's origin, so
  // what was copied is read back from a test page, which shares the clipboard.
  await context.grantPermissions(['clipboard-read', 'clipboard-write'], { origin: 'https://www.example.test' });
  const onClipboard = async (read) => {
    await page.bringToFront();
    const result = await page.evaluate(read);
    if (!r.isClosed()) await r.bringToFront();
    return result;
  };
  const r = await context.newPage();
  await r.setViewportSize({ width: 480, height: 560 });
  const offsite = [];
  r.on('request', (req) => { if (!/^(chrome-extension|blob|data):/.test(req.url())) offsite.push(req.url()); });
  const opened = Date.now();
  await r.goto(`chrome-extension://${id}/popup/popup.html#renderer`);
  await r.waitForFunction(() => !!globalThis.MathJax?.startup?.document?.inputJax);
  console.log(`      (renderer ready ${Date.now() - opened} ms after opening)`);

  const source = () => r.$eval('#latex', (e) => e.value);
  const caret = () => r.$eval('#latex', (e) => [e.selectionStart, e.selectionEnd]);
  const drawnSvg = () => r.$eval('#preview', (e) => !!e.querySelector(':scope > svg') && !e.classList.contains('stale'));
  const errorShown = () => r.$eval('#render-error', (e) => (e.hidden ? null : e.textContent));
  const copyEnabled = () => r.$eval('#copy-png', (e) => !e.disabled);
  const enter = async (latex) => {
    await r.fill('#latex', latex);
    await r.waitForTimeout(700);
  };
  const clear = async () => { await r.fill('#latex', ''); await r.focus('#latex'); await r.waitForTimeout(50); };
  // The PNG on the clipboard: its size, and the alpha of its corner pixel.
  const clipboardPng = () => onClipboard(async () => {
    const [item] = await navigator.clipboard.read();
    if (!item.types.includes('image/png')) return null;
    const bitmap = await createImageBitmap(await item.getType('image/png'));
    const canvas = new OffscreenCanvas(bitmap.width, bitmap.height);
    const context = canvas.getContext('2d');
    context.drawImage(bitmap, 0, 0);
    return { width: bitmap.width, height: bitmap.height, cornerAlpha: context.getImageData(0, 0, 1, 1).data[3] };
  });
  const clearClipboard = () => onClipboard(() => navigator.clipboard.writeText(''));
  const clipboardText = () => onClipboard(() => navigator.clipboard.readText());

  check('renderer: opens on its tab with the LaTeX box focused',
    await r.evaluate(() => document.activeElement.id), 'latex');

  await r.evaluate(() => chrome.storage.sync.set({ renderMacros: '\\newcommand{\\R}{\\mathbb{R}}' }));
  const renders = [
    '\\int_0^1 x^2\\,dx = \\frac{1}{3}',
    '\\begin{aligned} a &= b \\\\ c &= d \\end{aligned}',
    '\\overbrace{1+2+\\cdots+n}^{n\\text{ terms}}',
    '\\underbrace{x+y}_{\\text{sum}}',
    '\\overset{!}{=} \\underset{n\\to\\infty}{\\lim}',
    '\\begin{pmatrix} 1 & 0 \\\\ 0 & 1 \\end{pmatrix}',
    '\\cancel{x}', '\\ce{H2O}', '\\dv{f}{x}', '\\ket{\\psi}', 'x \\in \\R',
  ];
  for (const latex of renders) {
    await enter(latex);
    check(`renderer draws ${latex}`, [await drawnSvg(), await errorShown(), await copyEnabled()], [true, null, true]);
  }

  await enter('\\newcommand{\\half}{\\frac12} \\half');
  check('renderer: \\newcommand in the input', await drawnSvg(), true);
  await enter('\\half');
  check('renderer: a definition does not outlive its input', (await errorShown() ?? '').startsWith('\\half isn'), true);

  await r.evaluate(() => chrome.storage.sync.set({ renderMacros: '\\newcommand{\\R}{\\mathbb{R}' }));
  await enter('x');
  check('renderer: a mistake in the settings\' commands is blamed on them',
    (await errorShown() ?? '').startsWith('In your commands'), true);
  await r.evaluate(() => chrome.storage.sync.set({ renderMacros: '' }));
  await enter('\\href{https://example.test}{x}');
  check('renderer: \\href is not offered', (await errorShown() ?? '').startsWith('\\href isn'), true);

  await enter('\\begin{tikzpicture}\\end{tikzpicture}');
  check('renderer: TikZ is refused plainly', await errorShown(),
    "\\begin{tikzpicture} isn't supported: this renderer covers maths-mode LaTeX only.");
  check('renderer: nothing to copy while the input is wrong', await copyEnabled(), false);

  // Typing \frac{1}{2} key by key passes through wrong states; none of them
  // should flash an error, and the last good image stays, dimmed.
  await enter('x');
  await r.focus('#latex'); await r.keyboard.press('End');
  let flashed = false;
  for (const key of ' + \\frac{1}{2'.split('')) {
    await r.keyboard.type(key);
    await r.waitForTimeout(80);
    if (await errorShown()) flashed = true;
  }
  check('renderer: no error flashes while typing', flashed, false);
  await r.fill('#latex', 'x + \\frac{1}{');
  await r.waitForTimeout(300);
  check('renderer: the last good image stays, dimmed, and cannot be copied',
    await r.$eval('#preview', (e) => !!e.querySelector(':scope > svg') && e.classList.contains('stale')) &&
    !(await copyEnabled()), true);
  check('renderer: ...and no error yet', await errorShown(), null);
  await r.waitForTimeout(500);
  check('renderer: the error shows after a pause', await errorShown(), 'Missing close brace');

  // Copying: white at 3× by default, then transparent, which persists.
  await enter('\\frac{a}{b}');
  await clearClipboard();
  await r.click('#copy-png');
  await r.waitForTimeout(300);
  const width = await r.$eval('#preview > svg', (e) => parseFloat(e.getAttribute('width')));
  const white = await clipboardPng();
  check('renderer: Copy PNG copies a white image at 3×',
    [white?.width, white?.cornerAlpha], [Math.ceil(width * 3), 255]);
  await r.click('[data-background="transparent"]');
  check('renderer: the preview turns to a checkerboard',
    await r.$eval('#preview', (e) => e.classList.contains('transparent')), true);
  await r.click('#copy-png');
  await r.waitForTimeout(300);
  check('renderer: the next copy is transparent', (await clipboardPng())?.cornerAlpha, 0);
  await r.reload();
  await r.waitForFunction(() => !!document.querySelector('#preview > svg'));
  check('renderer: the background choice and the input are kept',
    [await r.$eval('[data-background="transparent"]', (e) => e.getAttribute('aria-checked')), await source()],
    ['true', '\\frac{a}{b}']);
  await r.click('[data-background="white"]');

  await r.click('#copy-svg');
  await r.waitForTimeout(200);
  const svgText = await clipboardText();
  check('renderer: Copy SVG copies self-contained markup',
    svgText.startsWith('<svg') && svgText.includes('xmlns="http://www.w3.org/2000/svg"') && !svgText.includes('<use'), true);

  const [svgFile] = await Promise.all([r.waitForEvent('download'), r.click('#download-svg')]);
  const [pngFile] = await Promise.all([r.waitForEvent('download'), r.click('#download-png')]);
  const saved = require('fs').readFileSync(await pngFile.path());
  check('renderer: downloads are named and are what they say',
    [svgFile.suggestedFilename(), pngFile.suggestedFilename(), saved.subarray(1, 4).toString()],
    ['equation.svg', 'equation.png', 'PNG']);

  // Ctrl+Enter copies and closes; with nothing valid it only shows why.
  await enter('\\frac{1}{');
  await clearClipboard();
  await r.focus('#latex');
  await r.keyboard.press(`${mod}+Enter`);
  await r.waitForTimeout(600);
  check('renderer: Ctrl+Enter on wrong input copies nothing and stays open',
    [r.isClosed(), await clipboardText()], [false, '']);

  // Autocomplete.
  await clear(); await r.keyboard.type('\\al');
  check('autocomplete: \\al offers \\alpha first',
    await r.$eval('#suggestions', (e) => !e.hidden && e.querySelector('li .name').textContent), '\\alpha');
  await r.keyboard.press('Tab');
  check('autocomplete: Tab accepts', await source(), '\\alpha');
  await clear(); await r.keyboard.type('\\lef');
  await r.keyboard.press('Tab');
  check('autocomplete: an accepted command does not offer itself again',
    [await source(), await r.$eval('#suggestions', (e) => e.hidden)], ['\\left', true]);
  await clear(); await r.keyboard.type('\\fr');
  await r.keyboard.press('Tab');
  check('autocomplete: \\frac comes with its braces, the cursor in the first',
    [await source(), await caret()], ['\\frac{}{}', [6, 6]]);
  await r.keyboard.type('1');
  await r.keyboard.press('Tab');
  await r.keyboard.type('2');
  check('autocomplete: Tab moves to the next brace', await source(), '\\frac{1}{2}');
  await clear(); await r.keyboard.type('\\fr');
  await r.keyboard.press('Enter');
  await r.keyboard.press(`${mod}+z`);
  check('autocomplete: undo takes back the insertion', await source(), '\\fr');
  await clear(); await r.keyboard.type('\\al');
  await r.keyboard.press('Escape');
  check('autocomplete: Esc closes the list, not the popup',
    [await r.$eval('#suggestions', (e) => e.hidden), r.isClosed()], [true, false]);

  // Braces.
  await clear(); await r.keyboard.type('x^{');
  check('braces: { brings its }', [await source(), await caret()], ['x^{}', [3, 3]]);
  await r.keyboard.type('2}');
  check('braces: } steps over the one added', await source(), 'x^{2}');
  await clear(); await r.keyboard.type('a_{');
  await r.keyboard.press('Backspace');
  check('braces: Backspace in an empty pair takes both', await source(), 'a_');

  // Colour.
  await enter('x+y');
  await r.$eval('#latex', (e) => { e.focus(); e.setSelectionRange(0, 1); });
  await r.click('.swatch[data-name="red"]');
  await r.waitForTimeout(400);
  check('colour: a swatch wraps the selection in \\textcolor', await source(), '\\textcolor{red}{x}+y');
  check('colour: ...and it renders red',
    await r.$eval('#preview > svg', (e) => !!e.querySelector('[fill="red"]')), true);
  await r.$eval('#latex', (e) => { e.focus(); e.setSelectionRange(0, 0); });
  await r.click('.swatch[data-name="white"]');
  check('colour: with nothing selected, white colours the image and warns on white',
    [await r.$eval('#preview > svg', (e) => e.style.color), await r.isVisible('#render-warning')],
    ['rgb(255, 255, 255)', true]);
  await r.click('.swatch[data-name="black"]');
  check('colour: black again clears the warning', await r.isVisible('#render-warning'), false);

  // Braces over and under a selection.
  await enter('a+b+c');
  await r.$eval('#latex', (e) => { e.focus(); e.select(); });
  await r.click('#overbrace');
  await r.fill('#brace-label', '3 terms');
  await r.press('#brace-label', 'Enter');
  check('overbrace wraps the selection with its label', await source(), '\\overbrace{a+b+c}^{\\text{3 terms}}');
  await r.waitForTimeout(400);
  check('overbrace renders', await drawnSvg(), true);
  await enter('{a+b}');
  await r.$eval('#latex', (e) => { e.focus(); e.setSelectionRange(0, 2); });
  await r.click('#underbrace');
  check('underbrace refuses a selection with half a pair of braces',
    [await source(), await r.isVisible('#label-form'), (await r.textContent('#render-message')).includes('brace')],
    ['{a+b}', false, true]);

  check('renderer: nothing was fetched from outside the extension', offsite.join(' '), '');
  // Chrome leaves a suggested key unassigned when it uses the key itself, and
  // the set it keeps grows: Chrome 153 took Alt+Shift+R, the first choice. So
  // this checks Chrome did assign the renderer's key, which fails when a new
  // Chrome takes it too, and that the renderer shows it.
  const assigned = await r.evaluate(async () =>
    (await chrome.commands.getAll()).find((c) => c.name === 'open-renderer')?.shortcut || '');
  check('Chrome assigns the renderer its shortcut', ['Alt+Shift+E', '⌥⇧E'].includes(assigned), true);
  check('renderer shows it', [await r.textContent('#open-keys'), await r.isVisible('#open-shortcut')], [assigned, true]);

  // The shortcut. Headless Chromium accepts openPopup but shows Playwright no
  // page for it, so openPopup is made to fail, as it does before Chrome 127:
  // the same page then opens in a window of its own, which proves the rest,
  // that it opens on the Renderer tab with the last input selected, ready to
  // be typed over.
  const [shortcutPage] = await Promise.all([
    context.waitForEvent('page'),
    (await worker()).evaluate(() => {
      chrome.action.openPopup = () => Promise.reject(new Error('no popup here'));
      return openRenderer();
    }),
  ]);
  await shortcutPage.waitForLoadState();
  await shortcutPage.waitForFunction(() => document.activeElement?.id === 'latex');
  check('the renderer shortcut opens it with the input selected',
    await shortcutPage.$eval('#latex', (e) => [e.selectionStart, e.selectionEnd, e.value.length])
      .then(([start, end, length]) => start === 0 && end === length && length > 0), true);
  // The page closes inside the key press, which Playwright reports as an error.
  await shortcutPage.keyboard.press('Escape').catch(() => {});
  await new Promise((resolve) => setTimeout(resolve, 300));
  check('Esc closes it', shortcutPage.isClosed(), true);

  await enter('\\sqrt{2}');
  await r.focus('#latex');
  await r.keyboard.press(`${mod}+Enter`);
  await new Promise((resolve) => setTimeout(resolve, 800));
  check('Ctrl+Enter copies the PNG and closes', r.isClosed(), true);
  check('...and the PNG is on the clipboard', !!(await clipboardPng()), true);

  // The options page holds the rest of the settings.
  const reader = await context.newPage();
  await reader.goto(`chrome-extension://${id}/options/options.html#renderer`);
  await reader.fill('#render-macros', '\\newcommand{\\N}{\\mathbb{N}}');
  await reader.$eval('#render-macros', (e) => e.blur());
  await reader.selectOption('#render-scale', '2');
  await reader.waitForTimeout(300);
  check('options: renderer settings are saved',
    await reader.evaluate(async () => {
      const { renderMacros, renderScale } = await chrome.storage.sync.get(['renderMacros', 'renderScale']);
      return [renderMacros, renderScale];
    }),
    ['\\newcommand{\\N}{\\mathbb{N}}', 2]);

  // MARK: Renderer, from selected text

  check('the menu item exists', await (await worker()).evaluate(() => new Promise((resolve) =>
    chrome.contextMenus.update('render-selection', {}, () => resolve(!chrome.runtime.lastError)))), true);
  check('delimiters come off a selection, and only a pair around all of it',
    await (await worker()).evaluate(() => ['$x^2$', '$$\\frac12$$', '\\[a\\]', '\\(b\\)', '$a$ and $b$', 'costs $5']
      .map((t) => globalThis.LaTeXSquiggly.stripDelimiters(t))),
    ['x^2', '\\frac12', 'a', 'b', '$a$ and $b$', 'costs $5']);
  // What the menu item does with Chrome's selectionText, through the same
  // window as the shortcut test above.
  const [selectionPage] = await Promise.all([
    context.waitForEvent('page'),
    (await worker()).evaluate(() => {
      chrome.action.openPopup = () => Promise.reject(new Error('no popup here'));
      return renderSelection('  $$\\frac{1}{2}$$ ');
    }),
  ]);
  await selectionPage.waitForFunction(() => !!document.querySelector('#preview > svg'));
  check('the menu item opens the renderer with the selection, delimiters off',
    await selectionPage.$eval('#latex', (e) => e.value), '\\frac{1}{2}');
  await selectionPage.close();

  // MARK: History

  const h = await context.newPage();
  await h.setViewportSize({ width: 480, height: 700 });
  await h.goto(`chrome-extension://${id}/popup/popup.html#renderer`);
  await h.evaluate(() => chrome.storage.local.set({ rendererHistory: [] }));
  await h.waitForFunction(() => !!globalThis.MathJax?.startup?.document?.inputJax);
  for (let i = 0; i < 25; i++) {
    await h.fill('#latex', `x^{${i}}`);
    await h.click('#copy-svg');
    await h.waitForTimeout(50);
  }
  await h.fill('#latex', 'x^{10}');
  await h.click('#copy-svg');
  await h.waitForTimeout(200);
  const stored = await h.evaluate(async () => (await chrome.storage.local.get('rendererHistory')).rendererHistory.map((e) => e.source));
  check('history: 10 entries, newest first, each once',
    [stored.length, stored[0], stored[1], stored.filter((s) => s === 'x^{10}').length, stored.includes('x^{15}')],
    [10, 'x^{10}', 'x^{24}', 1, false]);
  check('history: closed, with nothing drawn, until opened',
    [await h.$eval('#history', (e) => e.open), await h.$eval('#history-list', (e) => e.children.length)], [false, 0]);
  await h.click('#history summary');
  await h.waitForTimeout(200);
  check('history: opening it draws every entry',
    await h.$$eval('#history-list .entry > svg', (e) => e.length), 10);
  await h.click('#history-list li:nth-child(3) .entry');
  check('history: an entry loads into the editor', await h.$eval('#latex', (e) => e.value), 'x^{23}');
  await h.click('#history-list li:nth-child(1) .remove');
  await h.waitForTimeout(100);
  check('history: ✕ removes an entry', await h.$$eval('#history-list li', (e) => e.length), 9);
  await h.click('#history-clear');
  await h.waitForTimeout(100);
  check('history: Clear history empties it',
    [await h.$$eval('#history-list li', (e) => e.length), await h.isVisible('#history-empty')], [0, true]);

  console.log(`\n${results.filter(Boolean).length}/${results.length} passed`);
  await context.close();
  if (results.some((ok) => !ok)) process.exitCode = 1;
})().catch((e) => { console.error(e); process.exit(1); });
