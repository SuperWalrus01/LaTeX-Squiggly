// What the renderer needs from wherever it runs: storage, the clipboard,
// saving a file, closing, and its own files' addresses. The renderer runs in
// three places, the extension's popup and the macOS and Windows apps'
// renderer windows, and this is the only file that knows which.
//
// In the extension it is Chrome's own APIs. In the apps the page is in a web
// view, and each call is a message to the app, which answers it: see
// Sources/LaTeXSquigglyApp/RendererWindow.swift and
// windows/LaTeXSquiggly.App/Platform/RendererWindow.cs for the other side.
//
// A classic script, not a module, so the classic renderer/settings.js can use
// it too.

(() => {
  const ns = (globalThis.LaTeXSquiggly ??= {});
  const listeners = [];

  const bridge = globalThis.webkit?.messageHandlers?.squiggly;

  // WebView2 has no message that returns a value, so each message carries an
  // id and the app's answer comes back as a message with the same id.
  const webview = bridge ? undefined : globalThis.chrome?.webview;
  const pending = new Map();
  let nextId = 0;
  webview?.addEventListener("message", (event) => {
    const { id, result, error } = event.data ?? {};
    const waiting = pending.get(id);
    if (!waiting) return;
    pending.delete(id);
    if (error) waiting.reject(new Error(error));
    else waiting.resolve(result ?? null);
  });

  // One message to the app, answered by a promise, on either platform.
  function call(message) {
    if (bridge) return bridge.postMessage(message);
    return new Promise((resolve, reject) => {
      const id = ++nextId;
      pending.set(id, { resolve, reject });
      webview.postMessage({ ...message, id });
    });
  }

  // chrome.storage.get's three forms: a key, a list of keys, or an object of
  // defaults that stored values replace.
  function wanted(keys) {
    if (typeof keys === "string") return { names: [keys], defaults: {} };
    if (Array.isArray(keys)) return { names: keys, defaults: {} };
    return { names: Object.keys(keys), defaults: keys };
  }

  async function base64(blob) {
    const url = await new Promise((resolve, reject) => {
      const reader = new FileReader();
      reader.onload = () => resolve(reader.result);
      reader.onerror = () => reject(reader.error);
      reader.readAsDataURL(blob);
    });
    return url.slice(url.indexOf(",") + 1);
  }

  const app = {
    kind: bridge ? "mac" : "windows",
    url: (path) => new URL(`/${path}`, location.href).href,
    async get(area, keys) {
      const { names, defaults } = wanted(keys);
      const stored = await call({ op: "get", area, keys: names });
      return { ...defaults, ...stored };
    },
    async set(area, items) {
      await call({ op: "set", area, items });
      const changes = Object.fromEntries(Object.entries(items).map(([k, v]) => [k, { newValue: v }]));
      for (const listener of listeners) listener(changes, area);
    },
    onChanged: (listener) => listeners.push(listener),
    shortcut: (name) => call({ op: "shortcut", name }),
    // The app keeps the settings in the same window, so there is nowhere else
    // to go: the page opens its own settings section.
    openSettings: () => document.dispatchEvent(new Event("squiggly-open-settings")),
    close: () => call({ op: "close" }),
    // The size goes with the PNG so the app can say it on the clipboard: a
    // 3x image then pastes at the size it was previewed, not three times it.
    async copyImage(blob, { width, height }) {
      await call({ op: "copyImage", png: await base64(await blob), width, height });
    },
    copyText: (text) => call({ op: "copyText", text }),
    async save(blob, name) {
      return call({ op: "save", name, data: await base64(blob) });
    },
  };

  const chromeHost = {
    kind: "chrome",
    url: (path) => chrome.runtime.getURL(path),
    get: (area, keys) => chrome.storage[area].get(keys),
    set: (area, items) => chrome.storage[area].set(items),
    onChanged: (listener) => chrome.storage.onChanged.addListener(listener),
    async shortcut(name) {
      const [command] = (await chrome.commands.getAll()).filter((c) => c.name === name);
      return command?.shortcut || null;
    },
    openSettings() {
      chrome.tabs.create({ url: chrome.runtime.getURL("options/options.html#renderer") });
      window.close();
    },
    close: () => window.close(),
    // The blob goes in as a promise, so the write starts inside the click,
    // while the page still has the user's permission to use the clipboard.
    // Chrome re-encodes the PNG and drops any size in it, so the size is unused.
    copyImage: (blob) => navigator.clipboard.write([new ClipboardItem({ "image/png": blob })]),
    copyText: (text) => navigator.clipboard.writeText(text),
    async save(blob, name) {
      const url = URL.createObjectURL(blob);
      const link = document.createElement("a");
      link.href = url;
      link.download = name;
      link.click();
      setTimeout(() => URL.revokeObjectURL(url), 60_000);
      return true;
    },
  };

  ns.host = bridge || webview ? app : chromeHost;
})();
