const { settings } = globalThis.LaTeXSquiggly;

const enabled = document.getElementById("enabled");
const siteEnabled = document.getElementById("site-enabled");
const hostLabel = document.getElementById("host");
const note = document.getElementById("site-note");

let config = await settings.load();
let status = null;

enabled.checked = config.enabled;
enabled.addEventListener("change", async () => {
  await settings.save({ enabled: enabled.checked });
  config.enabled = enabled.checked;
  render();
});

document.getElementById("options").addEventListener("click", (event) => {
  event.preventDefault();
  chrome.runtime.openOptionsPage();
  window.close();
});

// The page reports its own host, so the popup needs no permission to read the
// tab's address. A page with no script in it is one Chrome keeps extensions out
// of, or one opened before the extension was installed.
try {
  const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
  status = await chrome.tabs.sendMessage(tab.id, { type: "status" });
} catch {
  status = null;
}

siteEnabled.addEventListener("change", async () => {
  if (!status) return;
  let sites = config.excludedSites;
  if (siteEnabled.checked) {
    // Remove the rule that matched, which may be a parent domain: turning
    // conversion back on for fr.overleaf.com removes overleaf.com.
    sites = sites.filter((site) => site !== status.excludedBy);
    status.excludedBy = null;
  } else {
    const host = settings.normalisedHost(status.host) ?? status.host;
    sites = [...new Set([...sites, host])].sort();
    status.excludedBy = host;
  }
  config.excludedSites = sites;
  await settings.save({ excludedSites: sites });
  render();
});

function render() {
  if (!status || !status.host) {
    siteEnabled.checked = false;
    siteEnabled.disabled = true;
    hostLabel.textContent = "Not available on this page";
    note.hidden = false;
    note.textContent = "Chrome keeps extensions out of its own pages and the Web Store. " +
      "On any other page, reloading it will start LaTeX Squiggly.";
    return;
  }
  hostLabel.textContent = status.host;
  siteEnabled.checked = status.excludedBy === null;
  siteEnabled.disabled = !config.enabled;
  const inherited = status.excludedBy !== null && status.excludedBy !== settings.normalisedHost(status.host);
  note.hidden = !inherited;
  if (inherited) {
    note.textContent = `Off because of the rule for ${status.excludedBy}. Turning it on removes that rule.`;
  }
}

render();
