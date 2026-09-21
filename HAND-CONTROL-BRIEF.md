Build hand control into the HUD, Swift only, in this worktree. Do not touch anything outside hud/.

The research is done and sits in BACKLOG.md item 10. Start there rather than re-deriving it.

STACK, measured on this exact M4 Pro: Apple's Vision framework, not MediaPipe.
VNDetectHumanHandPoseRequest measured 7.56ms per frame with one hand, 9.96ms with two,
and 4-6% of one core sustained, because it dispatches to the Neural Engine. MediaPipe
1.0.1 aborts the process creating a HandLandmarker on macOS arm64 and has no native
desktop path, so it is not an option.

LICENSES: all four repos Caleb linked are unusable. Two declare no license at all, one
is GPL-3.0 and requires an NVIDIA GPU, and barehands is AGPL-3.0. This repo is MIT.
Do not vendor any of them. Read barehands for its threshold tuning only.

BUILD EXACTLY TWO GESTURES.

1. Palm to dismiss. An open palm to the camera kills the panel, stops a run in flight,
   and mutes the mic. DoubleTap.swift already implements that exact semantic on the
   globe key, so this is its hands-free twin rather than a replacement.

2. Point to establish deixis. This is the valuable one and it is half built already:
   OutboundEvent.region(CGRect) exists in the HUD and its own comment says "this is what
   makes 'what is this' mean something." A finger pointed at a screen region while the
   person says "what is this" should emit that event, so it composes with the voice
   layer that already ships.

THREE HARD CONSTRAINTS, from the fatigue literature, not negotiable:
- Design for the forearm resting on the desk. Consumed Endurance (CHI 2014) shows arm
  elevation causes gorilla arm, not gesturing. Kinect, Leap Motion and Pixel 4 Motion
  Sense all died on this.
- Require three consecutive frames before firing. Apple's own sample-code gate, costs
  23ms. Vision sometimes reports feet as hands.
- Every gesture stays redundant with a keyboard shortcut that remains the primary path.
  Gestures have no discoverability and nothing in the literature solves that.

Ship the Doctor Strange overlay as a SEPARATE demo target with a README saying it is a
demo. It films beautifully and will be used once. Gavin, independently: "it better not
be for something retarded like Doctor Strange LARP, it has to be for something useful."

Commit to feat/hand-control only, and put the message before the paths:
  git commit -m "msg" -- path/one path/two

Start now. Do not ask questions you can answer by reading hud/Sources.
