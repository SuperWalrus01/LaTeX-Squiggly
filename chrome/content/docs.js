// Google Docs mode: on by default, and switched off in the settings.
//
// What this script reads, keeps, sends and types:
//
// - It runs only on docs.google.com, and only follows keys in a document's
//   hidden input frame while Google Docs mode is on and the extension is not
//   paused.
// - It keeps the last 64 characters typed, in memory, and forgets them after
//   4 seconds without a key, and on every click, arrow key and shortcut.
//   Nothing typed is ever stored.
// - Its messages stay inside the extension: "docs-forget", which carries
//   nothing, and "docs-notice", the text of a notice to show in the top frame.
//   Nothing goes over the network.
// - It types into Docs by sending the page Backspace and character key
//   events, and only to replace a command the user has just finished with a
//   space. See typeIntoDocs, at the end.
//
// Everywhere else the extension reads the text in front of the caret and only
// replaces it when it is exactly what was typed. Google Docs gives nothing to
// read: it draws the document itself and takes typing through a hidden frame,
// which it reads and empties. So in Docs this works the way the desktop apps
// do. It keeps its own record of the keys pressed, deletes the command with
// Backspace and types the result, trusting the record. Every rule below exists
// to keep that record honest, because a wrong record deletes the wrong text.
//
// Two parts, one per frame:
//
// - In Docs' top frame it only watches for clicks, which move the caret
//   somewhere the record knows nothing about, and passes them on.
// - In the hidden input frame it follows the keys and does the typing.
//
// content.js stays out of every frame inside Docs; see its HIDDEN_INPUT_HOSTS.
//
// The browser test runs it against a stand-in built the way Docs works, which
// proves this side. Docs' side can only be tested by hand, signed in: see
// "Google Docs" in chrome/README.md, and re-run that test after any change here.

(() => {
  const { engine, settings, keyboard } = globalThis.LaTeXSquiggly;
  const { trimmed, MODIFIERS, isShortcut, framedHosts } = keyboard;

  const DOCS_HOSTS = ["docs.google.com"];

  // A command with no key pressed for this long is forgotten: the caret may
  // have moved in a way this frame never saw. The desktop apps use the same.
  const LIFETIME_MS = 4000;

  // More deletes than any real command needs means the record is wrong.
  const MAXIMUM_DELETES = 40;

  if (settings.matchingSite(framedHosts(), DOCS_HOSTS) === null) return;

  let config = null;
  const load = () => settings.load().then((loaded) => { config = loaded; });
  load();
  chrome.storage.onChanged.addListener((_, area) => { if (area === "sync") load(); });

  const switchedOn = () =>
    config !== null && config.enabled && config.googleDocs
    && settings.matchingSite(framedHosts(), config.excludedSites) === null;

  // MARK: The top frame

  if (window === window.top) {
    // Clicks land here, on the drawn document, not in the input frame. The
    // background worker passes this on to every frame in the tab.
    addEventListener("mousedown", () => {
      if (!switchedOn()) return;
      chrome.runtime.sendMessage({ type: "docs-forget" }).catch(() => {});
    }, true);
    return;
  }

  // MARK: The input frame

  // Documents only. Sheets and Slides take input differently and are untested.
  let path = "";
  try { path = window.top.location.pathname; } catch { /* not same-origin: not Docs' own frame */ }
  if (!path.startsWith("/document/")) return;

  let buffer = "";
  let lastKey = 0;
  let typing = false;

  const forget = () => { buffer = ""; };

  chrome.runtime.onMessage.addListener((message) => {
    if (message?.type === "docs-forget") forget();
  });

  // The top frame shows the notice; nothing in this frame is visible.
  function notify(title, message) {
    chrome.runtime.sendMessage({ type: "docs-notice", title, message }).catch(() => {});
  }

  // Only real keys are followed. The keys this script sends are not trusted,
  // which is also how it avoids reading its own typing.
  addEventListener("keydown", (event) => {
    if (!event.isTrusted || typing || !switchedOn()) return;
    if (MODIFIERS.has(event.key)) return;

    const now = Date.now();
    if (now - lastKey > LIFETIME_MS) forget();
    lastKey = now;

    if (event.key === " ") {
      terminate(event);
      return;
    }
    if (event.key === "Backspace" && !isShortcut(event)) {
      buffer = engine.characters(buffer).slice(0, -1).join("");
      return;
    }

    // One character typed, including one typed with AltGr or Option: keep it.
    // Anything else, from arrows and Enter to shortcuts and dead keys, moves
    // the caret or builds a character in ways the record cannot follow.
    if (!isShortcut(event) && !event.isComposing && [...event.key].length === 1) {
      buffer = trimmed(buffer + event.key);
      return;
    }
    forget();
  }, true);

  addEventListener("compositionstart", forget, true);

  function terminate(event) {
    const outcome = engine.outcome(buffer, " ");
    if (outcome.kind === "none") {
      buffer = trimmed(buffer + " ");
      return;
    }
    forget();
    if (outcome.kind === "refuse") {
      notify("Left as typed", `${outcome.source}: ${outcome.reason}`);
      return;
    }

    // Characters outside the Basic Multilingual Plane, such as 𝔼, are two
    // UTF-16 units, and how Docs takes those from a key event is unknown.
    // Leaving the command as typed is the safe answer until it is known.
    if (outcome.deleteCount > MAXIMUM_DELETES || [...outcome.insert].some((c) => c.codePointAt(0) > 0xFFFF)) {
      notify("Left as typed", "Google Docs mode cannot type this one yet.");
      return;
    }

    // The space is swallowed and typed back as part of the replacement, as
    // everywhere else. Cancelling keydown also cancels the keypress Docs would
    // have turned into a space.
    event.preventDefault();
    event.stopImmediatePropagation();
    typing = true;
    try {
      typeIntoDocs(outcome.deleteCount, outcome.insert);
    } finally {
      typing = false;
    }
    if (outcome.notice) notify("Converted with an approximation", outcome.notice);
  }

  // Backspace as keydown and keyup, and each character as keypress, which is
  // how Docs reads keys: by keyCode and charCode, not key. Checked by hand in
  // Docs; see chrome/README.md.
  function typeIntoDocs(deletes, text) {
    const target = document.activeElement ?? document.body;
    const send = (type, init) =>
      target.dispatchEvent(new KeyboardEvent(type, { bubbles: true, cancelable: true, ...init }));

    for (let i = 0; i < deletes; i++) {
      const backspace = { key: "Backspace", code: "Backspace", keyCode: 8, which: 8 };
      send("keydown", backspace);
      send("keyup", backspace);
    }
    for (const character of text) {
      const code = character.charCodeAt(0);
      send("keypress", { key: character, charCode: code, keyCode: code, which: code });
    }
  }
})();
