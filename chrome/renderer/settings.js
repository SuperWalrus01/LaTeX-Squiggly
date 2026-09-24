// The renderer's settings, shared by the popup, the options page and the Mac
// app's renderer window. Kept apart from shared/settings.js, which every web
// page loads, because nothing here is any page's business.
//
// Stored in the host's sync area: chrome.storage.sync like the typing
// settings in the extension, the app's own defaults on the Mac. The last input
// is not a setting: it goes in the local area. Needs renderer/host.js first.

(() => {
  const ns = (globalThis.LaTeXSquiggly ??= {});

  const SCALES = [1, 2, 3, 4];
  const FONT_SIZE = { min: 12, max: 48 };
  const PADDING = { min: 0, max: 64 };
  const BACKGROUNDS = ["white", "transparent"];

  // White by default: black text on a transparent image disappears in any
  // app with a dark theme.
  const defaults = () => ({
    renderScale: 3,
    renderBackground: "white",
    renderColour: "#000000",
    renderFontSize: 20,
    renderPadding: 8,
    renderMacros: "",
  });

  const clamp = (n, { min, max }, fallback) =>
    Number.isFinite(Number(n)) ? Math.min(max, Math.max(min, Math.round(Number(n)))) : fallback;

  function clean(stored) {
    const d = defaults();
    return {
      renderScale: SCALES.includes(Number(stored.renderScale)) ? Number(stored.renderScale) : d.renderScale,
      renderBackground: BACKGROUNDS.includes(stored.renderBackground) ? stored.renderBackground : d.renderBackground,
      renderColour: /^#[0-9a-f]{6}$/i.test(stored.renderColour) ? stored.renderColour.toLowerCase() : d.renderColour,
      renderFontSize: clamp(stored.renderFontSize, FONT_SIZE, d.renderFontSize),
      renderPadding: clamp(stored.renderPadding, PADDING, d.renderPadding),
      renderMacros: typeof stored.renderMacros === "string" ? stored.renderMacros : d.renderMacros,
    };
  }

  async function load() {
    try {
      return clean(await ns.host.get("sync", defaults()));
    } catch {
      return defaults();
    }
  }

  const save = (changes) => ns.host.set("sync", changes);

  ns.rendererSettings = { SCALES, FONT_SIZE, PADDING, BACKGROUNDS, defaults, clean, load, save };
})();
