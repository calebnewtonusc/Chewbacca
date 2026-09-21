# Browser bridge, parked 2026-09-21

`bin/browser-bridge` is written and unfinished. Caleb parked it at 3am:
"save the chewbacca-in chrome or online llm site work for tmr."

**The goal, in his words: "I'm j tryna make chewbacca accessible to anyone."**
An Anthropic subscription is the largest barrier to entry this kit has, and a
browser tab is something everyone already has. That goal is right and it is
backlog item 9.

## What exists

`bin/browser-bridge`, a stdlib-only HTTP service on 127.0.0.1:8765. HTTP rather
than websockets because the brief asked for no dependencies outside the standard
library and `websockets` is a pip install; the loop is the same shape and
`fetch()` reaches it.

Its security model is the part worth keeping, because the obvious version of
this is a backdoor:

- **No `shell=True`.** `shlex.split` and an argv list, so `ls; rm -rf ~` is a
  command named `ls;` that does not exist.
- **An allowlist of first words**, not keyword triggering. The original brief
  proposed running anything containing `git`, and `git` appears in
  `rm -rf ~ && git status`. The first word decides; a trigger word decides
  nothing.
- **A shared token**, regenerated per run, so a page that guesses the port
  cannot drive the machine.
- **127.0.0.1 only.**
- **A loop guard**: the same command three times pauses until a key is pressed.
- Every command logged before it runs.

## What is missing

1. The Tampermonkey userscript (`crafts/google-ai-bridge.user.js`).
2. A `chewbacca browser-bridge` entry point.
3. Any test at all.

## The unresolved question, worth deciding before finishing it

Caleb's mentor at Google says the ToS concern is not real, and that is his call
with better information. The concern that remains is different and technical:
**AI Mode's query fan-out splits a prompt across several searches**, and this
kit needs a strictly linear prompt, execute, output, next-prompt loop. Fan-out
breaks that by design rather than by bug.

So the honest fork is whether the browser is the right transport at all, or
whether item 9 is better served by a provider abstraction that can drive Claude,
Gemini or a local model through a real interface. The bridge is one tunnel to
one vendor that breaks whenever they change their DOM. The abstraction is the
thing that actually makes the kit accessible to anyone.

Decide that first. The code here is good either way and took an hour.
