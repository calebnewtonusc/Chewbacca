---
description: Read a syllabus end to end and write it into the coursework ledger, with every date sourced
allowed-tools: Bash(coursework:*), Bash(ls:*), Bash(mkdir:*), Bash(cp:*), Read, Write, Edit, Glob
argument-hint: "<path to syllabus PDF or spreadsheet> [course code]"
---

# Syllabus

Turn a syllabus into a machine-readable course file. Load the `coursework` skill
and follow `references/syllabus-intake.md`. This is the one command where being
slow is correct: every later answer about this course is only as good as this
pass.

## Step 1: read all of it

Read every page of $ARGUMENTS. Not the first page, not a skim. Exam dates live on
the last page, the attendance penalty hides after the grading table, and the AI
policy is under academic integrity three pages from where it should be. For a
spreadsheet, dump every sheet.

## Step 2: extract

Identity, meetings (lecture, lab, and discussion as separate entries), people,
every dated deliverable, the grading breakdown, the attendance arithmetic, and
the policies quoted verbatim. Never paraphrase a policy: a summarized ban reads
as a suggestion in November.

## Step 3: write the course file

```bash
mkdir -p "${COURSEWORK_DIR:-$HOME/coursework}/courses"
```

Write `courses/<code-slug>.yml` using `templates/coursework/course.yml` as the
shape. Every deliverable carries `source` naming the page it came from. Copy the
syllabus itself into `syllabi/` so any claim can be re-checked later.

If this is the first course, write `semester.yml` too, including the registrar
milestones: the last day to drop without a W, the last day to withdraw, and the
finals window.

## Step 4: verify and report

```bash
coursework check
coursework due --days 30
```

Report three things, in this order:

1. **The next three deadlines**, with dates.
2. **What this course costs in absences**, in its own numbers.
3. **What the syllabus did not say.** Missing AI policy, missing room, undated
   assignments handled by later prompts. That list is the set of questions to
   ask in class this week. Do not fill any of it with a guess.

Flag a stale year in the schedule header: check whether the weekday names match
the dates for the current year before trusting a single date in the table.
