// Watches typing in the page and replaces LaTeX with Unicode when a space
// completes it.
//
// The desktop apps count keystrokes and type backspaces, trusting that the
// buffer matches what is on screen. A page gives us something better: the text
// itself. So the buffer here only decides *what* the user just typed, and
// nothing is changed until the text in front of the caret is confirmed to be
// exactly that. When the two disagree, because a site rewrote the field or the
// typing went to a hidden element (Google Docs does this), the space goes
// through untouched. Doing nothing is always a correct outcome.
//
// Nothing typed is stored or sent anywhere. The buffer holds at most 64
// characters, in memory, and is cleared on every click, arrow key and focus
// change.

(() => {
  const { engine, settings } = globalThis.LaTeXSquiggly;

  const CAPACITY = 64;

  // Code editors write LaTeX source too, and on the web they are components
  // rather than apps, so they are recognised by the editor's own markup.
  const CODE_EDITORS = ".cm-editor, .CodeMirror, .monaco-editor, .ace_editor";

  const TEXT_INPUT_TYPES = new Set(["text", "search"]);

  let config = null;
  let buffer = { element: null, text: "" };
  let replacing = false;

  // True between compositionstart and compositionend: an input method, or a
  // dead key such as ^ on a German keyboard, is building a character.
  let composing = false;

  const reset = () => { buffer = { element: null, text: "" }; };

  // MARK: Settings and suppression

  function framedHosts() {
    const hosts = [location.hostname];
    for (const origin of location.ancestorOrigins ?? []) {
      try { hosts.push(new URL(origin).hostname); } catch { /* an opaque origin has no host */ }
    }
    return hosts;
  }

  const excludedBy = () => settings.matchingSite(framedHosts(), config?.excludedSites ?? []);

  // Google Docs, Sheets and Slides draw their own text and take typing through
  // a hidden frame, which Docs reads and empties. Converting there could hand
  // Docs a second copy of what was typed, so inside Docs every frame below the
  // top one does nothing at all. The check cannot rest on the frame's address:
  // a frame the page has written into with document.open takes the page's
  // own address, so it looks like any other docs.google.com frame. Docs' own
  // text boxes, such as comments, are in the top frame and still convert.
  const HIDDEN_INPUT_HOSTS = ["docs.google.com"];
  if (window !== window.top && settings.matchingSite(framedHosts(), HIDDEN_INPUT_HOSTS) !== null) {
    return;
  }
  const active = () => config !== null && config.enabled && excludedBy() === null;

  settings.load().then((loaded) => { config = loaded; });
  chrome.storage.onChanged.addListener((_, area) => {
    if (area !== "sync") return;
    settings.load().then((loaded) => { config = loaded; reset(); });
  });

  // The popup asks the top frame which site it is on. Frames stay quiet, or
  // an embedded page could answer first.
  if (window === window.top) {
    chrome.runtime.onMessage.addListener((message, _, reply) => {
      if (message?.type !== "status") return;
      reply({ host: location.hostname, excludedBy: excludedBy() });
    });
  }

  // MARK: Which elements count

  function deepActiveElement() {
    let element = document.activeElement;
    while (element?.shadowRoot?.activeElement) element = element.shadowRoot.activeElement;
    return element;
  }

  function editable(element) {
    if (!element || element.closest?.(CODE_EDITORS)) return null;
    if (element instanceof HTMLTextAreaElement) {
      return element.readOnly || element.disabled ? null : { kind: "field", element };
    }
    if (element instanceof HTMLInputElement) {
      if (!TEXT_INPUT_TYPES.has(element.type) || element.readOnly || element.disabled) return null;
      return { kind: "field", element };
    }
    if (element.isContentEditable) return { kind: "rich", element };
    return null;
  }

  // MARK: Following what is typed

  function trimmed(text) {
    if (text.length <= CAPACITY) return text;
    const characters = engine.characters(text);
    return characters.length <= CAPACITY ? text : characters.slice(-CAPACITY).join("");
  }

  // Whether the element has a selection rather than a caret, in which case a
  // deletion removes more than the one character the buffer would drop.
  function hasSelection(element) {
    if (element instanceof HTMLInputElement || element instanceof HTMLTextAreaElement) {
      return element.selectionStart !== element.selectionEnd;
    }
    const selection = selectionFor(element);
    return !!selection && !selection.isCollapsed;
  }

  addEventListener("beforeinput", (event) => {
    if (replacing) return;
    const target = editable(deepActiveElement());
    if (!target) { reset(); return; }

    // Text being composed arrives in pieces and may still change. It is
    // recorded once, when the composition ends, and does not reset the
    // buffer: a dead key used to, which broke $x^2$ on a German Mac.
    if (composing || event.isComposing || event.inputType.startsWith("insertComposition")) return;

    if (buffer.element !== target.element) buffer = { element: target.element, text: "" };

    if (event.inputType === "insertText" && event.data) {
      buffer.text = trimmed(buffer.text + event.data);
    } else if (event.inputType === "deleteContentBackward" && !hasSelection(target.element)) {
      buffer.text = engine.characters(buffer.text).slice(0, -1).join("");
    } else {
      // Paste, drop, undo, a deleted word: the buffer no longer describes
      // what is in front of the caret.
      reset();
    }
  }, true);

  // Anything that can move the caret without typing ends the run.
  const NAVIGATION = new Set([
    "ArrowLeft", "ArrowRight", "ArrowUp", "ArrowDown", "Home", "End",
    "PageUp", "PageDown", "Enter", "Escape", "Tab",
  ]);
  addEventListener("mousedown", reset, true);
  addEventListener("focusin", () => { if (!replacing) reset(); }, true);
  // Leaving the window, for another app or the address bar, is a caret move
  // the page never sees.
  addEventListener("blur", (event) => { if (event.target === window) reset(); });

  addEventListener("compositionstart", () => { composing = true; }, true);
  addEventListener("compositionend", (event) => {
    composing = false;
    const target = editable(deepActiveElement());
    if (!target) { reset(); return; }
    if (buffer.element !== target.element) buffer = { element: target.element, text: "" };
    if (event.data) buffer.text = trimmed(buffer.text + event.data);
  }, true);

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

  // MARK: The terminator

  // Space only. Return sends messages in chat apps, and Tab moves focus in a
  // browser, so neither can safely be taken over.
  addEventListener("keydown", (event) => {
    if (replacing || MODIFIERS.has(event.key)) return;
    if (NAVIGATION.has(event.key) || isShortcut(event)) {
      reset();
      return;
    }
    if (event.key !== " " || event.isComposing || composing || !active()) return;

    const target = editable(deepActiveElement());
    if (!target || buffer.element !== target.element) return;

    const outcome = engine.outcome(buffer.text, " ");
    if (outcome.kind === "none") return;
    if (outcome.kind === "refuse") {
      notify("Left as typed", `${outcome.source}: ${outcome.reason}`);
      return;
    }

    const typed = target.kind === "field" ? fieldSource(target.element, outcome.source)
                                          : richSource(target.element, outcome.source);
    if (typed === null) { reset(); return; }

    let replaced = false;
    replacing = true;
    try {
      replaced = target.kind === "field"
        ? replaceInField(target.element, typed, outcome.insert)
        : replaceInRich(target.element, typed, outcome.insert);
    } finally {
      replacing = false;
      reset();
    }
    // Only a replacement that happened swallows the space. If the editor
    // refused it, the caret is back where it was and the space goes through,
    // so nothing the user typed is lost.
    if (!replaced) return;
    event.preventDefault();
    event.stopImmediatePropagation();
    if (outcome.notice) notify("Converted with an approximation", outcome.notice);
  }, true);

  // MARK: Text fields

  // The range [start, caret) when it holds exactly the source, otherwise null.
  function fieldSource(field, source) {
    const caret = field.selectionStart;
    if (caret === null || caret !== field.selectionEnd) return null;
    const start = caret - source.length;
    if (start < 0 || field.value.slice(start, caret) !== source) return null;
    return { start, end: caret };
  }

  function replaceInField(field, range, insert) {
    field.setSelectionRange(range.start, range.end);
    // insertText goes through the browser's own editing, so undo restores the
    // source and frameworks such as React see an ordinary input event.
    if (document.execCommand("insertText", false, insert)) return true;
    field.setRangeText(insert, range.start, range.end, "end");
    field.dispatchEvent(new InputEvent("input", { bubbles: true, inputType: "insertText", data: insert }));
    return true;
  }

  // MARK: Rich text

  // Walks back from the caret through the text nodes of the editing host,
  // collecting exactly as many code units as the source has, and returns the
  // range covering them when they match.
  // The selection that covers the host. A shadow root keeps its own, and the
  // document's only reports the shadow host, so an editor inside a web
  // component was never found.
  function selectionFor(host) {
    const root = host.getRootNode();
    if (root instanceof ShadowRoot && typeof root.getSelection === "function") return root.getSelection();
    return getSelection();
  }

  function richSource(host, source) {
    const selection = selectionFor(host);
    if (!selection || selection.rangeCount === 0 || !selection.isCollapsed) return null;
    const caret = selection.getRangeAt(0);
    if (!host.contains(caret.endContainer)) return null;

    const walker = document.createTreeWalker(host, NodeFilter.SHOW_TEXT);
    let node;
    let offset;
    if (caret.endContainer.nodeType === Node.TEXT_NODE) {
      node = caret.endContainer;
      offset = caret.endOffset;
    } else {
      const before = caret.endContainer.childNodes[caret.endOffset - 1];
      node = before ? lastTextIn(before) : null;
      if (!node) {
        walker.currentNode = before ?? caret.endContainer;
        node = walker.previousNode();
      }
      offset = node?.data.length;
    }

    let remaining = source.length;
    let text = "";
    while (node) {
      const take = Math.min(remaining, offset);
      text = node.data.slice(offset - take, offset) + text;
      remaining -= take;
      if (remaining === 0) {
        offset -= take;
        break;
      }
      walker.currentNode = node;
      node = walker.previousNode();
      offset = node?.data.length;
    }
    // Editors keep typed spaces visible as no-break spaces.
    if (remaining !== 0 || text.replaceAll(" ", " ") !== source) return null;

    const range = document.createRange();
    range.setStart(node, offset);
    range.setEnd(caret.endContainer, caret.endOffset);
    return range;
  }

  function lastTextIn(root) {
    if (root.nodeType === Node.TEXT_NODE) return root;
    const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT);
    let last = null;
    while (walker.nextNode()) last = walker.currentNode;
    return last;
  }

  function replaceInRich(host, range, insert) {
    const selection = selectionFor(host);
    const caret = selection.getRangeAt(0).cloneRange();
    selection.removeAllRanges();
    selection.addRange(range);
    if (host.ownerDocument.execCommand("insertText", false, insert)) return true;

    // The editor refused. Put the caret back rather than leave the command
    // selected, where the next keystroke would type over it.
    selection.removeAllRanges();
    selection.addRange(caret);
    return false;
  }

  // MARK: Notices

  // A fallback or a refusal is never silent: the user is told what happened.
  // Drawn in a closed shadow root so the page's styles cannot reach it.
  let notice = null;

  function notify(title, message) {
    // A frame in the background has no business interrupting.
    if (!config?.showNotices || (window !== window.top && !document.hasFocus())) return;
    if (!notice) notice = buildNotice();
    notice.title.textContent = title;
    notice.message.textContent = message;
    notice.card.classList.add("shown");
    clearTimeout(notice.timer);
    notice.timer = setTimeout(() => notice.card.classList.remove("shown"), 7000);
  }

  function buildNotice() {
    const host = document.createElement("latex-squiggly-notice");
    const root = host.attachShadow({ mode: "closed" });
    root.innerHTML = `
      <style>
        :host { all: initial; }
        .card {
          --bg: #fbf8f2; --fg: #2b2118; --muted: #6b5d50; --edge: #e6dccf; --accent: #d9661a;
          position: fixed; right: 16px; bottom: 16px; z-index: 2147483647;
          max-width: min(360px, calc(100vw - 32px)); box-sizing: border-box;
          padding: 12px 14px 12px 16px; border-radius: 10px;
          border: 1px solid var(--edge); border-left: 4px solid var(--accent);
          background: var(--bg); color: var(--fg);
          box-shadow: 0 6px 24px rgb(0 0 0 / 0.18);
          font: 13px/1.45 system-ui, -apple-system, "Segoe UI", sans-serif;
          opacity: 0; transform: translateY(8px); pointer-events: none;
          transition: opacity 160ms ease, transform 160ms ease;
          cursor: pointer;
        }
        .card.shown { opacity: 1; transform: none; pointer-events: auto; }
        .title { font-weight: 600; margin: 0 0 2px; }
        .message { margin: 0; color: var(--muted); overflow-wrap: anywhere; }
        @media (prefers-color-scheme: dark) {
          .card { --bg: #231d17; --fg: #f3ece3; --muted: #bfb2a4; --edge: #3a3129; --accent: #f28a3a; }
        }
        @media (prefers-reduced-motion: reduce) { .card { transition: none; } }
      </style>
      <div class="card" role="status" aria-live="polite" title="Dismiss">
        <p class="title"></p>
        <p class="message"></p>
      </div>`;
    document.documentElement.append(host);
    const card = root.querySelector(".card");
    card.addEventListener("mousedown", (event) => {
      event.preventDefault();
      card.classList.remove("shown");
    });
    return { card, title: root.querySelector(".title"), message: root.querySelector(".message"), timer: 0 };
  }
})();
