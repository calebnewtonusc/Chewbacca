---
name: kit-builder
description: Build a kit, a repo somebody lives inside for weeks while an agent walks them through a process they have never done and will not do again for years. Use when the user faces a long multi-session process with a deadline and an evaluator (applications, appeals, accommodations, estate admin, a job search, a fundraise, a thesis), when they ask for help with something bureaucratic they have never done, when they want to hand a process to a friend, or when they say "make a kit". Also use to decide whether an idea should be a kit at all, because most should stay skills.
---

# Kit builder

A **skill** is one file that loads when relevant, fires once, and forgets. That is the
right shape for most things and it is what you should build by default.

A **kit** is a repo somebody lives inside for weeks. It carries state between sessions,
drives the conversation instead of waiting for a prompt, and does arithmetic in real
scripts because the model gets numbers wrong. It is the right shape when somebody has to
be walked through something over weeks, under a deadline, where a wrong fact is expensive
and they have no instincts to fall back on.

Almost nobody in the ecosystem ships kits. There are thousands of skills. That gap is the
opportunity, and it is also the trap: the temptation is to build a kit for everything,
and a kit built around an afternoon's work is just ceremony around a prompt.

## First, run the test. Out loud, in one line each.

Seven properties. **Five or more is kit-shaped. Four or fewer stays a skill.**

1. **Spans sessions.** Days or weeks. State survives a closed laptop.
2. **The bottleneck is extraction, not generation.** They have the material and cannot get
   it out. Nobody ever asked them the right question.
3. **A hidden evaluator.** Somebody scores this against criteria not written on the form.
4. **A mechanical constraint the model reliably fails.** Word counts, date arithmetic,
   dollar totals, page limits. Something needing a real script.
5. **Rare and high-stakes.** Once every few years, so no instincts and no way to build any.
6. **Facts must stay consistent across many artifacts.** One canonical set feeding a dozen
   documents.
7. **A professional would run a process, and most people do not know it exists.**

**Property 4 is the one people skip, and skipping it is why most "kits" are just folders
of markdown.** If you think your domain has no arithmetic, look harder. Days between
dates, totals of a column, counts of anything: every one is a place a model produces a
confidently wrong number.

Score it before writing a single file. Say the score and say which properties failed. If
it scores four or lower, say so and write a skill instead. That refusal is the most
valuable thing in this file.

## Before anything: check what exists

```
kits
```

Finds every kit on this machine by its `.kit` marker. **If one already covers this, `cd`
there and work inside it.** It holds their state and their deadlines, and working outside
it throws that away.

## Then build from the template

```
git clone https://github.com/calebnewtonusc/kit-template <name>-kit
cd <name>-kit && rm -rf .git && git init
grep -rn "{{" --include="*.md" --include="*.sh" .
```

Everything general is already there and should not be rewritten: the phase machine,
`PROGRESS.md` plus the session-start hook, the `TEMPLATE: unfilled` convention, the five
override rules, six domain-agnostic plays, four skills, and `stale.sh` plus `deadline.sh`.

Read `MAKING-A-KIT.md` in the clone. It is the authoring guide and it is more current
than this file.

## What you actually write

In order of how much it matters.

**1. The phases in `CLAUDE.md`.** This is the kit. A phase is not a chapter heading, it is
a rule for deciding what to ask next given what is already known. Write them so an agent
reading `PROGRESS.md` can locate itself without asking the person where they are.

**2. The opening question.** Phase 0 gets exactly one, and picking it well is most of the
difference between a kit that works and one abandoned in session one. It is almost never
"tell me about yourself." It is usually the clock, because the clock decides everything
downstream.

**3. `reference/`, one file per variant.** The method is usually constant across variants
and the evaluator is not. One file each, and the agent reads only the one that applies.

**4. `tools/`, the arithmetic.** POSIX `sh`, no gawk extensions, no `date -d`, so it runs
the same on macOS, Linux and Git Bash. Every tool exits non-zero on a real problem so it
can gate a step.

**5. Rule 4, the hard line.** Every kit needs one thing it refuses to do, named
explicitly, with what it does instead. Write it before anything else, because it shapes
every other file and a kit without one will eventually hurt somebody. See
`references/hard-lines.md`.

## The rules the kit inherits and you do not rewrite

Drive the conversation, never ask permission, three to five questions at a time, pick
lists the moment answers get thin. Never invent a fact about them. Never invent a fact
about the other party. Never ask what is already answered. **And rule 5: facts expire.**

Rule 5 exists because of a real failure. Somebody said in week one they were taking
eighteen units, dropped a class at add/drop, and six weeks later four submitted
applications carried a false number. Every honesty check passed, because the fact was
honest, sourced, and correct when written. `stale.sh` and the `Checked` columns are the
enforcement. Do not remove them from a kit because the domain "does not have numbers."
Every domain has facts that go stale.

## The bar is not "a kit," it is these two

**apply-kit and accommodations-kit.** Every floor in the checker is measured from the
weaker of them, so meeting it is not aspirational.

```
sh tools/kit-check.sh
```

Nineteen checks. **Zero failures or it does not ship.** Both reference kits pass all
nineteen clean; a fresh clone of the template fails five.

The check people try hardest to argue around is the domain tool. If you believe your
domain has no arithmetic, look harder. Days between dates, totals of a column, counts of
anything. apply-kit counts words because a model cannot. accommodations-kit checks whether
a letter was actually delivered and whether a booking window is closing, which is the
entire failure it exists to prevent.

Then read `STANDARD.md` and answer its four questions out loud, because they are what
actually separate a good kit from a folder of markdown that passes nineteen checks:

1. Would a tired person at 11pm answer your opening question, or close the terminal?
2. Do your interview questions get at something nobody has ever asked them?
3. Does the kit sit where people actually fail, or where the process starts? Almost nobody
   fails at registration.
4. If the agent followed rule 4 exactly, would the kit still be worth opening?

**A kit that passes nineteen checks and fails those four is worse than one that fails a
check and passes them.**

## Before handing it to anybody

```
sh .claude/hooks/session-start.sh
sh tools/stale.sh
sh tools/deadline.sh
python3 -c "import json;json.load(open('.claude/settings.json'))"
```

Then simulate a ZIP download, which is how most people will get it and which strips the
executable bit off every script:

```
mkdir -p /tmp/kittest && tar --exclude=.git -cf - . | (cd /tmp/kittest && tar xf -)
chmod 644 /tmp/kittest/tools/*.sh
cd /tmp/kittest && sh tools/stale.sh && sh .claude/hooks/session-start.sh
```

Everything must work invoked as `sh tools/whatever.sh`. Never document a bare
`./tools/whatever.sh` as the only way to run something.

**Last and most important: fill in a fake profile with one deliberately stale fact and
confirm the briefing surfaces it.** Cold start and returning user are different code
paths and only one gets exercised while you build. A real bug shipped this way: the
`TEMPLATE: unfilled` check ran inside awk, but the marker sits at the bottom of the file,
so awk had already processed every row above it. Empty templates hid it completely.

## Write the marker, or it will get rebuilt

Every kit carries a `.kit` file at its root. This is not optional. It is what makes the
kit discoverable by `kits` and by the session briefing, and it is the difference between a
tool that extends itself and one that builds the same thing twice.

```
name: <domain>-kit
domain: <one line, what it covers>
use-when: <concrete phrases somebody would actually say, comma separated>
status: ready
```

**Keep `use-when` in their words, not yours.** It gets matched against what somebody types
at three in the morning. "a professor ignoring an accommodation letter" routes correctly.
"post-approval implementation failures" does not.

Then confirm it took:

```
kits --context
```

## Then push it

Kits are repos, per the "Deliverables ship as repos" doctrine. Public unless the domain is
personal. Tell the user the URL.

## Reference

- `references/scoring.md` — worked examples of the test, including ideas that failed it
- `references/hard-lines.md` — writing rule 4 for domains that touch law, medicine, money
- `references/existing-kits.md` — what is already built, so nothing gets built twice
