# methods/

`crafts/` answers **what makes a good one of these**. This answers **how to run
the work at all**.

## The failure this exists for

Caleb, 2026-09-20, after a night where the kit built a design system, a
linter, a crawler and 120 questions: *"Make chewbacca always ask creative high
leverage outside of the box questions to itself before it builds anything...
I should never have to prompt engineer ever again."*

Every good idea in this repo has failed the same way once: written down as
guidance and then never applied. `voice.md` loaded into every session and was
enforced by nothing until a hook started refusing replies. `research-the-craft`
was written as a rule and did nothing until `craft-gate` could exit 1.

**So this is not a document to read. It is a question injected before work and
one answer checked afterwards.**

## Why one checkable answer instead of a checklist

A question generated and answered in the same breath is not thinking, it is a
performance of thinking. A checklist makes that performance cheaper, not
rarer, which is how a ritual forms: the boxes get ticked and the work does not
change.

So the gate demands exactly one thing back, and it is the one thing that
cannot be faked by answering in a friendly tone:

> **What result would tell me this was the wrong approach?**

A falsifier is checkable because it is a prediction. Either it gets stated
before the work and tested after, or it does not. And it is the one question
whose answer regularly CHANGES the plan, because "nothing could show this is
wrong" is itself the finding: it means the work is unfalsifiable and probably
unnecessary.

Measured, same night: the six-stance experiment was run with the falsifier
stated first ("if all six score the same, generation is the bottleneck and I
have it backwards"). It came back near-tied, which killed the hypothesis and
produced the most useful result of the session. Three earlier experiments run
without a stated falsifier produced findings that were all confirmations.

## The invariant across every process

Scientific, creative, engineering, research, design, decision. They differ in
vocabulary and share one move:

**Say what would prove this wrong, before building, in a form you could
actually observe.**

Everything else in the per-process files is elaboration on that.

## The second question, only when the first has an answer

> **What is the cheapest thing that would produce that result if it were true?**

This is what stops a week of building from preceding a two-minute check.
Tonight the false-positive rate of a linter went unmeasured for hours and was
then answered in ninety seconds by pointing it at two real sites. It found 12
blocking findings on good pages, which is a failing grade, and every hour
before that was spent adding rules to a detector nobody had validated.

## What this cannot do, stated plainly

A hook can verify that a falsifier was WRITTEN. It cannot verify that it was
believed, or that it was the right one, or that the work actually tested it.
That gap is real and no amount of prompt text closes it. The gate raises the
cost of skipping the step; it does not make the thinking happen.

## Prior art, checked 2026-09-20

This layer is **not novel** and the search took two minutes, which is two
minutes that should have happened before it was built.

- **PreFlect**: prospective reflection, LLM agents proactively identifying
  critical failures before execution, with reported consistent gains.
- **CoSQ** (Chain-of-Self-Questioning): prompt-only, makes answer commitment
  conditional on an explicit information check.
- **Self-Ask**: decompose into sub-questions before answering.
- **Reflexion / Self-Refine**: the reflection family generally.
- Commercial pre-mortem skills already ship as importable agent procedures
  with meta-reflection self-checks and output-discipline gates.

What is different here is the enforcement shape, not the idea: a hook that
injects rather than a document that is retrieved, a deterministic classifier
with no model call, and once-per-process-per-session so it does not become
noise. That is engineering on a known technique.

Recorded rather than quietly omitted, because the alternative is somebody
claiming this as new later and being wrong in front of someone who reads.

## Its own falsifier, which it shipped without

The gate demands a falsifier and was committed without stating one. Fixed
here:

> **If turns that receive the injection produce work no better than turns
> that do not, this is theater and should be deleted.**

Untested. The honest bar is the same one every other component in this
family has to clear, and most of them have not: one measured change all
night actually improved output (universal refusals in every generation
prompt, 26 emoji to 0 on an identical brief). Everything else is unvalidated.
