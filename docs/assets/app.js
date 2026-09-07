const SYMBOLS = DATA.symbols;
const BY_CMD = Object.fromEntries(SYMBOLS.map(s => [s.c, s]));
const BB = Object.fromEntries(SYMBOLS.filter(s => s.k === "Blackboard bold").map(s => [s.c, s.g]));
const SUP = DATA.sup, SUB = DATA.sub, VULGAR = DATA.vulgar, OPS = DATA.operators;
const REASONS = DATA.reasons;
const FRACTION_SLASH = "⁄", DIVISION_SLASH = "∕";

/* A working mirror of the app's converter: the same tables, and the same rules
   for the paths this page demonstrates. */
function fail(reason) { throw { reason }; }

function readArgument(s, i) {
  while (i < s.length && s[i] === " ") i++;
  if (s[i] === "{") {
    let depth = 1, j = i + 1, out = "";
    while (j < s.length && depth > 0) {
      if (s[j] === "{") depth++;
      else if (s[j] === "}") { depth--; if (!depth) break; }
      out += s[j]; j++;
    }
    if (depth) fail("That group was never closed.");
    return [out, j + 1];
  }
  if (s[i] === "\\") {
    let j = i + 1, name = "";
    while (j < s.length && /[A-Za-z]/.test(s[j])) { name += s[j]; j++; }
    return ["\\" + (name || s[i + 1] || ""), name ? j : i + 2];
  }
  if (i >= s.length) fail("An argument is missing.");
  return [s[i], i + 1];
}

function scripted(text, table, kind) {
  let out = "";
  for (const ch of text) {
    const mapped = table[ch];
    if (!mapped) fail("There is no Unicode " + kind + " for “" + ch + "”.");
    out += mapped;
  }
  return out;
}

function parenthesised(t) { return [...t].length === 1 ? t : "(" + t + ")"; }

function render(src) {
  let out = "", notices = [], i = 0;
  while (i < src.length) {
    const ch = src[i];

    if (ch === "^" || ch === "_") {
      const [arg, next] = readArgument(src, i + 1);
      const inner = render(arg);
      out += ch === "^" ? scripted(inner.text, SUP, "superscript")
                        : scripted(inner.text, SUB, "subscript");
      i = next; continue;
    }

    if (ch !== "\\") { out += ch; i++; continue; }

    let j = i + 1, name = "";
    while (j < src.length && /[A-Za-z]/.test(src[j])) { name += src[j]; j++; }

    if (!name) {
      const symbol = src[i + 1];
      if (symbol && "{}$%&#_".includes(symbol)) { out += symbol; i += 2; continue; }
      fail("Spacing commands are typographic adjustments with no plain-text equivalent.");
    }

    if (name === "frac" || name === "dfrac" || name === "tfrac") {
      const [a, k1] = readArgument(src, j); const [b, k2] = readArgument(src, k1);
      const top = render(a), bottom = render(b);
      if (!top.text || !bottom.text) fail("\\" + name + " has an empty argument.");
      i = k2;
      if (!top.notices.length && !bottom.notices.length) {
        const exact = VULGAR[top.text + "/" + bottom.text];
        if (exact) { out += exact; continue; }
        const numeric = /^[0-9]+$/.test(top.text) && /^[0-9]+$/.test(bottom.text);
        const short = [...top.text].length <= 2 && [...bottom.text].length <= 2;
        if (numeric || short) {
          const up = [...top.text].map(c => SUP[c]), down = [...bottom.text].map(c => SUB[c]);
          if (up.every(Boolean) && down.every(Boolean)) {
            out += up.join("") + FRACTION_SLASH + down.join(""); continue;
          }
        }
      }
      out += parenthesised(top.text) + DIVISION_SLASH + parenthesised(bottom.text);
      notices = notices.concat(top.notices, bottom.notices,
        ["A fraction cannot be stacked in plain text, so it was written on one line with a slash."]);
      continue;
    }

    if (name === "sqrt") {
      let degree = "2", k = j;
      if (src[k] === "[") { const close = src.indexOf("]", k); degree = src.slice(k + 1, close); k = close + 1; }
      const [a, k2] = readArgument(src, k); const inner = render(a); i = k2;
      const sign = { "2": "√", "3": "∛", "4": "∜" }[degree];
      if (sign) {
        out += sign + parenthesised(inner.text);
        notices = notices.concat(inner.notices,
          ["A radical sign cannot extend over what is under it, so the root was written as " + sign + "(…)."]);
      } else {
        out += parenthesised(inner.text) + "^(1/" + degree + ")";
        notices = notices.concat(inner.notices,
          ["There is no Unicode radical sign for an index of " + degree + ", so the root was written as a fractional power."]);
      }
      continue;
    }

    if (name === "binom" || name === "dbinom" || name === "tbinom") {
      const [a, k1] = readArgument(src, j); const [b, k2] = readArgument(src, k1);
      const n = render(a), k = render(b); i = k2;
      out += "C(" + n.text + ", " + k.text + ")";
      notices = notices.concat(n.notices, k.notices,
        ["A binomial coefficient cannot be stacked in plain text, so it was written as C(n, k)."]);
      continue;
    }

    if (name === "mathbb") {
      const [a, k1] = readArgument(src, j); i = k1;
      const letter = BB[a.trim()];
      if (!letter) fail("There is no double-struck “" + a.trim() + "” in Unicode.");
      out += letter; continue;
    }

    if (["text", "textrm", "mathrm", "operatorname"].includes(name)) {
      const [a, k1] = readArgument(src, j); i = k1; out += a; continue;
    }

    if (name === "left" || name === "right") { i = j; continue; }

    i = j;
    if (BY_CMD[name]) { out += BY_CMD[name].g; continue; }
    if (OPS[name]) { out += OPS[name]; continue; }
    if (REASONS[name]) fail(REASONS[name]);
    fail("“\\" + name + "” is not a command this app knows.");
  }
  return { text: out, notices };
}

/* The trigger layer: what the app decides when you press space. */
const MATH_SIGNALS = ["\\", "^", "_"];
function outcome(buffer) {
  if (buffer.endsWith("$")) {
    const before = buffer.slice(0, -1), open = before.lastIndexOf("$");
    if (open >= 0) {
      const content = before.slice(open + 1);
      if (content && [...content].length <= 48 && MATH_SIGNALS.some(c => content.includes(c))) {
        try {
          const r = render(content);
          return { kind: "replace", deleteCount: [...content].length + 2, text: r.text, notices: r.notices, source: "$" + content + "$" };
        } catch (e) { return { kind: "refuse", reason: e.reason, source: "$" + content + "$" }; }
      }
    }
  }
  const start = buffer.lastIndexOf("\\");
  if (start < 0) return { kind: "none" };
  const source = buffer.slice(start);
  if (source.length < 2) return { kind: "none" };
  try {
    const r = render(source);
    return { kind: "replace", deleteCount: [...source].length, text: r.text, notices: r.notices, source };
  } catch (e) { return { kind: "refuse", reason: e.reason, source }; }
}

/* ---- the compose box ---- */
const compose = document.getElementById("compose");
const notice = document.getElementById("notice");

function say(html) { notice.innerHTML = html; }
function esc(s) { return s.replace(/[&<>]/g, c => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;" }[c])); }

function fire(terminator) {
  const at = compose.selectionStart;
  const result = outcome(compose.value.slice(0, at));
  if (result.kind === "none") return false;

  if (result.kind === "refuse") {
    say("<span class='said'>Left as you typed it — " + esc(result.reason) + "</span>");
    return false;
  }
  const cut = at - result.deleteCount;
  compose.value = compose.value.slice(0, cut) + result.text + terminator + compose.value.slice(at);
  const caret = cut + result.text.length + terminator.length;
  compose.setSelectionRange(caret, caret);
  say("<span class='did'>" + esc(result.source) + " → " + esc(result.text) + "</span>"
      + (result.notices.length ? " <span class='said'>" + esc(result.notices[0]) + "</span>" : ""));
  return true;
}

compose.addEventListener("keydown", event => {
  if (event.key !== " " && event.key !== "Tab") return;
  if (event.metaKey || event.ctrlKey || event.altKey) return;
  if (fire(event.key === "Tab" ? "\t" : " ")) event.preventDefault();
  else if (event.key === "Tab") event.preventDefault();
});

document.querySelectorAll(".try").forEach(button => {
  button.addEventListener("click", () => {
    const at = compose.selectionStart || compose.value.length;
    const src = button.dataset.src;
    compose.value = compose.value.slice(0, at) + src + compose.value.slice(at);
    compose.focus();
    compose.setSelectionRange(at + src.length, at + src.length);
    fire(" ");
  });
});

/* ---- the symbol browser ---- */
const grid = document.getElementById("grid"), query = document.getElementById("q"), count = document.getElementById("count");
function draw(list) {
  count.textContent = list.length + " of " + SYMBOLS.length;
  if (!list.length) { grid.innerHTML = "<p class='empty'>Nothing matches that. The app would say the same.</p>"; return; }
  grid.innerHTML = list.map(s =>
    "<div class='sym'><span class='g'>" + s.g + "</span><span class='t'><span class='c'>\\" +
    (s.k === "Blackboard bold" ? "mathbb{" + s.c + "}" : s.c) +
    "</span><span class='n' title='" + s.n + "'>" + s.n.toLowerCase() + "</span></span></div>").join("");
}
query.addEventListener("input", () => {
  const terms = query.value.toLowerCase().split(/\s+/).filter(Boolean);
  draw(SYMBOLS.filter(s => {
    const hay = (s.c + " " + s.n + " " + s.k).toLowerCase();
    return terms.every(t => hay.includes(t));
  }));
});
draw(SYMBOLS);
