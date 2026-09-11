---
name: study-guide
description: Build an interactive study guide, review sheet, practice quiz, walkthrough or set of flashcards for a course topic, from lecture notes, slides, a transcript, a reading or a problem set. Produces one HTML file with quizzes, step-throughs and flashcards that records what was missed, so a later session can pick up there. Use when asked to make or extend a guide, to turn notes into practice, or to review before an exam.
requires: [coursework, study-system]
---

# Study guide

The [study-system](../study-system/SKILL.md) skill is the pedagogy: ask, do not
tell; mark the gap specifically; bring the question back later. Its weakness is
that a conversation ends and takes the retrieval practice with it. Next week
starts from zero on material already failed once.

A guide is where that survives. One HTML file with quizzes, step-throughs and
flashcards, plus a JSON sidecar holding per-topic results that `guide progress`
reads back. Write markup only. The runtime is already written.

## Before writing anything

```sh
guide list                       # extend an existing guide, do not start a rival
guide progress                   # what they already got wrong
coursework policy <course> ai    # what help this course actually allows
```

The policy check is not optional and it is not a formality. Courses differ hard:
one bans AI outright, one requires disclosing every prompt, one allows ideation
only. A practice quiz is usually fine where a drafted essay is not, but read the
rule for the specific course before producing anything that reaches an
assignment. If the course bans it, say so and offer to quiz them live instead,
which is a thing you can do with no artifact at all.

If `guide progress` shows missed topics, the new guide opens on those. Do not
rebuild the whole unit because one section was weak.

## Making one

```sh
guide new "cache coherence" --course CSCI170   # writes guides/cache-coherence.html
```

Then edit the file: replace the starter blocks with real content and delete the
ones you did not use. Then:

```sh
guide open cache-coherence
```

**Always tell them to open it with `guide open`, never by double-clicking the
file.** Opened as a `file://` URL the runtime can only reach localStorage, which
nothing outside that one browser can read, so the next session cannot see what
was missed and the entire reason the guide exists is gone. The page says which
mode it is in, in the corner.

## The markup

**Quiz.** One `section.rg-quiz` per concept. `data-topic` is a stable slug and
progress is keyed on it, so renaming it orphans the history.

```html
<section class="rg-quiz" data-topic="mesi-states">
  <h2>Check yourself: MESI</h2>

  <div class="rg-question" data-answer="c">
    <p>A line in the Shared state is written by this core. What state does it move to?</p>
    <ol class="rg-options">
      <li>Invalid</li><li>Exclusive</li><li>Modified</li><li>It stays Shared</li>
    </ol>
    <div class="rg-explain">A write needs ownership, so the other sharers are
    invalidated and the line becomes Modified.</div>
  </div>

  <div class="rg-question" data-answer="a,c">
    <p>Which states allow a silent read hit, with no bus traffic?</p>
    <ol class="rg-options"><li>Modified</li><li>Invalid</li><li>Shared</li></ol>
  </div>

  <div class="rg-question" data-answer="write-back|writeback">
    <p>What does a Modified line do on eviction?</p>
    <input class="rg-input" placeholder="one or two words">
  </div>

  <button class="rg-check">Check answers</button>
</section>
```

`data-answer` takes a letter (`c`), a 1-based index (`3`), a comma list for
select-all (`a,c`), or `|`-separated alternatives for typed answers, matched
case- and whitespace-insensitively.

**Step-through.** A procedure one step at a time, Prev/Next and arrow keys. Put
the resulting **state** in each step, not only the action: the state is the thing
they have to be able to reconstruct in an exam.

```html
<div class="rg-steps">
  <div class="rg-step"><h3>1. Core 0 reads X</h3><p>Miss, goes to memory. Line enters <b>Exclusive</b> in C0.</p></div>
  <div class="rg-step"><h3>2. Core 1 reads X</h3><p>Snoop hit in C0, both now <b>Shared</b>.</p></div>
</div>
```

**Flashcards** and **reveal**:

```html
<div class="rg-cards">
  <div class="rg-card"><div class="rg-front">Write-allocate</div>
    <div class="rg-back">On a write miss, fetch the line, then write into it.</div></div>
</div>

<details class="rg-reveal"><summary>Show the derivation</summary><p>...</p></details>
```

## Writing good questions

This is the whole job. The markup is trivial and a guide full of bad questions
is a worksheet with extra steps.

- **A wrong answer must be tempting.** Every distractor should be something a
  person who half-learned this would actually pick: the right idea in the wrong
  direction, the adjacent term, the answer to the previous question. Three
  obviously-absurd options make a question that tests reading, not knowing.
- **Ask for the mechanism, not the label.** "What does MESI stand for" is
  recognition. "A line is Shared and this core writes it, what happens to the
  other copies" is the thing the exam asks.
- **Use the typed-answer form for anything they must produce from nothing.**
  Multiple choice always leaks the answer set, which is exactly the crutch the
  exam removes.
- **`rg-explain` explains the tempting wrong answer**, not just the right one.
  Saying why C is correct teaches less than saying why B is the trap.
- **Cite sources in the footer**, with the lecture date or slide range. A guide
  whose claims cannot be traced is worth nothing a week later when it disagrees
  with the professor.

## Afterwards

```sh
guide progress                 # what is still wrong
guide progress <name> --json   # for another skill to read
```

Bring the missed items back in the next session before anything new. That is the
whole loop, and skipping it makes the sidecar decoration.
