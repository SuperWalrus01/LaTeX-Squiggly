// Opens the settings page once, on first install, so the user reads what the
// extension does with their typing inside the extension itself, not only on
// the store listing. Updates do not reopen it.
//
// It also relays messages between the frames of a Google Docs tab, which
// cannot reach each other directly; see content/docs.js.

chrome.runtime.onInstalled.addListener(({ reason }) => {
  if (reason !== chrome.runtime.OnInstalledReason.INSTALL) return;
  chrome.tabs.create({ url: chrome.runtime.getURL("options/options.html#welcome") });
});

// Google Docs mode: a click in the top frame must reach the input frame, and a
// notice from the input frame must reach the top frame, where it can be seen.
// Sent to every frame of the tab it came from; each frame keeps what is meant
// for it. No permission is needed to message the extension's own scripts.
const RELAYED = new Set(["docs-forget", "docs-notice"]);

chrome.runtime.onMessage.addListener((message, sender) => {
  if (!sender.tab || !RELAYED.has(message?.type)) return;
  chrome.tabs.sendMessage(sender.tab.id, message).catch(() => {});
});
