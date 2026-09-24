// Starts the renderer in the Mac app's window, with its settings below it.
//
// The window is kept between uses, so MathJax loads once per launch rather
// than every time it opens. The app calls squigglyShown each time it shows
// the window, which selects the input, ready to be typed over, as the
// extension's shortcut does.

import { mountRenderer } from "./renderer/mount.js";
import { startSettingsForm } from "./renderer/settings-form.js";

const settings = document.getElementById("settings");

globalThis.squigglyShown = () => {
  const latex = document.getElementById("latex");
  latex?.focus();
  latex?.select();
};

document.addEventListener("squiggly-open-settings", () => {
  settings.open = true;
  settings.scrollIntoView({ block: "nearest" });
});

await mountRenderer(document.getElementById("renderer"), { selectAll: true });
await startSettingsForm(document.getElementById("renderer-settings"));
document.body.dataset.ready = "true";
