const { settings, rendererSettings, tables } = globalThis.LaTeXSquiggly;

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

// MARK: Renderer

const renderFields = {
  renderScale: document.getElementById("render-scale"),
  renderFontSize: document.getElementById("render-font-size"),
  renderPadding: document.getElementById("render-padding"),
  renderBackground: document.getElementById("render-background"),
  renderColour: document.getElementById("render-colour"),
  renderMacros: document.getElementById("render-macros"),
};
const renderSaveError = document.getElementById("render-save-error");

for (const scale of rendererSettings.SCALES) {
  const option = document.createElement("option");
  option.value = String(scale);
  option.textContent = `${scale}×`;
  renderFields.renderScale.append(option);
}

function showRendererSettings(values) {
  for (const [key, field] of Object.entries(renderFields)) {
    // Leave alone what the user is typing in; it is saved as they go.
    if (document.activeElement === field && field.type !== "color") continue;
    field.value = String(values[key]);
  }
}

// Numbers are saved once they make sense, on change, and put back in range.
// The commands are saved shortly after typing stops: sync storage allows 120
// writes a minute, which saving on every key could use up.
async function saveRendererField(key) {
  const field = renderFields[key];
  const cleaned = rendererSettings.clean({ ...rendererSettings.defaults(), [key]: field.value })[key];
  try {
    await rendererSettings.save({ [key]: cleaned });
    renderSaveError.hidden = true;
  } catch (e) {
    // Sync storage holds 8 KB to an item, which only a very long list of
    // commands reaches.
    renderSaveError.hidden = false;
    renderSaveError.textContent = `Couldn't save: ${e.message ?? e}`;
  }
  if (key !== "renderMacros") field.value = String(cleaned);
}

let macrosTimer = 0;
for (const key of Object.keys(renderFields)) {
  const field = renderFields[key];
  if (key === "renderMacros") {
    field.addEventListener("input", () => {
      clearTimeout(macrosTimer);
      macrosTimer = setTimeout(() => saveRendererField(key), 500);
    });
    field.addEventListener("blur", () => {
      clearTimeout(macrosTimer);
      saveRendererField(key);
    });
  } else {
    field.addEventListener("change", () => saveRendererField(key));
  }
}
document.getElementById("renderer-form").addEventListener("submit", (event) => event.preventDefault());

showRendererSettings(await rendererSettings.load());

const [renderCommand] = (await chrome.commands.getAll()).filter((c) => c.name === "open-renderer");
if (renderCommand?.shortcut) {
  document.getElementById("renderer-shortcut").textContent =
    ` ${renderCommand.shortcut} opens it from any page.`;
}

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
  showRendererSettings(await rendererSettings.load());
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
