// Runs the Mac app's renderer window page in Chromium, with a stand-in for the
// app: the same files the app serves, laid out by
// Sources/LaTeXSquigglyApp/Web/files.json, and a fake of the message bridge
// that answers as the app does and records what it was asked. It proves the
// page's side of the bridge; the app's side can only be tried on a Mac.
//
// Needs Playwright, as chrome/test/browser.cjs does:
//   NODE_PATH=/tmp/squiggly-test/node_modules node chrome/test/mac-window.cjs

const { chromium } = require('playwright');
const fs = require('fs');
const path = require('path');

const root = path.join(__dirname, '..', '..');
const { files } = JSON.parse(fs.readFileSync(path.join(root, 'Sources/LaTeXSquigglyApp/Web/files.json')));

// The file behind a served path, found the way the app finds it.
function source(served) {
  if (files[served]) return path.join(root, files[served]);
  for (const [prefix, folder] of Object.entries(files)) {
    if (prefix.endsWith('/') && served.startsWith(prefix)) {
      return path.join(root, folder, served.slice(prefix.length));
    }
  }
  return null;
}

const TYPES = { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css', '.json': 'application/json' };

// The app's side of the bridge: storage in two areas, and a log of the rest.
const FAKE_APP = `
  window.appLog = [];
  window.appStore = { sync: {}, local: {} };
  window.webkit = { messageHandlers: { squiggly: { postMessage: async (message) => {
    window.appLog.push(message);
    const store = window.appStore;
    switch (message.op) {
      case 'get': return Object.fromEntries(message.keys.filter((k) => k in store[message.area]).map((k) => [k, store[message.area][k]]));
      case 'set': Object.assign(store[message.area], message.items); return null;
      case 'shortcut': return message.name === 'open-renderer' ? '⌃⌥⌘L' : null;
      case 'save': return true;
      default: return null;
    }
  } } } };
`;

(async () => {
  const browser = await chromium.launch({ channel: process.env.CHROMIUM_PATH ? undefined : 'chromium',
    executablePath: process.env.CHROMIUM_PATH || undefined });
  const page = await browser.newPage();
  await page.setViewportSize({ width: 520, height: 900 });
  await page.addInitScript(FAKE_APP);
  const offsite = [];
  await page.route('**/*', (route) => {
    const url = new URL(route.request().url());
    if (url.hostname !== 'squiggly.test') {
      offsite.push(url.href);
      return route.abort();
    }
    const file = source(url.pathname.slice(1) || 'index.html');
    if (!file || !fs.existsSync(file)) return route.fulfill({ status: 404, body: '' });
    return route.fulfill({ contentType: TYPES[path.extname(file)] ?? 'application/octet-stream', body: fs.readFileSync(file) });
  });

  const results = [];
  const check = (name, got, want) => {
    const ok = Array.isArray(want) ? JSON.stringify(got) === JSON.stringify(want) : got === want;
    results.push(ok);
    console.log(`${ok ? 'PASS' : 'FAIL'}  ${name}${ok ? '' : `\n      want ${JSON.stringify(want)}\n      got  ${JSON.stringify(got)}`}`);
  };
  const log = (op) => page.evaluate((op) => window.appLog.filter((m) => m.op === op), op);
  const clearLog = () => page.evaluate(() => { window.appLog = []; });

  const errors = [];
  page.on('pageerror', (e) => errors.push(e.message));
  await page.goto('https://squiggly.test/index.html');
  await page.waitForFunction(() => document.body.dataset.ready === 'true' && !!globalThis.MathJax?.startup?.document);

  check('the page starts with no errors', errors.join(' | '), '');
  check('the renderer is the host the app provides', await page.evaluate(() => LaTeXSquiggly.host.kind), 'mac');

  await page.fill('#latex', '\\frac{a}{b}');
  await page.waitForTimeout(400);
  check('it renders', await page.$eval('#preview', (e) => !!e.querySelector(':scope > svg')), true);
  check('the input is kept, in the app\'s local area',
    await page.evaluate(() => window.appStore.local.rendererInput), '\\frac{a}{b}');
  check('the open shortcut is the app\'s', await page.textContent('#open-keys'), '⌃⌥⌘L');

  await clearLog();
  await page.click('#copy-png');
  await page.waitForTimeout(300);
  const [copy] = await log('copyImage');
  const width = await page.$eval('#preview > svg', (e) => parseFloat(e.getAttribute('width')));
  check('Copy PNG hands the app a PNG, with its size in points',
    [Buffer.from(copy?.png ?? '', 'base64').subarray(1, 4).toString(), copy?.width === width, copy?.height > 0],
    ['PNG', true, true]);

  await clearLog();
  await page.click('#copy-svg');
  await page.waitForTimeout(200);
  check('Copy SVG hands the app the markup', ((await log('copyText'))[0]?.text ?? '').startsWith('<svg'), true);

  await clearLog();
  await page.click('#download-svg');
  await page.waitForTimeout(200);
  const [save] = await log('save');
  check('Download SVG asks the app to save it',
    [save?.name, Buffer.from(save?.data ?? '', 'base64').toString().startsWith('<svg')], ['equation.svg', true]);
  check('what was copied and saved is in the history, in the app\'s local area',
    await page.evaluate(() => window.appStore.local.rendererHistory?.[0]?.source), '\\frac{a}{b}');

  await page.click('[data-background="transparent"]');
  check('the background switch is saved in the app\'s sync area',
    await page.evaluate(() => window.appStore.sync.renderBackground), 'transparent');

  await page.click('#image-settings');
  check('Image settings opens the settings below', await page.$eval('#settings', (e) => e.open), true);
  check('...which show the switch just changed', await page.$eval('#render-background', (e) => e.value), 'transparent');
  await page.selectOption('#render-scale', '2');
  await page.fill('#render-macros', '\\newcommand{\\R}{\\mathbb{R}}');
  await page.$eval('#render-macros', (e) => e.blur());
  await page.waitForTimeout(100);
  await page.fill('#latex', 'x \\in \\R');
  await page.waitForTimeout(400);
  check('settings from the form reach the renderer',
    [await page.evaluate(() => window.appStore.sync.renderScale),
     await page.$eval('#preview', (e) => !!e.querySelector(':scope > svg') && !e.classList.contains('stale'))],
    [2, true]);

  await page.evaluate(() => { document.getElementById('latex').blur(); squigglyShown(); });
  check('showing the window selects the input',
    await page.$eval('#latex', (e) => document.activeElement === e && e.selectionStart === 0 && e.selectionEnd === e.value.length), true);

  await clearLog();
  await page.keyboard.press('Meta+Enter');
  await page.waitForTimeout(700);
  check('⌘Enter copies, then asks the app to close the window',
    [(await log('copyImage')).length, (await log('close')).length], [1, 1]);
  await clearLog();
  await page.keyboard.press('Escape');
  check('Esc asks the app to close the window', (await log('close')).length, 1);

  check('nothing was fetched from anywhere else', offsite.join(' '), '');
  check('no errors along the way', errors.join(' | '), '');

  console.log(`\n${results.filter(Boolean).length}/${results.length} passed`);
  await browser.close();
  if (results.some((ok) => !ok)) process.exitCode = 1;
})().catch((e) => { console.error(e); process.exit(1); });
