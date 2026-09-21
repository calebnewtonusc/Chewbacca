---
name: debugging
description: "Find the root cause of a bug instead of guessing at it. Use when the user reports something broken, pastes an error or a stack trace, says this used to work, asks why is this happening, why is this failing, or what is wrong with this. Also use to trace how data flows through a codebase, follow a request end to end, or find where a value is being lost or changed. Also fires on: stack trace, traceback, exception, crash, crashed, segfault, null pointer, undefined, regression, reproduce, bisect, root cause, it broke, debug this."
requires: [git]
---

# Debugging

The protocol exists because the failure mode is universal: changing several
things at once, then not knowing which one helped.

## The order, and do not skip

**1. Read the error exactly.** Every word. `undefined` and `null` are different
bugs with different causes. "Cannot read property x of undefined" names the
property and that is usually the whole answer.

**2. Go to the file and line in the trace before doing anything else.** Not a
grep for something similar. The actual frame. If there is no stack trace, get one
before theorizing; a bug report without one is a rumor.

**3. Check the assumption.** Print the variable. Is it the shape you believed? Most
bugs are a value being a different type, a different case, or absent, and are
invisible to reasoning about the code because the code reads correctly.

**4. Search the exact message.** Framework, exact string, year. Someone has hit it.

**5. Check for a breaking change.** Read the migration guide for the version
actually installed, not the version remembered.

**6. `git diff` against the last working state.** The bug lives in the diff. This
step alone solves most "it used to work" reports and it is the one most often
skipped.

**7. `git bisect`** if still lost, then read that commit properly.

Never change several things at once, and never delete and rewrite before
understanding why it broke. A rewrite that works for reasons nobody understands
is the same bug with a longer fuse.

## Tracing a flow

To follow data end to end: name the entry point, then read each function in the
chain in full rather than skimming for the interesting line.

Mark three things as you go, because they are where flows actually break:
- **Where the data changes shape**: parsed, validated, serialized, renamed
- **Where it could be lost**: a swallowed error, an early return, a default that
  silently replaces a missing value
- **Where ownership changes**: one module handing to another, a queue, a network
  hop, a process boundary

Report it as the chain, file by file, with the shape at each step. A trace that
lists files without saying what the data looks like at each one has not traced
anything.

## When it is fixed

Write the test that would have caught it, and check the same mistake is not
sitting in three other places. A fix applied to only the instance that was
reported is a promise to debug it again.
