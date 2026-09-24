// The renderer's settings as a form: scale, font size, padding, background,
// text colour and the user's own commands. Its markup is
// renderer/settings-form.html; the extension's options page and the Mac app's
// renderer window each put it in their page with startSettingsForm.

const { rendererSettings, host } = globalThis.LaTeXSquiggly;

export async function startSettingsForm(container) {
  const response = await fetch(host.url("renderer/settings-form.html"));
  container.innerHTML = await response.text();
  const $ = (id) => container.querySelector(`#${id}`);

  const renderFields = {
    renderScale: $("render-scale"),
    renderFontSize: $("render-font-size"),
    renderPadding: $("render-padding"),
    renderBackground: $("render-background"),
    renderColour: $("render-colour"),
    renderMacros: $("render-macros"),
  };
  const renderSaveError = $("render-save-error");

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


  $("renderer-form").addEventListener("submit", (event) => event.preventDefault());
  showRendererSettings(await rendererSettings.load());

  // Another window, or the renderer itself, may change the same settings.
  host.onChanged(async (changes, area) => {
    if (area !== "sync" || !Object.keys(changes).some((key) => key.startsWith("render"))) return;
    showRendererSettings(await rendererSettings.load());
  });
}
