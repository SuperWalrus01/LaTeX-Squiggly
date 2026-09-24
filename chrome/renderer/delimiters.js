// Takes the maths delimiters off text selected on a page, for the renderer,
// which is always in display maths already: $...$, $$...$$, \(...\) and
// \[...\]. Only a matching pair around the whole selection is removed, so
// "costs $5 and $6" stays as it is.
//
// A classic script, not a module, because the background worker loads it with
// importScripts.

(() => {
  const ns = (globalThis.LaTeXSquiggly ??= {});

  const PAIRS = [["$$", "$$"], ["\\[", "\\]"], ["\\(", "\\)"], ["$", "$"]];

  function stripDelimiters(text) {
    const trimmed = String(text ?? "").trim();
    for (const [open, close] of PAIRS) {
      if (trimmed.length < open.length + close.length) continue;
      if (!trimmed.startsWith(open) || !trimmed.endsWith(close)) continue;
      const inner = trimmed.slice(open.length, trimmed.length - close.length);
      // $a$ and $b$ starts and ends with $ but is two pieces of maths.
      if (inner.includes(close)) continue;
      return inner.trim();
    }
    return trimmed;
  }

  ns.stripDelimiters = stripDelimiters;
})();
