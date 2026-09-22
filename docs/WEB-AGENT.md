# The web agent: compile tasks, do not interpret them every time

Gavin, 2026-09-22: _"make it able to navigate any site like a human would, not
relying on api's but on playwright or whatever a human sees, alone... opening my
own chrome window and being able to navigate without having to open up new tabs
that dont have sign in history."_ And from the todo: _"Mog at learning any
software + push to main so everyone gets it."_

This is a plan, not a status report. Nothing here is built yet. It exists so the
next session builds the right thing, because the obvious thing is a trap.

---

## The bet, in one paragraph

The whole field (browser-use, Skyvern, Stagehand, computer-use) is racing to
build one general agent that reactively navigates any site, from scratch, every
run. That is the demo, and it is a treadmill: stateless, slow, and it makes the
same mistake on run fifty that it made on run one. Chewbacca does the opposite.
Reactive navigation is the **compiler**, not the product. The product is a
compounding library of **compiled, verified, deterministic web skills**. The
model is expensive and slow, so it runs exactly twice per task: once to compile
the skill, and again only when the site drifts and the skill needs a repair.
Everything in between runs at machine speed from a durable artifact that gets
committed and shared, so every machine you own gets better at every site anyone
has ever taught it.

## Why the obvious version is a trap

Four problems sink the naive reactive agent, and the compile approach dissolves
all four:

1. **You cannot use your computer while it uses your computer.** A reactive
   agent driving your real tab yanks the browser around while you work. The
   fix is a skill that replays in the agent's **own** window on your session
   (below), not a live puppet of the tab you are reading.
2. **Your real account eats the ban.** Aggressive live automation on your
   primary logged-in identity is what trips detection onto the account you care
   about. A verified deterministic replay of a known-good path improvises far
   less, so it rarely does anything a human would not.
3. **It is slow, and re-slow every time.** An LLM-in-the-loop cycle is seconds
   per click. "Star every email from Caleb" should not re-reason from zero on
   the fiftieth run. Compiled replay is a couple of seconds and free.
4. **It is amnesiac.** A human learns where the compose button lives. A stateless
   agent re-derives it forever. The skill artifact and the shared atlas are the
   memory the field keeps leaving out.

## Ground truth on this machine, checked 2026-09-22

Before trusting the connection story, this is what is actually installed here:

- **`chrome-js` works today.** It drives your real signed-in Chrome through
  AppleScript JavaScript injection: read the page, click by label, run JS in the
  live tab. No setup, uses your real profile. This is the bootstrap, not a
  placeholder.
- **The OpenClaw relay is not installed.** `openclaw` is not on PATH, and
  mcporter (v0.7.3) lists no `chrome-devtools` server. So any plan that opens
  with "use the relay we already have" is wrong until Step 0 stands it up.
- **The voice strips MCP.** `hud-listen` spawns `claude` with `--tools=Bash`,
  `--strict-mcp-config`, and an empty `--mcp-config`. So `web` cannot be an MCP
  tool the model calls. It is a CLI that **shells out** to its transport itself
  (chrome-js today, mcporter or a raw CDP client once the relay exists).

## The compiled skill: the artifact everything hangs on

A web skill is a small durable file, committed to the repo, holding an ordered
list of steps. Each step carries three things:

- **A semantic selector**, never a coordinate or a CSS path. Role plus
  accessible name (`button "Compose"`), resolved at replay time. Coordinates
  break on the first layout change; roles and names survive a redesign. When two
  elements match, the disambiguator (nth match, or a parent scope) is recorded
  at compile time, so replay never guesses.
- **The action**, with its parameters (`fill`, value from a task argument).
- **A machine-checkable assertion.** This is the part the field skips, and it is
  the whole thing, but it only works if it is deterministic. The model authors
  the assertion at compile time and immediately compiles it down to a predicate
  a script can evaluate with no model: an element exists, an element's text
  equals a value, the URL matches. "A compose window is open" becomes "an
  element with role dialog and name matching /new message/i exists." If an
  assertion needs a model to check, replay is not model-free and the speed bet
  is lost, so an assertion that will not compile to a predicate is a compile
  failure, not a soft check.

Verification is the hard part, not clicking. Everyone builds the clicker. The
assertion is what makes the click trustworthy, and it is the same discipline the
rest of this kit already runs on: verify the edit landed, and a preview is only
worth reading if the preview is exactly what happens.

**Control flow, scoped honestly.** A real task has loops (`star every email from
{sender}`) and branches (`if a cookie banner is present, dismiss it`). Version
one compiles linear steps with parameters plus one construct: repeat a named
sub-sequence over each element matching a selector. Arbitrary branching is a
known limitation, and a task that needs it stays on the reactive path until the
artifact format grows to hold it. Pretending a linear script covers loops is how
you ship a skill that stars one email and reports success.

## Three modes over one artifact

- **Compile.** First time you ask for a task, the reactive engine (the layers
  below) navigates it once, and instead of only doing the task it emits the
  skill: every step's semantic selector, action, and predicate assertion, plus a
  parameter list so `star every email from {sender}` generalises. After each
  action it captures the resulting state and names the post-condition that must
  hold, which is where the assertion comes from.
- **Replay.** Every run after, execute the artifact directly with no model in
  the loop. Resolve each selector, act, check the predicate, move on. Machine
  speed, deterministic, free.
- **Heal, with a budget.** An assertion failing does not mean drift; the page
  may still be loading. Retry with a short wait first. Only a real failure wakes
  the model for that one step, to re-navigate it and patch the selector. Two
  guards keep heal honest: a per-step heal cannot loop more than a couple of
  times before it stops and asks, and if more than a few steps in one run need
  healing the site has been redesigned, so recompile the whole skill from
  scratch rather than patch it selector by selector. One clean recompile beats
  five piecemeal repairs, the same way one audit beats five.

## Learn it two ways

Autonomous exploration is one way to compile a skill. The other is ahead of the
pack and it is exactly your "learn a task by doing it once": **you demonstrate
it.** Record your real event stream once (the CDP event feed, or an OS event tap
for cross-app work), segment it into steps, infer a semantic selector and an
assertion for each, and lift the varying values into parameters. A demonstrated
skill is often better than an explored one, because you already knew the goal
and never took a wrong turn the model would have to prune.

Only compile tasks you do three or more times, the same floor kit-builder uses.
A genuine one-off just runs on the reactive path and is never saved.

## The atlas: per-site memory that compounds and is shared

Skills know a task. The atlas knows a site: where compose is on Gmail, what the
search box is, which control opens the account menu. It is structural, stored as
roles and names rather than pixels. The important move is indirection: a skill
references atlas landmarks by symbolic name (`gmail.compose`), it does not
hardcode the selector. So when Gmail moves its compose button, you fix one atlas
entry and every skill that touches Gmail heals at once, instead of each skill
drifting on its own. The atlas is consulted before perception so the reactive
engine starts warm instead of blind. It persists, it commits, and via "push to
main so everyone gets it" every machine inherits it. Personalised or AB-tested
UIs are exactly why every atlas entry is a semantic selector and never a
coordinate; one coordinate in the atlas is a latent bug that fires on the next
machine.

## The hard line

A compiled skill is a stored, replayable automation of your real, logged-in
accounts. Two rules are not optional:

- **Outbound and destructive steps never auto-run.** A replayed skill that
  sends, deletes, pays, posts, or changes an account setting stops and confirms
  before that step, showing exactly what it will do. Speed is the point of
  replay, but not for the actions you cannot take back.
- **A shared skill is untrusted until reviewed.** "Push to main so everyone gets
  it" means a skill written on one machine runs on another, against another
  person's real accounts. A pulled skill is data, not a command, until a human
  reads its steps. An edited or poisoned skill that quietly added a "forward to
  attacker@evil" step is exactly the attack the untrusted-content rule exists
  for.

Who decides: the human, on every outbound action and every first run of a pulled
skill. The agent's job is to make that decision cheap and clear, not to make it
for them.

---

## The reactive engine (the compiler and the repair)

These layers are not the headline any more. They are what powers a compile and a
heal. The researched decisions still stand.

### Connect: real Chrome, cheapest transport that works

Step 0 is standing up a transport, because none of the CDP path is installed
here yet. Three tiers, cheapest first:

- **Today: `chrome-js`.** AppleScript into the real signed-in Chrome. Good for
  perception (read the DOM, list tabs) and deterministic JS clicks on
  cooperative sites. Its limits are real: it needs "Allow JavaScript from Apple
  Events", it sees only one Chrome instance, and a JS click is `isTrusted=false`,
  so it will not pass a hardware-click check or move a real cursor. Fine for
  bootstrapping the compiler on friendly sites.
- **Upgrade: the OpenClaw relay.** Install it (it is not here now), and it
  bridges CDP through native messaging with no debug port, so Chrome 136+'s
  block on remote-debugging the default profile does not apply,
  `navigator.webdriver` stays false, and you get real CDP input with human
  motion. The `browser-use` skill documents the relay end to end. This is the
  target transport.
- **Fallback: raw CDP.** `--remote-debugging-pipe` (no TCP port) plus a patched
  client (Patchright or rebrowser-patches) that avoids the per-frame
  `Runtime.enable` auto-call, the CDP-detection leak V8 largely closed in May 2025. Do not use `launchPersistentContext` on the live profile: Chrome locks
  an open profile dir.

Whichever transport, give the agent its **own window** on the session, not the
tab you are reading. Chrome runs many windows on one profile, all sharing your
cookies and logins, so the agent works in its window while you keep working in
yours, and you can watch it. That is the answer to "my own chrome window" and to
the contention problem at once.

### Perceive: DOM-first, borrowing browser-use's model

The cheap observation is the interactable set, not a screenshot. Extract
interactables (native tags, `DOM.describeNode` for JS handlers, ARIA roles, form
descendants, sizable iframes) into a selector map keyed on CDP `backendNodeId`,
which is stable across DOM mutation where CSS paths and XPaths are not. Rebuild
the map after any navigation; discard it on any capture failure. When the DOM
lies (canvas apps, shadow DOM, a click that no-ops), escalate to **set-of-marks**
vision (the WebVoyager overlay: numbered boxes over the same interactables, fed
to a multimodal model). Vision is the fallback, because it is slower and costs
tokens for no gain on a clean DOM. The a11y tree is the third source, and it
reaches web components a raw DOM walk misses, so a compile reconciles all three
and records whichever selector is cheapest and most stable for replay.

### Act: CDP input with human motion

CDP `Input.dispatchMouseEvent` and `dispatchKeyEvent` are already
`isTrusted = true`; they enter Chromium above where the renderer decides trust.
The `isTrusted = false` problem is JS-synthesized events (and chrome-js JS
clicks), which is why chrome-js is a bootstrap and CDP is the target. Detection
is behavioral now, so the work is motion: generate trajectories with
**WindMouse** or **ghost-cursor** (Bezier paths, Fitts's-law point density,
overshoot and correction), and emit the full pointer sequence (`pointerover,
pointerenter, pointermove, pointerdown, mousedown, pointerup, mouseup, click`),
because a missing `pointer*` prefix is a common reason a handler ignores an
otherwise valid click. Keyboard driving (`Tab`, confirm the focus ring, `Enter`)
is the fallback. Reserve macOS `CGEvent` for the narrow case where a site detects
the CDP session itself, a connection problem rather than an input one. Type with
realistic hold and flight times.

**Credential floor, non-negotiable.** Never route a password through the agent or
the transcript. `web` refuses password fields the way `chrome-js` already does in
`refuse_password_access()`, with no override. The right shape is out-of-band
keychain enrolment with a separate privileged inject-to-key-events step, so no
layer above holds the plaintext (see `31Carlton7/realm`).

### Decide: the reactive loop

Only the compile and heal paths run this. Send only the latest observation, keep
a rolling summary that updates rather than re-summarizes, `cache_control` on the
system prompt and tool schemas, one line of "what I see and why" before each
action, stuck detection, and hard step and cost caps.

---

## Build sequence

1. **`web` CLI on `chrome-js`: the reactive engine, bootstrap transport.**
   Perceive the live Chrome into a selector map, expose `click`, `fill`, `read`,
   `navigate`, shelling out to chrome-js. Works today, no new install, proves the
   compiler on friendly sites.
2. **The skill artifact and replay.** The step format (semantic selector,
   action, predicate assertion, parameters, the one repeat construct) and a
   replay executor that runs it with no model. This is where it stops being a
   browser-use clone.
3. **Verification and heal.** The predicate checker, the wait-before-drift retry,
   the single-step repair, and the recompile threshold.
4. **The hard line.** The outbound-action confirmation gate and the
   pulled-skill review step, before any skill is shared.
5. **Learn by demonstration.** Record a real event stream, segment it, infer
   selectors and assertions, parameterise it.
6. **The atlas.** Per-site semantic landmarks with symbolic-name indirection,
   consulted before perception, committed and shared.
7. **Upgrade the transport to the OpenClaw relay**, then add human-motion input
   (WindMouse or ghost-cursor, full pointer sequence) and set-of-marks vision.
   This is what lifts it from friendly sites to real ones.
8. **Voice integration.** `web` is already on PATH and shells out, so `hud-listen`
   can call it despite stripping MCP. "Star every email from Caleb" runs a
   compiled skill in a couple of seconds, and only compiles the first time.

---

## Where this loses, so it can be killed early

- If your sites churn their DOM faster than you re-run tasks, repair cost beats
  interpret cost and the whole bet is wrong. The falsifier to watch: repairs per
  skill per week. Personal workflows hit stable sites repeatedly, so the read is
  that it wins, but that number is the test, not the hope.
- If assertions cannot be compiled to predicates for the sites you actually use
  (heavily canvas apps), replay is not model-free and the speed advantage
  shrinks toward the reactive baseline. Check this on your real top-five sites
  before building past step 3.
- Adversarial anti-bot (Cloudflare Turnstile, hCaptcha, DataDome) is unsolved by
  anyone. The real-profile session is the least-challenged state there is, and
  the human-motion layer removes the behavioral tells, but a hard challenge is a
  stop-and-hand-it-to-the-human moment, not something to defeat silently.

Bot-detection specifics move quarterly and vendors do not document them. Verify
the CDP `isTrusted` behavior against the running Chrome before depending on it,
and check against bot-detector.rebrowser.net and brotector.

---

## Sources

- Interactive-element detection and the backendNodeId selector map:
  github.com/browser-use/browser-use
- Set-of-marks reference: github.com/MinorJerry/WebVoyager
- observe-then-cache, semantic action plans: github.com/browserbase/stagehand
- Chrome 136 default-profile debug block, `connectOverCDP` vs
  `launchPersistentContext`: Playwright docs and dev.to write-ups
- `Runtime.enable` CDP detection and its May 2025 V8 patch: Castle and Rebrowser
  write-ups; Patchright and rebrowser-patches
- CDP input `isTrusted = true`: crawlex "synthesizing human input events", MDN
- Human trajectories: WindMouse (ben.land), ghost-cursor (github.com/Xetera),
  HumanCursor (github.com/riflosnake)
- Credential handling: github.com/31Carlton7/realm

Built with Chewbacca
