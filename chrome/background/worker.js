// The extension's background worker. It holds no state of its own and does four
// small jobs:
//
// - opens the settings page once, on first install, so the user reads what the
//   extension does with their typing inside the extension itself;
// - keeps the toolbar icon honest: orange where it is converting, grey with a
//   strike where it is not, the same two states as the desktop apps' icons;
// - pauses and resumes everything from a keyboard shortcut;
// - opens the popup on its Renderer tab from another shortcut, and from the
//   "Render selection as image" menu item on selected text;
// - relays messages between the frames of a Google Docs tab, which cannot reach
//   each other directly; see content/docs.js.
//
// None of it needs a permission beyond storage, and contextMenus for the menu
// item, which asks the user for nothing: Chrome shows no warning for it.

importScripts("../shared/settings.js", "../renderer/delimiters.js");

const { settings } = globalThis.LaTeXSquiggly;

// MARK: First install

chrome.runtime.onInstalled.addListener(({ reason }) => {
  showPauseState();
  addMenuItem();
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
//
// The tab may be gone by the time this runs: closed at once, or a page Chrome
// prerendered and never showed. Reading lastError in a callback is what tells
// Chrome the failure was expected. setIcon logs one to the extensions page
// even when its promise is caught.
function showState(on, title, tabId) {
  const where = tabId === undefined ? {} : { tabId };
  const ignoreError = () => void chrome.runtime.lastError;
  chrome.action.setIcon({ ...where, path: on ? ICONS.on : ICONS.off }, ignoreError);
  chrome.action.setTitle({ ...where, title }, ignoreError);
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

// Declared as open-renderer, Alt+Shift+E unless changed. Not Alt+Shift+R,
// which Chrome 153 keeps for itself and leaves unassigned; see the check in
// chrome/test/browser.cjs. The popup reads the
// flag to open on the Renderer tab with its text selected, ready to be typed
// over, or with the text it is given in place of it. action.openPopup()
// arrived for every extension in Chrome 127; before that, and when there is
// no browser window to anchor it to, the popup's page opens in a small window
// of its own instead.
async function openRenderer(input) {
  await chrome.storage.session.set({
    openRenderer: true,
    ...(typeof input === "string" ? { rendererSelection: input } : {}),
  });
  try {
    await chrome.action.openPopup();
  } catch {
    await chrome.windows.create({
      url: chrome.runtime.getURL("popup/popup.html"),
      type: "popup",
      width: 520,
      height: 640,
    });
  }
}

chrome.commands.onCommand.addListener((command) => {
  if (command === "toggle-conversion") toggleConversion();
  if (command === "open-renderer") openRenderer();
});

// MARK: The menu item

// Selected text, straight into the renderer. Chrome hands over the selection
// with the click, so no page is read and no page permission is needed. The
// renderer does the copying: a menu click is not a click in a page, and does
// not let the extension write an image to the clipboard.
const MENU_ITEM = "render-selection";

// Items outlive the worker, so they are made once, on install and update.
function addMenuItem() {
  chrome.contextMenus.removeAll(() => {
    chrome.contextMenus.create({
      id: MENU_ITEM,
      title: "Render selection as image",
      contexts: ["selection"],
    });
  });
}

function renderSelection(text) {
  return openRenderer(globalThis.LaTeXSquiggly.stripDelimiters(text));
}

chrome.contextMenus.onClicked.addListener((info) => {
  if (info.menuItemId === MENU_ITEM) renderSelection(info.selectionText ?? "");
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
