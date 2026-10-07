// node capture.mjs <portrait|landscape> stills t1,t2,...   -> stills/<o>-<t>.png
// node capture.mjs <portrait|landscape> video              -> out/<o>-silent.mp4 + out/events.json
import { chromium } from "/opt/node-tools/node_modules/playwright/index.mjs";
import { spawn } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const dir = path.dirname(fileURLToPath(import.meta.url));
const [orientation, mode, times] = process.argv.slice(2);
const [W, H] = orientation === "landscape" ? [1920, 1080] : [1080, 1920];
const FPS = 30;

const browser = await chromium.launch({ args: ["--allow-file-access-from-files", "--font-render-hinting=none"] });
const page = await browser.newPage({ viewport: { width: W, height: H }, deviceScaleFactor: 1 });
page.on("pageerror", (e) => console.error("pageerror:", e.message));
page.on("console", (m) => { if (m.type() === "error") console.error("console:", m.text()); });
await page.goto(`file://${dir}/index.html?o=${orientation}`);
await page.waitForFunction(() => window.READY === true, null, { timeout: 60000 });
const duration = await page.evaluate(() => window.DURATION);
console.log(`duration ${duration.toFixed(2)} s`);

if (mode === "stills") {
  fs.mkdirSync(`${dir}/stills`, { recursive: true });
  for (const t of times.split(",").map(Number)) {
    await page.evaluate((t) => render(t), t);
    await page.screenshot({ path: `${dir}/stills/${orientation}-${t}.png` });
  }
} else {
  fs.mkdirSync(`${dir}/out`, { recursive: true });
  fs.writeFileSync(`${dir}/out/events.json`, JSON.stringify(await page.evaluate(() => ({ duration: window.DURATION, events: window.EVENTS })), null, 1));
  const ff = spawn("ffmpeg", ["-v", "error", "-y", "-f", "image2pipe", "-framerate", String(FPS), "-c:v", "mjpeg", "-i", "-",
    "-c:v", "libx264", "-preset", "slow", "-crf", "18", "-pix_fmt", "yuv420p", "-movflags", "+faststart",
    `${dir}/out/${orientation}-silent.mp4`], { stdio: ["pipe", "inherit", "inherit"] });
  const frames = Math.ceil(duration * FPS);
  for (let i = 0; i < frames; i++) {
    await page.evaluate((t) => render(t), i / FPS);
    const buf = await page.screenshot({ type: "jpeg", quality: 95 });
    if (!ff.stdin.write(buf)) await new Promise((r) => ff.stdin.once("drain", r));
    if (i % 150 === 0) console.log(`frame ${i}/${frames}`);
  }
  ff.stdin.end();
  await new Promise((r) => ff.on("close", r));
}
await browser.close();
