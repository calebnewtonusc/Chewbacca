---
description: Build a study plan for an exam or a topic, working backwards from the date and the actual material range
allowed-tools: Bash(coursework:*), Bash(date:*), Read, Write, Glob
argument-hint: "<course code> [topic or exam name]"
---

# Study

Load the `study-system` skill. Plan from the exam, not from the notes that
happen to exist.

## Step 1: the three facts

```bash
coursework due --days 45
coursework grade $ARGUMENTS
```

The date, the exact material range, and the format. The range is the one people
get wrong: "chapters 1 to 5" and "everything through week 5" can differ by a
chapter. Get it from the syllabus schedule, not from memory.

Also check what it is worth and whether a makeup exists. A course with no
makeups changes what exam morning costs.

## Step 2: diagnose before planning

Do not build a schedule over unknown ground. Run a closed-book diagnostic across
the whole range, 20 to 30 questions, right now. Score it, and sort the material
into solid, shaky, and absent.

This step gets skipped constantly and it is the reason study time lands on the
chapter that was already fine.

## Step 3: the plan

Spaced sessions from today to the exam, interleaved across topics, weighted
toward shaky and absent. Each session opens with retrieval on what was missed
last time. One session under exam conditions with the real time limit. The last
session is retrieval only, nothing new.

Write it into the ledger's course notes or the user's task list so it survives
the conversation.

## Step 4: hand them the first session

Not the whole plan. The first set of questions, now.
