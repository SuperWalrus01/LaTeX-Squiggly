// What the renderer's autocomplete offers. The symbols and operators come
// from the typing feature's own tables, so there is one list of them; this
// file adds only the commands that take arguments or build structure, which
// the typing tables have no Unicode for.
//
// In a template, each \0 is where the cursor goes, in order: the first when
// the command is inserted, the rest one Tab at a time.

const STRUCTURE = {
  frac: "\\frac{\0}{\0}",
  dfrac: "\\dfrac{\0}{\0}",
  tfrac: "\\tfrac{\0}{\0}",
  binom: "\\binom{\0}{\0}",
  sqrt: "\\sqrt{\0}",
  overbrace: "\\overbrace{\0}^{\0}",
  underbrace: "\\underbrace{\0}_{\0}",
  overset: "\\overset{\0}{\0}",
  underset: "\\underset{\0}{\0}",
  stackrel: "\\stackrel{\0}{\0}",
  overline: "\\overline{\0}",
  underline: "\\underline{\0}",
  overrightarrow: "\\overrightarrow{\0}",
  overleftarrow: "\\overleftarrow{\0}",
  xrightarrow: "\\xrightarrow{\0}",
  xleftarrow: "\\xleftarrow{\0}",
  hat: "\\hat{\0}",
  widehat: "\\widehat{\0}",
  bar: "\\bar{\0}",
  vec: "\\vec{\0}",
  dot: "\\dot{\0}",
  ddot: "\\ddot{\0}",
  tilde: "\\tilde{\0}",
  widetilde: "\\widetilde{\0}",
  text: "\\text{\0}",
  mathrm: "\\mathrm{\0}",
  mathbf: "\\mathbf{\0}",
  mathit: "\\mathit{\0}",
  mathsf: "\\mathsf{\0}",
  mathtt: "\\mathtt{\0}",
  mathcal: "\\mathcal{\0}",
  mathbb: "\\mathbb{\0}",
  mathfrak: "\\mathfrak{\0}",
  mathscr: "\\mathscr{\0}",
  boldsymbol: "\\boldsymbol{\0}",
  operatorname: "\\operatorname{\0}",
  textcolor: "\\textcolor{\0}{\0}",
  color: "\\color{\0}",
  colorbox: "\\colorbox{\0}{\0}",
  boxed: "\\boxed{\0}",
  cancel: "\\cancel{\0}",
  bcancel: "\\bcancel{\0}",
  xcancel: "\\xcancel{\0}",
  cancelto: "\\cancelto{\0}{\0}",
  ce: "\\ce{\0}",
  pu: "\\pu{\0}",
  dv: "\\dv{\0}{\0}",
  pdv: "\\pdv{\0}{\0}",
  abs: "\\abs{\0}",
  norm: "\\norm{\0}",
  ket: "\\ket{\0}",
  bra: "\\bra{\0}",
  braket: "\\braket{\0}{\0}",
  newcommand: "\\newcommand{\0}{\0}",
  left: "\\left",
  right: "\\right",
  displaystyle: "\\displaystyle",
  quad: "\\quad",
  qquad: "\\qquad",
  limits: "\\limits",
  tag: "\\tag{\0}",
};

const ENVIRONMENTS = [
  "aligned", "align", "gathered", "split", "cases", "matrix", "pmatrix", "bmatrix",
  "Bmatrix", "vmatrix", "Vmatrix", "smallmatrix", "array",
];

for (const name of ENVIRONMENTS) {
  STRUCTURE[`begin{${name}}`] = `\\begin{${name}} \0 \\end{${name}}`;
}

// { name, glyph, template, tier }. The tier orders the commands that start
// with what was typed: structure first, so \fr finds \frac before \frown;
// then the symbols, in the tables' own order, which puts the Greek letters
// first, so \al finds \alpha before \aleph; then the environments, so that
// \be finds \beta before a list of \begin{...}.
export function allCommands(tables) {
  const seen = new Set();
  const list = [];
  const add = (name, glyph, template, tier) => {
    if (seen.has(name)) return;
    seen.add(name);
    list.push({ name, glyph, template: template ?? `\\${name}`, tier });
  };
  for (const [name, template] of Object.entries(STRUCTURE)) {
    if (!name.includes("{")) add(name, "", template, 0);
  }
  for (const entry of tables.entries) add(entry.command, entry.glyph, undefined, 1);
  for (const name of Object.keys(tables.operators)) add(name, "", undefined, 1);
  for (const [name, template] of Object.entries(STRUCTURE)) add(name, "", template, 2);
  return list;
}

// What was typed exactly, then the commands starting with it by tier, then any
// other command containing it.
export function suggestions(commands, typed, limit = 8) {
  const prefix = [];
  const inside = [];
  for (const command of commands) {
    if (command.name.startsWith(typed)) prefix.push(command);
    else if (command.name.includes(typed)) inside.push(command);
  }
  const rank = (c) => (c.name === typed ? -1 : c.tier);
  prefix.sort((a, b) => rank(a) - rank(b));
  return [...prefix, ...inside].slice(0, limit);
}
