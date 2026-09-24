// The rules content.js and docs.js share for following what is typed: how much
// they remember, which keys are shortcuts, and which sites a frame sits in.
// Nothing here listens to anything; it only answers questions.

(() => {
  const ns = (globalThis.LaTeXSquiggly ??= {});
  const { engine } = ns;

  // The most characters either script remembers, which is more than the
  // longest command needs. Held in memory only, never stored or sent.
  const CAPACITY = 64;

  // The last CAPACITY characters of the text, counted as the user sees them,
  // so an emoji or 𝔼 is never cut in half.
  function trimmed(text) {
    if (text.length <= CAPACITY) return text;
    const characters = engine.characters(text);
    return characters.length <= CAPACITY ? text : characters.slice(-CAPACITY).join("");
  }

  // Pressed on their own, these change nothing.
  const MODIFIERS = new Set(["Shift", "Control", "Alt", "AltGraph", "Meta", "CapsLock", "Fn", "OS"]);

  // A shortcut, as opposed to a modifier used for typing. AltGr is Control
  // and Alt together as far as the browser is concerned, and on most
  // European keyboards it is how { } \ are typed; Option does the same on a
  // Mac. Neither is a shortcut. Resetting on every modified key used to mean
  // \frac{1}{2} could never convert on those keyboards.
  function isShortcut(event) {
    const altGr = event.getModifierState?.("AltGraph") || (event.ctrlKey && event.altKey);
    return (event.ctrlKey || event.metaKey) && !altGr;
  }

  // The host of this frame and of every frame it sits inside, so a rule for a
  // site also covers anything embedded in it.
  function framedHosts() {
    const hosts = [location.hostname];
    for (const origin of location.ancestorOrigins ?? []) {
      try { hosts.push(new URL(origin).hostname); } catch { /* an opaque origin has no host */ }
    }
    return hosts;
  }

  ns.keyboard = { CAPACITY, trimmed, MODIFIERS, isShortcut, framedHosts };
})();
