# Doing anything on this Mac

The goal is a machine where Chewbacca is the only thing you open. This is what
stands between here and there, measured on a real Mac on 2026-09-20 rather than
reasoned about, and what the people who build computer-use agents for a living
say to do about it.

Numbers in the first half came from running something. Numbers in the second
half carry a citation. Where a claim is unverified it says so.

Companion docs: [1000.md](1000.md) is the gap list, [ROADMAP.md](ROADMAP.md) is
what was next before this, [mac/BENCHMARKS.md](mac/BENCHMARKS.md) is the
external scoreboard, [mac/DECISION-TREE.md](mac/DECISION-TREE.md) is the
routing prose this argues with.

---

## The short version

Chewbacca does not need more ways to click. It has seven layers, every
permission granted, a benchmark-literate doctrine, and the right architecture
on paper. Five things are actually in the way:

1. **The action vocabulary is hand-written and 9 wide.** This Mac declares 170
   URL schemes that are free to call and 249 typed App Intent actions that are
   free to read. Nothing reads or calls either.
2. **The one path that carries the safety gate and the audit log is the one
   path nobody takes**, and it has a hole in it anyway.
3. **Nothing records what happened**, so nothing improves.
4. **The ambient surface cannot be corrected, cannot be undone, and cannot show
   its work**, so it cannot be trusted with anything that matters.
5. **All three legs of the lethal trifecta are present by design**, with no
   sandbox and prompting off by default.

Fix 2 and 3 first. They are small, they are the substrate for everything else,
and one of them is a live security bug.

---

## Part one: what is true today

### The doors this machine actually has

This machine runs **macOS 15.7.3 Sequoia**, not 26 or 27. Everything measured
here is a Sequoia measurement.

| Door | Count | Measured by |
| --- | --- | --- |
| App bundles installed | 140 | `/Applications/*.app`, `/Applications/*/*.app`, `/System/Applications/**` |
| With an AppleScript dictionary | 27 (19%) | bundled `*.sdef` or `OSAScriptingDefinition` |
| Declaring at least one URL scheme | 78 (56%) | `CFBundleURLTypes` |
| **Distinct URL schemes declared** | **170** | same |
| Shipping an App Intents catalog | 23 | `Contents/Resources/Metadata.appintents/extract.actionsdata` |
| **Typed App Intent actions** | **249** | parsed from those catalogs |
| Same, counting nested helpers and XPC services | 274 | `Contents/**/` glob |
| Shortcuts installed | 5, all Apple samples | `shortcuts list` |

`mac/data/grammar.json` declares **9 actions, 5 queries, 5 streams**, all
written by hand.

The App Intents catalogs are the finding. Each entry carries parameter names,
parameter types, return entity types, a description and an `isDiscoverable`
flag. Notes exposes 50 actions. Mail exposes 26, including `ArchiveMessage`,
`BlockSender`, `ComposeMessage` and `CancelDraft`. Music 23, Freeform 23,
Preview 17, Maps 16, VoiceMemos 14. Third-party apps do it too: Maccy exposes
`Get`, `Select`, `Delete` and `Clear` over clipboard history, returning a
`HistoryItemAppEntity` with `text`, `richText`, `html`, `image` and `file`
properties. [MACOS-TOOLS.md](MACOS-TOOLS.md) says Maccy's history cannot be
read programmatically. It has shipped a typed reader the whole time.

One thing the catalog will not tell you: **247 of 248 actions declare
`authenticationPolicy: 0`.** The metadata does not mark what is dangerous. Risk
classification is yours to build and yours to own, by verb rather than by what
the app claims.

This is the same artifact `grammar.json` is: a typed action catalog with
confirm-worthy operations identifiable by name. Apple generates it per app, at
build time, for free.

Two collection bugs worth knowing. Globbing `/Applications/*.app` misses the
entire Adobe suite, which lives in `/Applications/Adobe Illustrator 2026/` and
is fully scriptable through both AppleScript and ExtendScript. And
[mac/DECISION-TREE.md](mac/DECISION-TREE.md) opens by telling the agent to run
`sdef /Applications/Foo.app`, which on this machine prints an Xcode error and
zero bytes while exiting 0, because only Command Line Tools are installed. The
first check in the routing document returns a silent wrong answer.

### What the layers actually cost

| Layer | Operation | Latency | Result size |
| --- | --- | --- | --- |
| 1 | `sqlite3 chat.db 'select count(*)'` | 32 ms | bytes |
| 1 | `defaults read -g` | 25 ms | bytes |
| 0 | `shortcuts list` | 31 ms | bytes |
| 2 | `osascript` frontmost app | 137 ms | bytes |
| 2 | `osascript` Safari tabs | 128 ms | bytes |
| 3 | `chewie see --app Finder` | 171 ms | 311 B |
| 3 | `agent-desktop snapshot` | 132 ms | 294 B |
| 5 | `screencapture -x` full screen | 134 ms | **2,832,134 B** |

Latency across all seven layers spans 6.8x. Result size spans **9,600x**.

The decision tree argues for the cheap layers on speed. Speed is not the
argument and never was. Every layer is fast. The argument is context, and
secondarily determinism: an AppleScript that fails returns an error code, while
a vision click that fails returns a plausible wrong answer.

Real accessibility snapshots, for scale: Chrome 24 KB, Claude 40 KB. Both
Electron, both fine. The "Electron tree is empty" folklore did not reproduce.

### The tax before anything starts

`chewbacca context` reports **29,742 always-on tokens against its own stated
15,000 budget**. Over by 14,742. CLAUDE.md is 7,583 of it, 90 skill
descriptions are 4,491, and `writing.md` alone is 2,264.

### The voice loop, from its own log

Five turns have ever been recorded in `~/.bob/listen.log`. Time to first text:
1.1s, 1.4s, 3.7s, 6.0s, 2.5s. The single turn that used tools spent
**18,937 ms** in the API across three tool calls.

### Defects confirmed by execution

**1. The confirm gate is bypassable, and the bypass is invisible in the log.**
`run_shell` as an action is correctly refused:

```
STOP: action 'run_shell' is confirm-gated in the grammar. Re-run with --yes.
```

The same side effect placed in an `app_data` *query* runs with no gate at all.
`grammar.json` classifies `app_data` as a read that "never has a side effect",
and `mac/lib/run_plan.py:108` hands its `script` parameter to `osascript`.
AppleScript has `do shell script`. Verified live with a harmless script. The
trace recorded it as `query:app_data ok 7 bytes` and never logged the body, so
the audit trail shows a clean read.

The gate is in the grammar, which is the right place. The type system that puts
it there does not yet distinguish a read from a write.

**2. `verify` is dead code.** `run_plan.py:209` calls `_jarvis(...)`. Only
`_chewie` exists; an AST walk returns `called but never defined: ['_jarvis']`.
The call sits outside the enclosing `try/except`, so any plan carrying
`"verify"` raises NameError *after* the action has fired, and `tr.close()`
never runs, truncating the trace. `verify` is also absent from every action's
params in the grammar, so `check()` neither validates nor advertises it. The
see-act-see discipline four documents call mandatory has never executed.

**3. The type checker does not check types.** Both of these pass clean:

```json
{"name":"texts","days":"banana","unanswered":"yes please"}
{"name":"texts","days":1,"nonsense":true,"verify":"Finder"}
```

`check()` tests only whether params whose type string lacks a trailing `?` are
present. Unknown params are accepted silently. Strong typing is the first
design principle listed in `grammar.json`.

**4. Four of five streams are ignored.** `every`, `on_text`, `on_file` and
`on_calendar` are validated at `run_plan.py:60` and never branched on. `main()`
runs queries, runs actions, exits. The grammar's own worked example is a daily
schedule that runs once and never says so.

**5. Nothing records what Chewbacca does.** Only `chewie plan run` writes a
trace. Ten of eleven `chewie` verbs are uninstrumented. Before this session
`~/.chewie/runs/` was empty: zero plans had ever run on this machine.

**6. Five doc paths cited by five skills and one slash command do not exist.**

```
docs/05-DATA-LAYER.md    -> docs/mac/05-DATA-LAYER.md
docs/WORKAROUNDS.md      -> docs/mac/WORKAROUNDS.md
docs/BENCHMARKS.md       -> docs/mac/BENCHMARKS.md
docs/DECISION-TREE.md    -> docs/mac/DECISION-TREE.md
data/failure-modes.json  -> mac/data/failure-modes.json
```

Cited by `mac-runtime`, `mac-debug`, `mac-see`, `mac-apps`, `mac-control` and
`/mac-layers`. The agent gets file-not-found exactly when it is choosing a
layer or debugging a failure. Inherited from the standalone repo this was
absorbed from.

**7. `/brief` does not exist.** `mac/app/install-brief.sh` schedules
`claude -p "/brief"` at 08:00. The commands directory has `daily-brief.md` and
`mac-brief.md`. Also unbuilt here: the launchd job itself, and
`~/Applications/Chewbacca.app`, so the "grant once, ever" win in
[mac/BREAKING-WALLS.md](mac/BREAKING-WALLS.md) is unrealized and grants remain
per host terminal. `chewie doctor` reports the host as Terminal.

**8. The reliability layer is installed and unused.** `agent-desktop` exposes
roughly 50 commands including `wait`, `batch`, `session` with trace JSONL,
`list-windows`, `resize-window`, `clipboard-get`, `list-notifications` and
snapshot-scoped refs. `chewie` reaches two of them: `snapshot` and `click`.
`peekaboo` exposes roughly 30; `chewie` reaches five. Its errors are already
good:

```
WINDOW_NOT_FOUND  Application 'Safari' is running but has no matching window
suggestion: Wait for the app to present a window, or run 'list-windows --app'.
```

That retires item 385 of [1000.md](1000.md) without the list noticing.

**9. `agent-desktop list-apps` timed out here** after 121 attempts, while one
line of `osascript` answered the same question instantly. Nothing measures
which layer won, so the routing never learns it.

**10. The ambient agent is forbidden from the ambient display.**
`bin/hud-agent.md:43`: "Do not draw on the display: no panels, no cards, no
`hud draw`." The HUD renders 18 component types. The one agent that hears you
may use none of them.

### What is already running

Kyber.app, `hud-listen`, `hud-speak`, a `claude -p` subprocess and
`node bin/lib/chewbacca-hud.js` on port 7474 have been up for hours.

[ROADMAP.md](ROADMAP.md) lists a daemon under **Deliberately not doing**, on the
grounds that "nothing is left running" is the difference between this and every
alternative. That is no longer true. The daemon arrived through the HUD and the
roadmap has not noticed, so nothing is built on it: `hud-watch` ships exactly
two checks and both are coursework. Zero Chewbacca launchd jobs are installed.

This is worth deciding on purpose rather than by accident. The four streams in
the grammar that do not work are exactly the four that need the thing that is
already running.

---

## Part two: what the field says

Full citations in the research appendix below. The short list of what
practitioners have measured, ordered by how much it bears on Chewbacca.

**Call the API before you touch the UI.** Microsoft's UFO2 added 12 native APIs
across 27 office tasks and gained 6.1 points with GPT-4o and 8.2 with o1, while
cutting steps by up to 58.5%. An API call cannot miss a button, cannot land on
a stale frame, and costs one step instead of six.

**Put code execution in the action space.** Agent S3 went from 48.8% to 62.6%
on OSWorld by letting the GUI policy invoke programmatic edits natively, the
largest single architectural gain in the literature. The matching failure mode:
4 of 12 analyzed failures were the GUI agent overwriting the coding agent's
work because it never read back after the handoff.

**Verification is the biggest unclaimed win.** Across every system measured in
OSWorld 2.0, recovery and repair together stay **under 7% of budget**. False
completion, declaring success without checking, is the most frequent production
failure.

**Version element refs and fail on mismatch.** A ref shaped
`snapshotVersion:elementId` turns a stale click into a caught error instead of
a click on whatever moved into that position. `agent-desktop` already does
this, which is item 379 of the gap list solved by a binary already installed.

**Never retry the same failed action.** Analyze why, then try a different
approach. Repetitive looping is a top-five production failure. Chewbacca states
this rule in four documents and enforces it in zero lines of code.

**Batch actions rather than one per turn.** A 28-field form took 104.5s and
154K tokens in bulk against 245.1s and 260K sequentially: 57% faster, 41%
fewer tokens, 74% fewer calls. The best OSWorld 2.0 configuration is the
batched one. `agent-desktop batch` exists and is unused.

**Budget for the planner, not the environment.** OSWorld-Human measured
planning and reflection at **75% to 94% of total task latency**. Optimizing
screenshot capture optimizes the wrong quarter. This matches the HUD's own
18,937 ms tool turn.

**Cache successful trajectories as reusable workflows.** Agent Workflow Memory
gained 12.0 absolute on WebArena and 24.6% relative step success on Mind2Web,
inducing workflows online from the agent's own successes. Commercially the same
idea is Stagehand's replay cache and OpenAdapt's compile-to-deterministic-code.
This is items 377 and 378 of the gap list, and it is the biggest unbuilt win
on that list.

**Skip the high-level planner.** Agent S3 removed hierarchical manager-worker
for a flat step-level policy that can replan at any observation, and gained 9.1
points with 43.8% fewer LLM calls and 52.1% less wall-clock. Do not build a
planner layer.

**Accessibility-primary hybrid, vision selective.** Raw DOM is unusable, one
form field can take 100 lines of HTML. Pure vision fails on 24px targets.
95.9% of top websites have accessibility conformance errors, so a11y alone is
not enough either. UFO2 fused both and recovered up to 9.86% of the failures
that a tree-only path produced. Chewbacca's layer ordering is already right.

**Do not rely on human confirmation as a control.** In a study of 1,053 paid
developers, Claude Code's automated auto mode blocked 89% of harmful actions
against **13.6% for human reviewers**. Confirmation dialogs get rubber-stamped.
Gate on categories that genuinely warrant a stop and automate the rest.

**Enforce safety in deterministic code, never in model judgment.** A classifier
guarding a model is not a security boundary.

### The scoreboard, honestly

OSWorld is saturated: the top is now 85 to 86% against a **72.36% human
baseline**, and two reputable aggregators disagree about the leader by about 7
points. That number is no longer informative.

OSWorld 2.0 is where the real gap lives. 108 long-horizon workflows, median
human completion time **1.6 hours**, an average of 318 tool calls against
roughly 30 in OSWorld 1.0. The paper's best binary end-to-end completion is
**20.6%** at roughly $72 per task. Leaderboards since report higher across
different versions, step budgets and graders, up to about 32% binary. The
binary number is the honest one and it is roughly a third.

The number that matters most is not on a leaderboard: one production write-up
reports **78% single-attempt success and 36% reliability across ten identical
runs of the same task**, with the variance coming from different planning
strategies rather than noise. Reliability across runs is what is failing, not
single-attempt capability.

Read every number with its harness attached: step budget, resolution, task
filtering, thinking effort, run count, and whether a vendor or a third party
ran it. One vendor documents a 2.79-point gap between its internal and its
verified score.

### The security problem this goal creates

Simon Willison's framing, now standard: the **lethal trifecta** is access to
private data, exposure to untrusted content, and a means of exfiltration. Any
two are survivable. All three is the attack.

Chewbacca has all three by design, and "do anything on your computer without
using anything else" makes each leg wider:

- **Private data.** Full Disk Access, `chat.db`, Contacts, Calendar, Mail.
- **Untrusted content.** Email bodies, web pages, screen text, PDFs, calendar
  invite descriptions. `untrusted-content.md` is a prompt, not a boundary.
- **Egress.** `run_shell`, `chewie run`, the web bridge, the network.

And prompting is off by default. [ARCHITECTURE.md](ARCHITECTURE.md): "Nothing
prompts. Bypass mode is on by default, with a deny list for what stays
blocked." `mac/data/failure-modes.json` already marks prompt injection
`severity: critical` with a detect field reading "not reliably detectable;
treat as always present." That is the correct assessment and nothing acts on
it.

What actually happened to other people, all with dates and sources in the
appendix: Perplexity Comet, full account takeover through page content, July
2025. Google Antigravity exfiltrating `.env` credentials to a default-allowlisted
webhook, November 2025. Superhuman pulling dozens of sensitive emails into an
attacker's Google Form, January 2026. Claude Cowork exfiltrating files through
Anthropic's own allowlisted API domain, January 2026. A self-replicating
injection in Word, July 2026. Claude Code auto mode bypassed at an 80% success
rate, August 2026.

The practitioner position is blunter than the vendor position: general-purpose
autonomous operation at full user privilege is the thing these attacks exploit,
and the defense that works is **specialization**, scoping an agent to one
surface so a compromise has a bounded blast radius.

That is in tension with "do anything with nothing else", and the tension is the
most important design decision in this document. The resolution is in Part
three.

---

## Part three: what to build, in order

Ordered by what each one returns per unit of work, not by size.

### Tier 0: three small fixes that are bugs, not projects

These are hours, not weeks, and two of them are correctness.

1. **Close the `app_data` hole.** Split the grammar's type system into `read`
   and `write` rather than `query` and `action`, and put the confirm gate on
   the effect, not on the phase. An AppleScript query is a write until proven
   otherwise. Log the script body in the trace.
2. **Fix `_jarvis`, add `verify` to the grammar, move the call inside the
   `try`.** Then make verification the default for any action with a side
   effect rather than opt-in, since the literature says under 7% of budget
   reaches repair and this is the one place the kit automates it.
3. **Check types in `check()`, and reject unknown params.** Twenty lines.
   Without it the word "typed" in the architecture is decorative.

Then the trivia: repoint the five broken doc paths, create `brief.md` or fix
the plist, and replace the `sdef` line in the decision tree with something that
works without Xcode (read `Contents/Resources/*.sdef` and `OSAScriptingDefinition`
out of `Info.plist` directly, which is what produced the 27/140 number above).

### Tier 1: generate the action catalog instead of writing it

This is the answer to "anything", and the research changed its shape. Read this
before building it, because the obvious plan does not work.

**The verdict on App Intents: you can read all 249, and you cannot call any of
them.** Both halves were confirmed first-hand.

Reading costs nothing. `extract.actionsdata` is world-readable at a fixed path,
no entitlement, no TCC. The format is undocumented and unstable, emitted by
Xcode's `appintentsmetadataprocessor`, with a `version.json` beside it and a
`generator` key inside, which is Apple saying the schema moves. `AppIntents.framework`
is an authoring framework: it has no entry point that lists the system's intents
and none that performs another app's.

Calling is gated by `com.apple.shortcuts.background-running`, an Apple-private
entitlement that AMFI enforces. `codesign -d --entitlements` on
`WorkflowKit.framework/XPCServices/BackgroundShortcutRunner.xpc` shows why Apple
will never open it: the runner holds `com.apple.private.tcc.allow` for fourteen
services including Accessibility, Screen Capture, Microphone, Apple Events,
Photos and Contacts. The runner is a privileged TCC-exempt broker, and handing
out a generic "run any intent" API would hand out that bypass set. A non-Apple
binary claiming the entitlement is killed at exec. The one public project that drives it directly says plainly that it needs
SIP and AMFI disabled, and its own author recommends against running it on a
machine you care about.

Apple did not open a route in macOS 26 or 27 either. Checked against the full
WWDC26 session index: no MCP support, no computer-use API, no external agent
API. App Intents got richer and stayed closed, and every new surface (App
Schemas, View Annotations) requires the target app's own developer to opt in.

**Shortcuts is the only execution door, and it does work.** Authoring and
signing a `.shortcut` headlessly is real:

```
shortcuts sign -m anyone -i min.shortcut -o signed.shortcut   # rc=0, AEA1 container
shortcuts sign -m people-who-know-me ...                      # fails
```

The input is a plist whose root is `WFWorkflowActions`, an array of
`{WFWorkflowActionIdentifier, WFWorkflowActionParameters}`. Keep it minimal;
extra top-level keys break it, which is what made a first attempt here fail
before a second one succeeded. `-m anyone` is the mode that works and it needs
network. The run contract is
`shortcuts run <name-or-UUID> [-i path|-] [-o path|-] [--output-type UTI]`,
errors on stderr with exit 1, and `shortcuts list --show-identifiers` gives
stable UUIDs to address by.

What that door costs, and it is not small:

1. **One wrapper per intent, per parameter shape.** No generic "run intent X
   with params Y" exists. Structured I/O is possible via `--output-type
   public.json`, but the shortcut itself has to be authored to parse and emit
   it. There is no automatic marshalling.
2. **One human-present first run per wrapper, forever.** Shortcuts gates data
   access per shortcut with Allow Once / Always Allow / Don't Allow. No flag,
   no plist key, no `tccutil` equivalent answers it. Design an explicit "arm
   the assistant" session where every wrapper is run once, rather than meeting
   this prompt at 2am in a scheduled job.
3. **A GUI session.** `shortcuts run` is Aqua-bound. It works from a
   LaunchAgent in a logged-in session, not from a LaunchDaemon or bare SSH.
4. **A click to import**, unless you write `~/Library/Shortcuts/Shortcuts.sqlite`
   directly, which is fragile: CoreData triggers, `siriactionsd` caching, Full
   Disk Access, and iCloud restoring what you delete.

**So do the cheap door first.** URL schemes are free to enumerate *and* free to
call. There are 170 of them across 78 apps on this machine, many undocumented.
`open -g wispr-flow://start-hands-free` is how one engineer replaced a hotkey
synthesis that macOS had broken: no grant, no focus theft, one command. For an
agent this is higher yield and lower friction than App Intents, and nothing in
Chewbacca's seven-layer model has a slot for it.

The build, in order:

1. **`chewie catalog`**, which scans the machine and emits one typed catalog
   merging four sources: `CFBundleURLTypes` (170 schemes, callable now),
   AppleScript dictionaries (27 apps), App Intents metadata (249 actions,
   readable now), and `shortcuts list` (user-authored compound actions).
   Generate it; do not write it.
2. **Wire the URL-scheme half straight into the grammar as actions.** That is
   the part that pays this week.
3. **Treat the App Intents half as a capability map for planning**, which
   answers the question [mac/DECISION-TREE.md](mac/DECISION-TREE.md) currently
   answers with a broken `sdef` call: does this app have a semantic door at
   all.
4. **Add Shortcuts wrappers only where an intent is worth the per-intent cost**,
   and expect that cost to be the dominant engineering line item.

The prize, in the literature's terms: this is rule one, call the API before you
touch the UI, applied at the scale of the whole machine instead of twelve
hand-written office APIs. UFO2 got 6 to 8 points and a 58% step reduction
from twelve.

### Tier 2: one path, always instrumented

Today the model's fastest route to any capability the 11 verbs do not cover is
to bypass `chewie` entirely and call `peekaboo`, `agent-desktop`, `mac` or
`osascript` directly. `skills/mac-act/SKILL.md` explicitly tells it to. Every
one of those calls also bypasses the type check, the confirm gate and the
trace, because all three live inside `chewie plan run`.

That is the architecture seam and it is the reason tier 0 item 1 is not enough
on its own. A gate nobody routes through is not a gate.

Two changes:

1. **Widen the waist to match the drivers underneath it**, so bypassing is not
   attractive. `agent-desktop` alone offers `wait`, `batch`, window management,
   clipboard and notifications that Chewbacca has no verb for. Adding a
   capability currently takes four hand-edits in four files with no coupling;
   generate three of them from the catalog.
2. **Instrument every verb, not just `plan run`.** Same JSONL trace, one line
   per call, including the layer used and whether it succeeded. That single
   change turns item 372, "nothing measures which layer succeeded, so the
   routing never improves", from a permanent condition into a dataset. It is
   also the precondition for tier 3.

Wire `agent-desktop --trace` and `session` through instead of writing a second
tracer. It is already there and `mac/lib/see.py` drops it on the floor.

### Tier 3: remember what worked

Agent Workflow Memory is the best-measured idea in the field that nobody has
built here: induce reusable workflows from successful trajectories, online,
from the agent's own successes. 12.0 absolute on WebArena.

With tier 2 shipping traces, this becomes tractable: a successful plan is
already a typed, canonical, checkable object. Cache it keyed on its canonical
form, which `grammar.json` already says is the point of canonicalization, and
replay it instead of re-reasoning. That is items 377 and 378, and it is the
difference between an assistant that can do a thing and one that has done it
before.

Stagehand's number for the commercial version of this is 10 to 100x on repeats.

### Tier 4: the streams, and the daemon that already exists

Once traces and replay exist, honor `every`, `on_text`, `on_file` and
`on_calendar` by compiling them to launchd jobs and file watchers rather than
ignoring them. The failing part is small; the decision is not.

Make the daemon deliberate. It is running. Either bring it into the
architecture document with its own boundaries, or take it out. The current
state, where ROADMAP says no daemon and four processes are up, is the worst of
both: the cost is being paid and the capability is not being used.

At minimum, stop a plan that declares a stream it cannot honor from silently
pretending it ran.

### Tier 5: scope, because capability without it is the vulnerability

Do not ship "one agent with every permission." Ship one entry point with
several scoped executors behind it, which is the specialization defense and
also just better engineering.

Concretely: the thing that reads email should not be the thing that can shell
out. The thing that browses should not hold Full Disk Access. The HUD's voice
agent already demonstrates the shape, running a lean profile with one tool, and
that was done for cost rather than for safety. The same mechanism buys both.

Three rules from the research worth encoding rather than writing down:

- Break one leg of the trifecta per session, not by policy but by construction.
- Gate on categories, not on every action, because humans rubber-stamp at 13.6%.
- Put the gate in deterministic code, and treat a model checking a model as
  no boundary at all.

---

## Part four: the interface

The capability half is above. This half is why a capable system still does not
get used.

### There are three front doors and none of them is the one

| Surface | Can do | Cannot do |
| --- | --- | --- |
| Claude Code in a terminal | everything: files, git, subagents, long work | not ambient, not glanceable, not voice |
| Kyber overlay plus voice | ambient, hears you, renders 18 component types | forbidden from drawing, no history, no undo |
| `chewbacca open` on :7474 | one glance at people and coursework | read-only, cannot act |

The HUD's own audit says it best, item 995: "Two front doors, the pill and the
glass, with different capabilities and no shared model of a conversation." The
third door on 7474 makes it three. `bin/hud-agent.md` and `skills/hud/SKILL.md`
give opposite instructions to the two agents behind them.

Picking one is the whole UX decision. The overlay is the right one: it is
already running, already keyless, already renders, and it is the only surface
that can be present without being opened.

### The five gaps that actually stop people using it

Ranked by how much each one costs, from the HUD's own 1000-item audit
cross-checked against what desktop assistants get praised and uninstalled for.

**1. It cannot show what is in flight, and cannot be corrected.** Items 786,
787, 785, 783, 710. There is no agent tray, clicking the presence ring does
nothing, there is no per-action cancel, and there is no way to say "no, I said
the other one" mid-run. You can stop, and stopping destroys state rather than
restoring it.

This is the one that decides whether the thing is trustworthy, and trust is the
gate on everything in Part three. An agent that can do anything and cannot be
watched will not be allowed to do anything.

**2. There is no undo, anywhere.** Item 305. Not for a control press, not for a
file save, not for a `mac` side effect. `review-discipline.md` requires that
anything writing in bulk ships a reverse. Nothing in `mac/` honors it. The only
reversal primitive in the system is Escape, which clears rather than reverses.

The grammar makes this tractable in a way a freehanding agent does not: a typed
action with typed params can declare its compensating action in the same
signature the confirm flag lives in.

**3. Nothing persists.** Items 856, 989, 990, 991. Quitting loses every
surface. It does not know what it told you yesterday. Chat turns cap at 200 in
memory and die with the process. There is no searchable history of what it did,
which is the same hole as "nothing records what it does" from the capability
half, seen from the user's side.

**4. It does not know when to be quiet.** Items 443, 444, 445, 446, 958.
No Focus mode integration, no quiet hours, no screen-share detection, no
full-screen detection, and urgency is claimed by the sender so an agent that
always says `alert` wins. An ambient surface that interrupts a meeting gets
turned off once and never turned back on.

**5. The voice loop acts on text it knows is unrevised.** The recognizer never
sends a final; every release returns error 1101 or 1110 within 7 to 78ms, so
the error path commits the last raw partial. The final is where proper nouns
get corrected. Combined with the removal of the confirmation window on
2026-09-19, a misheard name goes straight to `mac messages send`. The barge-in
comment in `hud-listen` records exactly this happening.

### What to do about it

**Give the ring a tray.** It is already the one persistent element, it already
has nine states, and clicking it already does nothing. One surface listing what
is in flight, what each step is, and a cancel per row closes items 783, 785,
786 and 787 together. This is the single most valuable UI change in the repo.

**Let the voice agent draw.** Delete the line in `bin/hud-agent.md` that
forbids it and let one prompt govern both doors. A display that renders 18
component types and an agent that may only speak is a capability sitting idle
behind a prompt.

**Make the transcript visible before it acts on a name.** Not a blanket
confirmation window, which was removed for good reason. Confirm on the
categories that warrant it, which is the same rule the research gives for
actions: outbound messages, payments, deletion. The 13.6% number says a
blanket gate is worse than a categorical one because people stop reading it.

**Persist the session.** Traces from tier 2 are the same data. A history you
can search is the difference between "what did it do" being answerable and not.

**Read Focus and screen sharing before drawing.** Small, and it is the
difference between an ambient surface someone keeps and one they quit.

**Then pay the context tax down.** 29,742 against a 15,000 budget is a
real cost on every session, and `writing.md` at 2,264 tokens is the single
largest rule. The deferred-loading mechanism already exists and is used for
three rules. Use it for more.

### Do not invent these, they are solved

Every pattern below is shipping somewhere and was found by looking at what
people praise and what makes them uninstall. Sources in the appendix.

**Name the step, never the state.** Apple's own guidance: instead of
"Processing", say "Finding substitutions for ingredients". The HUD's pill
currently shows a phase. It should show the step.

**Allow, Always allow, Deny, on one keystroke each.** Raycast's exact shape is
Return, Command-Return, Escape, plus Allow All and Deny All once a queue builds
up. Batch approval is what stops per-action confirmation from being abandoned,
and abandonment is what the 13.6% number measures.

**Three tiers, not one switch: scope, confirm, refuse.** App-level permission
that is grantable and revocable; per-action confirmation for consequential
operations; a hard category blocklist that is refused rather than gated.
Anthropic's model, and the only one with published numbers behind it. Keep a
hardcoded floor no preference can lower: Raycast always asks before reading
`.env` files and private keys even in auto mode.

**Never auto-send. Render outbound artifacts as Edit, Discard, Send.**
Highlight's pattern, and the one Operator violated when it spent $31.43 on eggs
it was asked only to find.

**Hand control back for credentials, and stop recording during the handoff** so
the assistant is never in a position to have retained a password. Operator's
best micro-interaction.

**Checkpoint before every multi-step run, with one-key rollback.** Cursor
checkpoints on every apply. This is the concrete shape of the undo that
[review-discipline.md](../.claude/rules/review-discipline.md) already requires
and `mac/` does not have.

**Make every claim one click from its source.** Granola puts a magnifying glass
on each summary line that jumps to the transcript moment it came from. Anything
Chewbacca asserts from a message, a page or a file should be clickable back to
the bytes.

**Typographically separate what you wrote from what the model wrote.** Granola
renders human notes in black and generated text in gray. Cheap, and it is why
the output reads as a person's notes.

**Withhold proactive suggestions below a confidence threshold**, and never
render a confidence number you have not calibrated. Both are Apple's explicit
guidance, and the first is the mechanism that would prevent most interruption
complaints. `hud-watch`'s two-per-hour cap is a rate limit, not a threshold.

**Prefer guided corrections to a blank box.** Offer alternatives. This is the
right shape for the mid-run correction the HUD does not have.

### The failure modes that actually kill these products

Worth reading as a list of things not to ship.

**A success indicator over a silent non-answer.** Granola users reported
sessions that showed recording and produced nothing, unrecoverable because no
audio is retained. This is the worst failure mode in the entire research set,
and Chewbacca already has its own version of it: `mac messages send` accepts
handles never registered with iMessage and returns success. Verify the thing
landed, not that it started.

**Confidently wrong, stated authoritatively.** Cursor's support bot invented a
login policy that did not exist. 1,511 points on Hacker News, public
cancellations, and an engineer having to deny his own product's bot. The bug
cost less trust than the explanation did.

**Data leaving the device without a dated, visible opt-in moment.** Wispr Flow
was found sending periodic screenshots of the active window to third-party
servers continuously, not only during dictation, and its first move was to ban
the user who found it. The ban did more damage than the finding. Chewbacca's
answer here is structural and already half-built: `failure-modes.json` names
prompt injection critical, and nothing yet distinguishes data that may leave
the machine from data that must not. That is items 549 to 551.

**Battery.** Rewind is the cautionary tale, and nobody in the research set has
solved always-on capture without a power cost users notice. Five processes are
already resident. Measure it and show it rather than hoping.

**Requiring an account for something that worked locally.** Warp required login
for a terminal emulator and the top comment was "I have never uninstalled a
program faster in my life", before any AI feature was touched. Chewbacca has no
account and no server. Keep it that way.

**Latency.** Reviewers independently say one second breaks a fast talker's
flow. The HUD's measured time to first text runs 1.1 to 6.0 seconds, and 75% to
94% of that is the model. Local-first is a latency requirement before it is a
privacy one, which is the real argument for the Kokoro work already done.

---

## What not to do

Do not build a planner. Agent S3 removed one and gained 9.1 points with
43.8% fewer model calls. A flat policy that can replan at any observation is
the current best practice.

Do not chase OSWorld. It is saturated above the human baseline and two
aggregators disagree about its leader by 7 points. If a benchmark is wanted,
the honest one is reliability across repeated runs of the same real task, where
the field sits near 36%.

Do not escalate to vision to route around a fixable layer-3 problem. The docs
already say this. The 9,600x result-size measurement is the reason, and it
is stronger than the reason currently given.

Do not add a second tracer, a second control binary, or a second HUD.
Three of each already exist. The work is consolidation.

Do not widen capability before tier 0 and tier 2 land. An ungated, unlogged
path that can reach 274 actions instead of 9 is not an improvement.

---

## Research appendix

Every claim in Part two, with its source. Numbers are as reported by the cited
work, with the harness caveats attached where the sources disagree.

### Architecture

| Claim | Number | Source |
| --- | --- | --- |
| Native APIs beat clicking | +6.1 (GPT-4o) / +8.2 (o1) points, 27 office tasks, 12 APIs; steps cut 6.5% / 58.5% | [UFO2, arXiv 2504.14603](https://arxiv.org/html/2504.14603v1) |
| Hybrid a11y plus vision recovers tree-only failures | up to 9.86% | same |
| Speculative multi-action planning | steps cut up to 10% (WAA), 51.5% (OSWorld-W) | same |
| Code execution in the action space | OSWorld 48.8% to 62.6% | [Agent S3 / bBoN, arXiv 2510.02250](https://arxiv.org/html/2510.02250v1) |
| Flat policy beats hierarchical planner | +9.1 points, 43.8% fewer LLM calls, 52.1% less wall-clock | same |
| Best-of-N over behavior narratives | OSWorld 62.6% to 69.9% at N=10 | same |
| Mixture-of-grounding: visual, OCR, structural experts | Agent S2 design | [arXiv 2504.00906](https://arxiv.org/html/2504.00906v1) |
| Workflow memory induced from successes | +12.0 absolute WebArena, +24.6% relative step success Mind2Web | [Agent Workflow Memory, arXiv 2409.07429](https://arxiv.org/html/2409.07429) |
| A11y-primary hybrid; raw DOM rejected; grid overlays rejected | 100+ lines of HTML per form field | [arXiv 2511.19477](https://arxiv.org/html/2511.19477v1) |
| Architecture dominates model choice | ~85% WebGames vs ~50% prior on similar base models; human 95.7% | same |
| Vision-only parity, and why a11y alone is not enough | 95.9% of top sites have a11y conformance errors | [UGround / SeeAct-V, arXiv 2410.05243](https://arxiv.org/html/2410.05243v3) |
| Build the agent-computer interface with care; poka-yoke tool params | absolute-only file paths removed a class of error | [Anthropic, building effective agents](https://www.anthropic.com/engineering/building-effective-agents) |

### Benchmarks

| Benchmark | Figure | Source |
| --- | --- | --- |
| OSWorld human baseline | 72.36% | [osworld-v1.xlang.ai](http://osworld-v1.xlang.ai/) |
| OSWorld current top | Qwen3.8-Max 86.1%, Claude Mythos Preview 85.4%, Opus 4.8 83.4% | [leaderboard.steel.dev](https://leaderboard.steel.dev/leaderboards/osworld/) |
| OSWorld disagreement between aggregators | ~7 points (Seed 2.1 Pro 78.8% elsewhere) | [llm-stats.com](https://llm-stats.com/benchmarks/osworld) |
| Vendor internal vs verified gap | 2.79 points | [coasty.ai](https://coasty.ai/blog/osworld-benchmark-2026-computer-use-results) |
| OSWorld 2.0: 108 tasks, median human 1.6h, ~318 tool calls | best binary 20.6% / 54.8% partial at ~$72.4 per task | [arXiv 2606.29537](https://arxiv.org/html/2606.29537v1) |
| Recovery and repair share of budget | under 7% across all systems | same |
| OSWorld 2.0 leaderboards disagree | up to 44.33% binary (Snorkel), 32.0% (Steel) | [Snorkel](https://snorkel.ai/leaderboard/os-world-2-0/), [Steel](https://leaderboard.steel.dev/leaderboards/osworld-2/) |
| macOSWorld: 202 tasks, 30 apps | proprietary agents above 30%, open-source research models below 5% | [arXiv 2506.04135](https://arxiv.org/html/2506.04135v4) |
| WebArena human baseline | 78.24%, GPT-4 original 14.41% | [Steel](https://leaderboard.steel.dev/leaderboards/webarena/) |
| Online-Mind2Web exists because WebVoyager saturated | plain search agent: 51% WebVoyager, 22% here | [arXiv 2504.01382](https://arxiv.org/html/2504.01382v2) |
| Operator failure breakdown | filter and sorting errors 57.7%, navigation 19.6% | same |
| ScreenSpot-Pro: targets at 0.07% of image area | best specialist at launch 18.9%; now GPT-6 Astra 92.7% | [ACM](https://dl.acm.org/doi/10.1145/3746027.3755688), [benchlm.ai](https://benchlm.ai/benchmarks/screenspot-pro) |
| Reliability across runs, production | 78% single attempt, 36% over ten identical runs | [marissaharcourt.substack.com](https://marissaharcourt.substack.com/p/computer-using-agents-are-production) |
| Failures compound nonlinearly with task length | synthesis of 27 papers, 19 benchmarks | [arXiv 2607.05775](https://arxiv.org/abs/2607.05775) |

### Latency and cost

| Claim | Number | Source |
| --- | --- | --- |
| Planning and reflection share of latency | 75% to 94% | [OSWorld-Human, arXiv 2506.16042](https://arxiv.org/html/2506.16042v1) |
| Later steps slow as history accumulates | ~3x slower than early steps | same |
| Per step | 6.8s average, 8,958 tokens, $0.0048 | [arXiv 2511.19477](https://arxiv.org/html/2511.19477v1) |
| Batching a 28-field form | 57% faster, 41% fewer tokens, 74% fewer calls | same |
| Prompt caching, static-to-dynamic ordering | ~75% cache hit, ~89% cost reduction over 100 requests | same |
| Context trimming on long tasks | +34% tool calls, 57% less total cost | same |
| Anthropic screenshot pruning | prune in batches every 25 turns, not per turn, to keep the cached prefix byte-identical | [computer use tool docs](https://platform.claude.com/docs/en/agents-and-tools/tool-use/computer-use-tool) |

### Safety

| Incident | Date | Source |
| --- | --- | --- |
| Perplexity Comet: page content to full account takeover | Jul to Aug 2025 | [brave.com](https://brave.com/blog/comet-prompt-injection/) |
| Google Antigravity: `.env` exfiltrated to a default-allowlisted webhook | 25 Nov 2025 | [simonwillison.net](https://simonwillison.net/2025/Nov/25/google-antigravity-exfiltrates-data/) |
| Superhuman: dozens of emails into an attacker's Google Form | 12 Jan 2026 | [simonwillison.net](https://simonwillison.net/2026/Jan/12/superhuman-ai-exfiltrates-emails/) |
| Claude Cowork: files exfiltrated through Anthropic's own allowlisted domain | 14 Jan 2026 | [simonwillison.net](https://simonwillison.net/2026/Jan/14/claude-cowork-exfiltrates-files/) |
| Self-replicating injection in Word | 29 Jul 2026 | [simonwillison.net](https://simonwillison.net/2026/Jul/29/ai-worming-through-word/) |
| Claude Code auto mode bypassed | 27 Aug 2026, 80% success | [simonwillison.net](https://simonwillison.net/2026/Aug/27/breaking-claude-code-opus-5-auto-mode/) |
| UK AISI: sustained unsanctioned agent activity | 5 Aug 2026 | [simonwillison.net](https://simonwillison.net/2026/Aug/5/incident-report/) |

| Defense | Evidence | Source |
| --- | --- | --- |
| The lethal trifecta framing | private data + untrusted content + exfiltration | [simonwillison.net](https://simonwillison.net/2026/Aug/8/auto-mode/) |
| Humans rubber-stamp confirmations | auto mode blocked 89% of harmful actions, human reviewers 13.6%, n=1,053 | same |
| Anthropic Chrome pilot hardening | attack success 23.6% to 11.2%; browser-specific 35.7% to 0% | [claude.com](https://claude.com/blog/claude-for-chrome) |
| At GA, red teams | 0% against Sonnet 5 and Opus 5, 0.3% against Fable 5 | [claude.com](https://claude.com/blog/claude-in-chrome-generally-available) |
| Categorical confirmation gating | `require_confirmation` for finance, comms, account creation, legal | [Gemini computer use docs](https://ai.google.dev/gemini-api/docs/computer-use) |
| Specialization as the primary defense | bound the blast radius, one surface per agent | [arXiv 2511.19477](https://arxiv.org/html/2511.19477v1) |
| Tool coloring: red touches untrusted data, blue takes critical action, never both | MCP colors | [simonwillison.net](https://simonwillison.net/2025/Nov/4/mcp-colors/) |

### macOS surfaces

| Claim | Source |
| --- | --- |
| `AppIntents` is an authoring framework with no enumerate or perform entry point | [developer.apple.com](https://developer.apple.com/documentation/appintents/appintent) |
| `.shortcut` file format and signing | [zachary7829.github.io](https://zachary7829.github.io/blog/shortcuts/fileformat), [cherrilang.org](https://cherrilang.org/compiler/signing.html) |
| `shortcuts` CLI run contract | [man page](https://keith.github.io/xcode-man-pages/shortcuts.1.html), [Apple guide](https://support.apple.com/guide/shortcuts-mac/run-shortcuts-from-the-command-line-apd455c82f02/mac) |
| Shortcuts URL and x-callback-url routes | [Apple guide](https://support.apple.com/guide/shortcuts-mac/run-a-shortcut-from-a-url-apd624386f42/mac) |
| `BackgroundShortcutRunner` entitlement wall; SIP and AMFI must be off | [tarq.net, Action Relay](https://tarq.net/posts/action-relay-shortcut-actions-mcp/) |
| URL scheme mining as an event-synthesis replacement | [nick-liu.com](https://www.nick-liu.com/posts/tahoe-hotkey-dead-end/) |
| WWDC 2026: App Intents central and closed; no external agent API | [Apple WWDC26 guide](https://developer.apple.com/wwdc26/guides/apple-intelligence/), [Apple newsroom](https://www.apple.com/newsroom/2026/06/apple-aids-app-development-with-new-intelligence-frameworks-and-advanced-tools/) |
| SiriKit deprecated in favour of App Intents | [dracode.dev](https://dracode.dev/blog/2026-06-08-09-wwdc-2026-siri-2-app-intents/) |
| Accessibility tree is the cheap channel; vision the expensive one | [NN/g, AI agents as users](https://www.nngroup.com/articles/ai-agents-as-users/) |

Entitlements were read first-hand with `codesign -d --entitlements` on
`/usr/bin/shortcuts` and on
`WorkflowKit.framework/XPCServices/BackgroundShortcutRunner.xpc`.

### Assistant UX

| Pattern or failure | Source |
| --- | --- |
| Allow / Always allow / Deny keystrokes; auto-mode hardcoded floor; agent tool scoping | [Raycast manual](https://manual.raycast.com/ai/ai-extensions), [agents](https://manual.raycast.com/ai/agents) |
| Three-tier permission model with published attack numbers | [claude.com](https://claude.com/blog/claude-for-chrome) |
| Name the step, not the state; confirm before irreversible actions | [Apple HIG, generative AI](https://developer.apple.com/design/human-interface-guidelines/generative-ai) |
| Guided corrections, confidence thresholds, proactive-feature caution | [Apple HIG, machine learning](https://developer.apple.com/design/human-interface-guidelines/machine-learning) |
| Claim-to-source jump; human text vs generated text typography | [wondertools.substack.com](https://wondertools.substack.com/p/granolaguide) |
| Checkpoint on every apply, one-key rollback | [callmissed.com](https://www.callmissed.com/en/blog/cursor-composer-in-2026-how-it-reshaped-editing) |
| Credential handoff with recording stopped | [Washington Post via archive](https://web.archive.org/web/20250207135803/https://www.washingtonpost.com/technology/2025/02/07/openai-operator-ai-agent-chatgpt/) |
| Silent non-answer under a success indicator | [anarlog.so](https://anarlog.so/blog/granola-ai-complaints/) |
| Confidently wrong support bot | [news.ycombinator.com](https://news.ycombinator.com/item?id=43683012) |
| Screenshots leaving the device; banning the reporter | [embertype.com](https://embertype.com/blog/the-day-wispr-flow-banned-a-user/) |
| Account wall on a local tool | [news.ycombinator.com](https://news.ycombinator.com/item?id=42247583) |
| Always-on capture power cost | [andrewschreiber.substack.com](https://andrewschreiber.substack.com/p/an-early-adopters-thoughts-on-rewindais) |
| One second breaks dictation flow | [techcrunch.com](https://techcrunch.com/2026/08/17/wispr-raises-280m-at-2b-valuation-as-it-looks-beyond-dictation/) |
| Ambient done right: no chat window, everything inspectable before commit | [MacStories, macOS 26 review](https://www.macstories.net/stories/macos-26-tahoe-the-macstories-review/3/) |
| Separate user instructions from page content, structurally | [brave.com](https://brave.com/blog/comet-prompt-injection/) |
| Global, Local and Ambient context roles | [NN/g](https://www.nngroup.com/articles/3-agent-context-roles/) |

### Flagged as unverified

The research pass could not confirm these, and nothing in Part three depends on
them:

- Claude for Excel's control mechanism. Every candidate URL returned 404.
- Anthropic's March 2026 consumer computer use rests on a search summary; the
  CNBC page returned 403.
- Apple's 2026 agentic Siri. No primary source obtained. The claim that Siri
  was rebuilt on Gemini technology comes from Wikipedia only. Low confidence.
- Microsoft Agent Workspace details come from forum coverage, not Microsoft
  documentation. The learn.microsoft.com and blogs.windows.com URLs 404'd.
- OpenAI's 2026 status, including ChatGPT agent's removal in August 2026.
  openai.com returned 403 throughout.
- UI-TARS-2 scores come from a search summary of arXiv 2509.02544, not a direct
  read.
- Browser Use Cloud's 97% on Online-Mind2Web uses its own agentic judge, not
  the benchmark's standard evaluation. Not comparable to rows below it.
- Whether macOS 26 and 27 added any TCC restriction targeting accessibility
  automation. The Tahoe and Golden Gate release notes are JavaScript-rendered
  and could not be extracted. Treat as unconfirmed rather than absent.
- `LNActionRegistry` and `LNFetchAppShortcuts` as a third-party invocation
  vector. Named in PlugInKit reverse-engineering writeups, never demonstrated.
- Whether Obsidian, Arc, 1Password, Drafts, Fantastical, Slack or Notion expose
  modern App Intents rather than legacy Intents extensions. Not checked.

### Method

Local numbers came from running commands on one Mac on 2026-09-20:
`Info.plist` and `Metadata.appintents` parsing across 140 bundles, timed
invocations of each control layer, `chewbacca context`, `~/.bob/listen.log`,
and `chewie plan check` / `plan run` against crafted plans. The two plans run
were read-only and harmless; they are the first two traces in
`~/.chewie/runs/`.

The `_jarvis` defect was confirmed by AST walk, not by reading. The type
checker and the `app_data` gate bypass were confirmed by execution.
