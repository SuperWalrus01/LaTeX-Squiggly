// TEMPORARY: which Alt+Shift keys the newest Chromium assigns to an
// extension's commands. Removed once the renderer's shortcut is chosen.
const { chromium } = require('playwright');
const fs = require('fs');
const os = require('os');
const path = require('path');

const KEYS = ['E', 'K', 'M', 'Y', 'U', 'O', 'P', 'J', 'D', 'X', 'G', 'R'];
(async () => {
  const dirs = [];
  for (let i = 0; i < KEYS.length; i += 4) {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'probe-'));
    const commands = {};
    for (const key of KEYS.slice(i, i + 4)) {
      commands[`key-${key}`] = { suggested_key: { default: `Alt+Shift+${key}` }, description: key };
    }
    fs.writeFileSync(path.join(dir, 'manifest.json'), JSON.stringify({
      manifest_version: 3, name: `probe ${i}`, version: '1', commands, background: { service_worker: 'w.js' } }));
    fs.writeFileSync(path.join(dir, 'w.js'), '');
    dirs.push(dir);
  }
  const context = await chromium.launchPersistentContext('', { channel: 'chromium', headless: true,
    args: [`--disable-extensions-except=${dirs.join(',')}`, `--load-extension=${dirs.join(',')}`] });
  await new Promise((r) => setTimeout(r, 2000));
  const version = context.browser()?.version() ?? '';
  for (const sw of context.serviceWorkers()) {
    const got = await sw.evaluate(async () => (await chrome.commands.getAll()).map((c) => `${c.description}=${c.shortcut || '-'}`));
    console.log(`probe ${version}: ${got.join(' ')}`);
  }
  console.log('user agent:', await (await context.newPage()).evaluate(() => navigator.userAgent));
  await context.close();
})().catch((e) => { console.error(e); process.exit(1); });
