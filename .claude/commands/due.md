---
description: What is due, soonest first, with what it is worth and what is already late
allowed-tools: Bash(coursework:*), Bash(date:*)
argument-hint: "[days, default 14]"
---

# Due

```bash
coursework due --days ${ARGUMENTS:-14}
```

Print the list. Then, in at most three lines:

- **What is at risk**, meaning anything due in 48 hours that has not been started.
- **The one to start now.** Rank by deadline distance against weight, and name a
  single thing. Not a schedule for the week.
- **Anything overdue that is still recoverable**, with what it costs to be late,
  from `coursework policy <course> late`.

If the list is empty, say so in one line and stop. Do not invent work.
