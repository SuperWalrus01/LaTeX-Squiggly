// Loads the unpacked extension into Chromium and types into real fields: a
// textarea, inputs, contenteditable, a controlled field, a code editor, and an
// excluded site. Pages are served by route interception, so nothing touches
// the network.
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
<script>
  // A controlled field in the React style: it keeps its own copy of the value
  // and only knows about changes that arrive as input events.
  let model = ''; const r = document.getElementById('react');
  r.addEventListener('input', () => { model = r.value; document.getElementById('log').textContent = model; });
</script>`;

(async () => {
  const context = await chromium.launchPersistentContext('', {
    executablePath: process.env.CHROMIUM_PATH || undefined, headless: true,
    args: ['--headless=new', `--disable-extensions-except=${ext}`, `--load-extension=${ext}`],
  });
  let [sw] = context.serviceWorkers();
  if (!sw) sw = await context.waitForEvent('serviceworker');
  const id = sw.url().split('/')[2];

  await context.route('https://**/*', (route) => {
    const u = new URL(route.request().url());
    if (u.hostname.endsWith('example.test') || u.hostname.endsWith('overleaf.com')) {
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
