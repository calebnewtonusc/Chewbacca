# The spatial layer: hands, voice, and the glass

Caleb, 2026-09-21: *"I wanna be doctor strange iron man mixed tgt"* and
*"I'm tryna open a doctor strange portal and control chewbacca w hand gestures
and voice together. We're inventing a new operating system lol"*

This file is the plan for that, written so it can be picked up cold.

---

## Read this before writing any code

**Caleb already built most of the visual half, in September, and it is public.**
`github.com/calebnewtonusc/OpenVision`, live at `openvision.vercel.app`, last
touched 2026-09-04. He sent the link twice on 9/20 and 9/21 and both times this
kit built past it and started from scratch in Swift instead. That is the tenth
instance of the same failure this session, recorded in
[[../memory/feedback_built_but_never_fires]]: a capability exists, is correct,
is tested, and never fires.

What is in it, verified by reading the repo on 2026-09-21:

| Piece | Path | What it is |
| --- | --- | --- |
| Hand tracking | `lib/openvision/react/useHandTracking.ts` | MediaPipe Hands, 21 landmarks, 30fps+, as a hook |
| Gesture classifier | `lib/openvision/core/gestures.ts` | 44 lines, zero deps. fist, open, point, peace, thumbs_up, pinky, pinch. Has a 151-line test file |
| Pinch detector | `lib/openvision/core/pinch.ts` | `PinchDetector` class, 154 lines, 130 lines of tests |
| Eye tracking | `lib/openvision/react/useGazeTracking.ts` | WebGazer, 9-point calibration, Kalman-filtered |
| Dwell to click | `lib/openvision/react/useDwellClick.ts` | Stare 1.2s at any `data-gaze-target` element |
| Glass panels | `lib/openvision/react/SpatialPanel.tsx` | Draggable, gaze focus ring, already gaze-tagged |
| **Portal** | `components/HandsWeb.tsx:528-630` | Pulsing radial void, fingertip orbital trails, negative-gravity particles, per-finger glow |
| Air keyboard | `components/toolkit/AirKeyboard.tsx` | Type without touching anything |
| Glass hands | `components/toolkit/GlassHands.tsx` | |

`core/` is **zero-React and zero-dependency** by design, and its README says so:
*"When the toolkit matures into a standalone npm package, the `core/` folder
ports cleanly."* That is the seam this plan uses.

The portal is ~100 lines of Canvas 2D. No shader, no WebGL, no library. It reads
`hands[].lm` (21 landmarks each) and draws. **Anything that can produce 21
landmarks can drive it unchanged.**

---

## What Chewbacca has that OpenVision does not

Built the night of 2026-09-20 to 21, on branch `feat/hand-control`:

| Piece | Path | Measured |
| --- | --- | --- |
| Native hand tracking | `hud/Sources/BobHUDKit/HandTracker.swift` | Apple Vision, 380 lines. **7.56ms one hand, 9.96ms two, 4-6% of one core sustained on M4 Pro** |
| Two gestures wired to real actions | same | palm-to-dismiss, point-to-deixis |
| The event the voice layer already eats | `OutboundEvent.region` | point-deixis emits it |
| Voice with his whole brain | `bin/hud-agent.md`, `bin/superassistant` | lean+brain+doctrine+index, ~53,700 tokens, 6-10s |
| Narration in waves | `bin/hud-agent.md` | the Bash `description` field becomes the pill text |
| A transparent always-on-top window | `hud/` | already shipping |

So: **Chewbacca has the input and the intelligence. OpenVision has the output.**
Neither has the other. The remaining work is a seam, not a capability.

---

## The architecture

```
Apple Vision (Swift)          the OpenVision portal (Canvas 2D)
HandTracker.swift      ──►    WKWebView inside the HUD overlay
7.56ms, 4-6% of a core        ~100 lines, already written
      │                                  ▲
      │ 21 landmarks per hand, 30fps     │ window.chewbaccaHands(frame)
      └──────────────────────────────────┘

            gesture ──► OutboundEvent ──► hud-listen (voice, has his brain)
```

Three reasons this shape and not the others:

1. **Do not port the portal to Swift.** It is Canvas 2D with `shadowBlur` and
   `globalAlpha`. Reimplementing it in Core Graphics or Metal is a week for a
   pixel-identical result.
2. **Do not run MediaPipe in the HUD.** Apple Vision is already measured at
   7.56ms and needs no CDN, no WASM, no network. MediaPipe loads from a CDN,
   which the HUD should never depend on.
3. **The landmark format is the same.** MediaPipe and Apple Vision both give 21
   points per hand. The index order differs and needs one mapping table, written
   once. `lib/openvision/core/skeleton.ts` has `HAND_CONNECTIONS` for the
   MediaPipe order; Apple's `VNHumanHandPoseObservation.JointName` is the other
   side of that table.

---

## Build order

Each step is shippable on its own and each one is visible.

### 1. The landmark bridge (half a day)

Write `hud/Sources/BobHUDKit/LandmarkBridge.swift`: take
`VNHumanHandPoseObservation`, emit MediaPipe-ordered `[{x, y, z}]` as JSON,
push it into a `WKWebView` via `evaluateJavaScript("window.chewbaccaHands(...)")`.

The mapping table is the only real content. Apple gives named joints
(`.thumbTip`, `.indexMCP`); MediaPipe gives indices 0-20. Write the table with a
test that asserts a known pose maps to known indices, because getting it wrong
produces a hand that looks almost right, which is the worst failure mode to
debug by eye.

**Gate:** `classifyGesture` from OpenVision, running unmodified on
Apple-sourced landmarks, returns `point` when Caleb points. If that passes, 44
lines of his gesture logic and 151 lines of its tests come across for free.

### 2. Portal in the HUD (one day)

Extract `HandsWeb.tsx:528-630` into a standalone HTML file with no React and no
Next.js: a canvas, the particle loop, and `window.chewbaccaHands` as the entry
point. Load it in a transparent `WKWebView` layered over the HUD.

**Gate:** he waves at the screen and the portal follows his hands, with the HUD
still clickable through it. Transparent-window hit testing is the part that
will fight back: the WKWebView must not eat mouse events meant for what is
underneath.

### 3. Gesture to action (half a day)

`OutboundEvent.region` already exists and `hud-listen` already consumes it. Wire
the classifier's output to it, and hold the line already written in
[BACKLOG.md](../BACKLOG.md) item 10: **two gestures, not seven.** Palm dismisses.
Point says "this one" and hands the region to the voice agent.

A seven-gesture vocabulary is a demo. Two gestures nobody has to remember is a
feature.

### 4. Voice and hands in one turn (half a day)

The thing he actually asked for. He points at a window, says "what is this", and
the voice agent answers about that region, narrating in waves while it works.

Every piece for this exists today and none have been run together.

**Gate:** that exact sentence, start to finish, on video.

---

## What is deliberately not in this plan

**Eye tracking.** OpenVision has WebGazer with 9-point calibration and it works
in a browser. In an always-on desktop overlay, a 5-clicks-per-dot calibration
that decays as you move your head is a worse pointer than the mouse. Revisit
only if the hands land and it still feels like something is missing.

**The air keyboard.** Typing without touching anything is a party trick and he
has a keyboard four inches away. Same for a seven-gesture vocabulary, which step
3 already rules out, and for rebuilding the portal natively, which the
architecture section rules out. All three are written down here because each one
will get proposed again by somebody who has not read those sections.

---

## The honest read

The research verdict already in [BACKLOG.md](../BACKLOG.md) item 21 was **"a
demo, not a feature,"** and Gavin reached that independently. That verdict still
stands and this plan does not overturn it.

What changed is the cost. When the estimate was "build hand tracking, build a
particle system, build a gesture classifier," a demo was not worth it. Now the
tracker is measured and shipping, the classifier and the portal are written and
tested in his own repo, and what is left is a mapping table and a WKWebView.
**A two-day demo that makes his friends say woahhhh is worth two days.** A
two-week one was not.

Ship it as its own target with a README that says it is a demo, exactly as item
21 specifies. Do not let it become a dependency of anything in the daily path.

---

## Picking this up cold

```
git checkout feat/hand-control          # HandTracker.swift, HandDemo target
gh repo clone calebnewtonusc/OpenVision # the portal and the classifier
```

Read, in this order: `hud/Sources/BobHUDKit/HandTracker.swift`, then
OpenVision's `lib/openvision/README.md`, then `components/HandsWeb.tsx` lines
528-630.

Then start at step 1. Do not start by writing anything that already exists in
either repo, which is the whole reason this file is here.

Built with Chewbacca
