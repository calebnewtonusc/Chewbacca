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

## The compiled skill: the artifact everything hangs on

A web skill is a small durable file, committed to the repo, holding an ordered
list of steps. Each step carries three things:

- **A semantic selector**, never a coordinate or a CSS path. Role plus
  accessible name (`button "Compose"`), resolved at replay time. Coordinates
  break on the first layout change; roles and names survive a redesign.
- **The action**, with its parameters (`fill`, value from a task argument).
- **A verification assertion**: the observable state that must hold after the
  step (`a compose window is open, addressed to {recipient}`). This is the part
  the field skips, and it is the whole thing. The assertion is what lets a
  replay run unattended without lying that it worked, what detects drift
  automatically, and what makes the repair surgical.

Verification is the hard part, not clicking. Everyone builds the clicker. The
assertion is what makes the click trustworthy, and it is the same discipline the
rest of this kit already runs on: verify the edit landed, and a preview is only
worth reading if the preview is exactly what happens.

## Three modes over one artifact

- **Compile.** First time you ask for a task, the reactive engine (the four
  layers below) navigates it once, and instead of only doing the task it emits
  the skill: every step's semantic selector, action, and assertion, plus a
  parameter list so `star every email from {sender}` generalises.
- **Replay.** Every run after, execute the artifact directly with no model in
  the loop. Resolve each selector, act, check the assertion, move on. Machine
  speed, deterministic, free.
- **Heal.** When an assertion fails, the site changed. The model wakes for that
  one step, re-navigates it from the surrounding context, patches the selector
  in the artifact, and replay continues. You pay for a repair, not a
  re-interpretation, and only for the step that actually broke.

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
roles and names rather than pixels, and it is consulted before perception so the
reactive engine starts warm instead of blind. It persists, it commits, and via
"push to main so everyone gets it" every machine inherits it. Most agents are
amnesiac per-site; this one gets permanently better at every site anyone in your
circle has ever driven. Personalised or AB-tested UIs are exactly why the atlas
stores semantics, never coordinates.

---

## The reactive engine (the compiler and the repair)

The four layers below are not the headline any more. They are what powers a
compile and a heal. The researched decisions still stand.

### Connect: drive the real Chrome through the OpenClaw relay

Chrome 136+ refuses remote debugging on the default user-data-dir, so launching
your normal Chrome with `--remote-debugging-port` and attaching with
`connectOverCDP` no longer works on your real profile. The OpenClaw extension
bridges CDP through native messaging with no debug port, so the block does not
apply, nothing on localhost is fingerprintable, and `navigator.webdriver` stays
false because we never pass `--enable-automation`. The `browser-use` skill
documents this relay end to end. Do not use `launchPersistentContext` on the
live profile: Chrome locks an open profile dir. If raw CDP is ever needed, use
`--remote-debugging-pipe` plus a patched client (Patchright or rebrowser-patches)
that avoids the per-frame `Runtime.enable` auto-call, the CDP-detection leak V8
largely closed in May 2025.

Give the agent its **own window** on the session, not the tab you are reading.
Chrome runs many windows on one profile, all sharing your cookies and logins, so
the agent can work in its window while you keep working in yours, and you can
watch it. That is the answer to "my own chrome window" and to the contention
problem at the same time.

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
The `isTrusted = false` problem is JS-synthesized events, which we do not use, so
no OS-level workaround is needed for trust. Detection is behavioral now, so the
work is motion: generate trajectories with **WindMouse** or **ghost-cursor**
(Bezier paths, Fitts's-law point density, overshoot and correction), and emit the
full pointer sequence (`pointerover, pointerenter, pointermove, pointerdown,
mousedown, pointerup, mouseup, click`), because a missing `pointer*` prefix is a
common reason a handler ignores an otherwise valid click. Keyboard driving
(`Tab`, confirm the focus ring, `Enter`) is the fallback. Reserve macOS `CGEvent`
for the narrow case where a site detects the CDP session itself, a connection
problem rather than an input one. Type with realistic hold and flight times.

**Credential floor, non-negotiable.** Never route a password through the agent or
the transcript. `web` refuses password fields the way `chrome-js` already does,
with no override. The right shape is out-of-band keychain enrolment with a
separate privileged inject-to-key-events step, so no layer above holds the
plaintext (see `31Carlton7/realm`).

### Decide: the reactive loop

Only the compile and heal paths run this. Send only the latest observation, keep
a rolling summary that updates rather than re-summarizes, `cache_control` on the
system prompt and tool schemas, one line of "what I see and why" before each
action, stuck detection, and hard step and cost caps.

---

## Build sequence

1. **`web` CLI: the reactive engine.** Connect through the relay into an
   agent-owned window, perceive into a backendNodeId map, expose `click`,
   `fill`, `read`, `navigate`. This is the compiler and it is useful alone.
2. **The skill artifact and replay.** Define the step format (semantic selector,
   action, assertion, parameters), and a replay executor that runs it with no
   model. This is the moment the project stops being a browser-use clone.
3. **Verification and heal.** The assertion checker, and the single-step repair
   that patches a drifted selector and continues.
4. **Learn by demonstration.** Record a real event stream, segment it, infer
   selectors and assertions, parameterise it into a skill.
5. **The atlas.** Per-site semantic memory, consulted before perception,
   committed and shared.
6. **Human-motion input and vision escalation.** WindMouse or ghost-cursor and
   the full pointer sequence; set-of-marks when the DOM is opaque.
7. **Voice integration.** Drop `web` on PATH. `hud-listen` spawns a headless
   Claude turn with Bash and PATH and strips MCP, so a CLI is the integration.
   "Star every email from Caleb" then runs a compiled skill in a couple of
   seconds, and only compiles the first time.

---

## Where this loses, so it can be killed early

- If your sites churn their DOM faster than you re-run tasks, repair cost beats
  interpret cost and the whole bet is wrong. The falsifier to watch: repairs per
  skill per week. Personal workflows hit stable sites repeatedly, so the read is
  that it wins, but that number is the test, not the hope.
- The atlas breaks on personalised or AB-tested UIs unless every stored selector
  is semantic. A single coordinate in the atlas is a latent bug.
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
