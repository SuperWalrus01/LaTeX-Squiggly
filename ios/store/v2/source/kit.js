
const LANDSCAPE = document.body.className === "landscape";
const ENGINE = globalThis.LaTeXSquiggly.engine;
const TABLES = globalThis.LaTeXSquiggly.tables;

// ---------- MathJax ----------
window.MathJax = {
  loader: { load: ["input/tex-full", "output/svg"], paths: { mathjax: "./mathjax" } },
  tex: { packages: { "[-]": ["noundefined", "noerrors", "require", "autoload"] }, formatError: (_, err) => { throw err; } },
  svg: { fontCache: "none" },
  startup: { typeset: false },
};
const mjCache = new Map();
function tex(latex) {
  if (mjCache.has(latex)) return mjCache.get(latex);
  let out = null;
  try {
    const node = MathJax.tex2svg(latex, { display: false });
    const svg = node.querySelector("svg");
    if (!svg || node.querySelector("[data-mjx-error], merror")) throw new Error("bad");
    out = svg.outerHTML;
  } catch (e) { out = null; }
  mjCache.set(latex, out);
  return out;
}
function rendered(latex, px, color = "#000") {
  const svg = tex(latex);
  if (!svg) return "";
  return `<span style="font-size:${px}px;color:${color};display:inline-block;line-height:0">${svg}</span>`;
}
function card(latex, px, extra = "") {
  return `<div class="rcard" style="${extra}">${rendered(latex, px)}</div>`;
}

// ---------- Ports of the iOS keyboard's rules ----------
const SYMBOLS = new Map(TABLES.entries.map((e) => [e.command, e.glyph]));
const TEMPLATES = { frac: ["\\frac{}{}", 3], sqrt: ["\\sqrt{}", 1], text: ["\\text{}", 1],
  mathbb: ["\\mathbb{}", 1], mathrm: ["\\mathrm{}", 1], binom: ["\\binom{}{}", 3] };
const COMMON = ["alpha","beta","gamma","delta","epsilon","theta","lambda","mu","pi","sigma","phi","omega","infty",
  "sum","int","frac","sqrt","partial","nabla","pm","times","cdot","leq","geq","neq","approx","to","rightarrow","in",
  "subset","cup","cap","forall","exists","Delta","Sigma","Omega","text","mathbb"];
const RANK = new Map(COMMON.map((c, i) => [c, i]));
function partialCommand(before) {
  const m = before.match(/\\([A-Za-z]*)$/);
  return m ? m[1] : null;
}
function suggestions(prefix, limit = 3) {
  if (!prefix) return [];
  const names = new Set([...SYMBOLS.keys(), ...Object.keys(TEMPLATES)]);
  const matches = [...names].filter((n) => n.startsWith(prefix)).sort((a, b) => {
    if ((a === prefix) !== (b === prefix)) return a === prefix ? -1 : 1;
    const ra = RANK.has(a) ? RANK.get(a) : 1e9, rb = RANK.has(b) ? RANK.get(b) : 1e9;
    if (ra !== rb) return ra - rb;
    if (a.length !== b.length) return a.length - b.length;
    return a < b ? -1 : a > b ? 1 : 0;
  });
  return matches.slice(0, limit).map((n) => ({ command: n, glyph: TEMPLATES[n] ? null : SYMBOLS.get(n) }));
}
function trailing(before) {
  const text = before.trim();
  if (!text) return null;
  for (const d of ["$$", "$"]) {
    if (text.endsWith(d)) {
      const body = text.slice(0, -d.length);
      const open = body.lastIndexOf(d);
      if (open >= 0) return text.slice(open);
    }
  }
  let depth = 0, start = text.length;
  while (start > 0) {
    const ch = text[start - 1];
    if (/\s/.test(ch) && depth <= 0) break;
    if (ch === "}") depth++;
    if (ch === "{") depth--;
    start--;
  }
  const run = text.slice(start);
  return run || null;
}
function openBraces(before) { let d = 0; for (const c of before) { if (c === "{") d++; if (c === "}") d = Math.max(0, d - 1); } return d; }
function looksLikeMath(s) {
  if (s.length > 2 && s.startsWith("$") && s.endsWith("$")) return true;
  if (/[\^_]/.test(s)) return true;
  const i = s.indexOf("\\");
  return i >= 0 && i + 1 < s.length && /[A-Za-z]/.test(s[i + 1]);
}
function stripDelimiters(s) { return s.replace(/^\$\$?/, "").replace(/\$\$?$/, ""); }
function inMath(before) { return ((before.match(/\$/g) || []).length % 2 === 1) || openBraces(before) > 0; }
function currentWord(before) { const m = before.match(/[A-Za-z']+$/); return m ? m[0] : null; }
function stripFor(before, words, notice) {
  if (notice) return { kind: "notice", text: notice };
  const p = partialCommand(before);
  if (p !== null) {
    const found = suggestions(p);
    if (!(found.length === 0 || (found.length === 1 && found[0].command === p))) return { kind: "sug", list: found };
  }
  const src = trailing(before);
  if (src && looksLikeMath(src)) {
    const latex = stripDelimiters(src);
    if (latex && tex(latex)) return { kind: "math", latex: latex.replace(/\{\}/g, "{\\square}") };
  }
  if (words && !inMath(before)) { const w = currentWord(before); if (w) return { kind: "words", typed: w }; }
  return { kind: "quick" };
}

// ---------- Keyboard layout (ios/KeyboardUI/Layouts.swift) ----------
const UNIT = (390 - 2 * 6.67 - 9 * 6) / 10, GAP = 6, INSET = 6.67 - 3;
const K = (label, kind, width, ch) => ({ label, kind, width, ch });
const plain = (s) => [...s].map((c) => K(c, "text", 1, c));
const wide = (s) => [...s].map((c) => K(c, "text", null, c));
const SP = { spacer: true };
const BACK = K("delete", "back", 1.35);
const bottom = (left, extra, trail) => [left, extra, K("space", "space", null, " "), trail, K("return", "return", 2.3)];
const BS = K("\\", "text", 1.29, "\\");
const PAGES = {
  letters: [plain("qwertyuiop"), [SP, ...plain("asdfghjkl"), SP], [K("shift", "shift", 1.35), SP, ...plain("zxcvbnm"), SP, BACK],
    bottom(K("123", "page", 1.29, "@numbers"), K("∑", "page", 1.29, "@math"), BS)],
  numbers: [plain("1234567890"), plain("-/:;()$&@\""), [K("#+=", "page", 1.35, "@symbols"), ...wide(".,?!'"), BACK],
    bottom(K("ABC", "page", 1.29, "@letters"), K("∑", "page", 1.29, "@math"), BS)],
  symbols: [plain("[]{}#%^*+="), plain("_\\|~<>€£¥•"), [K("123", "page", 1.35, "@numbers"), ...wide(".,?!'"), BACK],
    bottom(K("ABC", "page", 1.29, "@letters"), K("∑", "page", 1.29, "@math"), BS)],
  math: [
    "α β γ δ ε θ λ μ π σ".split(" ").map((g) => K(g, "text", 1, g)),
    "φ ω Δ Σ Ω ∞ ∂ ∇ ± ×".split(" ").map((g) => K(g, "text", 1, g)),
    [K("·", "text", 1.35, "·"), SP, ..."≤ ≥ ≠ ≈ → ∈ ∫".split(" ").map((g) => K(g, "text", 1, g)), SP, BACK],
    bottom(K("ABC", "page", 1.29, "@letters"), K("α", "fn", 1.29), K("123", "page", 1.29, "@numbers"))],
};
const ICON = {
  shift: `<svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="#000" stroke-width="1.7" stroke-linejoin="round"><path d="M12 3.5 3.5 12.5H8v8h8v-8h4.5z"/></svg>`,
  shiftOn: `<svg width="22" height="22" viewBox="0 0 24 24" fill="#000" stroke="#000" stroke-width="1.7" stroke-linejoin="round"><path d="M12 3.5 3.5 12.5H8v8h8v-8h4.5z"/></svg>`,
  back: `<svg width="26" height="20" viewBox="0 0 28 20" fill="none" stroke="#000" stroke-width="1.6" stroke-linejoin="round"><path d="M9 2h16a2 2 0 0 1 2 2v12a2 2 0 0 1-2 2H9L1.5 10z"/><path d="m13 6.5 7 7m0-7-7 7" stroke-linecap="round"/></svg>`,
  ret: `<svg width="24" height="20" viewBox="0 0 24 20" fill="none" stroke="#000" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"><path d="M20 3v7a3 3 0 0 1-3 3H4"/><path d="m8 9-4 4 4 4"/></svg>`,
  globe: `<svg width="26" height="26" viewBox="0 0 24 24" fill="none" stroke="#3C3C43" stroke-width="1.5"><circle cx="12" cy="12" r="9.5"/><path d="M2.5 12h19M12 2.5c3 3 3 16 0 19M12 2.5c-3 3-3 16 0 19"/></svg>`,
  mic: `<svg width="22" height="26" viewBox="0 0 20 26" fill="none" stroke="#3C3C43" stroke-width="1.6" stroke-linecap="round"><rect x="6" y="1.5" width="8" height="14" rx="4"/><path d="M2.5 12a7.5 7.5 0 0 0 15 0M10 19.5v4"/></svg>`,
  copy: `<svg width="17" height="17" viewBox="0 0 20 20" fill="none" stroke="currentColor" stroke-width="1.6"><rect x="6.5" y="6.5" width="11" height="11" rx="2"/><path d="M13.5 6.5V4a1.5 1.5 0 0 0-1.5-1.5H4A1.5 1.5 0 0 0 2.5 4v8A1.5 1.5 0 0 0 4 13.5h2.5"/></svg>`,
  check: `<svg width="17" height="17" viewBox="0 0 20 20" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="m3.5 10.5 4.5 4.5 8.5-10"/></svg>`,
  kbd: `<svg width="22" height="16" viewBox="0 0 22 16" fill="none" stroke="currentColor" stroke-width="1.5"><rect x="1" y="1" width="20" height="14" rx="2.5"/><path d="M5 5h1M9 5h1M13 5h1M17 5h1M5 8.5h1M9 8.5h1M13 8.5h1M17 8.5h1M7 12h8" stroke-linecap="round"/></svg>`,
  share: `<svg width="18" height="20" viewBox="0 0 18 22" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"><path d="M9 14V1.5M4.5 6 9 1.5 13.5 6"/><path d="M6 9H3.5a1.5 1.5 0 0 0-1.5 1.5v8A1.5 1.5 0 0 0 3.5 20h11a1.5 1.5 0 0 0 1.5-1.5v-8A1.5 1.5 0 0 0 14.5 9H12"/></svg>`,
  sun: `<svg width="16" height="16" viewBox="0 0 20 20" fill="none" stroke="#000" stroke-width="1.6" stroke-linecap="round"><circle cx="10" cy="10" r="3.6"/><path d="M10 1.5v2M10 16.5v2M1.5 10h2M16.5 10h2M4 4l1.4 1.4M14.6 14.6 16 16M4 16l1.4-1.4M14.6 5.4 16 4"/></svg>`,
  moon: `<svg width="15" height="15" viewBox="0 0 20 20" fill="none" stroke="#000" stroke-width="1.6" stroke-linejoin="round"><path d="M16.5 12.5A7 7 0 0 1 7.5 3.5a7 7 0 1 0 9 9z"/></svg>`,
  up: `<svg width="16" height="16" viewBox="0 0 16 16" fill="none" stroke="#fff" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M8 13.5V2.5M3.5 7 8 2.5 12.5 7"/></svg>`,
  pencil: `<svg width="26" height="26" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"><path d="M11 4H5a2 2 0 0 0-2 2v13a2 2 0 0 0 2 2h13a2 2 0 0 0 2-2v-6"/><path d="M18.5 2.5a2.1 2.1 0 0 1 3 3L12 15l-4 1 1-4z"/></svg>`,
};
const STATUS = `<div class="status"><span>9:41</span><span class="icons">
  <svg width="18" height="12" viewBox="0 0 18 12"><rect x="0" y="8" width="3" height="4" rx="1"/><rect x="5" y="5.5" width="3" height="6.5" rx="1"/><rect x="10" y="3" width="3" height="9" rx="1"/><rect x="15" y="0" width="3" height="12" rx="1"/></svg>
  <svg width="16" height="12" viewBox="0 0 16 12" fill="none" stroke="#000" stroke-width="1.8" stroke-linecap="round"><path d="M1.5 4.5a9.5 9.5 0 0 1 13 0M4 7.3a6 6 0 0 1 8 0"/><circle cx="8" cy="10" r="1.2" fill="#000"/></svg>
  <svg width="27" height="13" viewBox="0 0 27 13"><rect x=".5" y=".5" width="23" height="12" rx="3.5" fill="none" stroke="#000" opacity=".4"/><rect x="2" y="2" width="20" height="9" rx="2.2"/><rect x="24.5" y="4.5" width="1.6" height="4" rx=".8" opacity=".4"/></svg>
</span></div>`;

function buildKeyboard(prefix) {
  let html = `<div class="kb" id="${prefix}kb"><div class="strip" id="${prefix}strip"></div><div class="rows">`;
  for (const [name, rows] of Object.entries(PAGES)) {
    html += `<div class="page" data-page="${name}">`;
    rows.forEach((row, r) => {
      const avail = 390 - 2 * INSET;
      let fixed = 0, flex = 0;
      for (const it of row) { if (it.spacer || it.width == null) flex++; else fixed += it.width * UNIT + GAP * (it.width - 1) + GAP; }
      const share = flex ? (avail - fixed) / flex : 0;
      let x = INSET;
      row.forEach((it, i) => {
        const slot = it.spacer || it.width == null ? share : it.width * UNIT + GAP * (it.width - 1) + GAP;
        if (!it.spacer) {
          const id = `${prefix}${name}-${r}-${i}`;
          let label = it.label, cls = "k";
          if (it.kind === "shift") label = `<span data-shift>${ICON.shift}</span>`;
          else if (it.kind === "back") label = ICON.back;
          else if (it.kind === "return") label = ICON.ret;
          else if (it.kind === "space") label = "";
          else if (it.kind === "page" || it.kind === "fn") cls += it.label === "∑" ? " fn sum" : " fn";
          else if (it.ch && /[a-z]/.test(it.ch)) label = `<span data-letter>${it.label}</span>`;
          html += `<div class="${cls}" id="${id}" style="left:${x + GAP / 2}px;width:${slot - GAP}px;top:${r * 54 + 5.5}px">${label}</div>`;
          it.ids = it.ids || {}; it.ids[prefix] = id;
        }
        x += slot;
      });
    });
    html += `</div>`;
  }
  html += `</div><div class="panel" id="${prefix}panel"></div>
    <div class="kbfoot"><span class="globe">${ICON.globe}</span><span class="mic">${ICON.mic}</span></div></div>`;
  return html;
}
function findKey(page, pred) {
  for (const row of PAGES[page]) for (const it of row) if (!it.spacer && pred(it)) return it;
  return null;
}
