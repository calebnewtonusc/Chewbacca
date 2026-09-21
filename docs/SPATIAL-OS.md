# The spatial layer: hands, voice, and the glass

Caleb, 2026-09-21: *"I wanna be doctor strange iron man mixed tgt"* and
*"I'm tryna open a portal and control chewbacca w hand gestures and voice
together. We're inventing a new operating system lol"*

Built overnight 2026-09-20 to 21. **This file was a plan and is now a status
report**, because a plan left lying around after the work is done is worse
than no document: the next person builds what it describes instead of what
is missing.

---

## Try it in one minute

```
cd hud && ./scripts/bundle-portal.sh    # builds Portal.app
portal open dashboard                    # or: notes, calendar, chewbacca
```

Pinch thumb to index, sweep a circle in the air. The portal burns open where
you drew it, with that window behind the hole. Pinch again to close. Esc
quits. `portal targets` lists what it knows; add a line to
`~/.chewbacca/portal-targets.tsv` and a new target is openable immediately.

The browser version, for hacking on the visuals without a Swift build, is
`calebnewtonusc/OpenVision` route `/strange`: `npm run dev`.

---

## What is built

| Piece | Where | State |
| --- | --- | --- |
| Circle gesture, by total turning angle | `OpenVision lib/openvision/core/circle.ts` | Works. 13 tests, including realistic landmark noise |
| Least-squares circle fit (Kasa) | same | Works. Centre lands 0.0005 off on a 216 degree arc, versus 0.0656 for a centroid |
| Open/close state machine | `core/portal-state.ts` | Works. Pure reducer, 7 tests |
| Eye-through-fingertip pointing | `core/pointing.ts` | Works. 20 tests, collinearity asserted in 3D |
| Apple Vision hand tracking | `hud/Sources/BobHUDKit/HandTracker.swift` | Works. 7.56ms one hand, 4-6% of one core on an M4 Pro |
| Landmark bridge, and pupils | `hud/Sources/BobHUDKit/LandmarkBridge.swift` | Works. 8 tests |
| The portal on the HUD glass | `hud/Sources/Portal/` | Works. Transparent WKWebView, click-through |
| Window placement behind the hole | `hud/Sources/Portal/WindowPlacer.swift` | Works. Needs Accessibility, prompts for it |
| `portal` CLI and named targets | `bin/portal` | Works |
| Voice knows about portals | `bin/hud-agent.md` | Works |

### The architecture, and why it is not the obvious one

```
Apple Vision  ->  LandmarkBridge  ->  WKWebView  ->  canvas
7.56ms/frame      y flip, pupils     no camera      draws
```

**Not MediaPipe in a webview.** That is the quick build: point a WKWebView at
the browser version and let it open the camera. It is a second camera stream
beside the one the process already runs, a WASM model off a CDN at every
launch, and several times the CPU.

**The gesture logic stays in the web layer**, which looks backwards until you
count implementations. The circle detector, the fit, the mirror mapping, the
pointing ray and the state reducer have 73 tests in OpenVision. A Swift
rewrite means two implementations of subtle geometry and tests for one. The
core is vendored into `hud/Sources/Portal/Resources/portal/vendor/` at a
recorded commit, with `sync.sh` to update it, because an app bundle must not
resolve a dependency at launch.

**An armed portal punches a real hole** with `destination-out`, and the
target window is moved behind it. Nothing is captured and nothing is
composited, so it is live with no latency by construction. ScreenCaptureKit
would cost a frame of latency, a second encode of pixels already on screen, a
recording indicator in the menu bar, and a picture of a window rather than
the window.

---

## What is NOT built

1. **The voice answering before he draws.** He wants to say *"Can I open a
   portal to some dashboards"* and hear *"sure go ahead doctor strange"*, and
   only then draw. Today `portal open` arms silently and the reply is
   whatever the agent says about the command. The arming and the spoken line
   need to be one turn.
2. **The dashboard INSIDE the ring.** Today the window sits BEHIND a hole, so
   it is framed rather than contained: it does not move or scale with the
   portal, and drawing a small circle crops the window rather than shrinking
   it. His words were "the dashboard pops up in the middle of the portal".
3. **The browser build still uses the camera-relative cursor.** `pointing.ts`
   is only wired into the HUD, because MediaPipe there has no face landmarks
   without adding FaceMesh.
4. **Palm-dismiss and point-deixis are off.** They work and they were noisy:
   *"it's j randomly picking up me pointing my finger and it isn't useful"*.
   Still in `HandTracker`, still on the menu toggle, `hud.handControl` false.

---

## What this cost, and the lessons worth inheriting

**One screenshot beat an hour of reading the code.** Four visual bugs shipped
at once with 47 tests green: a squashed ellipse, a flat orange wash, a neon
hairline instead of a band of fire, and sparks pinned to the rim. All four
were obvious in a picture and invisible in source.

**Tests of correctness say nothing about plausibility.** The circle fit was
mathematically right and visually absurd: a small flick genuinely does lie on
a circle bigger than the screen. `circle.noise.test.ts` and the
ill-conditioned-fit tests are the pattern, and they assert what must be true
ON SCREEN.

**Perfect synthetic input hides real failures.** The detector fired 0 times
out of 20 on a circle with realistic landmark jitter while passing every test
built from a compass, because noise flips the sign of a turn and the sweep
restarted on every flip.

**Do not make an agent infer.** Asked for "a portal to dashboard" the voice
agent spent 68 seconds cloning repos, because the name resolved to nothing.
A lookup table fixed it. An agent given a puzzle will always find something
expensive to do.

**Check his own repos first.** OpenVision already had hand tracking, a
gesture classifier and a portal, built in September. It was linked twice
before anyone opened it.

Built with Chewbacca
