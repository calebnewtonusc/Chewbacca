# Jev everywhere: Chewbacca as a System One / System Two machine

Written 2026-09-23. [JEV-HUD.md](JEV-HUD.md) plans Jev inside the HUD. This is the
wider plan: onboarding, development and the brain as well as the HUD, and the one
piece of infrastructure they all share.

## The shift

An LLM decision costs seconds and cents, so Chewbacca asks as few as it can and
guesses the rest with word lists. Measured here: the Haiku classifier took 9 to 17 s
and $0.074 per sentence and never beat its timeout once. Jev answers the same question
in 0.18 to 0.35 s for a small fraction of a cent (see `project-voice-router-fix`).

That changes the design question: once decisions are cheap, Chewbacca can ask
typed questions about its own state and the person's state continuously, on every
event, every partial transcript and every tool call, and wake the LLM only when an
answer crosses a line. Jev is System One: fast, typed, calibrated, never writes text.
Claude is System Two: slow, generative, called on purpose.

Everything below follows the article's rule. **Text comes from the LLM. Picking,
scoring and yes/no go to Jev. An exact rule stays in code.**

## The foundation: a decision registry with outcomes

Every idea further down plugs into this. Build it first, because without it each Jev
call is a one-off with a hand-set threshold and a hand-written eval.

1. **Registry.** `decisions/<id>.json` declares each decision: the question, how the
   options are built (static or rebuilt live), the floor, the fallback rule when Jev
   is down or unsure, and the eval file. `jev.decide(id, state)` is the only call site.
   Adding a decision means one file.
2. **Log.** Every call appends to `~/.bob/decisions.jsonl`: decision id, state hash,
   answer, probability, latency, tokens, cost.
3. **Outcome join.** When a verifier or a correction resolves a decision ("no, the
   terminal", a permission denied, a click that missed), the outcome is written against
   the same row. This is the earned-autonomy ledger from [RELIANCE.md](RELIANCE.md),
   keyed by decision id instead of by action type.
4. **Calibration, nightly.** Per decision: accuracy by probability bucket from real
   outcomes. The floor becomes the lowest bucket that clears the target accuracy,
   recomputed instead of hand-set. Every floor then carries its evidence, which
   `review-discipline.md` already demands.
5. **Shadow mode.** A new decision runs beside the current rule for a week, acts on
   nothing, and logs disagreements. It goes live when its calibrated accuracy beats the
   rule on real traffic. This retires the "30/30 on labels we wrote ourselves" caveat.
6. **Fan-out.** One call carries every question about an event. Jev runs them in
   parallel, so ten questions cost one round trip.

The dataset this builds, calibrated decisions with verified outcomes per decision
type, is the moat [LEARNING-TO-ACT.md](LEARNING-TO-ACT.md) describes for the registry.

## Onboarding

| Idea                     | Jev question                                                                                                                                        | Why it matters                                                                                              |
| ------------------------ | --------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------- |
| Pick the first win       | Choice over first-win candidates (people brief, coursework, inbox triage, stays, agent board), with the state being what is detected on the machine | ONBOARDING.md's "real success" gap: the first thing it does is chosen for this person, in under two minutes |
| Interview without an LLM | Each free answer to "what do you do all day" is mapped onto a profile schema with Choice and Score questions (role, tools, school, business, pace)  | YOU.md and NOW.md are drafted from typed answers; the LLM only writes the prose at the end                  |
| Permission at first use  | Noul per request: "does this need Calendar / Contacts / Accessibility"                                                                              | Moves every grant from install time to the moment it pays off, which is ONBOARDING.md's open rule           |
| Doctor that fixes        | Choice from `doctor.sh` output over known fixes in TROUBLESHOOTING.md, fix run and re-checked                                                       | Setup failures resolve themselves instead of printing a paragraph                                           |
| Install shape            | Choice: fast, full, voice-first, school, founder                                                                                                    | Kills the ten-minute default without asking a question                                                      |
| Friction in week one     | Score per turn: "how stuck is this person" from retries, corrections, "no", long silences                                                           | Above the line, the HUD offers a guide bubble. This is the churn signal                                     |

## Development: Chewbacca building Chewbacca, and his other code

| Idea                     | Jev question                                                                                                    | Evidence it is needed                                                                                                                                                                                                                                 |
| ------------------------ | --------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Skill routing            | Choice over every installed skill's description plus "none", floor from shadow data                             | `.claude/hooks/skill-route.sh` is word matching. On 2026-09-23 it sent "make chewbacca better using jev" to the `people` skill, matched on "indus, every, know". The descriptions are written to be routed on; a Choice over them reads them properly |
| Model and effort routing | Choice: haiku, sonnet, opus, and effort, per prompt and per subagent spawn                                      | The model-router hook in settings.json is keyword based too                                                                                                                                                                                           |
| Permission triage        | Noul "safe without review" per waiting tool call; the voice reads them grouped: "three safe, one risky"         | Planned in JEV-HUD.md step 4. Ranks, never grants                                                                                                                                                                                                     |
| Compaction               | Score per tool call for relevance to the live goal; drop the rest                                               | fast-jev-compaction's claim is 904.7k to 86.5k tokens in about a second. Unverified: measure on our own long sessions                                                                                                                                 |
| Test selection           | Choice over test files given the diff; run those first, the full suite after                                    | Feedback in seconds on a repo with a large suite                                                                                                                                                                                                      |
| Commit gate              | Noul per staged hunk: "belongs to this change"                                                                  | The stale-staged guard exists because other sessions' files kept landing in commits                                                                                                                                                                   |
| Memory writes            | Noul "durable fact", Choice "which brain file", Choice over retrieved memories: same, contradicts, updates, new | Catches the stale and the renamed memory at write time, which is the failure CLAUDE.md spends a whole section on                                                                                                                                      |
| Procedure retrieval      | Choice over learned procedures and maps: "does one already cover this request"                                  | LEARNING-TO-ACT.md build 3, "retrieve before exploring"                                                                                                                                                                                               |

## The HUD

JEV-HUD.md already covers the agent board, one parallel call per sentence, permission
triage, guide mode and the cost line. These go further.

- **End-of-turn detection.** `hud/Sources/BobHUDKit/Voice.swift` closes a turn after a
  fixed 1.1 s of silence, and its own comment says that is shorter than a pause for
  thought. Ask Jev on every partial transcript: "is this utterance finished". A
  finished sentence fires at 300 ms of silence; "and then the" waits. Turn-taking is
  the hardest problem in voice UX and this is the cheapest good answer to it.
- **Speculative routing.** Run the full fan-out on partials while he is still talking.
  When he stops, destination, agent and urgency are already decided and the agent turn
  starts immediately. The fixed cost of a turn falls to the length of the last partial.
- **Interruptibility.** Every few seconds: front app, window title, idle time, next
  calendar event, the board. Noul "is he in deep focus", Score per pending item
  "worth interrupting for". The HUD speaks only when both clear. An assistant that
  talks at the wrong moment gets muted within a week.
- **Addressed to me.** Noul on each sentence: "is this said to the assistant or to
  someone in the room". Audio never leaves the Mac; only the transcript line would.
  Gated by the privacy choice below.
- **Proactive agents.** A session waiting on a permission while he is idle, a meeting
  in five minutes with an agent mid-edit, a build that failed while he was away: each
  is a Noul on the board state, spoken once.
- **Mac control on Jev.** The accessibility tree becomes the menu, rebuilt every step,
  and Jev picks action and target. That is Browser Use's loop, applied to peekaboo.
  `tests/eval_ground_jev.py` already measured the grounding half: 29/30 top-1 against
  12/30 for word overlap.
- **Speak or write.** Choice per answer: speak it, write it to the hyper bar, or both
  with a one-line pointer, from answer length, front app and whether he is on a call.
- **Corrections are labels.** "No, the terminal" already recovers a bad route. Written
  against the decision log, every correction becomes an eval row automatically.

## The brain

The fan-out engine from `research/jevbacca/BRAIN-PLAN.md` in the context repo belongs on the same registry: every heard sentence, message and calendar change gets
the same batch of questions (worth remembering, which person, which project, is it a
commitment, is it a deadline). JevBacca's Opportunity Book is that batch pointed at a
business. None of it runs on personal text until the A/B/C choice is made.

## Built

- **Amber's people scoring, fed by Jev (2026-09-23).** `people note` and `people me`
  now ask Jev for dimensions, modality and source whenever the flags leave them out.
  Before this, every observation in the live store was `actual`, so the modality
  weights in Amber's design never fired. `tests/eval_people_jev.py`: dimensions
  22/24, modality 24/24, source 22/24, against 9, 13 and 20 for the keyword path.

## Order

1. **Decision registry, log and shadow mode.** Nothing else is measurable without it.
2. **Skill routing on Jev**, in shadow. Every session, every prompt, and the bug is
   visible today.
3. **End-of-turn detection**, behind a flag, because it is the largest latency win he would feel.
4. **The JEV-HUD.md list**, starting with voice wiring for the agent board.
5. Model routing, permission triage, test selection, commit gate.
6. Onboarding: first win, permission at first use, doctor fixes.
7. The brain fan-out, once the privacy choice is made.

## Falsifier

If a decision's calibrated accuracy on a week of shadowed real traffic does not beat
the rule it replaces, that decision stays a rule. If Jev's p >= 0.7 bucket falls below
90% accuracy on real outcomes, its probabilities are not usable as floors and the
whole calibration approach needs rethinking before anything graduates.

## Hard lines

- Jev picks, scores and ranks. It never grants a permission, sends a message or posts
  anything on its own.
- Irreversible external actions confirm per instance, whatever the record says.
- No personal text goes to Jev before the brain privacy choice.
- Every floor carries the run that set it, or says it was never measured.
