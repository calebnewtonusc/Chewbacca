---
paths:
  - "**/*.swift"
  - "**/portal/**/*.{ts,js,html}"
  - "**/*.{metal,glsl}"
  - "**/*{hand,gaze,landmark,tracker,overlay,canvas}*.{swift,ts,js,py}"
---

<!-- This frontmatter is what defers the rule. Without it the file is
     always-on however its first paragraph reads, which is what
     `tests/run.sh` checks and what this file failed on arrival. -->

# Spatial input: one mapping, applied once, at the door

Loads when the work touches hand tracking, gaze, a HUD overlay, a canvas
driven by sensor input, or anything where a physical position becomes a
pixel. Written 2026-09-21, after the portal's ring and the user's fingers
came apart six separate times in one morning.

## The rule

**A sensor coordinate becomes a screen coordinate in exactly one function,
and everything downstream works in the space that function produces.**

Downstream means everything: the gesture detector, the cursor, the hit
testing, the drawing, the physics. Not "the renderer". Everything.

## Why, with the receipts

Every one of these was a separate session, a separate diagnosis, and a
separate fix, and they are all the same bug:

| Symptom the user reported | Cause |
| --- | --- |
| "not even close to my finger" | the cursor used a physical screen model, the fingertips used a mirror |
| "the circle is much farter from the center than the hand" | the centre was mapped, the radius had its own scale |
| "impossible to finish" a circle | a display compression reached the DETECTOR and shrank the gesture |
| "way too big", an oval | x divided by width, y by height, so a circle stretched |
| "the pinch isn't on the circle any more" | a hand-size knob moved the drawn point and not the detected one |
| the ring built away from the hand | the detector's angles were in landmark space, the arc drawn in mirrored space |

Six fixes, each correct, each undone by the next adjustment. That is what a
wrong shape does: it converts every future change into a new alignment bug.

## What it buys

When the detector is fed mapped coordinates, corrections **disappear**
rather than needing maintenance. The portal had a `mirrorAngle` helper and a
negated sweep, both existing only to undo a mirror applied elsewhere. Once
the detector saw screen space, both were deleted. Nothing to keep in sync is
better than something kept in sync carefully.

## The test, before you ship a spatial feature

**Can a new adjustment be added in one place?**

Add an imaginary knob: a zoom, a rotation, a per-user calibration. Count how
many places have to change. One is right. Two means the next person, or you
in an hour, will change one and not the other, and no amount of care
prevents it.

## How to build it

1. One function, `toScreen(sensorPoint) -> screenPoint`. Mirror, scale,
   offset, clamp, calibration: all of it, in there.
2. Call it **once per input**, at the boundary. Never again further down.
3. Feed the gesture layer its output, not the raw sensor.
4. Keep the unit conversion (normalized to pixels) separate and decision
   free. If the pixel step contains an `if`, it is not a unit conversion.
5. Anything that survives as a "correction for" something else is evidence
   the door is in the wrong place. Move the door and delete the correction.

## The measurement discipline that goes with it

Sensor input is noisy and the noise is amplified by every division. Before
adding a correction that needs an estimated quantity, measure how far the
result moves with a **still** hand and realistic jitter. On this machine:

- direct mapping: 6px of wander
- the same point through an eye-parallax ray with per-frame depth: 117px

Predictable beats correct when a person is aiming. A constant offset is
learned in a minute without noticing; noise cannot be learned at all.

See `second-brain/memory/feedback_one_mapping_for_spatial_input.md`.
