// node store-shots.mjs <out dir> [name ...] -> 1320x2868 PNGs of store.html's shots
import { chromium } from "/opt/node-tools/node_modules/playwright/index.mjs";
import path from "node:path";
import { fileURLToPath } from "node:url";
const dir = path.dirname(fileURLToPath(import.meta.url));
const [out, ...names] = process.argv.slice(2);
const all = ["iphone-1-type", "iphone-2-see", "iphone-3-copy", "iphone-4-symbols", "iphone-5-share", "iphone-6-messages", "imessage-1-write"];
const b = await chromium.launch({ args: ["--allow-file-access-from-files"] });
for (const name of names.length ? names : all) {
  const p = await b.newPage({ viewport: { width: 1320, height: 2868 }, deviceScaleFactor: 1 });
  p.on("pageerror", (e) => console.error(name, e.message));
  await p.goto(`file://${dir}/store.html?shot=${name}`);
  await p.waitForFunction(() => window.READY === true, null, { timeout: 60000 });
  await p.waitForTimeout(300);
  await p.screenshot({ path: `${out}/${name}.png` });
  await p.close();
  console.log(name);
}
await b.close();
