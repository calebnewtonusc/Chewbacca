# Does Chewbacca learn? No. Here is exactly why, and what would fix it.

Caleb asked on 2026-09-21 whether any reinforcement learning had been
implemented, and then asked for a big emphasis on it. The honest answer is
that the machinery for a learning loop is mostly built and **the loop has
never closed once**. This file says precisely where it is open, so the next
person fixes the gap instead of rebuilding the parts that already work.

---

## What exists

| Piece | What it does | Real? |
| --- | --- | --- |
| `bin/evolve` | Applies a patch in an isolated worktree, scores it, archives the result | Yes, and it works |
| `bin/fitness` | Scores the kit: structural, and behavioural against eval cases | Yes |
| `bin/scars` | Failures written down so a later session inherits them | Yes |
| `memory/` | One fact per file, indexed, loaded every session | Yes |
| `.claude/hooks/ask-capture.sh` | Every prompt Caleb types, to `~/.chewbacca/asks.jsonl` | Yes, 86 captured |
| `write-log.tsv` | Which session wrote which path | Yes, 148 rows |

That is a reward function, an archive, isolation, a memory, and a log of
every request the user has ever made. It is most of an RL system.

---

## Why it is not learning

**The score has never moved.** Ten runs in `~/.chewbacca/fitness.jsonl`, and
`structural_score` is **90.12 in all ten**. A reward signal that returns the
same number regardless of the policy carries no information, and optimising
against it is a no-op dressed as progress.

**The behavioural score was recorded once.** Nine of the ten rows have
`behavioural_score: null`. The tenth says 84.76, with 139 passed and 25
failed.

**Nothing records WHICH 25 failed.** `failed` is the integer `25`. Credit
assignment is the entire problem in RL, and a scalar count makes it
impossible: there is no way to attribute the loss to a rule, a skill, a
prompt line, or a hook, so there is nothing to update.

**`evolve` deliberately never merges.** That is a defensible design and it is
written up in the file itself, but it means there is no selection step. An
archive with no selection is a museum. Variation without retention is not
evolution, and it is not learning either.

**The 86 captured asks are never read by anything.** Every correction Caleb
has typed is on disk, and nothing consumes them. That is the single largest
unused signal in the kit.

---

## What it IS, honestly

`evolve` is closer to the **Darwin Godel Machine** than to reinforcement
learning: archive-based evolutionary search over self-modifications, scored
by a benchmark. That is a legitimate and current approach, and it is not the
same thing as a policy updated from reward, so the two should not be
conflated when describing what this does.

Except that a DGM keeps the improvements it finds. This one does not.

---

## What would close the loop

In order, because each step is useless without the one before it.

**1. Make the reward move, and make it attributable.** `fitness` must record
WHICH eval cases failed, by id, every run. Until then nothing downstream is
possible. This is small and it is the blocker.

**2. Assign credit.** Each eval case names the rule, skill or prompt section
it exercises. A failure then points at a specific line of policy rather than
at the kit in general.

**3. Name the policy.** The policy here is not weights. It is the prompts,
the rules in `.claude/rules/`, the skill descriptions, and the hooks. Those
are the things a gradient would move, and they are all text under version
control, which is a considerable advantage over weights.

**4. Close it, behind a gate.** `evolve` gets a merge path that requires: the
behavioural score to rise, no eval case to regress from pass to fail, and the
full test suite to pass. A human approves the diff. That is the retention
step the archive is missing.

**5. Mine the asks.** 86 prompts, including every "bruh" and every
correction. A correction following a failure is a labelled example, and this
is the closest thing to on-policy data the kit will ever have. Gavin's
framing on 2026-09-21 was the same idea from the other direction: *"automate
prompting where whatever I say automatically gets interpreted by the engine
as self learning."*

---

## The hard line

A kit that optimises its own score will optimise the score. Goodhart is the
default outcome of every step above, and the counterweight is already
written in `methods/doctrine.md`: the test is whether the people
around us are being transformed, and whether they can now do something they
could not, **eventually without it**.

So the behavioural evals have to measure whether Caleb got further, not
whether the kit looked clever, and any metric that can be moved without him
being better off is the wrong metric. Write the eval that could FALSIFY an
improvement before writing the improvement.

Built with Chewbacca
