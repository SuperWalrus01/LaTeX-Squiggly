// LaTeX to SVG and PNG, with MathJax, for the popup's renderer. Runs only in
// extension pages: MathJax is never loaded into a web page.
//
// MathJax is loaded on first use, from the copy in renderer/mathjax/ that
// scripts/fetch-mathjax.sh wrote, because Manifest V3 allows no remote code.

let loading = null;

// Every TeX package MathJax has, and physics, which it ships but leaves out of
// its default list because it redefines some standard commands (\Re, \Im and
// the trigonometric functions take arguments). Left out: require and autoload,
// which fetch packages from elsewhere; noerrors and noundefined, which would
// draw an error in red instead of reporting it; and html, whose \href and
// \style have no place in an image.
export function loadMathJax() {
  loading ??= new Promise((resolve, reject) => {
    globalThis.MathJax = {
      loader: {
        load: ["input/tex-full", "output/svg"],
        paths: { mathjax: chrome.runtime.getURL("renderer/mathjax") },
      },
      tex: {
        packages: { "[+]": ["physics"], "[-]": ["require", "autoload", "noerrors", "noundefined", "html"] },
        formatError: (_, error) => { throw error; },
      },
      // Each SVG carries its own glyph paths, so a copied or saved one is
      // complete without the page it came from.
      svg: { fontCache: "none" },
      startup: {
        typeset: false,
        ready() {
          globalThis.MathJax.startup.defaultReady();
          globalThis.MathJax.startup.promise.then(resolve, reject);
        },
      },
    };
    const script = document.createElement("script");
    script.src = chrome.runtime.getURL("renderer/mathjax/startup.js");
    script.onerror = () => reject(new Error("MathJax could not be loaded."));
    document.head.append(script);
  });
  return loading;
}

// Whether MathJax knows a command, for the autocomplete list. Only once loaded.
export function knowsCommand(name) {
  const jax = globalThis.MathJax?.startup?.document?.inputJax?.[0];
  if (!jax) return true;
  return !!jax.parseOptions.handlers.get("macro").lookup(name);
}

// Renders TeX in display style. Returns { svg } or { error }, with the error
// said plainly. The user's macros from the settings come first.
export function render(source, macros = "") {
  const { MathJax } = globalThis;
  forgetDefinitions(MathJax);
  try {
    const node = MathJax.tex2svg(`${macros}\n${source}`, { display: true });
    return { svg: node.querySelector("svg") };
  } catch (error) {
    return { error: explain(error) };
  }
}

// MathJax keeps every \newcommand, \def and \definecolor for as long as the
// page is open, so a command deleted from the source would go on working until
// the popup closed, and a copy could differ from what reopening it shows. Each
// render starts with only the built-in commands. The tables start empty in
// MathJax's newcommand and color packages, so emptying them loses nothing.
const DEFINITIONS = ["new-Command", "new-Environment", "new-Delimiter"];

function forgetDefinitions(MathJax) {
  const options = MathJax.startup.document.inputJax[0].parseOptions;
  for (const name of DEFINITIONS) options.handlers.retrieve(name)?.map?.clear();
  options.packageData.get("color")?.model?.userColors?.clear();
}

function explain(error) {
  const message = String(error?.message ?? error);
  const environment = /^Unknown environment '(.+)'$/.exec(message);
  if (environment) {
    return `\\begin{${environment[1]}} isn't supported: this renderer covers maths-mode LaTeX only.`;
  }
  const command = /^Undefined control sequence (\\.+)$/.exec(message);
  if (command) {
    return `${command[1]} isn't a command this renderer knows. It covers maths-mode LaTeX only; ` +
      "your own commands can be defined with \\newcommand, here or in the settings.";
  }
  return message;
}

// A standalone copy of a rendered SVG, sized in pixels and padded. MathJax
// measures in thousandths of an em, so an em is the font size and no ratio
// between em and ex has to be assumed.
export function standalone(svg, { fontSize, padding, colour }) {
  const copy = svg.cloneNode(true);
  const box = svg.viewBox.baseVal;
  const perPixel = 1000 / fontSize;
  const pad = padding * perPixel;
  const width = (box.width + 2 * pad) / perPixel;
  const height = (box.height + 2 * pad) / perPixel;
  copy.setAttribute("viewBox", `${box.x - pad} ${box.y - pad} ${box.width + 2 * pad} ${box.height + 2 * pad}`);
  copy.setAttribute("width", `${round(width)}px`);
  copy.setAttribute("height", `${round(height)}px`);
  copy.setAttribute("style", `color: ${colour}`);
  copy.removeAttribute("focusable");
  copy.removeAttribute("aria-hidden");
  return { svg: copy, width, height };
}

const round = (n) => Math.round(n * 1000) / 1000;

export function svgText(svg) {
  return new XMLSerializer().serializeToString(svg);
}

// Draws the SVG into a canvas at scale times its size. The background is
// white or nothing.
export async function pngBlob(image, { scale, background }) {
  const url = URL.createObjectURL(new Blob([svgText(image.svg)], { type: "image/svg+xml" }));
  try {
    const picture = new Image();
    picture.src = url;
    await picture.decode();
    const canvas = document.createElement("canvas");
    canvas.width = Math.max(1, Math.ceil(image.width * scale));
    canvas.height = Math.max(1, Math.ceil(image.height * scale));
    const context = canvas.getContext("2d");
    if (background === "white") {
      context.fillStyle = "#ffffff";
      context.fillRect(0, 0, canvas.width, canvas.height);
    }
    context.drawImage(picture, 0, 0, canvas.width, canvas.height);
    return await new Promise((resolve, reject) =>
      canvas.toBlob((blob) => (blob ? resolve(blob) : reject(new Error("The image could not be drawn."))), "image/png"));
  } finally {
    URL.revokeObjectURL(url);
  }
}
