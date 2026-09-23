// @ts-nocheck
/**
 * SPLITTING A CONTACT NAME THAT IS NOT ONLY A NAME.
 *
 * People type annotations into the name field, because Apple Contacts gives
 * them nowhere else to put it: "Dev Malhotra A2F USC IYA", "Mateo Ruiz Muir
 * Hs CC Prez", "Nina Park UCLA BTG". The label is real information and the
 * user wrote it themselves, so it must not be thrown away. It is also not their
 * name, so it must not be shown as one.
 *
 * PORTED FROM AMBER. This is a port of `src/lib/name-split.js` in
 * amberintelligence/amber-id, written by Karthik Devarakonda. The method, the
 * three-signal ordering and the sticky-tail rule are his. Ported with Karthik
 * and Sagar's standing permission, same as the rest of the people layer.
 *
 * WHAT IT REPLACES HERE, AND WHY THAT MATTERS FOR A PUBLIC KIT. The dashboard
 * used to strip labels with two hand-written lists: fifty-odd tokens like
 * "Nemmy", "Troy camp" and "BUAI", plus a second list of the ones that are also
 * somebody's given name. Both lists were Caleb's own vocabulary compiled by
 * hand, shipped in a kit other people install, where they do nothing at all. A
 * word had to be predicted before it could be handled, and the prediction was
 * only ever going to be right for one address book.
 *
 * THE ADDRESS BOOK IS ITS OWN DICTIONARY. No list ships with this and no model
 * is called. The signal is that a label REPEATS ACROSS PEOPLE and a name does
 * not:
 *
 *   "IYA" is on sixty cards belonging to sixty different people. Nobody has
 *   sixty relatives called IYA. It is a label.
 *
 *   "Newton" is on five cards - Caleb, Ava, Joshua, Selah, Joel - which is what
 *   a family looks like, and it sits where a surname sits.
 *
 * Frequency alone eats the surname. Position alone keeps "Alex IYA Prez" as a
 * three-word name. Shape alone calls every acronym a label and misses
 * "plumber". The three together are what make this work.
 *
 * WHEN IN DOUBT IT IS A NAME. A label wrongly kept in a name is invisible; a
 * surname wrongly reported as a label is the kit telling someone their brother
 * is tagged "Newton". The old SOFT list existed because "Maia IYA" stripped to
 * an empty string and "Lucas Brandt IYA" lost his first name. Here that
 * cannot happen for a different reason than a list: frequency tests fail closed
 * toward "name", and a person can never come back nameless.
 */

"use strict";

/** Split on whitespace, hyphens and punctuation. Case and symbols are noise. */
function tokenizeName(value) {
  return String(value || "")
    .replace(/[(){}\[\]<>"'`~!@#$%^&*_=+|\\/:;,.?]+/g, " ")
    .split(/[\s-]+/)
    .map((t) => t.trim())
    .filter(Boolean);
}

const norm = (t) => String(t || "").toLowerCase();

/**
 * Words that are never a label, however they appear. Name furniture is part of
 * a name and would read as a label on every card carrying it.
 */
const NAME_FURNITURE = new Set([
  "jr",
  "sr",
  "ii",
  "iii",
  "iv",
  "dr",
  "mr",
  "mrs",
  "ms",
  "miss",
  "prof",
  "rev",
  "van",
  "von",
  "de",
  "del",
  "della",
  "da",
  "di",
  "la",
  "le",
  "el",
  "bin",
  "ibn",
  "al",
  "san",
  "st",
  "saint",
  "mac",
  "mc",
  "o",
  "ben",
  "abu",
]);

/** Labels on a field rather than on a person. Phone-book debris. */
const FIELD_DEBRIS = new Set([
  "iphone",
  "phone",
  "mobile",
  "cell",
  "cellphone",
  "home",
  "work",
  "office",
  "old",
  "new",
  "number",
  "no",
  "tel",
  "fax",
  "main",
  "other",
  "backup",
  "alt",
  "do",
  "not",
  "call",
  "dnd",
  "spam",
  "unknown",
  "unnamed",
  "test",
  "temp",
  "the",
  "and",
  "or",
  "of",
  "at",
  "from",
  "for",
  "with",
  "a",
  "an",
  "guy",
  "lady",
]);

/**
 * Roles and relationships people write into a contact name. Present because one
 * occurrence should still read as a label, which corpus frequency by definition
 * cannot do: most address books hold exactly one plumber.
 */
const ROLE_WORDS = new Set([
  "plumber",
  "electrician",
  "dentist",
  "doctor",
  "vet",
  "mechanic",
  "landlord",
  "realtor",
  "agent",
  "broker",
  "barber",
  "hairdresser",
  "tailor",
  "trainer",
  "coach",
  "therapist",
  "lawyer",
  "attorney",
  "accountant",
  "cpa",
  "uber",
  "lyft",
  "driver",
  "cleaner",
  "nanny",
  "babysitter",
  "tutor",
  "recruiter",
  "boss",
  "manager",
  "intern",
  "professor",
  "ta",
  "advisor",
  "mom",
  "dad",
  "mother",
  "father",
  "sister",
  "brother",
  "aunt",
  "uncle",
  "cousin",
  "grandma",
  "grandpa",
  "wife",
  "husband",
  "roommate",
  "neighbor",
  "school",
  "college",
  "gym",
  "church",
  "class",
  "club",
  "team",
  // Officer titles, which is how a student address book annotates half of it:
  // "Mateo Ruiz Muir Hs CC Prez".
  "prez",
  "president",
  "vp",
  "treasurer",
  "secretary",
  "historian",
  "captain",
]);

/** An acronym or ticker-shaped token: USC, IYA, BTG, MIT, KTP, GS. */
function looksLikeAcronym(raw) {
  return /^[A-Z0-9&]{2,6}$/.test(raw) && /[A-Z]/.test(raw);
}

/**
 * How often each token appears across DISTINCT people in one address book.
 *
 * Counted per person, not per occurrence, so a card that repeats a word does
 * not inflate it. Built once per book and passed into every split, because the
 * whole method depends on comparing a token against its neighbours' cards. A
 * single card in isolation cannot tell a label from a surname.
 */
function buildNameCorpus(people) {
  const counts = new Map();
  const list = Array.isArray(people) ? people : [];
  for (const p of list) {
    const seen = new Set();
    for (const field of [
      typeof p === "string" ? p : null,
      p?.name,
      p?.full_name ?? p?.fullName,
      p?.first_name ?? p?.firstName,
      p?.last_name ?? p?.lastName,
      p?.nickname,
    ]) {
      for (const tok of tokenizeName(field)) seen.add(norm(tok));
    }
    for (const k of seen) counts.set(k, (counts.get(k) ?? 0) + 1);
  }
  return { counts, size: list.length };
}

/**
 * How many distinct people carry this token. 0 when there is no corpus, which
 * makes every frequency test below fail closed, i.e. toward "it is a name".
 */
function freq(corpus, token) {
  return corpus?.counts?.get(norm(token)) ?? 0;
}

/**
 * A token is a shared LABEL rather than this person's name.
 *
 * Thresholds are absolute rather than proportional. A label on three cards is a
 * label whether the book holds 40 people or 4,000; a proportional threshold
 * would make the same word a name in a big book and a label in a small one,
 * which is a worse kind of wrong.
 */
function isLabelToken(raw, index, corpus) {
  const k = norm(raw);
  if (NAME_FURNITURE.has(k)) return false; // part of the name, never a label
  if (FIELD_DEBRIS.has(k)) return true;
  if (ROLE_WORDS.has(k)) return true;
  if (/^\d+$/.test(k)) return true; // a phone fragment or a "2"

  // WHAT THIS BOOK HAS ALREADY BEEN SEEN TO ANNOTATE WITH.
  //
  // Added here, not in Amber. One pass cannot judge a label sitting where a
  // surname sits: "Ashton Avenues" puts a dorm at position 1, and position 1 is
  // surname territory, so it survives as a name. A second pass fixes that with
  // evidence rather than a list - a token that landed in the TAIL on three
  // other people is a label wherever it turns up, because the tail is where
  // this user demonstrably puts annotations.
  //
  // The tail requirement is the whole guard, and it is why this cannot eat a
  // family. "Newton" is on seven cards and "Park" on three, and neither has
  // ever appeared after somebody's name, so neither is ever promoted. Raw
  // frequency alone would have taken both.
  // NOT AT POSITION 0, and that guard is the whole of the old SOFT list, derived
  // instead of written. "Maia" and "Christian" are both this user's club labels
  // AND both first names, so a learned label applied at position 0 turns "Maia
  // IYA" into a person with no name and "Lucas Brandt IYA" into a man with
  // no first name. Those two failures are on record; they are why a hand list
  // was there. The first token is name territory, so the vocabulary starts
  // applying at the second.
  if (index >= 1 && corpus?.tailVocab?.has(k)) return true;

  // A TOKEN THIS BOOK MOSTLY USES AS A NAME IS A NAME, whatever position it
  // lands in. Everything below this line is position and frequency, and
  // position is what breaks on a three-part name: "Colin Jiho Kim", "Omor
  // Ravi Malhotra", "Alyssa Grey Garcia" all put the surname at index 2,
  // where the frequency rule reads it as annotation. Middle names are ordinary,
  // and in Korean, Vietnamese and Spanish books they are the common case, so a
  // splitter that treats a third token as a label is wrong for a large part of
  // any real address book.
  //
  // The evidence is the same count TAIL_DOMINANCE uses, read the other way: Kim
  // is a name on 39 cards and a label on 4, so it is a surname and the four are
  // the misfire. The explicit sets above still win, and so does the sticky
  // tail, so "Dev Malhotra A2F USC IYA" still splits on A2F.
  if (corpus?.nameVocab?.has(k)) return false;

  const n = freq(corpus, raw);

  // AN ACRONYM SHARED BY THREE PEOPLE, anywhere in the field including where a
  // first name would go. This is the case the old SOFT list was written for
  // from the other end: "Maia IYA" keeps Maia because Maia is on one card,
  // while "MAIA" as a club label on thirty cards is caught here without anybody
  // having had to write the word down.
  if (looksLikeAcronym(raw) && n >= 3) return true;

  // Beyond the second token the bar drops. Two people sharing a word already
  // past where a surname sits is a label.
  if (index >= 2 && n >= 2) return true;

  // A FOURTH TOKEN IS A LABEL. Nobody's legal name is typed into a phone as
  // four words; by this point the user is annotating.
  if (index >= 3) return true;

  // An acronym at position 2+ on its own. "Nina Park BTG" where BTG appears
  // nowhere else is still not a surname, because surnames are not three capital
  // letters.
  if (index >= 2 && looksLikeAcronym(raw)) return true;

  return false;
}

/**
 * Split one person's name into the name and the labels around it.
 * Returns `{ name, nameTokens, tags }`.
 *
 * `corpus` is optional; without it this degrades to position and shape, which
 * is the same conservative direction as everything else here.
 */
function splitName(person, corpus = null) {
  const src = typeof person === "string" ? { name: person } : person || {};
  const candidates = [
    tokenizeName(src.name ?? src.full_name ?? src.fullName),
    tokenizeName(src.first_name ?? src.firstName),
    tokenizeName(src.last_name ?? src.lastName),
  ];
  // first + last combined, for the ordinary card where they are split cleanly.
  // THE LONGEST FIELD WINS, because that is where the information is.
  const combined = [...candidates[1], ...candidates[2]];
  const tokens =
    [candidates[0], combined].sort((a, b) => b.length - a.length)[0] ?? [];

  if (tokens.length === 0) return { name: null, nameTokens: [], tags: [] };

  const nameTokens = [];
  const tags = [];
  // POSITION IS COUNTED WITHOUT THE FURNITURE. "Maria de la Cruz" puts Cruz at
  // raw index 3, where the fourth-token rule fires and would report her surname
  // as a label. `de` and `la` are joiners, not name positions, so the effective
  // position of Cruz is 1, exactly where a surname belongs.
  let position = 0;
  // THE STICKY TAIL. Once a label starts, the rest of the field is label. This
  // is how people write these - name first, annotation after - and it is why
  // "Prez" and "Secretary" need no vocabulary entry after the acronym resolves.
  let inTail = false;

  for (const raw of tokens) {
    if (inTail) {
      tags.push(raw);
      continue;
    }
    if (NAME_FURNITURE.has(norm(raw))) {
      nameTokens.push(raw);
      continue; // a joiner: kept, and it does not advance the position
    }
    if (isLabelToken(raw, position, corpus)) {
      inTail = true;
      tags.push(raw);
      continue;
    }
    nameTokens.push(raw);
    position += 1;
  }

  // NEVER RETURN A NAMELESS PERSON. If every token read as a label the corpus
  // has misled us - a whole family labelled the same way, an address book of
  // acronyms - and the field goes back to being the name whole. This is the
  // structural version of the "Maia IYA" fix: a person with no name cannot be
  // shown, matched or spoken about.
  //
  // THE WHOLE FIELD, not just the first token, which is where this diverges
  // from Amber. Amber promotes `tags[0]` and keeps the rest as labels, and on a
  // phone that is fine because the row it is drawing is a person. This store
  // also holds organisations somebody saved as a contact: "USC Christian
  // Challenge" is the name of a ministry, and promoting one token renders it as
  // "USC" tagged Christian and Challenge, which is a different entity. Handing
  // back the whole string keeps the org intact and costs a real person nothing,
  // because a real person only reaches this branch when the split already
  // failed.
  if (nameTokens.length === 0 && tags.length > 0) {
    return { name: tags.join(" "), nameTokens: [...tags], tags: [] };
  }

  return {
    name: nameTokens.join(" ") || null,
    nameTokens,
    // Furniture is dropped from tags here rather than in isLabelToken so the
    // sticky tail still sees it and does not break on "Smith Jr USC".
    tags: tags.filter((t) => {
      const k = norm(t);
      if (NAME_FURNITURE.has(k)) return false;
      if (FIELD_DEBRIS.has(k)) return false;
      if (/^\d+$/.test(k)) return false;
      return k.length >= 2;
    }),
  };
}

/**
 * The labels this address book actually uses, most common first.
 *
 * This is the part the hand-written list was standing in for. Run the splitter
 * over the whole book and the vocabulary falls out of it: the tokens that land
 * in `tags` on at least `min` different people are what this user annotates
 * with. It is different for every person who installs the kit, which is the
 * whole reason it could never have been a constant.
 */
/**
 * Run the splitter once to learn what this book annotates with, then hand that
 * back as `tailVocab` so a second pass can catch labels sitting in surname
 * position. `min` is how many different people must carry a token in their tail
 * before it counts as this user's vocabulary.
 *
 * Two passes, not more. A third would start promoting tokens the second pass
 * only stripped because the second pass stripped them, which is a list that
 * writes itself rather than evidence.
 */
/**
 * How far a token's tail usage must outweigh its name usage before it counts as
 * this book's vocabulary.
 *
 * MEASURED, NOT CHOSEN. Without this ratio the second pass eats surnames, and
 * it does so because of its own first pass: a three-part Korean name puts the
 * surname at index 2, where the frequency rule fires, so four cards reading
 * "Colin Jiho Kim" and "Hannah Vale Kim" leaked "kim" into the vocabulary
 * and all 43 Kims in the book then lost their surname. A misfire laundered into
 * a rule is worse than the misfire.
 *
 * Counted over Caleb's 3,351 people, tail hits against name hits:
 *
 *   IYA 57:1   USC 38.5:1   A2F 14.5:1   Prez, BISC, AGO all name-free
 *   Christian 1.4:1   Avenues 1.1:1   Maia 0.8:1
 *   Nemmy 0.11:1   Kim 0.10:1   Park 0.06:1   Newton, Chan, Lin 0:1
 *
 * Real labels sit at 14 and above, surnames at 0.11 and below, and the band
 * between is words that are honestly both. 3 sits in the empty gap. Raising it
 * to 10 would also work on this book; lowering it to 2 readmits Kim's cousins.
 */
const TAIL_DOMINANCE = 3;

function refineCorpus(people, corpus = null, min = 3) {
  const cor = corpus || buildNameCorpus(people);
  const tail = new Map();
  const asName = new Map();
  for (const p of Array.isArray(people) ? people : []) {
    const s = splitName(p, cor);
    for (const t of s.tags) tail.set(norm(t), (tail.get(norm(t)) ?? 0) + 1);
    for (const t of s.nameTokens)
      asName.set(norm(t), (asName.get(norm(t)) ?? 0) + 1);
  }
  const tailVocab = new Set(
    [...tail.entries()]
      .filter(
        ([k, n]) => n >= min && n >= (asName.get(k) ?? 0) * TAIL_DOMINANCE,
      )
      .map(([k]) => k),
  );
  // The same evidence read the other way: the tokens this book overwhelmingly
  // uses as names, which the position rules must not override. See isLabelToken.
  const nameVocab = new Set(
    [...asName.entries()]
      .filter(([k, n]) => n >= min && n >= (tail.get(k) ?? 0) * TAIL_DOMINANCE)
      .map(([k]) => k),
  );
  return { ...cor, tailVocab, nameVocab };
}

function discoverLabels(people, corpus = null, min = 3) {
  const cor = corpus || refineCorpus(people, null, min);
  const counts = new Map();
  const display = new Map();
  for (const p of Array.isArray(people) ? people : []) {
    for (const t of splitName(p, cor).tags) {
      const k = norm(t);
      counts.set(k, (counts.get(k) ?? 0) + 1);
      if (!display.has(k)) display.set(k, t);
    }
  }
  return [...counts.entries()]
    .filter(([, n]) => n >= min)
    .sort((a, b) => b[1] - a[1] || a[0].localeCompare(b[0]))
    .map(([k, n]) => ({
      key: k.toUpperCase(),
      label: display.get(k),
      count: n,
    }));
}

module.exports = {
  tokenizeName,
  buildNameCorpus,
  refineCorpus,
  splitName,
  discoverLabels,
  NAME_FURNITURE,
  FIELD_DEBRIS,
  ROLE_WORDS,
};
