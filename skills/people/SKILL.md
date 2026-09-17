---
name: people
description: Remember everything about the people in the user's life, answer questions about their network, and notice who is slipping. Use when they mention a person by name, tell you something about someone, ask who they know at a company or in a field, ask who to reconnect with, mention a birthday or a job change, come back from a meeting or a call, or ask what you know about someone. Also use before drafting any message to a named person, so the draft is grounded in what is actually true about them. Also use for when did I last talk to someone, how long has it been since I spoke to them, what did we talk about last time, catch me up on this person before I see them, and who have I not replied to. ALWAYS use for any question shaped like "who do I know who ...", including who do I know in a city, at a company, in an industry, who has raised money, who is a founder or an investor, who went to my school, who could introduce me to someone, who did I meet through a person, who from a place has been funded, and who that I know has moved into a more senior role. Also use when they want to import or sync a LinkedIn export, match LinkedIn connections to their contacts, find where their connections live or work, or spot who changed jobs.
requires: [people]
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
people mute <who> --because "..."  # keep the record, stop the nudges
people unmute <who> | people muted
people rank --dim financial       # who is struggling with what
people search "hiking"
people intro Anthropic            # who could introduce them
people import --mac               # read the macOS Contacts app
people task add maggie "send the book" --due 2026-09-20
people ask maggie                 # what you still do not know about her
people dashboard                  # who you texted, ranked and categorised
```

`people help` has the rest. Add `--json` nowhere: this CLI prints for humans,
and you should read its output the same way.

## "Who do I know who ..."

The question a relationship store exists to answer. **Never answer it from
memory or from the conversation.** Run `people who` with the user's sentence,
close to verbatim, and report what comes back.

```bash
people who "who do I know in hardware in San Francisco"
people who "founders I know who have raised recently"
people who "people I know at YC companies"
people who "investors I know in New York"
people who "who from my high school has been funded"
```

It reads the sentence and pulls facets out of it: a place, an industry, an
employer, whether somebody founded a company or invests in them. It needs no
flags and no prefix, because a person asking this question types a sentence.

**It says what it could not do.** When the sentence names a city and the people
it found have no location recorded, it prints that rather than quietly dropping
the filter. Report that line too. A list that looks right because half the
question was skipped is the worst possible answer here, and the user has no way
to see it happened.

### Where the data comes from

Two imports make these questions answerable, and both are worth running before
the first one is asked:

```bash
people texts sync                 # their own message history
people linkedin sync              # a LinkedIn export in ~/Downloads
people linkedin locate            # where those connections live, and their roles
```

`people linkedin sync` matches a LinkedIn export against the contacts app. **It
never creates a contact.** It walks the address book looking for a LinkedIn
record for each card, so connections with no card stay out; the only write is a
company onto a card and a note. It also learns nicknames, and keeps whatever the
user typed into a contact name ("Reid Superman IYA") as how they know them.

**Asked where a connection lives or what they have done, the whole answer is
one command:**

```
people linkedin locate --who "Nathan Wang"
```

It prints where they live and their dated work history, and it costs nothing.
Do not go looking for the LinkedIn export on disk, do not open Contacts, and do
not start a filesystem sweep. The export is already imported and that command is
the free path.

**Check the key before saying anything about cost.** `cat ~/.chewbacca/clay-key`
is the whole check, and if it is there the answer is not "that costs credits".
Never make the user tell you a key exists that is sitting on their own disk.

**Read the balance with `clay-balance`, never `clay credits balance`.** Clay's
own CLI answers `auth_required` until somebody completes a browser login, which
an agent cannot do, and reporting the balance as unavailable on that basis is
wrong: `clay-balance` reads the stored key and returns the number.

The reason the cheap path exists: **Clay bills enrichment, not search.**
Resolving a phone number to a profile is billed per record. Searching by name
is free, and it returns location and dated work history in the same response.
The export already holds each connection's profile URL, so the right person
falls out of a string match instead of a paid disambiguation.

`people linkedin locate` needs a Clay API key in `~/.chewbacca/clay-key`, one
line, no quotes. It fills in where people live and what they have done,
using a search that costs nothing rather than an enrichment that is billed per
record. The export already carries each connection's profile URL, so the
result is matched on that URL exactly instead of guessed at. It is resumable:
run it again and it skips everyone already done.

`people linkedin changes` finds job changes for free by comparing two exports.
For anyone already connected, a fresh export is the cheapest job-change feed
there is, and no paid lookup is needed.

## Questions that need more than one source

`people who` filters one table. Most interesting questions are not one filter,
and answering them with a single command is the difference between a database
and an assistant. **Decompose, run several commands, then synthesise, and say
which source each claim came from.**

Five sources, and they know nothing about each other:

| Source           | Holds                                                       | Reach it with                    |
| ---------------- | ----------------------------------------------------------- | -------------------------------- |
| Texts, distilled | what somebody said they care about, believe, are working on | `people show`, `people search`   |
| Texts, inferred  | affiliations nobody typed, with a confidence                | `people infer`                   |
| LinkedIn export  | employer, title, dated career, who asked to connect first   | `people who`, `people show`      |
| Clay search      | where they live now, roles with dates, free                 | `people linkedin locate`         |
| Group threads    | who talks in which room, and to whom                        | `people show`, the `room` column |

**They cover different people, and that is the whole problem.** On this machine
583 people have facts from texts and 2,242 have a LinkedIn record, and only 99
have both. The people you text and the people you connect with professionally
are two populations with a thin, valuable overlap. A question that assumes
every person has every kind of data returns nothing and looks like an empty
answer rather than a mismatch.

### Worked decomposition

> "Who should I get coffee with in SF next week?"

Wrong: one `people who "people in SF"` and a list.

Right, four passes:

```bash
people who "people I know in San Francisco"   # LinkedIn + Clay: who is there
people reconnect                               # who is overdue, from message history
people show <each candidate>                   # facts from texts: what they care about
people infer --rule <relevant>                 # anything inferred, marked as such
```

Then answer as a person would: three names, why each one, when they last spoke,
and one concrete thing to open with that came out of an actual conversation.

> "Which of my USC friends ended up somewhere I'd want to work?"

`people who "people I know at YC companies"` gives employers. `people show` on
each gives what they said in texts. The answer joins them: not a list of
companies, but "you talked to X about Y, and he is now at Z."

### Rules for synthesising

- **Name the source of each claim.** "He said in March" and "his LinkedIn says"
  and "inferred from how often he mentions it" carry different weight, and the
  user needs to know which one they are acting on.
- **Say who was excluded for missing data**, not just who matched. "Four more
  are in SF but I have never recorded anything about them" is part of the
  answer.
- **Prefer the text over the profile** when they disagree about a person. A
  title is what somebody publishes; a message is what they said.
- **Never merge an inference into a stated fact.** See below.

### Inferred answers are marked, never blended

`people infer` concludes things nobody typed in, from rules over the message
history and the stored columns. Everything it writes is `source='inferred'` and
carries the rule, the evidence and a confidence in its body.

When an inferred fact is part of an answer, **say so in the same breath**. "Two
of these are inferred from how often they mention the school, not stated." A
guess that reaches the user as a statement is the failure this whole skill is
built to avoid, and it is worse here than a missing answer.

Rules are data. `people infer --list` shows them; the user's own live in
`~/.chewbacca/people/rules.json` and run identically to the built-ins. A rule
can match phrases in messages, columns on the person, or both, and can carry
`against` terms that disqualify it. Adding a new kind of inference is a JSON
entry, not a code change.

## The dashboard

`people dashboard` serves a page at `http://localhost:7373` that answers one
question: who have I been texting, most recent first, and what group are they
from. It syncs on load and every two minutes, so it is current without being
asked.

`people dashboard --install` puts it behind a LaunchAgent with `KeepAlive`, so
it survives a reboot and a crash and the link always works. `--uninstall`
removes the agent and touches no data.

**The categories come from the contact names, not from inference.** Somebody
who saved a contact as "Sid Chowdhury A2F USC IYA" has already done the
labelling, and they know what those letters mean. The dashboard reads the tags
out of the name, shows them as badges, and strips them from the displayed name
so it reads as a name again. Guessing that "Nemmy" means a residential college
would be an invention, so the tag is shown as written.

The one piece of real logic is that a label which is also a given name only
counts after the first token. Without that rule "Maia IYA" and "Christian
Stiker IYA" both lose their actual names.

New tags go in `TAGS` and `HARD`/`SOFT` in `bin/lib/people-dashboard.js`. It
binds to loopback deliberately: this is the user's entire message history and
it does not belong on the local network.

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

| They say                                | You run                                                 |
| --------------------------------------- | ------------------------------------------------------- |
| Anything factual about a named person   | `people note`                                           |
| They talked to someone                  | `people log`                                            |
| Someone changed jobs                    | `people update <who> --company X --role Y`              |
| They met someone new                    | `people add "Name" --met "where"`                       |
| A group of people belongs together      | `people circle create` then `people circle add`         |
| They want to hear from someone more     | `people update <who> --cadence 30`                      |
| An ex, a service number, a shortcode    | `people mute <who> --because "..."` (keeps the history) |
| A contact saved under a nickname        | `people update <who> --name "Real Name"`                |
| **They promised somebody something**    | `people task add <who> "..." --due DATE`                |
| A recurring date that is not a birthday | `people date add <who> "label" --on MM-DD`              |
| Money or an object changed hands        | `people loan <who> --lent "..."` or `--borrowed`        |
| Two people are related                  | `people rel <a> <kind> <b>`                             |
| Something is coming up for someone      | `people check-on <who> --in 14d --because "..."`        |
| A durable one-liner about a person      | `people fact <who> <key> "value"`                       |

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

## Events: what actually happened, on the day it happened

A relationship is made of things that happened on days. The store knew a
message was sent on a date, but not that the two of them got In-N-Out that
night, so a trajectory had nothing in it but message frequency.

```
people events scan --since 2025-01-01     read the messages, log what happened
people events list "Sagar"                what you did together, newest first
people events reset                       forget which days were read, not the events
```

`scan` is a two-stage funnel. A lexicon picks which person-DAYS are worth
reading, which cuts hundreds of thousands of messages to a few thousand days;
then Claude reads each day's conversation whole and says what happened. The
lexicon is deliberately loose, because a day it misses is a day the model never
sees, and precision is the model's job rather than the filter's.

**The hard part is telling a plan from a memory,** and it is the whole reason
this is not a regex. "6pm in n out?" and "grabbing in n out now with Shirley"
are the same words about opposite facts. That distinction lands in
`observations.modality`, which already existed for exactly this: `actual`,
`planned`, `declined`. **Only `actual` is written by default**, because a plan
that was never confirmed is noise on a timeline of a life.

Two things it does that are easy to miss:

- **Other people named as present get the event on their record too**, as
  `third_party` rather than `told_directly`, because it came from somebody
  else's message. A contact saved as "Sagar Tiwari GOAT" still resolves from
  "Sagar", but only when exactly one person matches. Two people named Chris is
  a reason to record neither.
- **The person's own name is stripped from their own row.** "met Sagar at
  village" reads wrong on Sagar's record, so it becomes "met at village". This
  is done deterministically after the model answers, not by asking it again
  more firmly.

State is kept per person-day, so rescanning never re-asks about a day already
read and never writes the same dinner twice. Runs take a while: budget roughly
one Claude call per dozen days.

**It keeps itself up to date.** The SessionStart hook runs `people texts sync`
and then `people events auto`, so new conversations become logged events without
anyone asking. `auto` throttles to once every six hours and caps each run, so
twenty sessions in a day cost one bounded scan rather than twenty open-ended
ones, and it stays silent unless it actually found something. Tell the user it
is already running before offering to run a scan by hand; a full-history
backfill is the only thing they need to start themselves.

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
- **Warmth needs message history.** It decays from the last contact as of each
  point on the curve, taking the later of a logged interaction and a synced
  message. Someone whose texts were never imported reads as flat zero.
  `people texts sync --days 3200` backfills the full archive; on a real machine
  that is around 500k messages and takes under a minute.
- **Standing and warmth answer different questions.** Warmth moves every time
  they talk. Standing only moves when something gets written down, so it stays
  flat for people with no observations no matter how close they are. `trend`
  ranks on both together for that reason.

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
