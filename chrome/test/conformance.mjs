// Replays every fragment the Swift engine was asked about and checks that the
// extension's engine answers identically: same text, same reason, same delete
// count, same decision to stay silent. Then checks the site rules.
//
// Run:  node chrome/test/conformance.mjs

import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { runInThisContext } from "node:vm";

const here = dirname(fileURLToPath(import.meta.url));
const root = join(here, "..", "..");

for (const file of ["engine/tables.js", "engine/engine.js", "shared/settings.js"]) {
  runInThisContext(readFileSync(join(here, "..", file), "utf8"), { filename: file });
}
const { convert, outcome } = globalThis.LaTeXSquiggly.engine;
const settings = globalThis.LaTeXSquiggly.settings;

const records = JSON.parse(readFileSync(
  join(root, "conformance", "reference.json"), "utf8"));

const failures = [];
let checks = 0;
const show = (text) => (text === null || text === undefined ? "(none)" : `[${text}]`);

for (const record of records) {
  checks += 1;
  const engine = convert(record.input);
  const expected = record.engine;
  if (engine.kind !== expected.kind ||
      (engine.text ?? null) !== (expected.text ?? null) ||
      (engine.reason ?? null) !== (expected.reason ?? null)) {
    failures.push(`  engine ${show(record.input)}\n` +
      `    swift: ${expected.kind} text=${show(expected.text)} reason=${show(expected.reason)}\n` +
      `    js   : ${engine.kind} text=${show(engine.text)} reason=${show(engine.reason)}`);
  }

  checks += 1;
  const trigger = outcome(record.input, " ");
  const want = record.trigger;
  const describe = (t) => {
    if (t.kind === "replace") {
      return `replace delete=${t.deleteCount} insert=${show(t.insert)} notice=${show(t.notice)}`;
    }
    if (t.kind === "refuse") return `refuse source=${show(t.source)} reason=${show(t.reason)}`;
    return "none";
  };
  if (describe(trigger) !== describe(want)) {
    failures.push(`  trigger ${show(record.input)}\n    swift: ${describe(want)}\n    js   : ${describe(trigger)}`);
  }
  // The extension deletes by comparing `source` against the page, so it has to
  // be exactly the text the delete count describes, ending the input.
  if (trigger.kind === "replace" && !record.input.endsWith(trigger.source)) {
    failures.push(`  source ${show(record.input)} does not end with ${show(trigger.source)}`);
  }
}

// Site rules: the same cases the Windows suppression checks hold to.
const siteChecks = [
  ["overleaf.com", "overleaf.com", true],
  ["www.overleaf.com", "overleaf.com", true],
  ["fr.overleaf.com", "overleaf.com", true],
  ["OVERLEAF.COM", "overleaf.com", true],
  ["notoverleaf.com", "overleaf.com", false],
  ["overleaf.com.example.net", "overleaf.com", false],
  ["example.com", "overleaf.com", false],
];
for (const [host, pattern, expected] of siteChecks) {
  checks += 1;
  if (settings.hostMatches(host, pattern) !== expected) {
    failures.push(`  site ${host} against ${pattern}: expected ${expected}`);
  }
}
const normalised = [
  ["https://www.overleaf.com/project/123", "overleaf.com"],
  ["Overleaf.com/", "overleaf.com"],
  ["  www.cocalc.com ", "cocalc.com"],
  ["docs.example.org/path", "docs.example.org"],
  ["localhost", null],
  ["not a host", null],
  ["", null],
  [".com", null],
];
for (const [input, expected] of normalised) {
  checks += 1;
  if (settings.normalisedHost(input) !== expected) {
    failures.push(`  normalise ${show(input)}: expected ${show(expected)}, got ${show(settings.normalisedHost(input))}`);
  }
}
checks += 1;
const defaults = settings.defaults().excludedSites;
if (!defaults.includes("overleaf.com") || defaults.length !== 5) {
  failures.push(`  default sites are ${defaults.join(", ")}`);
}

if (failures.length === 0) {
  console.log(`PASS  engine  ${records.length * 2} checks over ${records.length} fragments,`);
  console.log("              every answer identical to the Swift engine");
  console.log(`PASS  sites   ${checks - records.length * 2} checks on the site rules`);
  console.log(`      ${checks} checks passed.`);
} else {
  for (const failure of failures.slice(0, 40)) console.log(failure);
  if (failures.length > 40) console.log(`... and ${failures.length - 40} more`);
  console.log(`FAIL  ${failures.length} of ${checks} checks disagree`);
  process.exitCode = 1;
}
