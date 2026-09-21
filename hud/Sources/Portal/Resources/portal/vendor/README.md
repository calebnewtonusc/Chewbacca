# Vendored from OpenVision

These files are copied, unmodified, from
[calebnewtonusc/OpenVision](https://github.com/calebnewtonusc/OpenVision)
at commit `211c90a`, path `lib/openvision/core/`.

They are vendored rather than imported because the HUD ships as a signed Mac
app bundle and must not resolve a dependency, hit a registry, or reach a CDN
at launch. A copy with a commit written next to it is honest about what it
is; a git submodule in an app bundle is not.

They carry their own tests, in that repo: 53 of them covering the circle
detector, the least-squares fit, the portal state machine, the mirror
mapping, and behaviour under realistic landmark noise. Do not edit these
files here. Fix them upstream and re-run `sync.sh`.

| File | What it is |
| --- | --- |
| `circle.ts` | Circle gesture by total turning angle, plus the Kasa fit and `mirrorAngle` |
| `portal-state.ts` | The open/close state machine as a pure reducer |
| `pinch.ts` | Pinch detection with hysteresis |
| `gestures.ts` | Single-frame pose classification |
| `skeleton.ts` | `HAND_CONNECTIONS`, `FINGER_TIPS` |
| `pointing.ts` | Eye-through-fingertip ray to the screen plane, and the depth estimates it needs |
| `types.ts` | `Landmark`, `HandData`, `GestureName` |
