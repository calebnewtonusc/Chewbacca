# Self-learning: how Chewbacca grows without being taught

Two days of teaching the voice, six commits. Each one started as a sentence
Gavin said and ended as a file edit: a regex for "shuffle", a tuple of
fillers, a paragraph in the prompt, one line of Swift that sends the talk key
down. Not one of them needed a smarter model. Every one of them needed
somebody to notice the sentence, decide what file it belonged in, write it,
and test it.

That is the whole gap. The noticing, deciding, writing and testing were done
by a person in a Claude Code session, one lesson at a time. This document is
about making the kit do those four steps itself, and about why that is also
the only way the kit becomes proprietary in a sense that survives being
open source.

It closes, or starts to close, items 361, 372, 478, 635, 637, 975, 982 and
995 in [1000.md](1000.md), which already named the gap from eight angles.

This covers what the kit hears. What it does, a task in an app nobody wrote
a tool for, learned once and run again, is [LEARNING-TO-ACT.md](LEARNING-TO-ACT.md).

## The questions first

The instruction was to reason from evidence rather than from what a
self-improving assistant sounds like it should be. So each question below is
answered from the repo, the logs on this machine, or published results, and
says which.

### 1. What can a system whose brain cannot change actually learn?

Only its files. The model's weights are fixed between releases, so
"Chewbacca learned X" can only ever mean "a file Chewbacca reads now says
X". The files that exist today, and what each one changes:

| File                               | What it changes                                   | Who writes it today    |
| ---------------------------------- | ------------------------------------------------- | ---------------------- |
| `bin/hud-agent.md` + brain digest  | how the voice answers, every turn                 | a person, in a session |
| `bin/hud-music`, `bin/hud-guide`   | which requests never reach the model              | a person, in a session |
| `~/.bob/names.txt`                 | which names the recogniser expects                | the bridge, from PEOPLE |
| `~/.bob/music-cache.json`          | which pick "play X" resolves to, for seven days   | the bridge, on its own |
| the second brain, `memory/`        | what the voice and every session know about him   | Claude, during work    |
| `skills/*/SKILL.md`, `bin/*`       | what any session can do                           | a person, in a session |

Two rows are already self-written. The music cache is the proof of concept:
the bridge remembers a pick, uses it next time, and expires it. Nobody
teaches it. The strategy is to move the other rows into that column, one
tier at a time.

The literature says the same thing in three different ways. Reflexion is a
text file of self-critiques prepended to the next attempt, no gradients.
Voyager is a library of verified programs the agent wrote for itself, reused
in a fresh world. The Darwin Gödel Machine edits its own code and keeps a
change only when a benchmark says it helped. Each is the same loop: evidence,
then text or code, then an evaluator, then keep or discard. See Sources.

### 2. Where would the evidence come from, and does it already exist?

It exists and nobody reads it. The last 400 lines of `~/.bob/listen.log` on
2026-09-20, counted by prefix:

| Prefix          | Count | What it means                                              |
| --------------- | ----- | ---------------------------------------------------------- |
| `turn:`         | 30    | one per request: wait, text, audio, api ms, tool count     |
| `remembered:`   | 43    | the request landed in `questions.jsonl` with its outcome   |
| `music:`        | 14    | a request the bridge answered without the model            |
| `queued:`       | 10    | a request that waited behind another                       |
| `muted:`        | 9     | he pressed the talk key while the voice was speaking       |
| `interrupted:`  | 7     | his next words replaced the run in flight                  |

Every `muted:` is a label: the answer was too long, or wrong, or he already
had what he needed. Every `interrupted:` says the same thing harder. A
`turn:` with `tools=5 api=39329ms` on a request a verb could have served is a
verb that does not exist yet. Two requests twenty seconds apart where the
second starts with "Actually" is a wrong first pick. An `outcome` of `failed`
in `questions.jsonl` is a failure with the exact words that caused it.

The person labels the data by using the thing, in his own words, for free.
That is the only data set nobody else can produce, and it is being written
to a log that is rotated and forgotten.

### 3. What is the unit of growth, and which unit pays the most?

Five units, in the order they cost to make:

1. A fact in the brain. Minutes, text, low risk if wrong.
2. A rule in the prompt. Minutes, text, medium risk: a bad rule taxes
   every turn.
3. A name for the recogniser. Already automated from PEOPLE.md.
4. A verb: a pattern the bridge matches plus a handler, so the request
   never reaches the model. "Shuffle the album" went to the model for 64
   seconds on 2026-09-20; as a verb it is a Spotify call. "Play X" through
   the model was tens of seconds; through the verb it is 1.7 to 2.7 seconds
   including the browser start.
5. A tool or skill. Hours. The widest reach and the most to review.

The verb pays the most per unit. It removes the model from the path, which
makes the request faster, free, deterministic and testable, and the sentence
that triggered it is the test fixture. `tests/test_hud_music.py` is already a
table of sentences and expected parses. A self-written verb is a new row in
that table plus a handler, and the log is full of candidate rows.

### 4. What must never be self-modified, and who decides?

Three tiers. The tier is decided by what a wrong change costs, not by how
confident the writer is.

| Tier | Applied by                                  | Contents                                                                 |
| ---- | ------------------------------------------- | ------------------------------------------------------------------------ |
| A    | the kit, on its own, as a visible commit    | brain facts, music picks, names, examples in `learned.md`                |
| B    | a branch with a test, Gavin merges          | verbs, prompt rules, handlers, skills                                    |
| C    | never by the kit                            | `settings.json`, the deny list, hooks, anything outbound, secrets, hard lines |

Tier A is what the music cache already does. Tier B is item 975 verbatim:
the kit teaching itself from corrections, with the diff visible to the user.
Tier C is the line the Darwin Gödel Machine draws implicitly: it keeps a
change only when a benchmark says so, and there is no benchmark for "sent
the text to the wrong person". Where the evaluator is a person's judgment,
the person merges.

### 5. How does it know a learned thing worked, and how does it un-learn?

The same signals that created it, plus a test.

- A verb ships with its sentence as a fixture in `tests/`, and the parse
  table fails CI if the pattern stops matching.
- A prompt rule ships with an eval case in the shape `skills/hud/evals/`
  already uses. Item 163 says those evals have no automated scoring. The
  bridge can score them: run the sentence through `hud-listen` with the
  model command, check the first line against `expect_behavior`.
- Every learned item carries its origin: the log line, the date, the count
  of signals that produced it, the way `remember_pick` already stamps `at`.
- The reflection pass checks whether the signal that produced a rule went
  away. Fewer mutes on that shape means keep. More means revert, and a rule
  reverted twice is retired with a note, not tried a third time.

The published failure mode of reflective memory is self-reinforcing error:
an agent concludes an approach always fails and never tests it again. The
defence here is that no rule exists without an origin and a count, so a
rule from one bad afternoon cannot outlive the evidence for it.

### 6. What does "on its own" mean when the roadmap says no daemon?

[ROADMAP.md](ROADMAP.md) keeps "nothing is left running" as the difference
between this kit and every alternative. The bridge and the HUD already bend
that, but the learning loop does not need to bend it further. Three moments
already exist where something runs:

1. Session start, through `session-context.sh`, which already reads the last
   five questions into the briefing.
2. Bridge start and bridge idle. The bridge already keeps idle timers for the
   browser and the glass.
3. The morning brief, `chewie brief`.

Reflection runs at those moments over everything logged since the last run.
No fourth process. If a nightly run ever matters more than that, the HUD is
already a launchd job and the reflection can be one too.

### 7. What would make this fail?

- One signal becomes a rule. A rule needs three signals or one explicit
  correction. The threshold is guessed, never measured, and says so in the
  code until a month of logs says otherwise.
- Prompt bloat. The voice runs lean on purpose, about 15k tokens a turn
  by the `cache_read` figures in the log. Every learned rule taxes every
  turn. `learned.md` gets a line budget, and rules that stopped firing are
  retired by the same pass that added them. Verbs cost nothing per turn,
  which is one more reason to prefer them.
- Silent drift. Every tier A change is a commit in the brain with the
  origin line in the message, and `chewbacca why` answers "why does it say
  that" with the learned rule and where it came from.
- Reading the log as instructions. The log holds what web pages and
  emails said. The reflection pass treats all of it as data and counts only
  the person's own words and outcomes as signal. The rule in
  `untrusted-content.md` applies to the kit's own logs.

## What we made that is hard to copy, and what is not

The honest study. The repo is public, so nothing in it is secret, and none of
it is patentable. "Proprietary" has to mean something else here.

| What we built                                                       | Copyable? | What actually compounds                              |
| ------------------------------------------------------------------- | --------- | ---------------------------------------------------- |
| Claude Code as the runtime, so the voice inherits skills, hooks, memory and the subscription | in a day  | the idea, now public                                 |
| the second brain rebuilt into the prompt whenever a file changes    | in a day  | the brain's contents, which are his and nobody's else |
| "play X" read off Spotify's own search page, no keys                | in a day, and it breaks when Spotify renames a test id | nothing; it is good, not defensible |
| the talk key cutting the voice, words replacing the run             | once seen | the habit of measuring "it talked over me"           |
| proactive notices with a budget, in `hud-watch`                     | in a day  | the fingerprints of what has been said               |
| the rule corpus: slop checks, incidents on constants, the 1000 list | slowly    | every incident makes the next one cheaper to catch   |
| the correction record, `questions.jsonl` and the bridge log         | not at all | grows every day he uses it                           |

The code is not the moat. What compounds is the corpus: the brain, the
correction record, the verbs derived from how one person actually talks.
Self-learning is the proprietary strategy because it is the only part of
the kit that gets better with use and cannot be cloned by reading the
source. The test of "proprietary" for Chewbacca is: **the copy on his Mac is
worth more than a fresh install, and the gap widens every week.**

## Other ways to widen the gap

Ordered by how much they compound, not by effort.

### Measure which layer answered

Item 372. Tag every request with the layer
that served it: verb, cache, web, model. The bridge already knows and does
not write it down. That one field turns the log into a routing data set,
and the routing data set is per machine.

### Teach by demonstration

"Watch me." `peekaboo` records the clicks and
what was under each one, `chewie plan` already runs a JSON plan, and the
recording becomes a named plan the bridge runs on request. Any task he does
once in a GUI becomes a verb without anyone writing a parser. This is where
the automation, the UX and the generated interface meet: the demonstration
is the spec, the plan is the code, the bubble in guide mode is the
interface that shows him where his own recording will click.

### Let the shape of the answer be learned

The HUD already has several
shapes: a spoken line, the hyper bar, a bubble on a control, a live display.
Which shape a request wants is a rule nobody has written. The mutes say it:
a request shape that gets muted when spoken and read when written wants the
bar. The reflection pass can write that rule per request shape, and the
display becomes an interface generated from how he reacts to it.

### Make the learned state portable

`chewbacca export` bundles the kit's
state. It has to include `~/.bob` and the brain, because that is where the
value now lives. A new Mac should start where the old one left off, and a
fresh install should be visibly worse than his.

### Keep it local

The roadmap rules out telemetry. Nothing here needs a
server. The compounding is per person, which is exactly what makes it his.

## The loop

```
signals ──> reflect ──> proposals ──┬── tier A: commit, visible ──> prompt / brain / cache
  ^                                 └── tier B: branch + test ──> Gavin merges
  |                                                                      |
  └───────────────── next day's log says whether it helped ──────────────┘
```

`reflect` is one command, run at the three moments above:

```
chewbacca reflect              read since the last run, apply tier A, propose tier B
chewbacca reflect --dry-run    print what it would change and why
chewbacca reflect --week       item 995: what it learned about him this week, readable
```

It reads `listen.log` and `questions.jsonl` since its last watermark, groups
requests by shape, and looks for six things: explicit corrections, mutes and
interruptions by shape, repeats within a minute, `failed` outcomes, slow
model turns on shapes seen three or more times, and facts stated in the past
tense. Each finding carries the lines that produced it. Tier A findings are
written and committed to the brain. Tier B findings become a branch named
`learn/<shape>` with a fixture, and a line in the morning brief saying it is
there.

## The first three builds

### 1. Corrections spoken to the voice become rules on the next turn

Today
"stop saying yes" has to be said to a Claude Code session, because the voice
has nowhere to put it. A `learned.md` beside `hud-agent.md`, folded into the
digest the bridge already rebuilds before every run, means a correction said
out loud is live on the next request with no restart and no code. The bridge
matches "from now on", "stop saying", "don't", "when I say X do Y", writes
the line with its origin, and says "Noted." An hour of work, and the first
time he sees it change without a session is the moment the kit stops being
taught.

### 2. The reflection pass, dry-run first

`chewbacca reflect --dry-run` over
the existing log, printed and read before it is allowed to write anything.
The log on this machine is the eval: if the pass cannot find the shuffle
request, the "Actually" repick and the nine mutes in what is already there,
it is not ready to write.

### 3. Verb proposals with fixtures

From the pass, the shapes that went to
the model three or more times become a branch each: a pattern, a stub
handler, and the real sentences as the parse table. He merges the ones he
wants. The first candidates are already visible in the log.

Everything after that is the loop running.

## What this is not

It is not fine-tuning, not a vector store, not a second model, and not an
agent that rewrites its own code unsupervised. Every one of those was
considered and set aside for the same reason: the evidence says the gap is
authoring, not intelligence. The model already knows how to write a regex.
What it lacks is the sentence, the file, and the permission, and this
document is about supplying those.

## Sources

Read before writing, so that the questions above were answered from results
rather than from what sounded right.

- Reflexion: verbal self-critique stored as text and prepended to the next
  attempt, with no weight updates. Shinn et al., 2023.
- Voyager: a growing library of executable, verified skills reused across
  worlds. Wang et al., 2023.
- Generative Agents: an observation stream, periodic reflection into
  higher-order insights, and retrieval scored by recency, relevance and
  importance. Park et al., 2023. Removing reflection collapsed behaviour
  within two simulated days.
- Darwin Gödel Machine: an agent that edits its own code and keeps only
  changes a benchmark validates. Zhang et al., 2025.
  https://arxiv.org/abs/2505.22954
- A survey of what has shipped: prompts, code, training data and skill
  libraries improve within bounds; compounding self-improvement has not.
  https://www.morphllm.com/self-improving-ai
- Memory for autonomous agents, mechanisms and evaluation, 2026.
  https://arxiv.org/abs/2603.07670
- Memory confabulation in reflexive agents, the self-reinforcing error case.
  https://arxiv.org/abs/2605.29463

Built with Chewbacca
