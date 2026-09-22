# The web agent: drive the browser you are already signed into

Gavin, 2026-09-22: _"make it able to navigate any site like a human would, not
relying on api's but on playwright or whatever a human sees, alone... opening my
own chrome window and being able to navigate without having to open up new tabs
that dont have sign in history."_

This is a plan, not a status report. Nothing here is built yet. It exists so the
next session builds the `web` CLI from researched decisions instead of guessing
at four layers that each have a known best answer.

The goal: the hyper assistant navigates real sites the way you do, in your own
Chrome, with your logins already there, by seeing what a human sees and moving a
cursor the way a human moves it. Not through APIs. Not in a clean throwaway
browser.

---

## The one principle everything else follows from

Do not launch an automated browser. Attach to the one you are already signed
into.

A fresh Playwright or Puppeteer context has no cookies, no SSO, no device trust,
and ships `navigator.webdriver = true`. That is precisely the "new tab with no
sign-in history" problem, self-inflicted. The moment you drive your real profile
instead, most bot detection never fires, because you are a real, cookied,
trusted human session. The advantage is not a trick: it is your actual browser,
with your actual cookies and your actual logins.

Everything below is how to attach to it, see it, and act in it without throwing
that advantage away.

---

## Layer 1: connect to the real Chrome

**Decision: use the OpenClaw extension relay we already have.** It is the
cleanest path and it sidesteps the trap below.

Chrome 136+ (mid-2025) refuses remote debugging on the _default_ user-data-dir
as a security fix. So the obvious move, launch your normal Chrome with
`--remote-debugging-port=9222` and attach with Playwright `connectOverCDP`, no
longer works against your real profile. The OpenClaw extension never opens a
debug port. It bridges CDP through native messaging, so the 136 block does not
apply, no localhost debug port exists to fingerprint, and `navigator.webdriver`
stays false because we never pass `--enable-automation`. The `browser-use` skill
already documents this relay end to end.

Do not use `launchPersistentContext` against the live profile dir. Chrome holds
a lock on an open profile, so that path needs the browser closed and drifts from
the live session anyway.

If we ever need raw CDP without the relay, the fallback is
`--remote-debugging-pipe` (no TCP port) plus a patched client (Patchright or
rebrowser-patches) that avoids the per-frame `Runtime.enable` auto-call. That
`Runtime.enable` side-effect leak was the decisive CDP-detection signal from
2022 to 2025; V8 largely patched it in May 2025, but a raw driver can still
re-introduce it. The relay avoids the whole question.

## Layer 2: perceive (see it like a human)

**Decision: DOM-first, with vision on demand, borrowing the perception model
from `browser-use`.**

The cheap default observation is the interactable-element set, not a screenshot.
`browser-use` extracts interactables with a layered heuristic (native tags,
CDP `DOM.describeNode` for JS click-handlers, ARIA roles, form descendants,
sizable iframes) and assigns each a small integer index into a selector map
**keyed on CDP `backendNodeId`**. The model emits `click(index=N)`. The reason
to copy this exactly: `backendNodeId` is stable across DOM mutation, so the map
survives re-renders in a way CSS paths and XPaths do not. Rebuild the map after
any navigation; never try to persist indices across a re-render (browser-use
discards the whole map on any capture failure, and so should we).

When the DOM lies (canvas-rendered UI, a click that no-ops, a visually obvious
control the tree does not expose), escalate to vision with **set-of-marks**: the
WebVoyager approach, inject JS that draws numbered bounding boxes over the same
interactables and hand the screenshot plus the `index -> {backendNodeId, bbox,
role, text}` map to a multimodal model. Vision is the fallback, not the default,
because it is slower and costs more tokens for no gain on a well-behaved DOM.

For repeated flows, adopt Stagehand's observe-then-cache: cache the resolved
action plan for a known path so the common case is deterministic and cheap.

## Layer 3: act (move the mouse like a human)

**Decision: CDP synthetic input driven by human motion, with a keyboard
fallback, and OS-level clicking only as a last resort.**

The premise that we need macOS `CGEvent` to defeat trust checks is wrong. CDP
`Input.dispatchMouseEvent` and `Input.dispatchKeyEvent` produce events with
`isTrusted = true`; they enter Chromium upstream of where the renderer decides
trust. The `isTrusted = false` problem belongs to JS-synthesized events
(`element.dispatchEvent(new MouseEvent(...))`, Playwright's `dispatchEvent`),
which we will not use. CDP input clears hardware-click and trust checks with no
OS-level workaround, which frees Layer 3 to focus entirely on motion.

Detection has moved to the time domain: dwell, approach velocity, event
ordering. So the real work is human _motion_, not human-looking events:

- Generate trajectories with **WindMouse** (cursor as a mass under a constant
  pull to target plus decaying random "wind"; simplest to port) or
  **ghost-cursor** (Bezier paths, Fitts's-law point density, automatic
  overshoot-and-correct, hesitation). Naive constant-speed linear interpolation
  is the tell both libraries exist to kill.
- Emit the full Pointer Events sequence, not a bare click:
  `pointerover -> pointerenter -> pointermove -> pointerdown -> mousedown ->
pointerup -> mouseup -> click`. A missing `pointer*` prefix is a common reason
  a handler ignores an otherwise valid click. This is the concrete fix for the
  "clicks that do not click" problem the `browser-use` skill warns about.
- Keyboard driving is the fallback when pointer handlers are stubborn: `Tab` /
  `Shift+Tab` to focus, confirm the focus ring, `Enter`.
- Reserve macOS `CGEvent` (`CGEventCreateMouseEvent` / `CGEventPost` to
  `kCGHIDEventTap`) for the narrow case where a site detects the CDP _session
  itself_, which is a connection problem, not an input one. This is the "own
  cursor" the todo asks for, but it is the last resort, not the default.

Typing: model per-key hold time (~50-150ms) and inter-key flight (~80-200ms)
with variance and the occasional backspace, because Akamai-class detectors track
exactly those two distributions.

**Credential floor, non-negotiable.** Never route a password through the agent
or the transcript. `web` refuses to read or fill password fields, the way
`chrome-js` already does, with no flag to override. The correct shape for a
credential is the realm pattern (31Carlton7/realm): the human enrolls the secret
in the OS keychain out of band, and a separate privileged step injects it
straight into key events so no layer above ever holds the plaintext.

## Layer 4: decide (the loop)

This part is close to solved, and your own iOS-agent note already describes the
winning shape. Reuse it verbatim:

- Send only the **latest** observation each step. Compress prior steps into
  one-line summaries and _update_ a rolling summary rather than re-summarizing,
  so intent survives compaction. Images never accumulate in the message list.
  This alone was a 3-4x speedup in the reference work.
- `cache_control` on the system prompt and the tool schemas (max 4 breakpoints),
  which is roughly 75% off input cost on a multi-step task.
- Force a one-line "what I see and why I am about to do this" before every
  action, and log it.
- Stuck detection: same screen or same action three times injects a hint, then
  fails gracefully. Hard step cap and cost cap.

---

## Build sequence

1. **`web` CLI, connect + perceive primitives.** Attach through the OpenClaw
   relay, list pages, snapshot the interactable set into a backendNodeId-keyed
   map, and expose `click`, `fill`, `read`, `navigate`. Ship this and it is
   already useful.
2. **Set-of-marks vision escalation.** The WebVoyager JS overlay, invoked only
   when a click no-ops or the DOM is opaque.
3. **The loop.** Latest-observation-only, rolling summary, caching, stuck
   detection, caps.
4. **Human-motion input.** WindMouse or ghost-cursor trajectories plus the full
   pointer sequence, with keyboard fallback.
5. **Voice integration.** Drop `web` on PATH. `hud-listen` spawns a headless
   Claude Code turn with Bash and whatever is on PATH, and it strips MCP config,
   so a CLI is the integration, not an MCP server. The voice then says "open my
   inbox and star anything from Caleb" and it runs.

---

## What is genuinely unsolved, stated plainly

Reliability on adversarial sites (Cloudflare Turnstile, hCaptcha, DataDome) is
not solved by anyone. The honest stance is that on your real, cookied profile
you rarely trip these, because you are already a trusted session, and that is the
entire reason for Layer 1. Where it still breaks: behavioral tells (instant
clicks, zero mouse motion, superhuman timing), which Layer 3 exists to remove;
a leaked CDP signal, which Layer 1 exists to avoid; or bad exit-IP reputation,
which we do not control. DataDome and PerimeterX lean on behavior harder than
Cloudflare does, so Layer 3 matters most against them.

Bot-detection specifics move quarterly and vendors do not document them. Treat
the vendor behavior here as directional, and verify the CDP `isTrusted` behavior
against the running Chrome before depending on it, because it is an
implementation detail that has shifted before. Check against
bot-detector.rebrowser.net and brotector.

---

## Sources

- browser-use interactive-element detection and the backendNodeId selector map:
  github.com/browser-use/browser-use
- Set-of-marks reference: github.com/MinorJerry/WebVoyager
- observe-then-cache: github.com/browserbase/stagehand
- Chrome 136 default-profile debug block, `connectOverCDP` vs
  `launchPersistentContext`: Playwright docs and dev.to write-ups
- `Runtime.enable` CDP detection and its May 2025 V8 patch: Castle and Rebrowser
  write-ups; Patchright and rebrowser-patches
- CDP input `isTrusted = true`: crawlex "synthesizing human input events", MDN
- Human trajectories: WindMouse (ben.land), ghost-cursor (github.com/Xetera),
  HumanCursor (github.com/riflosnake)
- Credential handling: github.com/31Carlton7/realm

Built with Chewbacca
