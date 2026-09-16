# Onboarding kit

Researched 2026-09-16, mostly from Daniele Procida's Diátaxis framework
(diataxis.fr), which is the settled model for this genre, plus the progressive
disclosure pattern from onboarding practice. Rules only, each one falsifiable.
Vibes were left out on purpose.

These govern the writing inside a kit. Whether the thing should be a kit at all
is a separate question, and `skills/kit-builder/SKILL.md` has the seven-property
test for that. Score it there first.

**Know which of the four things you are writing.** Diátaxis separates tutorial
(learning), how-to (a specific goal), reference (lookup) and explanation
(understanding). The split is not cosmetic: tutorial and explanation serve
somebody while they learn, how-to and reference serve them while they work. A
file that mixes two serves neither, and most bad kit documentation is a
tutorial with reference material wedged into it.

**Organise around what the reader is doing, not what you want to tell them.**
The framework's central question is "what is the reader trying to do?" at that
exact moment. A kit ordered by the author's mental model of the domain is the
common failure.

**The walkthrough has to work every time.** "Your tutorial ought to be so well
constructed that things can't go wrong, that your tutorial works for every
user, every time." This is the highest bar in the whole genre and it is the
reason kits need real scripts rather than instructions to do arithmetic.

**Every step produces a visible result.** "Every step the learner follows
should produce a comprehensible result, however small." A step whose outcome is
invisible cannot be checked by the person taking it, so they cannot tell
success from silent failure.

**A broken promise costs more than a missing feature.** "A learner who follows
your directions and doesn't get the expected results will quickly lose
confidence, in the tutorial, the tutor and themselves." That last clause is the
one to take seriously for a kit used by somebody under a deadline on something
they have never done.

**Do not explain inside the walkthrough.** "A tutorial is not the place for
explanation." Link to it instead, "so that it's available, but doesn't get in
the way." Procida names over-explanation as an "anti-pedagogical temptation":
the writer has already abstracted the idea and wants to hand over the
abstraction, which is exactly what the learner cannot yet use.

**Cut every alternative.** "Your guidance needs to remain focused on what's
required to reach the conclusion, and everything else can be left for another
time." One path. Options, flags and "you could also" belong in reference.

**Say what they will see, then show it.** Maintain "a narrative of
expectations" with phrasing like "You will notice that ..." and include actual
example output. Then point at it, because learners are "too focused on what
they are doing to notice" on their own.

**Deliver something visible in the first session.** Progressive disclosure is
the standard onboarding pattern: immediate setup and a first real result in
session one, deeper capability over the first week, advanced use later. A kit
that front-loads configuration and pays out in week two loses people in week
one.

**Use the smallest words available.** "The most basic language possible. Link
to more detailed explanation."

## When the brief contradicts these

The usual ask is "document everything" or "explain why it works as we go."
Both produce the mixed file the framework exists to prevent. Say which rule it
breaks, in one line. Build the single-path walkthrough and put the rest in
reference and explanation files next to it. Silently delivering either one is
wrong.
