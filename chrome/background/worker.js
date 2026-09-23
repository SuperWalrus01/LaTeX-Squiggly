// The extension's background worker. It holds no state of its own and does four
// small jobs:
//
// - opens the settings page once, on first install, so the user reads what the
//   extension does with their typing inside the extension itself;
// - keeps the toolbar icon honest: orange where it is converting, grey with a
//   strike where it is not, the same two states as the desktop apps' icons;
// - pauses and resumes everything from a keyboard shortcut;
// - relays messages between the frames of a Google Docs tab, which cannot reach
//   each other directly; see content/docs.js.
//
// None of it needs a permission beyond storage.

importScripts("../shared/settings.js");

const { settings } = globalThis.LaTeXSquiggly;

// MARK: First install

chrome.runtime.onInstalled.addListener(({ reason }) => {
  showPauseState();
  if (reason !== chrome.runtime.OnInstalledReason.INSTALL) return;
  chrome.tabs.create({ url: chrome.runtime.getURL("options/options.html#welcome") });
});

// MARK: The toolbar icon

const ICONS = {
  on: { 16: "/icons/icon-16.png", 32: "/icons/icon-32.png" },
  off: { 16: "/icons/icon-off-16.png", 32: "/icons/icon-off-32.png" },
};

// Two states, not three. The icon answers "is it converting here", which has
// the same answer whether the extension is paused or staying quiet on
// Overleaf; the tooltip and the popup say which.
function showState(on, title, tabId) {
  const where = tabId === undefined ? {} : { tabId };
  chrome.action.setIcon({ ...where, path: on ? ICONS.on : ICONS.off }).catch(() => {});
  chrome.action.setTitle({ ...where, title }).catch(() => {});
}

// The default for every tab, which a page's own report then overrides. Pages
// the extension cannot run on, such as Chrome's own, keep this.
async function showPauseState() {
  const { enabled } = await settings.load();
  showState(enabled, enabled ? "LaTeX Squiggly" : "LaTeX Squiggly: paused");
}

chrome.runtime.onStartup.addListener(showPauseState);
chrome.storage.onChanged.addListener((changes, area) => {
  if (area === "sync" && "enabled" in changes) showPauseState();
});

// MARK: The shortcut

// Declared in the manifest as toggle-conversion, Alt+Shift+L unless the user
// has changed it at chrome://extensions/shortcuts. Every page hears about the
// change through storage, and the one in front says so.
async function toggleConversion() {
  const { enabled } = await settings.load();
  await settings.save({ enabled: !enabled });
}

chrome.commands.onCommand.addListener((command) => {
  if (command === "toggle-conversion") toggleConversion();
});

// MARK: Messages from pages

// Google Docs mode: a click in the top frame must reach the input frame, and a
// notice from the input frame must reach the top frame, where it can be seen.
// Sent to every frame of the tab it came from; each frame keeps what is meant
// for it.
const RELAYED = new Set(["docs-forget", "docs-notice"]);

chrome.runtime.onMessage.addListener((message, sender) => {
  if (!sender.tab) return;
  if (message?.type === "state" && sender.frameId === 0) {
    showState(message.on === true, String(message.title ?? "LaTeX Squiggly"), sender.tab.id);
    return;
  }
  if (RELAYED.has(message?.type)) chrome.tabs.sendMessage(sender.tab.id, message).catch(() => {});
});
