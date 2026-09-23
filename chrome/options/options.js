const { settings, tables } = globalThis.LaTeXSquiggly;

const enabled = document.getElementById("enabled");
const notices = document.getElementById("notices");
const googleDocs = document.getElementById("google-docs");
const siteList = document.getElementById("sites");
const addForm = document.getElementById("add-form");
const addInput = document.getElementById("add-site");
const addError = document.getElementById("add-error");
const search = document.getElementById("search");
const count = document.getElementById("count");
const symbolsRoot = document.getElementById("symbols");

let config = await settings.load();

document.getElementById("version").textContent = `Version ${chrome.runtime.getManifest().version}`;

// MARK: Welcome

// Opened by the background worker on first install.
const welcome = document.getElementById("welcome");
if (location.hash === "#welcome") welcome.hidden = false;
document.getElementById("welcome-done").addEventListener("click", () => {
  welcome.hidden = true;
  history.replaceState(null, "", location.pathname);
});

// MARK: The shortcut

// As Chrome has it, which the user may have changed or cleared.
const [command] = (await chrome.commands.getAll()).filter((c) => c.name === "toggle-conversion");
if (command?.shortcut) {
  document.getElementById("shortcut-hint").textContent =
    ` ${command.shortcut} does the same from any page; change it at chrome://extensions/shortcuts.`;
  document.getElementById("welcome-shortcut").textContent = command.shortcut;
} else {
  document.getElementById("welcome-shortcut").textContent = "A keyboard shortcut, set at chrome://extensions/shortcuts,";
}

// MARK: General

enabled.checked = config.enabled;
notices.checked = config.showNotices;
googleDocs.checked = config.googleDocs;
enabled.addEventListener("change", () => settings.save({ enabled: enabled.checked }));
notices.addEventListener("change", () => settings.save({ showNotices: notices.checked }));
googleDocs.addEventListener("change", () => settings.save({ googleDocs: googleDocs.checked }));

// MARK: Sites

async function saveSites(sites) {
  config.excludedSites = [...new Set(sites)].sort();
  await settings.save({ excludedSites: config.excludedSites });
  renderSites();
}

function renderSites() {
  siteList.replaceChildren();
  if (config.excludedSites.length === 0) {
    const empty = document.createElement("li");
    empty.className = "empty";
    empty.textContent = "No sites. LaTeX Squiggly converts everywhere.";
    siteList.append(empty);
    return;
  }
  for (const site of config.excludedSites) {
    const item = document.createElement("li");
    const name = document.createElement("span");
    name.textContent = site;
    const remove = document.createElement("button");
    remove.type = "button";
    remove.className = "remove";
    remove.textContent = "Remove";
    remove.setAttribute("aria-label", `Remove ${site}`);
    remove.addEventListener("click", () => saveSites(config.excludedSites.filter((s) => s !== site)));
    item.append(name, remove);
    siteList.append(item);
  }
}

addForm.addEventListener("submit", async (event) => {
  event.preventDefault();
  const host = settings.normalisedHost(addInput.value);
  if (host === null) {
    addError.hidden = false;
    addError.textContent = "That doesn't look like a site. Try something like overleaf.com.";
    return;
  }
  addError.hidden = true;
  addInput.value = "";
  await saveSites([...config.excludedSites, host]);
});

document.getElementById("restore").addEventListener("click", () =>
  saveSites([...config.excludedSites, ...settings.DEFAULT_SITES]));

// Another window, or the popup, may change the same settings.
chrome.storage.onChanged.addListener(async (_, area) => {
  if (area !== "sync") return;
  config = await settings.load();
  enabled.checked = config.enabled;
  notices.checked = config.showNotices;
  googleDocs.checked = config.googleDocs;
  renderSites();
});

renderSites();

// MARK: Symbols

const entries = tables.entries;

function renderSymbols() {
  const query = search.value.trim().toLowerCase().replace(/^\\/, "");
  const matching = entries.filter((e) =>
    query === "" ||
    e.command.toLowerCase().includes(query) ||
    e.unicodeName.toLowerCase().includes(query) ||
    e.category.toLowerCase().includes(query) ||
    e.glyph === query);

  symbolsRoot.replaceChildren();
  const groups = new Map();
  for (const entry of matching) {
    if (!groups.has(entry.category)) groups.set(entry.category, []);
    groups.get(entry.category).push(entry);
  }
  for (const [category, items] of groups) {
    const heading = document.createElement("h3");
    heading.textContent = category;
    const grid = document.createElement("div");
    grid.className = "grid";
    for (const entry of items) {
      const cell = document.createElement("div");
      cell.className = "symbol";
      cell.title = entry.unicodeName.toLowerCase();
      const glyph = document.createElement("span");
      glyph.className = "glyph";
      glyph.textContent = entry.glyph;
      const command = document.createElement("span");
      command.className = "command";
      command.textContent = "\\" + entry.command;
      cell.append(glyph, command);
      grid.append(cell);
    }
    symbolsRoot.append(heading, grid);
  }
  count.textContent = query === ""
    ? `${entries.length} symbols`
    : `${matching.length} of ${entries.length} symbols`;
}

search.addEventListener("input", renderSymbols);
renderSymbols();
