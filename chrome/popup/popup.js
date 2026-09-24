const { settings } = globalThis.LaTeXSquiggly;

const enabled = document.getElementById("enabled");
const siteEnabled = document.getElementById("site-enabled");
const hostLabel = document.getElementById("host");
const note = document.getElementById("site-note");
const docsRow = document.getElementById("docs-row");
const googleDocs = document.getElementById("google-docs");

// MARK: Tabs

// Typing is the switches for the conversion as you type; Renderer is the
// LaTeX to image editor, in renderer/, loaded only when it is opened. The
// popup reopens on the tab last used, and on Renderer when the renderer's
// shortcut opened it, which the background worker says through session
// storage (#renderer in the address does the same, for tests).
const TABS = ["typing", "renderer"];
let rendererStarted = false;

function showTab(name, { selectAll = false } = {}) {
  for (const tab of TABS) {
    document.getElementById(`tab-${tab}`).setAttribute("aria-selected", String(tab === name));
    document.getElementById(`tab-${tab}`).tabIndex = tab === name ? 0 : -1;
    document.getElementById(tab).hidden = tab !== name;
  }
  document.body.classList.toggle("wide", name === "renderer");
  chrome.storage.local.set({ popupTab: name }).catch(() => {});
  if (name === "renderer" && !rendererStarted) {
    rendererStarted = true;
    import("../renderer/panel.js").then((panel) => panel.startRenderer({ selectAll }));
  } else if (name === "renderer") {
    document.getElementById("latex").focus();
  }
}

async function firstTab() {
  if (location.hash === "#renderer") return { tab: "renderer" };
  try {
    const { openRenderer } = await chrome.storage.session.get("openRenderer");
    if (openRenderer) {
      await chrome.storage.session.remove("openRenderer");
      return { tab: "renderer", selectAll: true };
    }
  } catch {
    // No session storage: fall through to the last tab used.
  }
  try {
    const { popupTab } = await chrome.storage.local.get("popupTab");
    if (TABS.includes(popupTab)) return { tab: popupTab };
  } catch {
    // Nothing remembered.
  }
  return { tab: "typing" };
}

for (const tab of TABS) {
  const button = document.getElementById(`tab-${tab}`);
  button.addEventListener("click", () => showTab(tab));
  button.addEventListener("keydown", (event) => {
    if (event.key !== "ArrowLeft" && event.key !== "ArrowRight") return;
    const other = TABS[(TABS.indexOf(tab) + 1) % TABS.length];
    showTab(other);
    document.getElementById(`tab-${other}`).focus();
  });
}

const first = await firstTab();
showTab(first.tab, { selectAll: first.selectAll });

// MARK: Typing

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

// The Google Docs switch, offered where it matters: in a Google Doc, which is
// where a problem with it would be noticed.
googleDocs.addEventListener("change", async () => {
  config.googleDocs = googleDocs.checked;
  await settings.save({ googleDocs: googleDocs.checked });
});

// The pause shortcut as Chrome has it, which the user may have changed.
const [command] = (await chrome.commands.getAll()).filter((c) => c.name === "toggle-conversion");
if (command?.shortcut) {
  document.getElementById("shortcut-keys").textContent = command.shortcut;
  document.getElementById("shortcut").hidden = false;
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
  const inDocs = !!status?.host && settings.hostMatches(status.host, "docs.google.com");
  docsRow.hidden = !inDocs;
  googleDocs.checked = config.googleDocs;
  googleDocs.disabled = !config.enabled;

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
