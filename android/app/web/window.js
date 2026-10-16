// Starts the renderer in the Android app, with its settings below it.
//
// The LaTeX to start with comes from the app: text selected in another app,
// or what the keyboard found before the caret. Without any, the last input
// comes back, as it does in the extension.

import { mountRenderer } from "./renderer/mount.js";
import { startSettingsForm } from "./renderer/settings-form.js";

const settings = document.getElementById("settings");

document.addEventListener("squiggly-open-settings", () => {
  settings.open = true;
  settings.scrollIntoView({ block: "nearest" });
});

const input = globalThis.LaTeXSquiggly.host.initialInput();
await mountRenderer(document.getElementById("renderer"),
  input === null ? { selectAll: true } : { selectAll: true, input });
await startSettingsForm(document.getElementById("renderer-settings"));
document.body.dataset.ready = "true";
