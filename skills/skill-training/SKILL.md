---
name: skill-training
description: Update a skill from how a real run actually went. Use right after a skill produces output the user corrects, rejects, or edits before using. Also use when the user says a skill keeps making the same mistake, or asks to make something remember a preference. This is the loop that makes skills improve instead of drifting.
---

# skill-training

A skill that is never updated from real runs decays: the world moves and the
file does not. The correction the user just made is the training data, and it
is gone the moment this session closes.

## When this fires

The user edited the output before using it. Or rejected it. Or said "not like
that." Or fixed the same thing twice. That is the signal, and it is easy to
miss because the work still got done.

## The loop

1. **Name the delta.** What did the output say, what did the user change it
   to, and what is the difference in one sentence. Not the diff. The rule
   behind the diff.
2. **Ask which kind it is.** Three answers, and the user picks:
   - **Persist.** Always do it this way from now on.
   - **One-off.** This case was special, change nothing.
   - **Always ask.** Put a question in the skill at this point.
   Guessing here is how a skill acquires rules nobody wanted.
3. **Edit the skill file**, not the output. Fixing the artifact solves today.
   Fixing the file solves the next twenty.
4. **Append a dated changelog line** to the skill saying what changed and
   what prompted it. A rule whose reason is lost gets removed by whoever
   finds it unconvincing.
5. **Verify the edit landed.** Read the file back and confirm the new text is
   there. A stale string match fails silently, and a change you reported but
   never applied is worse than no change, because it stops both of you from
   ever looking at that spot again.

## Anchor the rule to its incident

A constraint carrying only a rationale gets raised by the next person who
disagrees with the rationale. A constraint carrying what actually happened
does not. Write the observation, not the reasoning.

## Where the lesson goes

Not everything belongs in the skill.

- **A reusable judgment** goes in the skill, or in a rule under
  `~/.claude/rules/` when it spans skills.
- **A repeatable mechanical failure** becomes a test next to the code. A
  paragraph does not fail CI.
- **A fact about the user, a project or a person** goes in the second brain,
  not in the skill. Skills hold instructions. Files hold facts.

If a correction produces none of those, it was a typo. Fix it and move on.

## Keep the skill short

Every training pass wants to add a line. Length is what stops a skill being
obeyed, so a pass that adds should also look for what the addition makes
redundant.
