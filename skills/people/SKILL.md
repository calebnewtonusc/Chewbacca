---
name: people
description: Remember everything about the people in the user's life, and notice who is slipping. Use when they mention a person by name, tell you something about someone, ask who they know at a company or in a field, ask who to reconnect with, mention a birthday or a job change, come back from a meeting or a call, or ask what you know about someone. Also use before drafting any message to a named person, so the draft is grounded in what is actually true about them.
---

# People

Most of what a person knows about the people in their life is never written
down. It sits in their head, decays, and is gone. The parts that survive land in
five places that do not talk to each other: a contacts app with names and
nothing else, a notes app, message history, memory, and the vague sense that
they owe someone a call.

This skill is one place for all of it, on their machine, in a file they own.

The design is ported from Amber's identity service with the permission of its
authors, Karthik Devarakonda and Sagar Tiwari. Amber is a multi-tenant Cloud SQL
service; this is one SQLite file on a laptop. The ideas carried over; the
tenancy did not.

## The two failure modes

Inventing a fact about a person is worse here than almost anywhere else,
because the user will act on it. They will congratulate someone on a job they
did not get, or ask after a partner who left. If you did not read it from the
database or hear it in this conversation, do not say it. When you write a fact,
record how you know it with `--source`.

Recording a maybe as a fact is the second one. "Thinking about moving to SF"
and "moved to SF" are different rows, not different phrasings. That is what `--modality` is for,
and getting it wrong produces a confidently wrong answer rather than a vague
one. Default is `actual`; use `planned`, `hypothetical`, `desired`, `available`,
or `declined` whenever the user's own wording hedges.

## The CLI

Everything goes through `people`, which ships with this kit. Run it rather than
reading the database, and never write SQL against it directly.

```bash
people today                      # birthdays and who is slipping
people show maggie                # everything known about one person
people note maggie "got promoted" --dim financial
people log maggie --channel call  # you actually talked
people reconnect                  # who you owe a message
people rank --dim financial       # who is struggling with what
people search "hiking"
people intro Anthropic            # who could introduce them
people import --mac               # read the macOS Contacts app
people task add maggie "send the book" --due 2026-09-20
people ask maggie                 # what you still do not know about her
```

`people help` has the rest. Add `--json` nowhere: this CLI prints for humans,
and you should read its output the same way.

## Write as the conversation happens

This is the whole point, and it is the part that gets skipped. When the user
mentions something about a person, **write it in the same turn, without
announcing it.** Do not offer to. Do not batch it for the end.

> "just got off the phone with maggie, she's stressed about funding"

```bash
people log maggie --channel call
people note maggie "stressed about the raise" --dim financial,emotional
```

Then answer what they actually asked. One line at the end is enough: "noted".

Things that should always produce a write:

| They say                              | You run                                                   |
| ------------------------------------- | --------------------------------------------------------- |
| Anything factual about a named person | `people note`                                             |
| They talked to someone                | `people log`                                              |
| Someone changed jobs                  | `people update <who> --company X --role Y`                |
| They met someone new                  | `people add "Name" --met "where"`                         |
| A group of people belongs together    | `people circle create` then `people circle add`           |
| They want to hear from someone more   | `people update <who> --cadence 30`                        |
| **They promised somebody something**  | `people task add <who> "..." --due DATE`                  |
| A recurring date that is not a birthday | `people date add <who> "label" --on MM-DD`              |
| Money or an object changed hands      | `people loan <who> --lent "..."` or `--borrowed`          |
| Two people are related                | `people rel <a> <kind> <b>`                               |
| Something is coming up for someone    | `people check-on <who> --in 14d --because "..."`          |
| A durable one-liner about a person    | `people fact <who> <key> "value"`                         |

The promise is the one that gets missed. Observations hold what is true and
interactions hold what happened, and neither has anywhere for "I said I'd send
him the book". When the user says they will do something for a named person, that is
a `people task add`, not a note.

`people rel maggie mother declan` writes both directions, so you never have to
add the inverse yourself.

`people check-on` refuses to run without `--because`. That is deliberate: a
reminder with no reason is a default rather than a decision, and it surfaces in
`people today` with the reason attached so it is actionable rather than nagging.

`people update --company` is not the same as editing a field. It records the
move as an observation, because a job change is news and worth congratulating
somebody on, while an overwrite silently destroys the fact that it happened.

## Dimensions: pass them, do not let the CLI guess

Every observation is scored across six dimensions: **spiritual, emotional,
physical, intellectual, social, financial**. They each decay at their own rate,
because someone's physical situation changes far faster than their spiritual
one.

Without `--dim`, the CLI falls back to keyword matching, which is worse than you
at this and often produces nothing. **Always pass `--dim`.** Multiple are fine
and often right: losing a job is `financial,emotional`.

That is what makes `people rank --dim financial` work, and that question is the
reason the scoring exists at all.

## Circles

A circle is a group: "Hiking", "Church", "Japan 2026", "the Silo team". Members
are people in their address book, not accounts, so anyone can be added whether
or not they have heard of this tool.

When the user makes a circle, classify it in the same turn, because that is what
propagates a fact to every member:

```bash
people circle create "Japan 2026" --desc "the trip crew"
people circle classify "Japan 2026" --kind experience --fact "was on the Japan trip in 2026"
people circle add "Japan 2026" maggie declan sagar
```

`--kind` is `interest`, `experience`, `affiliation`, or `other`. The `--fact`
must be a short third-person statement true of every member and naming the topic
so it is searchable. It is written onto each member and revoked automatically
when membership changes or the circle is deleted.

## Before coffee, a call, or a message

Run `people show <who>` first. It now carries the whole picture in one screen:
quick facts, who they are related to, their dates, what you owe them, anything
of theirs you still have, and the reason for the next check-in.

Then run `people ask <who>`, which lists the questions from the template that
are still blank for that person. That is what turns the completeness score into
something you can act on: it names what to ask about rather than telling you a
relationship is 40 percent known. A message that references what someone is
actually going through beats a well-written generic one, and this is the
difference between a tool that remembers and a tool that autocompletes.

Check the modality on what you find. Never write "congrats on the move" off a
row marked `planned`.

## Storage, and the honest limits

Lives in `~/.chewbacca/people/people.db`, or `$PEOPLE_DIR`. It works with no
setup and never touches the network.

`people sync init <private-git-url>` turns the directory into a git repo so it
follows them to another machine. Tell them to make the repo **private**: it is
everything they know about everyone. `people export` writes readable markdown
next to the database, and `sync push` runs it first so the repo carries both.

## Relationship graphs over time

Everything else answers "where does this stand today". These three answer "is it
getting better or worse", which is the question that changes what they do.

```
people history "Sagar" --days 365 --steps 12   one person's trajectory
people trend --days 90                         who is warming, who is cooling
people snapshot                                freeze today's numbers
```

`history` prints a sparkline for overall standing, warmth, and every dimension
that has any evidence, with the start value, the end value, and the direction.
`--json` gives the raw series for charting.

**Scores for a past date are recomputed, not looked up.** Only observations
recorded on or before that date are allowed to count, so a trajectory is
available the day the feature is installed rather than a year later. That filter
is the whole correctness story: without it a note written last week would land
in last year's score with a negative age, and exponential decay run backwards
becomes exponential growth. Every relationship would appear to be improving.

`snapshot` freezes the current numbers into `score_history`. Use it when they
are about to correct or delete old observations and want the curve to remember
what it actually knew at the time. `history` prefers a frozen point over a
recomputed one for the same day and says so in its output.

Two honest limits to state when it comes up:

- **A flat line usually means missing evidence, not a flat relationship.** The
  curve is only as good as what has been written down. Check the observation
  count in the footer before reading anything into the shape.
- **Warmth needs interactions.** It decays from the last logged contact, so it
  reads as zero for anyone whose interactions were never logged or synced.
  `people texts sync --days 3200` backfills years of iMessage history and makes
  the warmth curve real.

Three things this does not do, which you should say plainly rather than fake:

- **No semantic search.** Search is full-text, so it matches words, not meaning.
  "Who is stressed about money" will not find "worried about rent". Use
  `people rank --dim financial` for that question instead.
- **Syncing a database through git is a compromise.** The `.db` is binary, so
  git cannot merge it. Editing on two machines without pulling first means one
  side has to win. Pull before you write. When both sides have already moved,
  `people sync diff` compares the exported markdown, which is readable even
  though the database is not, and the error tells you the two commands that
  resolve it.
- **No integrations.** Nothing reads their LinkedIn, Instagram, or X. Contact
  import is macOS Contacts, vCard, or CSV, and everything else is written by
  them or by you.

## Never

- Never invent a fact about a person, or infer one confidently from a name
- Never record a hedge as `actual`
- Never overwrite a company or role without `people update`, which keeps the history
- Never `people import --mac` unprompted: it reads their entire address book
- Never write the `.db` with SQL directly; the CLI keeps the search index and
  the derived scores in step, and raw writes silently desynchronize both
- Never quote a score as if it means something absolute. It is a ranking signal
  built from tunable guesses, and `people dims` shows every one of them
