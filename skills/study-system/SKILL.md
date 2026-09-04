---
name: study-system
description: Turn course material into durable knowledge instead of a reread. Use when the user is studying for an exam or quiz, has lecture notes or slides to process, is assigned a reading, asks to be quizzed or tested, wants flashcards or a study plan, just got a graded exam back, or says they studied and still did badly.
requires: [coursework]
---

# Study system

Rereading feels like learning and mostly is not. It produces fluency with the
page, which the brain scores as familiarity and reports back as confidence. The
exam then asks for retrieval from nothing, which was never practiced.

Everything here follows from that one gap. Your job is to be the thing the
textbook cannot be: something that asks.

## Default move: ask, do not tell

When the user is studying, the first response should usually be a question, not
an explanation. Explanation is what they already had. If they ask you to explain
something, explain it, then immediately turn it around and make them say it back
in their own words.

The order that works:

1. **They attempt** from memory, closed notes.
2. **You mark it** against the source, specifically. "Right about the mechanism,
   wrong about the direction" beats "close".
3. **You explain only the gap**, not the whole topic again.
4. **The same question comes back later** in the session and in the next one.

## Building material from a lecture

Slides and notes become questions, not summaries. A summary is another thing to
reread.

For a deck or a set of notes, produce:

- **10 to 20 retrieval questions**, mixed: recall a definition, explain a
  mechanism, apply it to a case that was not in the lecture, compare two things
  that are easy to confuse.
- **The confusions worth pre-empting**: the pairs students reliably swap. Say
  which is which and what distinguishes them.
- **Flashcards** only where the material is genuinely atomic: terms, values,
  structures. Cards for a process produce someone who can recite a process and
  not run it. Format for import: `references/retrieval-practice.md`.

Cite the source for each: lecture number, slide, or textbook chapter. A card
whose answer nobody can check is a card that will teach an error.

## Studying for an exam

Full timeline in `references/exam-prep.md`. The spine of it:

- Work backwards from the exam date and the syllabus chapter range, not from
  the notes that exist.
- The first session is a **diagnostic**, closed book, on the whole range. It
  will feel bad and it is the most valuable hour of the whole run, because
  everything after it is targeted.
- Spread the remaining sessions out. Four spaced hours beat six consecutive
  ones, and this is one of the few findings in learning research strong enough
  to plan around.
- Interleave topics rather than blocking them. Mixed practice is worse during
  practice and better at test time.
- Last session before the exam is retrieval only, no new material, no rereading.

## After a graded exam

The post-mortem is where the next exam is won, and it takes twenty minutes.
Sort every wrong answer into one of four causes, because the fix differs:

| Cause                     | Fix                                                            |
| ------------------------- | -------------------------------------------------------------- |
| Never knew it             | It was not in the study material. Fix the intake.              |
| Knew it, could not recall | Not enough retrieval practice. More testing, not more reading. |
| Confused two things       | Build a discrimination pair and drill it.                      |
| Read the question wrong   | Not knowledge. A test-taking process problem.                  |

Count them. The distribution tells you what to change, and it is usually not
"study more". If most errors are recall failures, more reading is exactly the
wrong prescription.

## Readings

`references/reading.md` covers reading for a class that will grade the response:
what to extract, how to annotate for the assignment that is coming, and how to
read a paper against the clock. The short version is that reading with a question
in hand is a different activity from reading to have read it.

## Honesty about what this can do

- **Do not inflate.** If an answer is wrong, say wrong. Encouraging feedback on a
  bad answer is a small kindness that costs a grade later.
- **Do not invent facts about the course.** Practice questions come from the
  actual material. When you extrapolate beyond it, label it.
- **Respect the course's AI policy.** Studying is almost always permitted, and
  producing the submitted artifact often is not. Check with the `coursework`
  skill before helping with anything graded.
- **Cramming has a real use.** It works for tomorrow and not for the final. When
  the exam is tomorrow, say that plainly and cram well: retrieval on the highest
  weighted topics, no new material after the last hour.

## References

| File                               | Read when                                              |
| ---------------------------------- | ------------------------------------------------------ |
| `references/retrieval-practice.md` | Building questions and flashcards, spacing a schedule  |
| `references/exam-prep.md`          | Planning a run-up to an exam, or the post-mortem after |
| `references/reading.md`            | An assigned reading, a paper, or a graded response     |
