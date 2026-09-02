---
name: coursework
description: Run the user's semester from a machine-readable ledger built out of their syllabi. Use when they mention a class, an assignment, an exam, a deadline, a professor, a reading, a grade, attendance, or a syllabus; when they ask what is due, what to work on, or whether they can miss a class; when they hand over a syllabus PDF; and before helping with any graded work, because each course sets its own rules about what help is allowed.
---

# Coursework

A syllabus is a contract that states, in writing, every date the student will be
judged on, exactly how much an absence costs, and precisely what help is
permitted. Almost nobody reads it twice. The whole point of this skill is to read
it once, carefully, into a ledger, and then answer from the ledger forever.

Two failure modes to design against, both worse than being slow:

1. **Inventing a date.** A confidently wrong deadline is more damaging than "I
   do not know", because the user stops checking. Every date in the ledger
   carries a `source` field naming the page it came from. If you cannot cite it,
   it does not go in.
2. **Helping in a way the course forbids.** Three courses in one semester can
   have three different AI policies: banned outright, allowed with mandatory
   prompt disclosure, allowed for ideation but not for the submitted artifact.
   Getting this wrong is an academic integrity referral, not a style problem.

## The ledger

Lives in `$COURSEWORK_DIR` (default `~/coursework`), plain YAML in git:

```
semester.yml        term dates, drop deadlines, breaks
courses/*.yml       one file per course
syllabi/            the source PDFs, kept so any claim can be re-checked
```

It is read with the `coursework` CLI, which ships with this kit:

```bash
coursework due --days 14      # what is due, soonest first
coursework today              # today's classes and today's deadlines
coursework week               # the days ahead, one block each
coursework attendance         # absences used against the budget
coursework grade BISC --target 90
coursework policy WRIT ai     # what this course allows
coursework ics --out ~/Desktop/semester.ics
coursework check              # validate, loudly
```

**Run the CLI instead of reading the YAML by hand.** It is deterministic, costs
no tokens to think through, and it will not misread a date the way a skim will.
Add `--json` when you need the values rather than the display.

**The CLI never writes.** You and the user edit the ledger; the tool only reads
it. That split is deliberate: deadlines are facts copied from a document, and a
program that rewrites them can quietly disagree with the source.

## Before helping with anything graded

Run this first, every time, no exceptions:

```bash
coursework policy <course> ai
```

Then say what it returns, in one line, before doing the work. Not as a lecture:
as a fact the user needs in order to decide.

- **Banned:** do not draft, outline, or generate any part of the submitted
  artifact. Everything else is still available: explain the concept, quiz them,
  find where their reasoning broke, build a study plan, read their draft back to
  them and point at what is unclear. Say plainly which side of the line you are
  on.
- **Disclosure required:** help as asked, then write the disclosure paragraph
  with them: which tool, how it was used, the actual prompts. Leaving it off is
  the violation, not the use.
- **Ideation only:** brainstorm and pressure-test freely, hand over nothing that
  could be pasted in as the deliverable.
- **Unknown:** treat it as banned and tell them to ask the instructor. An
  unrecorded policy is not a permissive one.

This is also the user's own standard, not just the school's. The frustration to
avoid is AI doing the work instead of them learning it. Optimize for the version
of them that walks into the exam knowing the material.

## Reading a syllabus into the ledger

Full procedure, including what to do about the fields syllabi routinely omit:
`references/syllabus-intake.md`. Read it before ingesting a syllabus, not after.

The short version: read the whole PDF, never a skim of the first page. Extract
meetings, instructor, every dated deliverable, the grading breakdown, the
attendance arithmetic, the AI policy verbatim, and the late-work schedule. Write
one `courses/<code>.yml`. Run `coursework check`. Report what the syllabus did
not say, because that list is the set of questions to ask in class.

## Answering questions about the semester

- **"What's due?"** `coursework due`. Do not editorialize the list into a plan
  unless asked; the list is usually the answer.
- **"What should I work on?"** Rank by deadline distance times weight, then say
  the one thing to start now. Not a schedule for the whole week: the next block.
- **"Can I skip Wednesday?"** `coursework attendance <course>` and quote the
  real cost. In a labor-contract course the third absence can be a full grade
  step, and a doctor's note may not excuse it. This is arithmetic, so do the
  arithmetic instead of offering encouragement.
- **"How am I doing?"** `coursework grade`. For a contract-graded course the CLI
  refuses to produce a number and points at the policy, which is correct: read
  `references/grading-models.md` and count infractions against the step table
  instead of averaging scores that do not exist.
- **"I'm behind."** Triage, do not motivate. What is unrecoverable (a missed exam
  with no makeup), what is cheap to save (a late ancillary assignment worth one
  step), what is already sunk. Then one action.

## Keeping it true

The ledger goes stale in exactly three ways, and all three are silent:

- **A date moves in class** and the PDF still says the old one. When the user
  mentions a change, update the ledger in the same turn and set `source` to
  "announced in class YYYY-MM-DD".
- **Work gets done** and stays marked `todo`, so `due` keeps shouting about it.
  Flip `status: done` as things land.
- **An absence happens** and `absences.used` never moves. Increment it when the
  user says they missed a class. This is the field that decides a grade step and
  nobody remembers it in November.

Run `coursework check` at the start of any session that touches school. It
reports missing AI policies, deadlines with no source, past-due items still open,
and grading weights that do not sum to 100.

## References

| File                            | Read when                                                            |
| ------------------------------- | -------------------------------------------------------------------- |
| `references/syllabus-intake.md` | Ingesting a syllabus into the ledger                                 |
| `references/grading-models.md`  | Weighted, points-based, or labor-contract grading math               |
| `references/integrity.md`       | Deciding what help a course actually permits, and how to disclose it |
