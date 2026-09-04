# Architecture

Chewbacca is not a program. It is a set of files that change how an agent you
already run behaves, plus some command-line tools that agent can call.

## The shape

```
  you
   |
   v
Claude Code  <---- ~/.claude/          the configuration layer
   |                CLAUDE.md          9 always-on standards, imported
   |                rules/             3 more, loaded when the work calls
   |                skills/            78, routed by their description
   |                commands/          57, invoked by name
   |                agents/            4 subagents
   |                hooks/             8, run at fixed moments
   |                settings.json      permissions, hooks, MCP
   |
   +--> shell ----> ~/.local/bin/      the tools
   |                  chewbacca        status, doctor, log, bench, context
   |                  people           the relationship store
   |                  coursework       the semester ledger
   |                  chewie           Mac control
   |                  slop-check       prose
   |
   +--> MCP ------> 12 servers         peekaboo, github, supabase, ...
   |
   v
  your Mac         Messages, Contacts, Calendar, the screen, files
```

Nothing in that diagram is a service. There is no process running when you are
not in a session.

## Where state lives

| What | Where | Written by |
| --- | --- | --- |
| Configuration | `~/.claude/` | `setup.sh` |
| Install manifest | `~/.chewbacca/install-manifest.json` | `setup.sh` |
| People | `~/.chewbacca/people/people.db` | `people` |
| Logs | `~/.chewbacca/logs/`, `doctor.log` | hooks, `doctor.sh` |
| Session cache | `~/.chewbacca/cache/` | `session-context.sh` |
| Ledger | `~/coursework/` | you, with help |
| Context | `~/second-brain/` | you and the agent |

## What happens at session start

1. The `SessionStart` hook runs `session-context.sh`. It reads your context
   repo and the ledger, caches the result for 15 minutes, and injects a short
   block. Capped at 8KB so it cannot eat the window.
2. `kit-route.sh` checks whether your first prompt matches an installed kit.
3. `CLAUDE.md` and the nine imported rules are already in context.
4. Every skill's `description` is in context for routing. Not their bodies.

`chewbacca context` prints what that costs. `chewbacca bench` prints what it
takes. Both existed only after somebody measured, which was later than it
should have been.

## What happens when you ask for something

The model reads skill descriptions and loads the matching body. That is the
whole routing mechanism, which is why a description is written as carefully as
the code. `chewbacca evals` checks that every eval prompt shares vocabulary
with the description meant to catch it.

## The Mac layers

Seven ways to do the same thing, cheapest first: a database read, AppleScript,
a Shortcut, the accessibility tree, synthetic events, a screenshot, and a
vision model. `mac-control` picks. A screenshot is the last resort and is
usually a sign the cheaper path was not tried.

## Design decisions worth knowing

**Everything is plain text.** No compiled artifacts, no database of
configuration. You can read, diff and revert all of it.

**The installer is one file.** 1,700 lines of bash, guarded section by section,
with CI asserting each section is skippable. It is too big and that is a known
problem, item 26 and 50 in [1000.md](1000.md).

**Generated regions.** README counts, the extension tables and the setup
install list are generated from the tree by `tools/counts.py` and
`tools/inventory.py`. Hand-maintained numbers drifted and CI now catches it.

**Nothing prompts.** Bypass mode is on by default, with a deny list for what
stays blocked. See [THREAT-MODEL.md](THREAT-MODEL.md) for what that buys and
what it costs.
