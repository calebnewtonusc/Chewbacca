---
name: what-can-this-do
description: Propose things this kit could do here that the user has not thought to ask for. Use when the user asks what you can do, what they should automate, what they are missing, or says they do not know where to start. Also use on arriving in an unfamiliar repo, and when the user is stuck choosing what to work on.
---

# what-can-this-do

Every other skill assumes the user already knows the task. This one is for
when they do not, which is most of the time, because nobody can hold 39
skills and a second brain in their head.

## Read before proposing

Never answer this from the skill list alone. Read the ground:

- The repo: what it is, what is half-finished, what has no tests.
- `~/.claude/skills/` and `~/Chewbacca/skills/`: what is installed and what
  is quietly unused.
- The second brain, especially `NOW.md` for what is actually live and what is
  broken right now.
- `superassistant recent 20`: what he has actually been asking. Repeated
  questions are the strongest signal available, because a question asked
  three times is a procedure waiting to be written.
- `~/coursework` and the calendar when the week is the constraint.

## Return three, not ten

Three concrete proposals. For each one:

- **What it would do**, in a sentence, in terms of his actual work.
- **The evidence.** What in the files or the history says he needs this. A
  proposal with no evidence is a guess dressed up.
- **The cost.** Roughly how long, and what it touches.
- **Why it is not already done.** Often the honest answer is that it is a
  bad idea, and saying so is worth more than a fourth suggestion.

Rank them. Lead with the one you would actually do.

## Bias toward what repeats

The best candidate is something done by hand more than twice. The second
best is something currently failing silently. Novelty is the worst reason to
propose anything.

## Say what not to build

Close with at least one thing the kit could do and should not, with the
reason. A list that only ever grows is a list nobody trusts.
