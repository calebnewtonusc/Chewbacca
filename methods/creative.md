# Making something that should be good, not just correct

**Falsifier:** what would tell me this is merely competent? Competent is the
default outcome and it is invisible from the inside.

**Cheapest test:** show it to something that has not seen the intent and ask
what it perceived.

## Questions that change the work

- What is the tension in THIS problem that would be false of a different one?
  The organizing principle is just a decision about which side wins. Generic
  tensions like "simple vs powerful" fit everything and therefore decide
  nothing.
- What would three genuinely different answers look like, and do they
  disagree about what the thing is FOR? If they only differ in appearance,
  the space was never partitioned.
- Which norm here is arbitrary and which is functional? Coolness is autonomy
  from UNNECESSARY norms, bounded, not total (Warren & Campbell, JCR 2014).
  Breaking everything reads as weird; breaking the right two reads as
  intentional.
- What is the distant analogy? Cross-domain sources raise novelty and lower
  hit rate, which means generate several and filter, never bet on one.
- What would I remove if removal were free? It is free. Say it out loud,
  because the sentence is the intervention: 41% removed something by default,
  61% when told removal costs nothing (Adams et al., Nature 592).
- Am I reaching for the mode? The first idea is the mode almost by
  definition.

## Two procedures that worked here, from the people who ran them

Not theory. Both were described out loud on 2026-09-20 by the person who did
it, and both produced something the other one called insane.

### Gavin's, for making a thing look like nothing else

He built the HUD's liquid field this way, in his words:

> "I described what I wanted. My prompts were super long. It was a bunch of
> like crazy like art. **I feel like I was painting.** I was like, it needs to
> be like the flow of water with the resistance of fire, like oil and water
> displacement in a lava lamp. And I had to **download 10 minutes of lava lamp
> footage on YouTube.** And I had to go **research Damascus camos in Call of
> Duty** for coloring."

Version count, his: **600 iterations.** The repeatable procedure under that:

1. **Describe the behaviour as physics, not as design.** Not "smooth and
   organic". Water flow, fire resistance, oil and water displacement. A
   physical system has dynamics a style word does not, so the model has
   something to simulate rather than a mood to match.
2. **Go get the actual footage of the physical thing.** He watched ten minutes
   of lava lamp. This is the step everyone skips, and it is the one that makes
   the analogy load-bearing rather than decorative.
3. **Raid an unrelated domain for one dimension.** Colour came from Call of
   Duty gun camos. Borrowing one axis from far away beats borrowing the whole
   look from nearby, which is how a thing ends up looking like every other
   generated page.
4. **Iterate into the hundreds.** Not a number to hit, a fact about where the
   good version was: nowhere near the first twenty.

### Caleb's, for getting past the first plausible answer

> "Don't just say ask questions. Tell it it's wrong, and tell it it sucks, and
> tell it it's doing it the wrong way, and tell it to be more creative. Because
> if you just ask it, it'll do it, because it's probabilistic. That's probably
> right. Versus if you ask specific negative things, then it will engineer ways
> to do that."

That is the typicality bias stated from the operator's seat. A neutral request
returns the median candidate, because the median is what "probably right" means
to a sampler. A named defect is a constraint, and a constraint moves the
distribution. So the useful prompt names the defect: this is generic in
exactly this way, and here is what it must not do.

Its companion, for when the model has locked onto one theory:

> "Make a list of every possible factor and then the ones it's forgetting."
> "Tell it that it didn't work with the prompt you just had."

And for work that is actually the person's own, the inversion:

> "I dump everything in my brain, then I have it interview me. So I'm the one
> doing all the creative decisions, all the discernment, structuring how the
> ideas come together. Ask me high leverage questions that get me to a level of
> discernment and creativity I wouldn't have if I was just writing on my own."

The model holds the questions. The person holds the judgment. That ordering is
what keeps the output his and it is the reason the writing sounds like him.


### Ask for the distribution, not the answer

Measured here on 2026-09-22, after Caleb sent Dan Fabulich's argument that LLMs
tell bad jokes because they minimise surprise by design.

**Fabulich is right about the symptom and too pessimistic about the cause.** His
claim is architectural: next-token prediction avoids surprise, so no amount of
compute fixes it. The measured mechanism is narrower and more useful. It is
**typicality bias in preference data**: annotators systematically prefer familiar
text, so the alignment objective sharpens the output distribution. The base model
keeps the diversity; alignment narrows the sampling. Direct prompting retains
**23.8%** of base-model diversity, asking for a distribution retains **66.8%**
(Verbalized Sampling, Zhang et al., arXiv 2510.01171). The humor-specific version
of the symptom: one study asked ChatGPT for a joke 1,008 times and **over 90% of
the outputs were variants of the same 25 setups**.

That difference matters because it means the fix is at inference, not in training.

**The procedure.** Instead of asking for N candidates, ask for a distribution:

> Generate a distribution of 12 responses sampled from across the entire
> probability distribution rather than from its mode. For each, state the
> approximate probability you would give that response if asked once. At least
> half must be under 5%, meaning responses you would almost never produce.
> A set of near-synonyms is a failed answer.

This is the mechanical version of Caleb's "tell it it's wrong and tell it it
sucks." Both move the sampler off the mode. His is a constraint, this one is a
change of question.

**What it bought, on one premise, 12 candidates per arm:**

| | direct prompt | asked for a distribution |
| --- | --- | --- |
| distinct semantic frames | 5 | **12** |
| frames per candidate | 1.58 | **2.33** |

The control never once left software, database and a social scene. The other arm
reached a stack trace, medicine, prayer, family, sport, cartography and money:
seven frames the control touched zero times. That is mode collapse made visible.

**The trap, and it cost the first measurement.** Lexical diversity and conceptual
diversity are different things, and the first metric only saw the first one. Mean
pairwise word overlap was 0.012 versus 0.014, essentially identical, and the
verdict printed "no improvement". It was wrong. Twelve rewordings of one idea use
just as many distinct words as twelve different ideas. **Mode collapse is
conceptual, so it has to be measured conceptually.** The working version counts
distinct semantic frames: `comedy-engine/scripts/frames.py`.

## The trap specific to creative work

Every instrument you can build measures the ABSENCE of defects, so a process
built only from instruments converges on fine. Fine is the ceiling unless
something in the loop has a positive signal for good.
