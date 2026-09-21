#!/usr/bin/env node
// Checks the claims this procedure makes about its own output. Run after any
// change to run.mjs, and after any run whose numbers look surprising.
import { readFileSync, existsSync } from 'node:fs';
import { homedir } from 'node:os';

const school = process.argv[2] ?? 'acc';
const out = `${homedir()}/coursework/.ingest/${school}`;
let bad = 0;
const fail = (m) => { console.log(`FAIL  ${m}`); bad++; };
const ok = (m) => console.log(`ok    ${m}`);

if (!existsSync(`${out}/deliverables.json`)) { fail(`no deliverables.json in ${out}`); process.exit(1); }
const items = JSON.parse(readFileSync(`${out}/deliverables.json`, 'utf8'));

items.length ? ok(`${items.length} deliverables`) : fail('deliverables.json is empty');

// Every date must be traceable. This is the whole point: a deadline with no
// source is a deadline nobody can check, and an unchecked wrong date is worse
// than a missing one.
const unsourced = items.filter((i) => !i.source);
unsourced.length ? fail(`${unsourced.length} item(s) with no source`) : ok('every item carries a source');

const undated = items.filter((i) => !i.due || Number.isNaN(Date.parse(i.due)));
undated.length ? fail(`${undated.length} item(s) with an unparseable due date`) : ok('every due date parses');

const sorted = items.every((x, i) => i === 0 || items[i - 1].due <= x.due);
sorted ? ok('sorted by due date') : fail('not sorted by due date');

// Same course, same name, same minute, twice: that is a bug in the merge, not
// two real assignments.
const seen = new Map();
for (const i of items) {
  const k = `${i.course}|${i.name}|${i.due}`;
  seen.set(k, (seen.get(k) ?? 0) + 1);
}
const dupes = [...seen].filter(([, n]) => n > 1);
dupes.length ? fail(`${dupes.length} exact duplicate(s): ${dupes[0][0]}`) : ok('no exact duplicates');

const report = JSON.parse(readFileSync(`${out}/report.json`, 'utf8'));
report.report.length ? ok(`${report.report.length} course(s) in the report`) : fail('no courses read');
for (const c of report.report) {
  if (c.columns === 0 && c.contents <= 3) console.log(`note  ${c.course} has nothing posted yet (${c.columns} columns, ${c.contents} content items)`);
}

console.log(bad ? `\n${bad} check(s) failed` : '\nall checks passed');
process.exit(bad ? 1 : 0);
