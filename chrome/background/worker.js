// Opens the settings page once, on first install, so the user reads what the
// extension does with their typing inside the extension itself, not only on
// the store listing. Updates do not reopen it.

chrome.runtime.onInstalled.addListener(({ reason }) => {
  if (reason !== chrome.runtime.OnInstalledReason.INSTALL) return;
  chrome.tabs.create({ url: chrome.runtime.getURL("options/options.html#welcome") });
});
