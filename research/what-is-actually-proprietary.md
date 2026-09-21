# What is actually proprietary here

Caleb, 2026-09-20: *"strategize other ways we can make chewbacca proprietary,
start by asking yourself high leverage creative questions that force you to
not lean on intuition, but on critical thinking."*

## The measurement, before any strategy

| | |
|---|---|
| Tracked in the public repo | **536 files, 85,393 lines** |
| Local only, `~/.chewbacca` | **2.8 GB** |

But most of that 2.8 GB is not an asset:

| | | |
|---|---|---|
| `audio-venv` | 897 MB | a Python venv. `pip install` reproduces it |
| `methods/`, `craft/` | 48 KB | copies of files already in the repo |
| `logs`, `cache`, `stop-check` | 700 KB | operational exhaust |
| **`people/`** | **1.9 GB, 249 MB db** | **not reproducible by anyone** |
| **`scars.json`** | **53 failures** | **not reproducible by anyone** |

**A fork gets 100% of the capability and 0% of the data.** Every idea in this
kit is public and copyable in an afternoon. The only irreproducible things are
Caleb's own relationship graph and this kit's own recorded mistakes, and the
first of those belongs to him rather than to the product.

That is not a failure. It is a choice that was made implicitly and has never
been examined.

## The questions, and what each one decides

**1. Is "proprietary" even the goal, or is it distribution?**
These are opposite strategies. A public repo maximises adoption and minimises
moat; a private one inverts that. The kit currently does both halves badly:
public enough that nothing is protected, personal enough that a stranger's
install breaks. **Pick one.** Aryaa's own framing: if you can vibe code 95% of
an app in hours you have no technical moat, so the advantage has to be in
acquiring users. By that logic the repo IS the strategy and "proprietary" is
the wrong target.
*Decides:* everything below.

**2. What would Caleb actually be upset to lose?**
Measured answer: `people/`. Nothing else in `~/.chewbacca` would cost more
than an afternoon. That is the asset, and it is a personal data asset, not a
product one.
*Decides:* backup priority, and what a "Chewbacca account" would even hold.

**3. What gets measurably better the more it is used?**
Right now: `scars` grows, and that is all. The trial log has 1 entry. The
design prior has 10 samples. **If nothing compounds, there is no moat at any
level of secrecy**, because a fresh install is as good as a two-year-old one.
*Decides:* whether accumulation is worth engineering. It is the only moat
available to a public repo.

**4. Measured in TIME, what would take a competitor longest to reproduce?**
Reading the repo: hours. Rebuilding the relationship graph: impossible, it is
Caleb's data. Rebuilding the voice model: impossible, 183,402 of his own sent
texts. Rebuilding the scars: as long as it takes to make the same 53 mistakes.
**The only durable answers are the ones that required living through
something.**
*Decides:* build for accumulation, not for secrecy.

**5. Which rung of the ladder is the work on?**
research/aryaa-memory-architecture.md: everything here is at level 1 and 2,
prompt text and query-time lookup, the two weakest and the two most copyable.
Level 3, a LoRA trained on Caleb's own corpus, would be genuinely proprietary
because it needs both his data and a training run. **That is the one real
answer to the question as asked.** It is also the largest piece of unbuilt
work in this file.

**6. Who is the ICP, and what is their strongest criticism?**
"Every ICP" is not an answer, it is the absence of one, and it is why install
keeps breaking for strangers while working perfectly here. Steel-manned below.

## The strongest criticism from each ICP, and whether it lands

**The skeptical senior engineer.** *"This is 85,000 lines of prompt text with
no tests of the thing that matters. You test that files parse, not that the
output is better. Where is the eval?"*
**Lands.** Almost nothing here is measured against outcome. One change all
night was: universal refusals took emoji 26 to 0. Everything else is asserted.

**The solo technical founder.** *"I am not adopting someone else's 12 hooks
and 87 skills. I will take the three ideas and write my own."*
**Lands, and is correct behaviour.** The kit is not modular enough to take
three things from. Install is all-or-nothing.

**The non-technical user.** *"It broke on install and the fix was a terminal
command."*
**Lands.** Documented in the kit's own history: install was dead on main on
2026-09-19.

**The employer evaluating Caleb through it.** *"Impressive volume. What did
you build versus what did the model build, and can you defend any of it?"*
**Half lands.** The research files and the measurements are defensible; the
volume is not the argument and should not be led with.

**The privacy-conscious user.** *"It reads my texts, my contacts and my
calendar, and the repo is public."*
**Partly lands.** `reference_chewbacca_privacy_reality` already records that
retrieval makes 0 LLM calls and nothing is encrypted at rest. The honest
answer exists; it is not prominent.

## What follows

1. **Decide question 1 out loud.** Everything else is downstream and it has
   never been decided.
2. **Engineer the accumulation** (Q3), because it is the only moat compatible
   with a public repo: consolidation, decay, and a loop where a two-year-old
   install is demonstrably better than a fresh one.
3. **Measure one outcome** (the senior engineer's criticism), because it is
   the criticism that lands hardest and the cheapest to start answering.
4. **Level 3 on the ladder** (Q5) is the only literal answer to "make it
   proprietary", and it is a real project rather than an afternoon.

"Un-criticizable to every ICP" is not reachable: the founder wants modularity
and the non-technical user wants all-or-nothing, and those contradict. Knowing
which criticism you are choosing to accept is the achievable version.
