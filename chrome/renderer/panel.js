// The renderer: a LaTeX box, a live preview, and buttons that copy or save the
// result as PNG or SVG. The extension's popup loads it only when its Renderer
// tab is opened, so the Typing tab never pays for MathJax; the Mac app's
// renderer window loads it straight away. Its markup is renderer/panel.html,
// and everything it asks of the browser or the app goes through
// renderer/host.js.

import { loadMathJax, knowsCommand, render, standalone, svgText, pngBlob } from "./render.js";
import { allCommands } from "./commands.js";
import { Editor, balanced } from "./editor.js";
import * as history from "./history.js";

const { rendererSettings, tables, host } = globalThis.LaTeXSquiggly;

// Measured by feel in the popup: 150 ms is past the gap between keys in
// ordinary typing, so the preview does not redraw on every key. An error waits
// longer, so an unfinished \frac{1}{ is not flagged while it is being typed.
const RENDER_DELAY = 150;
const ERROR_DELAY = 600;
const CLOSE_DELAY = 400;

const $ = (id) => document.getElementById(id);
const textarea = $("latex");
const preview = $("preview");
const placeholder = $("placeholder");
const errorLine = $("render-error");
const warning = $("render-warning");
const messageLine = $("render-message");
const buttons = ["copy-png", "copy-svg", "download-png", "download-svg"].map($);
const swatches = [...document.querySelectorAll(".swatch[data-colour]")];
const custom = $("custom-colour");
const labelForm = $("label-form");
const labelInput = $("brace-label");
const historyPanel = $("history");
const historyList = $("history-list");

let config;
let editor;
let ready = false;
// The latest render: the SVG when it worked, the reason when it did not.
// shown is the last one that worked, kept on screen while the input is wrong.
let valid = false;
let error = null;
let shown = null;
let pending = false;
let renderTimer = 0;
let errorTimer = 0;
let messageTimer = 0;
let brace = null;

// input is text selected on a page, from the menu item; otherwise the last
// input comes back.
export async function startRenderer({ selectAll, input }) {
  config = await rendererSettings.load();
  if (typeof input === "string") {
    textarea.value = input;
    saveInput();
  } else {
    try {
      const { rendererInput } = await host.get("local", "rendererInput");
      if (typeof rendererInput === "string") textarea.value = rendererInput;
    } catch {
      // Nothing saved, or local storage unavailable: start empty.
    }
  }
  focusSource(selectAll);
  showSettings();
  showShortcuts();

  textarea.addEventListener("input", edited);
  document.addEventListener("keydown", keydown);
  wireButtons();

  host.onChanged(async (changes, area) => {
    if (area !== "sync" || !Object.keys(changes).some((key) => key.startsWith("render"))) return;
    const macrosChanged = "renderMacros" in changes;
    config = await rendererSettings.load();
    showSettings();
    if (macrosChanged) update();
    else draw();
  });

  placeholder.textContent = "Loading the renderer…";
  try {
    await loadMathJax();
  } catch (e) {
    placeholder.textContent = String(e.message ?? e);
    return;
  }
  ready = true;
  placeholder.textContent = "Type LaTeX above to see it rendered.";
  if (historyPanel.open) drawHistory();
  editor = new Editor(textarea, $("suggestions"), { commands: allCommands(tables), knows: knowsCommand });
  update();
  if (!valid && error) showError();
}

function focusSource(selectAll) {
  textarea.focus();
  if (selectAll) textarea.select();
  else textarea.setSelectionRange(textarea.value.length, textarea.value.length);
}

// MARK: Rendering

function saveInput() {
  try {
    host.set("local", { rendererInput: textarea.value }).catch(() => {});
  } catch {
    // Saving the input is a convenience; the editor works without it.
  }
}

function edited() {
  saveInput();
  pending = true;
  clearTimeout(renderTimer);
  clearTimeout(errorTimer);
  renderTimer = setTimeout(update, RENDER_DELAY);
  errorTimer = setTimeout(() => { if (!pending && !valid && error) showError(); }, ERROR_DELAY);
}

function update() {
  pending = false;
  clearTimeout(renderTimer);
  if (!ready) return;
  const source = textarea.value;
  if (source.trim() === "") {
    valid = false;
    error = null;
    shown = null;
    errorLine.hidden = true;
  } else {
    const result = render(source, config.renderMacros);
    valid = !!result.svg;
    error = result.error ?? null;
    // A mistake in the settings' commands breaks every image, and the message
    // alone would point at the input.
    if (error && config.renderMacros.trim() !== "") {
      const own = render("", config.renderMacros);
      if (own.error) error = `In your commands in Image settings: ${own.error}`;
    }
    if (valid) {
      shown = result.svg;
      errorLine.hidden = true;
    }
  }
  draw();
}

function draw() {
  preview.classList.toggle("white", config.renderBackground === "white");
  preview.classList.toggle("transparent", config.renderBackground === "transparent");
  warning.hidden = !(config.renderColour === "#ffffff" && config.renderBackground === "white");
  if (shown) {
    preview.replaceChildren(standalone(shown, imageOptions()).svg);
  } else {
    preview.replaceChildren(placeholder);
  }
  // A previous render stays in view, dimmed, while the input does not render,
  // and nothing can be copied from it.
  preview.classList.toggle("stale", !!shown && !valid);
  for (const button of buttons) button.disabled = !valid;
}

function showError() {
  errorLine.textContent = error;
  errorLine.hidden = false;
}

function flashError() {
  if (!error) return;
  showError();
  errorLine.classList.remove("flash");
  void errorLine.offsetWidth;
  errorLine.classList.add("flash");
}

function say(text) {
  messageLine.textContent = text;
  clearTimeout(messageTimer);
  messageTimer = setTimeout(() => { messageLine.textContent = ""; }, 4000);
}

// The image as it stands, or null after showing why not. A render still
// waiting on its delay is done now, so a copy is never of older input.
function currentImage() {
  if (pending) update();
  if (!valid) {
    flashError();
    return null;
  }
  return standalone(shown, imageOptions());
}

const imageOptions = () => ({
  fontSize: config.renderFontSize,
  padding: config.renderPadding,
  colour: config.renderColour,
});

// MARK: Copying and saving

async function copyPng() {
  const image = currentImage();
  if (!image) return false;
  try {
    // Not awaited: the host needs the copy started inside the click.
    const blob = pngBlob(image, { scale: config.renderScale, background: config.renderBackground });
    await host.copyImage(blob, { width: image.width, height: image.height });
    say("Copied.");
    await remember();
    return true;
  } catch (e) {
    say(`Couldn't copy: ${e.message ?? e}`);
    return false;
  }
}

async function copySvg() {
  const image = currentImage();
  if (!image) return;
  try {
    await host.copyText(svgText(image.svg));
    say("Copied the SVG as text.");
    await remember();
  } catch (e) {
    say(`Couldn't copy: ${e.message ?? e}`);
  }
}

async function download(kind) {
  const image = currentImage();
  if (!image) return;
  const blob = kind === "png"
    ? await pngBlob(image, { scale: config.renderScale, background: config.renderBackground })
    : new Blob([svgText(image.svg)], { type: "image/svg+xml" });
  if (await host.save(blob, `equation.${kind}`)) await remember();
}

// MARK: History

// Kept closed by default and read only when opened, so a long history costs
// nothing when the popup opens. Thumbnails are drawn afresh each time.
async function remember() {
  await history.add(textarea.value);
  if (historyPanel.open) await drawHistory();
}

async function drawHistory() {
  const list = await history.load();
  historyList.replaceChildren();
  $("history-empty").hidden = list.length > 0;
  $("history-clear").hidden = list.length === 0;
  for (const { source } of list) {
    const item = document.createElement("li");
    const entry = document.createElement("button");
    entry.type = "button";
    entry.className = "entry";
    entry.title = source;
    const drawn = ready ? render(source, config.renderMacros) : {};
    if (drawn.svg) {
      entry.append(standalone(drawn.svg, { fontSize: 14, padding: 2, colour: "#000000" }).svg);
    } else {
      const code = document.createElement("code");
      code.textContent = source;
      entry.append(code);
    }
    entry.setAttribute("aria-label", `Load ${source}`);
    entry.addEventListener("click", () => loadEntry(source));
    const remove = document.createElement("button");
    remove.type = "button";
    remove.className = "remove";
    remove.textContent = "✕";
    remove.setAttribute("aria-label", `Remove ${source} from history`);
    remove.addEventListener("click", async () => {
      await history.remove(source);
      await drawHistory();
    });
    item.append(entry, remove);
    historyList.append(item);
  }
}

// Through the editor, so loading an entry is one step of undo.
function loadEntry(source) {
  if (editor) editor.replace(0, textarea.value.length, source);
  else textarea.value = source;
  textarea.focus();
}

// MARK: Keys

async function keydown(event) {
  if (event.key === "Enter" && (event.ctrlKey || event.metaKey) && !event.altKey) {
    event.preventDefault();
    if (!labelForm.hidden) return;
    if (await copyPng()) setTimeout(() => host.close(), CLOSE_DELAY);
    return;
  }
  if (event.key === "Escape" && !event.defaultPrevented) {
    if (!labelForm.hidden) {
      event.preventDefault();
      closeLabelForm();
      return;
    }
    host.close();
  }
}

// MARK: Buttons

function wireButtons() {
  historyPanel.addEventListener("toggle", () => { if (historyPanel.open) drawHistory(); });
  $("history-clear").addEventListener("click", async (event) => {
    event.preventDefault();
    await history.clear();
    await drawHistory();
  });

  $("copy-png").addEventListener("click", copyPng);
  $("copy-svg").addEventListener("click", copySvg);
  $("download-png").addEventListener("click", () => download("png"));
  $("download-svg").addEventListener("click", () => download("svg"));

  for (const option of document.querySelectorAll("[data-background]")) {
    option.addEventListener("click", () => {
      config.renderBackground = option.dataset.background;
      rendererSettings.save({ renderBackground: config.renderBackground }).catch(() => {});
      showSettings();
      draw();
    });
  }

  for (const swatch of swatches) {
    // A mouse click would otherwise take the focus, and with it the selection
    // the colour is meant for.
    swatch.addEventListener("pointerdown", (event) => event.preventDefault());
    swatch.addEventListener("click", () => applyColour(swatch.dataset.colour));
  }
  custom.addEventListener("change", () => applyColour(custom.value.toLowerCase()));

  $("overbrace").addEventListener("pointerdown", (event) => event.preventDefault());
  $("underbrace").addEventListener("pointerdown", (event) => event.preventDefault());
  $("overbrace").addEventListener("click", () => openLabelForm("over"));
  $("underbrace").addEventListener("click", () => openLabelForm("under"));
  labelForm.addEventListener("submit", (event) => {
    event.preventDefault();
    addBrace();
  });
  $("label-cancel").addEventListener("click", closeLabelForm);

  $("image-settings").addEventListener("click", (event) => {
    event.preventDefault();
    host.openSettings();
  });
}

// A selection to wrap, or null after saying why there is none to use.
function wrappable() {
  const selection = editor?.selection();
  if (!selection || selection.text === "") return selection;
  if (!balanced(selection.text)) {
    say("The selection has a brace without its partner, so it can't be wrapped.");
    return null;
  }
  return selection;
}

// With text selected, colours that text in the source with \textcolor, so the
// LaTeX says it too. Without, sets the colour of the whole image.
function applyColour(hex) {
  if (!editor) return;
  const selection = wrappable();
  if (!selection) return;
  if (selection.text !== "") {
    editor.wrap(selection, `\\textcolor${colourArgument(hex)}{`, "}");
    return;
  }
  config.renderColour = hex;
  rendererSettings.save({ renderColour: hex }).catch(() => {});
  showSettings();
  draw();
}

// A name where the swatch has one, and otherwise the RGB model, which both
// MathJax and LaTeX's xcolor understand. (MathJax has no HTML model.)
function colourArgument(hex) {
  const named = swatches.find((s) => s.dataset.colour === hex);
  if (named) return `{${named.dataset.name}}`;
  const [r, g, b] = [1, 3, 5].map((i) => parseInt(hex.slice(i, i + 2), 16));
  return `[RGB]{${r},${g},${b}}`;
}

function openLabelForm(kind) {
  if (!editor) return;
  const selection = wrappable();
  if (!selection) return;
  if (selection.text === "") {
    say(`Select part of the equation first, then click ${kind === "over" ? "Overbrace" : "Underbrace"}.`);
    return;
  }
  brace = { kind, selection };
  $("brace-label-title").textContent = kind === "over" ? "Label above" : "Label below";
  labelInput.value = "";
  labelForm.hidden = false;
  labelInput.focus();
}

function closeLabelForm() {
  labelForm.hidden = true;
  const selection = brace?.selection;
  brace = null;
  textarea.focus();
  if (selection) textarea.setSelectionRange(selection.start, selection.end);
}

function addBrace() {
  if (!brace) return;
  const { kind, selection } = brace;
  const label = labelInput.value.trim();
  const script = kind === "over" ? "^" : "_";
  brace = null;
  labelForm.hidden = true;
  editor.wrap(selection, `\\${kind}brace{`, label === "" ? "}" : `}${script}{\\text{${label}}}`);
}

// MARK: Settings in view

function showSettings() {
  for (const option of document.querySelectorAll("[data-background]")) {
    option.setAttribute("aria-checked", String(option.dataset.background === config.renderBackground));
  }
  const preset = swatches.find((s) => s.dataset.colour === config.renderColour);
  for (const swatch of swatches) swatch.setAttribute("aria-pressed", String(swatch === preset));
  const customSwatch = custom.closest(".swatch");
  customSwatch.classList.toggle("active", !preset);
  if (!preset) {
    custom.value = config.renderColour;
    customSwatch.style.setProperty("--chosen", config.renderColour);
  } else {
    customSwatch.style.removeProperty("--chosen");
  }
}

async function showShortcuts() {
  if (/Mac/.test(navigator.platform)) $("copy-keys").textContent = "⌘Enter";
  try {
    const shortcut = await host.shortcut("open-renderer");
    if (shortcut) {
      $("open-keys").textContent = shortcut;
      $("open-shortcut").hidden = false;
    }
  } catch {
    // No shortcut to show.
  }
}
