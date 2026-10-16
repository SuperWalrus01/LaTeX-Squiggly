// Runs the Android app's renderer page in Chromium, with a stand-in for the
// app: the same files the app serves, laid out by android/app/web/files.json,
// and a fake of the SquigglyAndroid bridge that answers as RendererBridge.kt
// does and records what it was asked. It proves the page's side of the
// bridge; the app's side can only be tried on Android.
//
// Needs Playwright, as chrome/test/browser.cjs does:
//   NODE_PATH=/tmp/squiggly-test/node_modules node chrome/test/android-window.cjs

const { chromium } = require('playwright');
const fs = require('fs');
const path = require('path');

const root = path.join(__dirname, '..', '..');
const { files } = JSON.parse(fs.readFileSync(path.join(root, 'android/app/web/files.json')));

// The file behind a served path, found the way the app's build lays it out.
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

// The app's side of the bridge. Its methods are synchronous and take and
// return strings, as @JavascriptInterface methods do. Saving answers later,
// through squigglyAndroidReply, as the app does once a file is chosen.
const fakeApp = (input) => `
  window.appLog = [];
  window.appStore = { sync: {}, local: {} };
  window.SquigglyAndroid = {
    initialInput: () => ${JSON.stringify(JSON.stringify(input))},
    get(area, names) {
      window.appLog.push({ op: 'get', area });
      const store = window.appStore[area];
      return JSON.stringify(Object.fromEntries(JSON.parse(names).filter((k) => k in store).map((k) => [k, store[k]])));
    },
    set(area, items) {
      Object.assign(window.appStore[area], JSON.parse(items));
    },
    copyImage(png, width, height) {
      window.appLog.push({ op: 'copyImage', png, width, height });
      return '';
    },
    copyText(text) {
      window.appLog.push({ op: 'copyText', text });
      return '';
    },
    save(id, name, type, data) {
      window.appLog.push({ op: 'save', id, name, type, data });
      setTimeout(() => globalThis.squigglyAndroidReply(id, true, null), 10);
    },
    close() {
      window.appLog.push({ op: 'close' });
    },
  };
`;

(async () => {
  const browser = await chromium.launch({ channel: process.env.CHROMIUM_PATH ? undefined : 'chromium',
    executablePath: process.env.CHROMIUM_PATH || undefined });

  const results = [];
  const check = (name, got, want) => {
    const ok = Array.isArray(want) ? JSON.stringify(got) === JSON.stringify(want) : got === want;
    results.push(ok);
    console.log(`${ok ? 'PASS' : 'FAIL'}  ${name}${ok ? '' : `\n      want ${JSON.stringify(want)}\n      got  ${JSON.stringify(got)}`}`);
  };

  // The phone's page, at a phone's size, at the address the app serves it from.
  async function open(input) {
    const page = await browser.newPage();
    await page.setViewportSize({ width: 390, height: 800 });
    await page.addInitScript(fakeApp(input));
    page.offsite = [];
    page.errors = [];
    page.on('pageerror', (e) => page.errors.push(e.message));
    await page.route('**/*', (route) => {
      const url = new URL(route.request().url());
      if (url.hostname !== 'appassets.androidplatform.net') {
        page.offsite.push(url.href);
        return route.abort();
      }
      const file = source(url.pathname.slice(1) || 'index.html');
      if (!file || !fs.existsSync(file)) return route.fulfill({ status: 404, body: '' });
      return route.fulfill({ contentType: TYPES[path.extname(file)] ?? 'application/octet-stream', body: fs.readFileSync(file) });
    });
    await page.goto('https://appassets.androidplatform.net/index.html');
    await page.waitForFunction(() => document.body.dataset.ready === 'true' && !!globalThis.MathJax?.startup?.document);
    return page;
  }

  const page = await open('\\frac{a}{b}');
  const log = (op) => page.evaluate((op) => window.appLog.filter((m) => m.op === op), op);
  const clearLog = () => page.evaluate(() => { window.appLog = []; });

  check('the page starts with no errors', page.errors.join(' | '), '');
  check('the renderer is the host the app provides', await page.evaluate(() => LaTeXSquiggly.host.kind), 'android');
  check('it starts with the LaTeX the app passed', await page.inputValue('#latex'), '\\frac{a}{b}');
  await page.waitForTimeout(400);
  check('it renders', await page.$eval('#preview', (e) => !!e.querySelector(':scope > svg')), true);
  check('the input is kept, in the app\'s local area',
    await page.evaluate(() => window.appStore.local.rendererInput), '\\frac{a}{b}');
  check('the keyboard shortcut line is hidden on a phone',
    await page.$eval('#copy-keys', (e) => e.offsetParent === null), true);

  await clearLog();
  await page.click('#copy-png');
  await page.waitForFunction(() => window.appLog.some((m) => m.op === 'copyImage'), null, { timeout: 5000 })
    .catch(() => {});
  const [copy] = await log('copyImage');
  const width = await page.$eval('#preview > svg', (e) => parseFloat(e.getAttribute('width')));
  check('Copy PNG hands the app a PNG, with its size',
    [Buffer.from(copy?.png ?? '', 'base64').subarray(1, 4).toString(), copy?.width === width, copy?.height > 0],
    ['PNG', true, true]);

  await clearLog();
  await page.click('#copy-svg');
  await page.waitForTimeout(200);
  check('Copy SVG hands the app the markup', ((await log('copyText'))[0]?.text ?? '').startsWith('<svg'), true);

  await clearLog();
  await page.click('#download-png');
  await page.waitForFunction(() => window.appLog.some((m) => m.op === 'save'), null, { timeout: 5000 })
    .catch(() => {});
  const [save] = await log('save');
  check('Download PNG asks the app to save it, as a PNG',
    [save?.name, save?.type, Buffer.from(save?.data ?? '', 'base64').subarray(1, 4).toString()],
    ['equation.png', 'image/png', 'PNG']);
  await page.waitForTimeout(100);
  check('...and the answer reaches the page, which remembers it in the history',
    await page.evaluate(() => window.appStore.local.rendererHistory?.[0]?.source), '\\frac{a}{b}');

  await page.click('[data-background="transparent"]');
  check('the background switch is saved in the app\'s sync area',
    await page.evaluate(() => window.appStore.sync.renderBackground), 'transparent');

  await page.click('#image-settings');
  check('Image settings opens the settings below', await page.$eval('#settings', (e) => e.open), true);

  await clearLog();
  await page.focus('#latex');
  await page.keyboard.press('Escape');
  check('Esc asks the app to close', (await log('close')).length, 1);

  check('nothing was fetched from anywhere else', page.offsite.join(' '), '');
  check('no errors along the way', page.errors.join(' | '), '');
  check('the page fits the phone, with nothing to scroll sideways',
    await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth), true);

  // Opened from the app itself: no input, so the last one comes back.
  const fresh = await open(null);
  check('with no LaTeX passed, it opens empty and without errors',
    [await fresh.inputValue('#latex'), fresh.errors.join(' | ')], ['', '']);

  console.log(`\n${results.filter(Boolean).length}/${results.length} passed`);
  await browser.close();
  if (results.some((ok) => !ok)) process.exitCode = 1;
})().catch((e) => { console.error(e); process.exit(1); });
