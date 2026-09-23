/**
 * Regression tests for bin/lib/name-split.js.
 *
 * Every case here is a real failure, not a hypothetical. The first group is the
 * two names that forced the old hand-written SOFT list into existence. The
 * second is what that list could never do, which is work for somebody who is
 * not Caleb. The third is the pair of bugs found while porting this, both of
 * which ate real surnames off real people.
 *
 *   node --test tests/test_name_split.mjs
 */

import test from "node:test";
import assert from "node:assert/strict";
import { createRequire } from "node:module";

const require = createRequire(import.meta.url);
const {
  splitName,
  refineCorpus,
  buildNameCorpus,
  discoverLabels,
} = require("../bin/lib/name-split.js");

/**
 * A stand-in address book. Shaped like a real one: a handful of labels on many
 * people, one family sharing a surname, and the awkward cases spelled out.
 */
const BOOK = [
  ...Array.from({ length: 30 }, (_, i) => ({ name: `Person${i} USC` })),
  ...Array.from({ length: 12 }, (_, i) => ({ name: `Student${i} IYA` })),
  // Avenues is a dorm, and it has to appear BEHIND a name on some cards for
  // the second pass to learn it. That is the real distribution: 8 cards put it
  // in the tail and 7 put it in surname position, and the second pass is what
  // reconciles the two.
  ...Array.from({ length: 8 }, (_, i) => ({
    name: `Member${i} Lastname${i} Avenues`,
  })),
  ...Array.from({ length: 2 }, (_, i) => ({ name: `Resident${i} Avenues` })),
  // Two people from the same high school. One occurrence is not evidence, which
  // is the rule working rather than a gap in it.
  { name: "Grace Yoon Muir Hs" },
  { name: "Maia IYA" },
  { name: "Lucas Brandt IYA" },
  { name: "Caleb Stone" },
  { name: "Ava Stone" },
  { name: "Josh Stone" },
  { name: "Sela Stone" },
  { name: "Alana Kim" },
  { name: "Danny Kim" },
  { name: "Gina Kim" },
  { name: "Colin Jiho Kim" },
  { name: "Dev Malhotra A2F USC IYA" },
  { name: "Mateo Ruiz Muir Hs CC Prez" },
  { name: "Maria de la Cruz" },
  { name: "USC Christian Challenge" },
];

const corpus = refineCorpus(BOOK);

test("a first name that is also a label survives", () => {
  // "Maia IYA" used to strip to an empty string. The old fix was to write
  // "Maia" into a SOFT list by hand; the rule now is that position 0 is name
  // territory, so no list is needed.
  const s = splitName("Maia IYA", corpus);
  assert.equal(s.name, "Maia");
  assert.deepEqual(s.tags, ["IYA"]);
});

test("a given name that is also a label is not eaten mid-name", () => {
  const s = splitName("Lucas Brandt IYA", corpus);
  assert.equal(s.name, "Lucas Brandt");
  assert.deepEqual(s.tags, ["IYA"]);
});

test("a stack of labels all come off, and the name stays whole", () => {
  const s = splitName("Dev Malhotra A2F USC IYA", corpus);
  assert.equal(s.name, "Dev Malhotra");
  assert.deepEqual(s.tags, ["A2F", "USC", "IYA"]);
});

test("the sticky tail needs no vocabulary for what follows a label", () => {
  // Muir, Hs, CC and Prez are not in any list and not frequent in this book.
  // They come off because something to their left was judged a label.
  const s = splitName("Mateo Ruiz Muir Hs CC Prez", corpus);
  assert.equal(s.name, "Mateo Ruiz");
  assert.deepEqual(s.tags, ["Muir", "Hs", "CC", "Prez"]);
});

test("a family surname is never reported as a label", () => {
  // Four Stones is what a family looks like. Frequency alone would take it.
  for (const n of ["Caleb Stone", "Ava Stone", "Josh Stone"]) {
    const s = splitName(n, corpus);
    assert.match(s.name, /Stone/, `${n} lost its surname`);
    assert.deepEqual(s.tags, []);
  }
});

test("name furniture does not advance the position, so a surname is safe", () => {
  // Cruz sits at raw index 3, where the fourth-token rule fires. `de` and `la`
  // are joiners, so its effective position is 1 and it stays a name.
  const s = splitName("Maria de la Cruz", corpus);
  assert.equal(s.name, "Maria de la Cruz");
  assert.deepEqual(s.tags, []);
});

test("a three-part name keeps its surname", () => {
  // THE BUG THIS EXISTS FOR. The surname of a three-part name lands at index 2,
  // where the frequency rule read it as annotation. On the real book that took
  // "Kim" off all 43 Kims, because the four cards it misfired on were then
  // learned as vocabulary. Middle names are ordinary, and in Korean, Vietnamese
  // and Spanish books they are the common case.
  const s = splitName("Colin Jiho Kim", corpus);
  assert.match(s.name, /Kim$/);
  assert.deepEqual(s.tags, []);
});

test("a learned label is never applied to a first token", () => {
  // The second pass learns this book's vocabulary. Applied at position 0 it
  // reintroduces exactly the "Maia IYA" failure, so it starts at position 1.
  assert.ok(corpus.tailVocab.has("iya"), "IYA should be learned as a label");
  assert.equal(splitName("Iya Smith", corpus).name, "Iya Smith");
});

test("a label in surname position still comes off", () => {
  // What the second pass is for. "Avenues" is a dorm, sitting where a surname
  // sits, and one pass leaves it in the name.
  const s = splitName("Ashton Avenues", corpus);
  assert.equal(s.name, "Ashton");
  assert.deepEqual(s.tags, ["Avenues"]);
});

test("an organisation saved as a contact stays whole", () => {
  // Every token here reads as a label. Amber promotes the first one and keeps
  // the rest as tags, which renders a ministry as a person called "USC".
  const s = splitName("USC Christian Challenge", corpus);
  assert.equal(s.name, "USC Christian Challenge");
  assert.deepEqual(s.tags, []);
});

test("nobody ever comes back nameless", () => {
  for (const p of BOOK) {
    assert.ok(splitName(p, corpus).name, `${p.name} split to nothing`);
  }
});

test("the vocabulary is discovered, not declared", () => {
  // The whole point of the port: no list ships, and the labels fall out of
  // whatever book this is pointed at.
  const found = discoverLabels(BOOK, corpus, 3).map((t) => t.key);
  assert.ok(found.includes("USC"));
  assert.ok(found.includes("IYA"));
  assert.ok(!found.includes("NEWTON"), "a family surname is not vocabulary");
  assert.ok(!found.includes("KIM"), "a surname is not vocabulary");
});

test("no corpus degrades to position and shape, and stays conservative", () => {
  // Callers without a book still get something sane rather than a crash.
  const s = splitName("Caleb Stone");
  assert.equal(s.name, "Caleb Stone");
  assert.equal(buildNameCorpus([]).size, 0);
  assert.deepEqual(splitName("", null), {
    name: null,
    nameTokens: [],
    tags: [],
  });
});
