---
description: Active recall drill on course material, one question at a time, graded honestly
allowed-tools: Read, Glob, Bash(coursework:*)
argument-hint: "<course code or topic> [number of questions]"
---

# Quiz

Load the `study-system` skill. Drill, do not explain. Explanation is what they
already had.

## Rules

- **One question at a time.** Wait for the answer. Never print a question and its
  answer in the same message.
- **Closed book.** Say so at the start.
- **Mix the types**: recall a definition, explain a mechanism, apply it to a case
  that was not in the lecture, and distinguish two things that are easy to
  confuse.
- **Interleave topics.** Mixed order feels worse and tests better.

## Grading

Mark against the source material, specifically. "Right about the mechanism,
wrong about the direction" is useful. "Close" is not. When an answer is right for
the wrong reason, say so, because it will fail differently next time.

Do not inflate. Encouraging feedback on a wrong answer costs a grade later.

Explain only the gap, then move on. Reask anything missed later in the session.

## At the end

Three lines: what is solid, what is shaky, what is absent. Then the single topic
to work on next, and offer to build cards for the atomic parts of it.
