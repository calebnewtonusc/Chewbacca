---
description: After a graded exam, sort every wrong answer by cause and fix the actual failure
allowed-tools: Read, Bash(coursework:*), Bash(date:*), Write
argument-hint: "<course code> [exam name]"
---

# Postmortem

Twenty minutes with a returned exam is worth more than the next three study
sessions. Load the `study-system` skill.

## Step 0: the regrade clock

```bash
coursework policy $ARGUMENTS regrade
```

Check this first. Many courses give one week from the day the exam was returned,
demand a specific request format, and reject anything incomplete without notice.
That window expires while the postmortem is being scheduled.

## Step 1: record the score

Update the `grading` entry in the course file with the real score, then:

```bash
coursework grade <course> --target 90
```

Now the standing is a fact rather than a feeling, and "what do I need on the
final" has an actual answer.

## Step 2: sort every wrong answer

| Cause                     | Fix                                               |
| ------------------------- | ------------------------------------------------- |
| Never knew it             | It was not in the study material. Fix the intake. |
| Knew it, could not recall | More retrieval practice. Not more reading.        |
| Confused two things       | Build the discrimination pair, drill both ways.   |
| Misread the question      | Process, not knowledge. Slow down on the stem.    |

Count them. The distribution is the prescription, and it is usually not "study
more".

## Step 3: one change

Name a single change to how the next unit gets studied, specific enough to do
this week. Then build the first artifact for it: the missing cards, the
discrimination drill, the intake fix.
