// Puts the renderer's markup into a page and starts it: the one way in, for
// both the extension's popup and the Mac app's renderer window. panel.js
// finds its elements as it loads, so it is imported only once they are there.

const { host } = globalThis.LaTeXSquiggly;

export async function mountRenderer(container, options = {}) {
  const response = await fetch(host.url("renderer/panel.html"));
  container.innerHTML = await response.text();
  const panel = await import("./panel.js");
  await panel.startRenderer(options);
}
