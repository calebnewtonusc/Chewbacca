---
description: Absence budget across courses, what the next one costs, and how to buy it back
allowed-tools: Bash(coursework:*), Bash(date:*), Edit
argument-hint: "[course code] | miss <course> [date]"
---

# Attendance

```bash
coursework attendance $ARGUMENTS
```

## Answering "can I skip Wednesday?"

This is arithmetic, not encouragement. Quote the real cost from the policy:

- In a labor-contract course, the third absence can be a full grade step, and a
  doctor's note may not nullify it.
- In a course that drops a third of a letter per absence, the fourth one is a
  letter grade.
- Check whether the free absences may be spent on the day in question at all.
  Many courses forbid using them on quiz, exam, or presentation days.

Then check whether it can be bought back. Make-up attendance assignments exist in
more courses than people realize, are usually capped at a few uses, and almost
always expire one week after the absence. That deadline is the one that gets
missed, not the assignment.

## Recording one

When the user says they missed a class, increment `absences.used` in the course
file in the same turn. Nobody remembers this in November, and it is the field
that decides a grade step.

If a make-up is available, say what it requires and when it expires, in one line.
