# Finding out why something is broken

**Falsifier:** what would I see if my current theory of the bug were wrong?

**Cheapest test:** the log line or one-line check that distinguishes the two
theories, before any fix.

## Questions that change the debugging

- Have I read the actual error, every word? "undefined" and "null" are
  different bugs.
- Is the thing reporting success actually doing the work? A script that
  prints "done" is not evidence. A `sed` that matched nothing exits 0. A bare
  `except` turns a TypeError into a clean run over missing data.
- What changed? The bug lives in the diff.
- Am I looking at my tool's output or at reality? A screenshot taken before
  the page finished animating produces confident analysis of a blank frame.
- Did I verify the fix landed, by reading the file rather than trusting the
  edit?
- Is this one bug or the visible one of several?

## The trap specific to debugging

Silent failure is the expensive kind. Anything that can fail quietly should
be made to say so, even when that makes the output uglier.
