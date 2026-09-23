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
    const ok = got === want;
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

  console.log(`\n${results.filter(Boolean).length}/${results.length} passed`);
  await context.close();
  if (results.some((ok) => !ok)) process.exitCode = 1;
})().catch((e) => { console.error(e); process.exit(1); });
