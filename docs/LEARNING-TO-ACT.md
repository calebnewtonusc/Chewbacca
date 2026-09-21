# Learning to act: procedures, maps and the registry

[SELF-LEARNING.md](SELF-LEARNING.md) is about the kit learning from what is
said to it. This is about the harder half: learning from what it does. A
sheet comparing stays in Valencia. A list pulled through Clay or LinkedIn.
The school's Blackboard, which has no API anyone was given. The site the
Spanish homework lives on, which nobody has written a tool for and nobody
will. And the version of all of this that has to work for a stranger who
installs the product, not for one person with a Claude session open.

What those tasks share: an app nobody wrote a tool for, a first attempt that
is exploration, and a second attempt later with different parameters that
should not be exploration again.

## The questions first

Answered from the repo, from what is on this machine, and from the web-agent
literature, which has measured most of this by now.

### 1. What is learned when an agent does a task in an app it has never seen?

Four things, and the obvious one is the least valuable.

| What is learned  | Example from the Valencia sheet                              | Reused by                              |
| ---------------- | ------------------------------------------------------------ | -------------------------------------- |
| a procedure      | search a city and dates, open each stay, read the total, write a row | the same task with a different city    |
| a map            | where search is, how results page, what a listing page holds, where the real total hides | every other task on that site          |
| a preference     | price per night with fees, kitchen, distance to the beach, drop the rest | every sheet he ever asks for           |
| a strategy       | a booking site shows one price on the map and another at checkout; open the listing | every booking site, every marketplace  |

Intuition says "record the macro" and keeps the first row. The second row
is what makes the next task on the same site fast even when it is a
different task: once the school's Blackboard is mapped, "what is due" and
"what did I get on the quiz" are two short procedures on one map. The
fourth row is what lets the kit walk into a site it has never seen and not
start from zero.

### 2. Does storing what was learned actually pay?

Not automatically, and the evidence is recent. A 2026 budget-matched study
of three memory and skill modules for web agents (workflow memory, skill
induction and a reasoning bank) found that a plain agent given the same
token budget as extra steps matched or beat all three on WebArena and
WorkArena, and that run-to-run variance was large enough to swamp the
differences. Their line: the apparent gains "often vanish against a
budget-matched actor". Sources below.

That is the honest baseline, and it decides the design. What those modules
have in common is that the learned thing goes back into the model's context
as text, so every use costs tokens and a model turn. The gain here has to
come from the opposite move: a learned procedure is code that runs with the
model out of the path. "Play X" is the proof already on this machine, at
under three seconds against tens of seconds through the model. A procedure
that still needs the model to drive it has learned nothing that pays. Maps
and strategies are text, and they are read only when the kit is inside that
app, never on every turn.

Three things the benchmarks do not price, and this product does: a person
waiting on a voice, a logged-in account where every exploratory click is
real, and the same task done weekly, where variance is the whole cost.

### 3. How does it figure out an app on the spot?

The order already exists. `chewie` climbs five layers: data, scripting,
accessibility tree, synthetic input, vision. The cheapest layer that can
answer wins, and a school portal with a calendar export never needs a
screenshot. What is missing is not the climbing. It is that nothing is
written down while it happens.

The loop, for a task with no procedure yet:

1. Look for the cheap layer first. An export, an ICS feed, a CSV, a JSON
   the page itself fetches. `chrome-js` can read what a page loaded.
2. Read before clicking. `chewie see --json` returns every control with
   a role and a name. `chrome-js --text` returns the page as text. Pick the
   next action from what is there, not from a guess.
3. Act, then check. One step, then read the state again. Did the URL
   change, did a row appear, did the total render. A step is done when the
   observation says so, not when the click returned.
4. Record every step, including the ones that went nowhere: the action,
   the target by role and name, what was read afterwards, the time.
5. Ask only for judgment and hands. Which of the two matching courses.
   Whether to book. A code from a phone. Never a password: the kit acts in
   his own Chrome through `chrome-js`, where the login is already his.
6. On success, distill. The trace becomes a procedure, a map delta and
   maybe a strategy, then is replayed once before it is kept.

### 4. What is a procedure, so that a stranger's machine can run it?

A directory, plain text, the way everything in the kit is stored:

```
procedures/stays-compare/
  PROCEDURE.md     what it does, in one line for retrieval and a paragraph for people
  params.json      city, check-in, check-out, guests; each typed, each with an example
  run.py           Playwright or chrome-js steps, locators by role and text, never by pixel
  verify.py        what the end state must contain: at least one row with a price and a URL
  effects          read-only | writes-local | outbound
  origin.jsonl     the run it was distilled from, the date, who confirmed it worked
  stats.json       runs, successes, last success, last failure and the step it failed on
maps/airbnb.com/
  MAP.md           pages, how to reach each, what each holds, the quirks, how to tell you are logged out
```

The `effects` line is the tier. Read-only procedures are kept on their own.
Anything outbound (submit, send, book, post) is a branch a person merges,
and confirms on every run, the way the plan grammar in `mac/data/grammar.json`
already puts `confirm: true` into the type of every irreversible action.

A procedure is parameterised only from evidence. The first run in Valencia
is a literal recipe with the city in it. The second run in Lisbon is what
turns the city into a parameter, because now two instances differ in one
place. SCAFFOLD calls this the multi-instance abstraction constraint, and it
is the difference between a library that generalises and one that
hallucinates parameters nobody asked for.

### 5. Where does judgment come from?

From corrections on outputs, the same mechanism as spoken corrections in
[SELF-LEARNING.md](SELF-LEARNING.md), scoped to the procedure. The first
sheet has the columns the kit guessed. "Add distance to the beach and drop
the ones without a kitchen" is a correction, and it lands on
`stays-compare` as a preference, with its origin. The next sheet is right.
A preference stated in a different app that says the same thing about
sheets in general is promoted to the person's brain, and every sheet
inherits it.

### 6. What cannot be learned into a procedure?

- Credentials. Never stored, never typed. The kit works inside the
  person's own logged-in browser. If a site wants a login, the step is handed
  back and the procedure waits.
- Captchas and blocks. If a site refuses a browser the kit runs, the
  procedure moves into his Chrome through `chrome-js`. If it refuses that
  too, the kit says so and stops. It does not try to look human.
- Judgment. Which stay. Whether the price is worth it. A procedure ends
  at the sheet; the choice is his.
- Graded work. The kit learns the homework site the way it learns
  Blackboard: what is due, where to open it, how to submit what he wrote.
  Whether it may help with the exercises themselves is the course's AI
  policy in the coursework ledger, and an unrecorded policy is a ban. This
  is also the product's line: a tool that does students' homework has a
  short life.

### 7. What makes this proprietary once it is a paid product?

The registry. Every procedure and map that a person chooses to publish,
scrubbed of everything personal, with the scrubbed diff shown before it
leaves the machine. Verified by replay. Versioned. Carrying its success
statistics. And self-healing: when a site changes and a procedure starts
failing, the failures flag it, and the next person who succeeds at the task
re-learns it for everyone.

That is a network effect on procedures, not on data about people. A
competitor can copy the runtime in a week. They cannot copy ten thousand
verified procedures for the long tail of apps that nobody will ever write an
API for: every school's portal, every homework site, every regional
booking site, every internal console. Each user's success makes the next
user's first attempt shorter, and a fresh install of anyone else's product
starts at zero.

[ROADMAP.md](ROADMAP.md) rules out telemetry, and that stays true for the
open kit. Publishing a procedure is not telemetry. It is a person choosing to
share a recipe with the personal parts removed, once, with the diff in
front of them. That is the consent model the registry runs on.

### 8. What would make it fail?

- Brittle locators. A procedure that clicks a coordinate or a generated
  class name breaks on the next deploy. Locators are role plus visible text,
  and the map notes which ones have changed before.
- Abstracting from one run. Parameters only from two or more instances.
  The first run is a recipe, not a template.
- Loading everything. A map is read only when the kit is in that app.
  Procedures are retrieved by their one-line description, not carried in the
  prompt. The 2026 study is what happens when learned text rides along on
  every turn.
- The registry as supply chain. A published procedure is code that runs
  on someone else's machine. Signed, read-only by default, and the effects
  tier is enforced by the runner, not by trust in the author.
- Silent failure. A procedure that half-worked and reported success
  poisons its own statistics. `verify.py` is not optional, and a run without
  a verifier is a run that does not count.

## What exists today, and what is missing

| Piece                                   | State on this machine                                                       |
| --------------------------------------- | --------------------------------------------------------------------------- |
| formal plans with typed, gated actions  | `chewie plan check` and `run`, grammar in `mac/data/grammar.json`            |
| a run trace                             | `~/.chewie/runs/<ts>.jsonl`, one run on disk, fields step, status, detail, t |
| reading a screen as controls            | `chewie see --json`, roles and names                                         |
| acting inside the logged-in browser     | `chrome-js`: text, click by label, arbitrary JS                              |
| a headless browser                      | Playwright, already used by `hud-music`                                      |
| a procedure that runs without the model | `hud-music`, `hud-guide`, hand-written                                       |
| a recorder for free-form sessions       | missing: what Claude does through peekaboo and chrome-js leaves no trace     |
| a distiller                             | missing                                                                      |
| retrieval before acting                 | missing: nothing checks for a procedure before exploring                     |
| the registry                            | missing                                                                      |

The plan runner writes a trace and the free-form session does not, which
is backwards: the exploratory session is where the learning happens.

## Worked through

### Stays in Valencia

First time: no procedure. The kit opens the booking
site in his Chrome, reads the search form, fills city and dates, reads the
results as text, opens each listing for the real total, writes a CSV, and
says "Sheet's in the bar." Minutes, with every step recorded. He says "add
distance to the beach". Distilled: `stays-compare` with city and dates as
literals, the beach column as a preference, a map of the site. Second time,
Lisbon: the city becomes a parameter, the procedure runs in his Chrome in
seconds with no model turn, and the sheet has the beach column.

### Blackboard

First task, "what is due": the kit finds the calendar export
before it touches the UI, because the strategy for school portals says to.
The map records where courses, grades and announcements live. Second task,
"what did I get on the quiz", is a short procedure on the map, and it runs
the same on the next person's Blackboard once the map is in the registry,
with their courses where his were.

### The Spanish homework site

The map is learned the same way. The
procedures are due dates, opening an activity, submitting what he wrote.
The coursework ledger's policy line for that course decides everything
else, and the kit says which policy applies, once, before it helps.

## The first three builds

### 1. Record what the session does

Every peekaboo, chrome-js, chewie and Playwright action taken during a task
appends to a trace: action, target by role and name, what was read after,
the time, and the task it belonged to. The plan runner already writes this
shape. The free-form path joins it. Without this nothing else exists, and
it is a day of work.

### 2. Distill on success, replay before keeping

`chewbacca learn <trace>` turns a successful trace into the procedure
directory above, drops the dead ends, writes the verifier from the observed
end state, and replays it once. A procedure that does not replay is not
kept. Parameters appear only when a second trace differs from the first.

### 3. Retrieve before exploring

A rule in the skill that owns Mac and web tasks, and a line in the session
briefing: before acting in an app, list the procedures whose description
matches and the map for that site. Run the procedure; fall into exploration
only at the step that fails, and update the procedure from there. That is
the moment the second attempt stops being the first attempt again.

The registry comes after those three have run on one machine for a month,
because a registry of procedures that were never replayed is a registry of
guesses.

## Sources

- Agent Workflow Memory: workflows induced from past trajectories, offline
  and online, retrieved at test time. Wang et al., 2024.
- SkillWeaver: agents propose tasks, practise them, distil successful runs
  into executable APIs, then test and debug them.
  https://www.researchgate.net/publication/390639561
- SCAFFOLD: parametric skills from successful trajectories under a
  multi-instance abstraction constraint, hierarchical, compacted by
  behavioural equivalence. https://arxiv.org/abs/2609.05511
- Are online skill and memory modules always worth their tokens? A
  budget-matched actor matched or beat all three on WebArena and WorkArena,
  and variance was a first-class result. https://arxiv.org/abs/2606.15017
- Voyager: a library of verified, executable skills reused in a fresh world.
  Wang et al., 2023.

Built with Chewbacca
