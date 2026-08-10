---
name: second-brain
description: Read from and write to the user's personal context repo, the private markdown store holding who they are, what they are working on, who they work with, and how their systems are wired. Use when the user asks what you know about something, states a durable fact worth persisting (new role, project shipped or died, collaborator joined, preference, infrastructure change), says "remember this", asks for a context review, or when substantial work just changed something that context should reflect. Also use before advising on anything personal, so the advice is grounded in their actual situation rather than a guess.
---

# Second brain

The context repo is the difference between an assistant that knows the user and
one that asks the same three questions every session. It is plain markdown in
git, not a database, and that is deliberate: the user can read it, correct it,
and see its history.

Your job is to keep it true and to use it before guessing.

## Layout

```
core/       loaded into every session automatically
domains/    read on demand: health, faith, money, whatever runs deep
projects/   read on demand: one file per real project
systems/    read on demand: infrastructure, tooling, accounts
memory/     granular auto-memory, one fact per file, indexed by MEMORY.md
```

`core/` is small on purpose. Everything there costs tokens in every session on
every project, so it holds only what is true regardless of what the user is
doing: identity, current state, people. Everything else is read when relevant.

## Reading

**Grep before you ask.** `grep -ri "<term>" <context-repo>` is the fast path and
it beats asking a question the repo already answers. Being asked something you
were told three weeks ago is the failure this system exists to prevent.

**Read the specific file, not the whole repo.** If the user mentions a project,
read that project's file. Loading everything is slow and crowds out the actual
work.

**Check `core/now.md` first for anything time-sensitive.** It is the most useful
file and the most likely to be stale.

## Writing

Update it as work happens, in the same turn, without being asked and without
announcing it. A new role, a project shipping or dying, a collaborator joining,
a preference stated, something breaking or getting fixed: write it to the right
file while it is true, not at the end of the session when it has been forgotten.

Five rules, each of which exists because its absence rots the repo:

**One fact, one home.** Before adding anything, grep for it. If it already
exists, update that file. Duplicated facts are how these systems die: five
copies in five directories, all disagreeing, all stale, none authoritative.

**Volatility decides the file.** Stable facts (identity, values) go in files
reviewed rarely. Volatile facts (current work, priorities) go in `now.md`. A
volatile fact in a stable file is how an identity file ends up lying about what
semester it is.

**Absolute dates only.** "Last week" is meaningless to a session six months
from now. Every dated claim gets `YYYY-MM-DD`.

**Mark what you are unsure of.** A question mark on a carried-over claim is
worth more than false confidence. A future reader needs to know what was
verified and what was inherited.

**If the user contradicts the repo, the user is right.** Fix the file in the
same turn. Never argue with someone using their own stale notes.

## What does not belong

- Anything derivable from a codebase: structure, git history, past fixes
- Anything that only matters inside one conversation
- Secrets. Those live in a password manager or environment variables, never here

If asked to remember something in one of those categories, ask what was
non-obvious about it and save that instead. "We fixed the auth bug" is in git.
"Auth breaks whenever the staging env var drifts, and it has happened three
times" is worth keeping.

## Granular memory

`memory/` holds one fact per file with frontmatter naming its type: `user`,
`feedback`, `project`, or `reference`. `feedback` and `project` entries carry a
**Why** and a **How to apply**, because a rule without a reason gets
misapplied. Link related entries so the store becomes a graph rather than a pile.

Every new memory file gets a one-line pointer in `MEMORY.md` immediately.
`MEMORY.md` is the index that gets loaded; a memory missing from it is a memory
that will not be found.

## Auditing

When asked to review the context repo, check for:

- Facts that contradict each other across files
- Anything in `core/` that should have aged out into `domains/` or `projects/`
- Relative dates that were never converted
- Projects listed as active that have not been touched in months
- Duplicates, which mean the one-fact-one-home rule slipped

Report what you found and fix the mechanical problems directly. Ask before
deleting anything that looks like judgment rather than rot.
