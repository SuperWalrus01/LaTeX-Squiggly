// The renderer's LaTeX box: command autocomplete, closing braces, Tab between
// a command's arguments, and wrapping a selection in a command.
//
// Every change goes through execCommand("insertText") or "delete", the same as
// the typing feature, so each one is a step in the textarea's own undo history
// and Ctrl+Z takes back exactly one.

import { suggestions } from "./commands.js";

export function balanced(text) {
  let depth = 0;
  for (let i = 0; i < text.length; i++) {
    if (text[i] === "\\") i++;
    else if (text[i] === "{") depth++;
    else if (text[i] === "}" && --depth < 0) return false;
  }
  return depth === 0;
}

// An odd run of backslashes before a position means the character there is
// escaped: \{ is a literal brace, while \\{ is a line break then a group.
function escaped(text, at) {
  let n = 0;
  while (at - 1 - n >= 0 && text[at - 1 - n] === "\\") n++;
  return n % 2 === 1;
}

export class Editor {
  constructor(textarea, list, { commands, knows }) {
    this.textarea = textarea;
    this.list = list;
    this.commands = commands;
    this.knows = knows;
    // Offsets in the text that follow it as it is edited: the braces this
    // editor closed by itself, and the places Tab goes next.
    this.closers = [];
    this.stops = [];
    this.items = [];
    this.active = 0;
    this.dismissed = null;
    this.before = null;
    this.accepting = false;

    textarea.addEventListener("beforeinput", () => this.remember());
    textarea.addEventListener("input", (event) => this.edited(event));
    textarea.addEventListener("keydown", (event) => this.keydown(event));
    textarea.addEventListener("pointerdown", () => { this.stops = []; this.close(); });
    textarea.addEventListener("blur", () => this.close());
    list.addEventListener("pointerdown", (event) => {
      // Keep the focus, and the caret, in the textarea.
      event.preventDefault();
      const item = event.target.closest("[data-index]");
      if (item) this.accept(Number(item.dataset.index));
    });
  }

  get open() { return !this.list.hidden; }

  // MARK: Following edits

  remember() {
    const { value, selectionStart, selectionEnd } = this.textarea;
    this.before = { value, selectionStart, selectionEnd };
  }

  // Works out which stretch of the text changed, anchored at the caret where
  // the text alone is ambiguous (typing } before a }), and moves every tracked
  // offset after it.
  edited(event) {
    const before = this.before;
    this.before = null;
    if (before) {
      const old = before.value;
      const now = this.textarea.value;
      const caret = this.textarea.selectionStart;
      let start = 0;
      const limit = Math.min(old.length, now.length, before.selectionStart, caret);
      while (start < limit && old[start] === now[start]) start++;
      let tail = 0;
      while (tail < old.length - start && tail < now.length - start &&
             old[old.length - 1 - tail] === now[now.length - 1 - tail]) tail++;
      const oldEnd = old.length - tail;
      const shift = now.length - old.length;
      // An offset inside what was replaced goes; one at or after its end moves.
      const move = (offsets) => offsets
        .filter((o) => o <= start || o >= oldEnd)
        .map((o) => (o >= oldEnd ? o + shift : o));
      this.closers = move(this.closers);
      this.stops = move(this.stops);
    }
    // Only for what the user typed: a command just inserted from the list
    // would otherwise offer itself again, and Enter would not start a line.
    if (this.accepting) return;
    if (event.inputType?.startsWith("insert") || event.inputType?.startsWith("delete")) this.suggest();
  }

  // MARK: Autocomplete

  typedCommand() {
    const { value, selectionStart, selectionEnd } = this.textarea;
    if (selectionStart !== selectionEnd) return null;
    const match = /\\([A-Za-z]+)$/.exec(value.slice(0, selectionStart));
    if (!match || escaped(value, match.index)) return null;
    return { start: match.index, typed: match[1] };
  }

  suggest() {
    const found = this.typedCommand();
    if (!found || this.dismissed === `${found.start}:${found.typed}`) return this.close();
    this.dismissed = null;
    const known = this.commands.filter((c) => c.name.includes("{") || this.knows(c.name));
    let items = suggestions(known, found.typed);
    // A finished command with nothing to fill in needs no list, and Enter then
    // starts a new line as it should.
    if (items.length === 1 && items[0].name === found.typed && !items[0].template.includes("\0")) items = [];
    if (items.length === 0) return this.close();
    this.items = items;
    this.active = 0;
    this.draw();
  }

  draw() {
    this.list.replaceChildren();
    this.items.forEach((item, index) => {
      const row = document.createElement("li");
      row.dataset.index = index;
      row.id = `suggestion-${index}`;
      row.setAttribute("role", "option");
      row.setAttribute("aria-selected", String(index === this.active));
      const name = document.createElement("span");
      name.className = "name";
      name.textContent = "\\" + item.name;
      const glyph = document.createElement("span");
      glyph.className = "glyph";
      glyph.textContent = item.glyph;
      row.append(name, glyph);
      this.list.append(row);
    });
    this.list.hidden = false;
    this.textarea.setAttribute("aria-expanded", "true");
    this.textarea.setAttribute("aria-activedescendant", `suggestion-${this.active}`);
  }

  close() {
    this.list.hidden = true;
    this.items = [];
    this.textarea.setAttribute("aria-expanded", "false");
    this.textarea.removeAttribute("aria-activedescendant");
  }

  accept(index) {
    const item = this.items[index];
    const found = this.typedCommand();
    this.close();
    if (!item || !found) return;
    const text = item.template.replaceAll("\0", "");
    const stops = [];
    let offset = found.start;
    for (const part of item.template.split("\0").slice(0, -1)) {
      offset += part.length;
      stops.push(offset);
    }
    this.accepting = true;
    try {
      this.replace(found.start, this.textarea.selectionStart, text);
    } finally {
      this.accepting = false;
    }
    if (stops.length > 0) {
      this.textarea.setSelectionRange(stops[0], stops[0]);
      this.stops = [...stops.slice(1), ...this.stops].sort((a, b) => a - b);
    }
  }

  // MARK: Keys

  keydown(event) {
    if (event.isComposing) return;
    // AltGr arrives as Control and Alt together, and on most European
    // keyboards it is how { and } are typed, so only Control alone or Command
    // make a shortcut.
    const shortcut = event.metaKey || (event.ctrlKey && !event.altKey);
    const plain = !shortcut && !event.altKey && !event.ctrlKey;

    if (this.open) {
      if (event.key === "ArrowDown" || event.key === "ArrowUp") {
        event.preventDefault();
        const n = this.items.length;
        this.active = (this.active + (event.key === "ArrowDown" ? 1 : n - 1)) % n;
        this.draw();
        return;
      }
      if ((event.key === "Tab" && !event.shiftKey && plain) || (event.key === "Enter" && plain && !event.shiftKey)) {
        event.preventDefault();
        this.accept(this.active);
        return;
      }
      if (event.key === "Escape") {
        // Handled here, so the popup stays open.
        event.preventDefault();
        event.stopPropagation();
        const found = this.typedCommand();
        if (found) this.dismissed = `${found.start}:${found.typed}`;
        this.close();
        return;
      }
    }

    if (["ArrowLeft", "ArrowRight", "Home", "End", "PageUp", "PageDown"].includes(event.key)) this.close();

    if (event.key === "Tab" && plain && !event.shiftKey) {
      const caret = this.textarea.selectionEnd;
      const next = this.stops.find((o) => o >= caret && o <= this.textarea.value.length);
      if (next !== undefined) {
        event.preventDefault();
        this.stops = this.stops.filter((o) => o !== next);
        this.textarea.setSelectionRange(next, next);
      }
      return;
    }

    if (shortcut) return;
    const { value, selectionStart: start, selectionEnd: end } = this.textarea;

    if (event.key === "{" && !escaped(value, start)) {
      event.preventDefault();
      const inner = value.slice(start, end);
      const next = value[end];
      // Wrap a selection; close an empty group only where nothing follows that
      // the brace could be meant to take in.
      if (inner === "" && next !== undefined && /[A-Za-z0-9]/.test(next)) {
        this.replace(start, end, "{");
        return;
      }
      this.replace(start, end, `{${inner}}`);
      const caret = start + 1 + inner.length;
      this.textarea.setSelectionRange(caret, caret);
      this.closers.push(caret);
      return;
    }

    if (event.key === "}" && start === end && value[start] === "}" && this.closers.includes(start)) {
      event.preventDefault();
      this.closers = this.closers.filter((o) => o !== start);
      this.textarea.setSelectionRange(start + 1, start + 1);
      return;
    }

    if (event.key === "Backspace" && start === end && value[start - 1] === "{" && value[start] === "}" &&
        !escaped(value, start - 1)) {
      event.preventDefault();
      this.textarea.setSelectionRange(start - 1, start + 1);
      document.execCommand("delete");
    }
  }

  // MARK: Changing the text

  replace(start, end, text) {
    this.textarea.focus();
    this.textarea.setSelectionRange(start, end);
    // execCommand fires input but not beforeinput, so the text before the
    // edit is recorded here. Without it, the braces already closed would not
    // move, and a nested group's outer } would stop being typed over.
    this.remember();
    if (text === "") document.execCommand("delete");
    else document.execCommand("insertText", false, text);
  }

  selection() {
    const { value, selectionStart, selectionEnd } = this.textarea;
    return { start: selectionStart, end: selectionEnd, text: value.slice(selectionStart, selectionEnd) };
  }

  // Wraps the range in before and after, and selects the result, so another
  // click can wrap it again.
  wrap({ start, end, text }, before, after) {
    const result = before + text + after;
    this.replace(start, end, result);
    this.textarea.setSelectionRange(start, start + result.length);
  }
}
