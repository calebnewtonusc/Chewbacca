# Building something

**Falsifier:** what would I observe that tells me this should not exist?

**Cheapest test:** what is the smallest version that would produce that
observation, and can it be built in under an hour?

## Questions that change the build

- What already does this, and why is it not good enough? Not "is there prior
  art" but "I read it and here is the specific thing it gets wrong."
- What is the deliverable actually FOR: a person reading it once, or a process
  consuming it forever? Those are different artifacts and the second one is
  usually what was wanted.
- Who would be annoyed if this ran and was wrong? If nobody, there is no
  pressure keeping it correct and it will rot.
- What is the false positive rate, and at what rate does this get turned off?
  A gate nobody trusts is worse than no gate, because it trains people to
  bypass gates.
- Will this fire on its own, or does it need someone to remember it? Anything
  that needs remembering has already failed in this repo, repeatedly.
- What would I delete if I could only keep a third of it?

## The trap specific to building

Scope grows to fill the enthusiasm available. The version that ships and gets
used is almost always the one that felt embarrassingly small at the start.
