# Reliance: how a person comes to depend on this, safely

Gavin, 2026-09-22, asked for the thing that _"genuinely changes the way this
super assistant could be used forever, where people can become fully reliant on
it."_

This is a plan and a thesis, not a status report. It names the one primitive
that has to exist for reliance to be possible, and it ties together the four
docs that already circle it: [SELF-LEARNING.md](SELF-LEARNING.md),
[LEARNING-TO-ACT.md](LEARNING-TO-ACT.md), [LEARNING.md](LEARNING.md), and
[WEB-AGENT.md](WEB-AGENT.md).

---

## The thesis: reliance is a reliability problem, not a capability problem

Nobody is fully reliant on any AI assistant today, and it is not because they
cannot do enough. It is because they work most of the time, and the failure
lands on the thing that mattered: the wrong text sent, the wrong date booked,
the deadline missed, the wrong file deleted. Reliance is a trust asymptote, and
a single irreversible wrong action resets it to zero and keeps it there.

That has a hard consequence for what to build. A more capable assistant that is
still eighty percent reliable is more dangerous, not more depended-upon, because
you hand it bigger things and the failures get more expensive. So the target is
not more skills. The target is to drive the failure rate on things-that-matter
toward zero and to bound the cost of the failures that remain. Everything below
serves that and only that.

## The keystone: an earned-autonomy ledger

Assistants today are all-or-nothing. Either a human supervises every action or
the agent runs unwatched. That is exactly why reliance cannot grow: there is no
middle, and no way to _earn_ trust one capability at a time. The missing
primitive turns supervision from a switch into a curve.

**Every action carries a machine-checkable verifier.** A post-condition, checked
against reality after the act: texted Caleb, then read the thread back, because
Messages reports sent for a handle that never received it; added the event, then
re-read the calendar; edited the file, then grepped for the change. Nothing is
reported done until reality confirms it. The kit already does this in spots
(`hud-agent.md` tells the voice to read a thread back). The rule makes it
universal: **an action with no verifier cannot claim success.** A verifier is
also a separate step from the action that produced it, the same reason the
graph-engineering skill keeps the verification node separate from the worker: a
worker grading its own output is not evidence.

**Every verified outcome and every human correction writes to a ledger, keyed by
action type.** As the record accumulates, each capability graduates on evidence:

- **Confirm every time**, when new or low-trust: show exactly what will happen,
  wait for a yes.
- **Do it and tell me**, once the record shows it is reversible and reliable:
  act, report, keep an easy undo.
- **Do it silently and log it**, at a high record and low stakes: ambient, it
  just works, and the log is there if asked.

A failure demotes the capability a rung. And there is a floor that never lifts:
catastrophic and irreversible external actions (moving money, mass deletion,
posting under their name) always confirm per instance, no matter the record.
This is the same hard line [WEB-AGENT.md](WEB-AGENT.md) draws for replayed web
skills, generalised to every action the assistant can take.

This is the mechanism by which a person becomes _rationally_ reliant. They stop
double-checking a capability at the moment the record says they can, not before,
and never for the catastrophic thing. The assistant never claims autonomy it has
not earned. The moment someone stops verifying its work is the moment they
depend on it, and a graduated, evidence-backed, per-capability ledger is the
only honest way to reach that moment.

## What the ledger sits on

Three substrates, each already half-built, each with a doc that owns the detail:

- **Total memory with provenance.** Reliance means it knows everything and never
  forgets, but a confidently wrong memory is worse than none. Memory needs
  provenance, expiry, and correction-on-contradiction, the mechanical form of
  the standing rule that the user is the source and the notes are a cache.
- **Ambient proactivity.** Full reliance is when it acts before being asked: the
  deadline tomorrow against a full week, the reply owed, the renewal lapsing. A
  standing loop over real state that surfaces the right thing at the right time
  without being noisy. `mac-brief` and the follow-up scan are the seed.
- **The closed learning loop.** Every success compiles into a fast, deterministic
  procedure and a reusable map of the app it ran in; every correction is
  credit-assigned to the file that caused it. This is the compounding asset, and
  it is the same compile-verify-heal engine as [WEB-AGENT.md](WEB-AGENT.md),
  generalised from the browser to every app. [LEARNING-TO-ACT.md](LEARNING-TO-ACT.md)
  already argues that the valuable part is the map and the strategy, not the
  macro.

And it needs a two-tier agent so the trusted, compiled path is instant and only
the novel path pays the heavy cost: a lean front that answers the simple eighty
percent in under two seconds and escalates the hard, novel request to the full
Chewbacca agent in the background, speaking a progress line and the result. For
hard tasks the voice is not _like_ chat, it _is_ chat, run async.

## Close the loop first, because right now it does not close

[LEARNING.md](LEARNING.md) is blunt and correct: the machinery for learning
exists (`bin/evolve`, `bin/fitness`, `bin/scars`, `memory/`, the ask-capture
log) and the loop has never closed once. Two reasons, both of which the ledger
depends on:

- **The reward signal is dead.** `structural_score` is 90.12 in all ten runs. A
  reward that does not move carries no information, and the ledger's graduation
  logic is exactly a reward signal, so if it does not vary it is theatre.
- **There is no credit assignment.** `failed` is the integer `25`, with no record
  of which cases failed or which rule, skill or procedure caused each. The ledger
  is the fix: a verifier failure names the action and the file, which is credit
  assignment by construction.

So the ledger is not a new subsystem bolted on. It is the wire that closes the
loop the kit already mostly built.

## The unglamorous half, which is half the answer

An engineer has to say this out loud: an assistant you rely on cannot be dead
when you reach for it. The backlog already has the listener orphaning on every
HUD restart so voice silently dies (#50), and a rebuild going deaf unless the
signing requirement is pinned. Reliance dies permanently on the first day it was
not there when it was needed. So uptime, state that survives a restart, graceful
degradation, and never losing data are not the boring prerequisite to the
interesting work. For reliance they _are_ the work, equal in weight to the
ledger. Fix #50 before building any of the above.

## Build sequence

1. **Fix the reliability floor.** #50 and the deaf-after-rebuild bug. Nothing
   below matters if the voice is not there.
2. **Verifier plus ledger on the top five `mac` actions** (text, calendar add,
   email triage, reminder, note): a post-condition check after each, and a ledger
   entry keyed by action type.
3. **Graduation logic.** The three rungs and the catastrophic floor, driven off
   the ledger's record.
4. **Wire it into the learning loop.** A verifier failure writes a scar named to
   a file; a run of verified successes compiles a procedure.
5. **Ambient layer and two-tier escalation**, once the trusted path is instant.

## Falsifiers, measured, not hoped

- **Verifier coverage.** What fraction of real actions can produce a
  machine-checkable post-condition? If it is low the ledger stays sparse and no
  capability ever graduates. Measure it on the real top twenty actions before
  building past step 2. This is the falsifier for the whole approach.
- **Confirmation surface over time.** Does the count of "confirm this?" prompts
  actually fall as the record grows? If it does not, the ledger is the same dead
  metric [LEARNING.md](LEARNING.md) already caught, and it is theatre.

## Why this is the moat

The source is open, so the code is not the moat. The moat is the closed loop and
what a single person's real use accretes inside it: their verified procedures,
their app maps, their scars, and their earned-autonomy ledger, none of which
exists for anyone else and all of which make the assistant better at _their_
life specifically. The switching cost becomes their entire accreted context plus
every capability it has earned the right to do silently. Nobody leaves the thing
that knows them best and does their recurring life instantly and correctly. That
is what full reliance is, and the ledger is the primitive that lets it happen
honestly instead of by pretending.

Built with Chewbacca
