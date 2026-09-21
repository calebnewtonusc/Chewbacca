import { smoothPath } from "./vendor/smooth";
import { CircleGestureDetector, type CircleProgress } from "./vendor/circle";
import {
  initialPortalState,
  stepPortal,
  ignitionAmount,
  collapseAmount,
} from "./vendor/portal-state";
import { PinchDetector } from "./vendor/pinch";
import { FINGER_TIPS } from "./vendor/skeleton";
import type { Landmark } from "./vendor/types";
import {
  pointingPoint, DepthTracker, MACBOOK_14, PARALLAX_STRENGTH,
  type ScreenModel,
} from "./vendor/pointing";

/**
 * The Doctor Strange portal, on the HUD glass.
 *
 * NO CAMERA IN HERE. This page never calls getUserMedia and never loads
 * MediaPipe. Apple Vision, already running in the host process at 7.56ms a
 * frame, pushes landmarks in through `window.chewbaccaHands`. Everything in
 * this file is arithmetic and canvas.
 *
 * The gesture logic is the vendored OpenVision core, unmodified, so the same
 * code that has 53 tests against it in that repo is what decides when a
 * portal opens here. The alternative, reimplementing the circle detector in
 * Swift, would have meant two implementations and one set of tests.
 */

const CORE = "255, 236, 189";
const SPARK_HOT = "255, 196, 94";
const SPARK_MID = "255, 141, 44";
const SPARK_COLD = "214, 74, 16";

const IGNITE_MS = 520;
const CLOSE_MS = 380;
const MIN_OPEN_MS = 600;

const ease = (t: number) => 1 - Math.pow(1 - t, 3);

interface Spark {
  x: number; y: number; vx: number; vy: number;
  life: number; decay: number; heat: number; width: number; bind: boolean;
}

const IDLE_PROGRESS: CircleProgress = {
  progress: 0, sweep: 0, center: null, radius: 0, roundness: 0,
  completed: false, direction: null, startAngle: null, endAngle: null,
};

const canvas = document.getElementById("c") as HTMLCanvasElement;
const ctx = canvas.getContext("2d")!;

const detector = new CircleGestureDetector();
const pinchL = new PinchDetector();
let state = initialPortalState();
let sparks: Spark[] = [];
let comet: { x: number; y: number }[] = [];
let geom = { cx: 0.5, cy: 0.5, r: 0.1 };
let attract: { cx: number; cy: number; r: number } | null = null;
let spin = 0;
let latest: Landmark[] | null = null;
let latestEyes: { left: { x: number; y: number }; right: { x: number; y: number } } | null = null;
// Kept across frames so the depths drift over seconds instead of jumping
// every frame. This object is the whole fix. See ROUGH_EYE_MM in pointing.ts.
const depths = new DepthTracker();
// How much of the parallax correction to apply. Low on purpose: the ray's
// gain is about 2.4, which pushed the portal off the edges. Tunable live so
// the right value can be found by moving a hand rather than by rebuilding:
//   window.chewbaccaGain(0.4)
let parallaxStrength = PARALLAX_STRENGTH;
// How big the portal is relative to the circle drawn. Well under 1 on
// purpose: the fitted circle is the path the HAND took, and an arm sweeps a
// far wider arc than the hole anybody wants on screen. Tunable live:
//   portal size 0.4
// 1 means the ring is the size of the circle drawn. It was 0.45 while it
// was compensating for a reach compression that has since been removed, and
// a compensation left behind after its cause is just a wrong number.
let sizeScale = 1;
// The circle being drawn, latched once there is enough arc to trust it.
//
// The fit is recomputed every frame from a growing trail, so early on the
// centre and radius move under the hand: "The circle shouldn't rlly move
// once it's started getting made." Past a threshold the geometry is frozen
// and the arc only extends along it, which is also what the reference does
// and what makes the gesture feel like drawing rather than negotiating.
let drawing: { cx: number; cy: number; r: number; a0: number } | null = null;
// The oldest part of the stroke is dropped once, at the latch, not every
// frame after it, or the line would eat itself.
let trimmedAtLatch = false;
// The raw path the pinch has taken this stroke, in screen-normalized space.
// It is drawn as a line from the first frame and BENDS onto the fitted
// circle as the detector starts to recognise one, which is what he asked
// for: "I wanna draw a line, and once it starts detecting a circle that
// line bends into starting the circle."
// Each point keeps where the finger WAS and where it is being DRAWN. The
// drawn position eases toward the fitted circle every frame, so the
// correction is visible as motion: "wtv is outside the circle should move
// to the circle as it is drawn, so you can see what I'm drawing move to
// the perfect circle."
//
// Computing the bend from progress alone could not do this. It produced the
// right shape with no motion in it, because a point's drawn position was a
// pure function of how far round the hand had got rather than of where the
// point was a frame ago.
let stroke: { x: number; y: number; rx: number; ry: number; t: number }[] = [];
// The circle the line is bending toward, smoothed across frames.
//
// Latching alone was not enough: below the latch threshold the target was
// the raw per-frame fit, which moves as the trail grows, so the line was
// chasing something that would not sit still. An average settles it while
// still following a genuine change of intent.
let softFit: { cx: number; cy: number; r: number } | null = null;
// How far from the centre of the screen the hand can reach.
//
// DEFAULT 1, which is no compression at all: the fingertip is exactly where
// the circle is drawn. Anything less moves the ring away from the hand that
// drew it, and after a morning of stacking transforms on top of each other
// he was blunt about it: "Literally just make the tip of the finger be
// where the circle is being drawn like you had it before we added the eye
// stuff."
//
// Below 1 still works and pulls everything toward the middle, but it is
// off by default because being predictable beats covering less screen.
//   portal reach 0.6
let reachScale = 1;
// How wide the hand is drawn, around its own centre.
//
// The landmarks map one to one from the camera frame to the display, so a
// hand filling a third of the frame draws five hundred pixels across and
// the fingers look flung apart. Shrinking toward the hand's own middle
// keeps the hand WHERE it is and only changes how large it reads.
//   portal hand 0.5
let handScale = 0.45;
// How much of the path stays on the glass before a circle is recognised, in
// pixels of travel. Live: `portal trail 420`.
let trailPx = 300;

// WHERE THE CIRCLE STOPS MOVING, and, because they are the same moment, where
// it first appears at all.
//
// "Also the circle is still moving while it is being created." The ring became
// visible at 0.55 of progress and froze at 0.65, so for that tenth it was on
// the glass and still being refitted every frame. Two correct numbers in two
// places, and the gap between them was the bug.
//
// One constant now. The bend gate below derives from it, so the ring cannot
// appear before it is fixed.
//
// 0.65 itself is measured. Against an oval path with arm drift, scored on the
// fit to the whole stroke: latching at 45% is 59px off centre, at 65% 19px,
// at 75% 26px. Worse again past 65 because the last stretch of a hand-drawn
// circle is where the wrist gives out.
// WAY TOO EASILY STARTING A CIRCLE. 0.65 of progress is 209 degrees of arc,
// barely past halfway, and the ring was already on the glass. 0.80 is 257
// degrees: most of the way round, and past the point where a curved flick
// could still turn into something else.
const LATCH_AT = 0.8;
let lastSeen = 0;

// The host pushes frames in here. Declared on window so evaluateJavaScript
// from Swift can reach it.
declare global {
  interface Window {
    chewbaccaHands: (
      pts: Landmark[] | null,
      eyes?: { left: { x: number; y: number }; right: { x: number; y: number } } | null,
    ) => void;
    chewbaccaPortalState: () => string;
    chewbaccaArm: (label: string | null) => void;
    chewbaccaGain: (k?: number) => number;
    chewbaccaSize: (k?: number) => number;
    chewbaccaReach: (k?: number) => number;
    chewbaccaHand: (k?: number) => number;
    chewbaccaTrail: (k?: number) => number;
    webkit?: { messageHandlers?: { portal?: { postMessage: (m: unknown) => void } } };
  }
}
/**
 * ARMED means the portal is a window onto something rather than a void.
 *
 * The interior is then PUNCHED OUT rather than painted. This panel is
 * transparent glass floating over the desktop, so erasing the disc leaves a
 * real hole: whatever window sits behind it is simply visible, live, at zero
 * latency, with no screen capture anywhere in the path. The host positions
 * the target window behind the circle once it knows where the circle landed.
 */
let armed: { label: string } | null = null;
window.chewbaccaGain = (k) => {
  if (typeof k === "number" && isFinite(k)) {
    parallaxStrength = Math.max(0, Math.min(1, k));
  }
  return parallaxStrength;
};
window.chewbaccaSize = (k) => {
  if (typeof k === "number" && isFinite(k)) {
    sizeScale = Math.max(0.05, Math.min(3, k));
  }
  return sizeScale;
};
window.chewbaccaReach = (k) => {
  if (typeof k === "number" && isFinite(k)) {
    reachScale = Math.max(0.05, Math.min(2, k));
  }
  return reachScale;
};
window.chewbaccaHand = (k) => {
  if (typeof k === "number" && isFinite(k)) {
    handScale = Math.max(0.1, Math.min(1, k));
  }
  return handScale;
};
window.chewbaccaTrail = (k) => {
  if (typeof k === "number" && isFinite(k)) {
    trailPx = Math.max(40, Math.min(1200, k));
  }
  return trailPx;
};
window.chewbaccaArm = (label) => {
  armed = label ? { label } : null;
};
window.chewbaccaHands = (pts, eyes) => {
  latest = pts && pts.length === 21 ? pts : null;
  latestEyes = eyes ?? null;
  if (latest) lastSeen = performance.now();
};
// So the host, and a test, can ask what the portal is doing without a screenshot.
window.chewbaccaPortalState = () => state.phase;

function resize() {
  const dpr = Math.min(window.devicePixelRatio || 1, 2);
  canvas.width = window.innerWidth * dpr;
  canvas.height = window.innerHeight * dpr;
  canvas.style.width = `${window.innerWidth}px`;
  canvas.style.height = `${window.innerHeight}px`;
  ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
}
resize();
window.addEventListener("resize", resize);

function frame(now: number) {
  requestAnimationFrame(frame);
  const W = window.innerWidth;
  const H = window.innerHeight;

  // Persistence, not a clear. This is the motion blur that turns discrete
  // frames into the streaks the eye reads as sparks. On the HUD it must also
  // be transparent, so the desktop shows through: `destination-out` erases a
  // fraction of the alpha each frame instead of painting black over it.
  ctx.globalCompositeOperation = "destination-out";
  ctx.fillStyle = "rgba(0, 0, 0, 0.20)";
  ctx.fillRect(0, 0, W, H);

  // A hand that stopped arriving is a hand that left. Without this the last
  // frame's landmarks hang on screen forever if the host stops pushing.
  const lm = now - lastSeen < 300 ? latest : null;

  // ═══════════════════════════════════════════════════════════════════════
  // ONE MAPPING. THE RULE THIS FILE LEARNED THE HARD WAY.
  //
  // A landmark becomes a screen position in exactly one place, `toScreen`,
  // and EVERYTHING downstream works in the space it produces: the gesture
  // detector, the fingertip lights, the ring, the sparks, the hole.
  //
  // WHY. Over one morning the ring and the fingers came apart six separate
  // times, and every cause was the same shape: two paths from a landmark to
  // a pixel, and an adjustment applied to one of them.
  //
  //   the eye ray used a physical screen model while the tips used a mirror
  //   `reach` compressed the position and left the radius alone
  //   the radius had its own scale factor while the centre used mx/my
  //   `reach` reached the DETECTOR and shrank the gesture as well
  //   mapping x by width and y by height stretched the circle to an oval
  //   `hand` shrank the drawn pinch point and not the detected one
  //
  // Each was fixed on its own and the next adjustment broke it again, which
  // is what a wrong shape does. Tuning cannot be safe while a knob has to
  // be remembered in more than one place.
  //
  // So: transform at the door. The detector is fed `toScreen` output, so
  // the circle it fits is already in screen space and the ring is drawn
  // from it directly. A new knob added inside `toScreen` moves the fingers,
  // the gesture and the ring together, because by then there is nothing
  // left that could disagree.
  //
  // THE TEST, for any spatial thing after this: can a new adjustment be
  // added in one place? If it has to be remembered twice, the shape is
  // wrong and no amount of care will hold it.
  // ═══════════════════════════════════════════════════════════════════════
  //
  // `reachScale` pulls everything toward the middle, because the camera sees
  // a wide field and an arm uses all of it, so mapping it one to one runs
  // off both edges. The clamp is the guarantee that a wrong mapping is
  // VISIBLE rather than silent: "I cant see the knob its prob off screen".
  const fit = (v: number) => Math.max(0.02, Math.min(0.98, 0.5 + (v - 0.5) * reachScale));
  // Normalized landmark -> normalized screen. Mirror, reach, clamp. The one
  // door. Kept in normalized units so the detector, which works in them,
  // sees exactly what is drawn.
  const toScreen = (p: { x: number; y: number }, hub?: { x: number; y: number }) => {
    const sx = hub ? hub.x + (p.x - hub.x) * handScale : p.x;
    const sy = hub ? hub.y + (p.y - hub.y) * handScale : p.y;
    return { x: fit(1 - sx), y: fit(sy) };
  };
  // Screen-normalized -> pixels. No decisions here, just units.
  const mx = (nx: number) => nx * W;
  const my = (ny: number) => ny * H;
  const RMIN = 24;
  const RMAX = Math.min(W, H) * 0.42;
  // THE RADIUS IS COMPRESSED TOO. `fit` pulls every POSITION toward the
  // middle by reachScale, so a radius left at full size describes a circle
  // that no longer passes through the compressed fingertip path: the ring
  // was drawn nowhere near the points. "the portal isn't drawing where the
  // finger tips are lmao". A distance has to shrink by the same factor the
  // positions do.
  // Clamp in NORMALIZED units, so the limits survive the mapping instead of
  // being applied to a number that is about to be transformed again.
  const clampRN = (rn: number) => {
    const scaled = rn * sizeScale;
    const minRN = RMIN / Math.min(W, H);
    // "Big circles are ugly and rlly hard to complete."
    //
    // 0.46 is 452px of radius on a 982px-tall display: a ring 904px across,
    // touching top and bottom, and it took a hand circle nearly the width of
    // the camera frame to draw one. At the edge of the frame the landmarks
    // are worst, which is the hard-to-complete half.
    //
    // A soft knee rather than a hard cap. Up to a comfortable size the ring
    // is exactly as big as the circle drawn, and past it the extra is
    // compressed, so a bigger hand circle always makes a bigger ring and
    // never an unusable one. A hard clamp would make every large circle come
    // out identical, which feels broken in a different way.
    const KNEE = 0.24;      // 236px radius, drawn one to one below this
    const maxRN = 0.34;     // 334px radius, approached but never reached
    const capped = scaled <= KNEE
      ? scaled
      : KNEE + (maxRN - KNEE) * (1 - Math.exp(-(scaled - KNEE) / (maxRN - KNEE)));
    return Math.max(minRN, capped);
  };

  // Pull a normalized position toward the middle of the screen.
  //
  // The camera sees a wide field and the hand uses all of it, so at reach 1
  // a comfortable arm sweep runs off both edges of the display. Compressing
  // about the centre keeps the whole reachable area on screen and costs
  // only precision, which is the right trade for something aimed by an arm.
  const px = mx;
  const py = my;

  // EVERY POINT GOES THROUGH THE SAME MAPPING AS THE FINGERTIPS.
  //
  // The radius used to be scaled by its own factor while positions went
  // through mx/my, so the two disagreed and the ring sat further from the
  // centre than the hand that drew it: "the circle is much farter from the
  // center than the hand". A circle drawn from a mapped centre plus an
  // unmapped radius is not the image of the circle the hand traced.
  //
  // Now the arc is built in NORMALIZED space and each point is mapped, so it
  // is the image of the hand's path by construction and cannot drift from
  // it however reach, size or the clamp are set. `rn` is a normalized
  // radius; the jitter is still in pixels because raggedness is a fixed
  // number of pixels whatever the ring's size.
  // A CIRCLE, with ONE radius in pixels.
  //
  // Mapping every point through mx and my stretched it into an oval, because
  // x divides by the width and y by the height and a 1512x982 display is not
  // square. The centre still maps, so the ring follows the hand; only the
  // radius is uniform, so it is round.
  const RPX = Math.min(W, H);
  const arcPath = (
    cn: { x: number; y: number }, rn: number,
    a0: number, a1: number, segs = 96, jitterPx = 0,
  ) => {
    const cx0 = px(cn.x), cy0 = py(cn.y);
    const r = rn * RPX;
    ctx.beginPath();
    for (let i = 0; i <= segs; i++) {
      const a = a0 + ((a1 - a0) * i) / segs;
      const rr = jitterPx ? r + (Math.random() - 0.5) * jitterPx : r;
      const qx = cx0 + Math.cos(a) * rr;
      const qy = cy0 + Math.sin(a) * rr;
      if (i === 0) ctx.moveTo(qx, qy); else ctx.lineTo(qx, qy);
    }
  };
  /** The on-screen radius of a normalized radius, for line widths and glows. */
  // Normalized radius to pixels. ONE radius for both axes, so a circle is
  // a circle: dividing x by width and y by height is what made it an oval.
  const rpxOf = (rn: number) => rn * RPX || 1;
  const disc = (cn: { x: number; y: number }, rn: number) => {
    ctx.beginPath();
    ctx.arc(px(cn.x), py(cn.y), rn * RPX, 0, Math.PI * 2);
  };

  const spawnAt = (
    x: number, y: number, tangentX: number, tangentY: number,
    count: number, speed: number, bind = false,
  ) => {
    for (let i = 0; i < count; i++) {
      const spread = (Math.random() - 0.5) * 0.9;
      const sp = speed * (0.4 + Math.random() * 1.1);
      sparks.push({
        x, y,
        vx: (tangentX + spread * -tangentY) * sp,
        vy: (tangentY + spread * tangentX) * sp,
        life: 1,
        decay: 0.03 + Math.random() * 0.05,
        heat: Math.random(),
        width: 0.35 + Math.random() * 0.85,
        bind,
      });
    }
  };

  // The pinch is the gate and the pen. Same detector the browser build uses.
  const pinch = lm ? pinchL.update(lm, now) : (pinchL.update(null, now), null);
  const pinched = !!(pinch && pinch.isPinched && pinch.center);

  // THE PINCH POINT, STRAIGHT FROM THE CAMERA. No eye, no ray, no depth.
  //
  // An eye-through-fingertip ray was here, built because he described the
  // feel he wanted as "the line from eye to fingertip to the point on screen
  // should be straight". That was a description, taken as a specification,
  // and it needs two depths, each estimated from apparent size, each noisy.
  // Measured with a perfectly still hand and realistic landmark jitter:
  //
  //     ray, no smoothing        x 30px   y 121px
  //     ray, best smoothing      x 30px   y  20px
  //     this, direct mapping     x  6px
  //
  // 121 pixels of wander on a hand that is not moving is exactly what he
  // reported: "it's still in such random places". The parallax the ray
  // corrects is real and constant; the noise it adds is neither, and a
  // constant offset you can learn beats a random one you cannot. He settled
  // it himself: "Eye direction should have nothing to do with it."
  //
  // pointing.ts stays in OpenVision. The maths is right and tested, and it
  // would earn its place with a depth sensor rather than a size estimate.
  // THE CURSOR IS WHERE THE EYE-THROUGH-FINGERTIP RAY LANDS.
  //
  // Not gaze. Where the eyes are LOOKING is never used and is not accurate
  // enough to use; only where they ARE. Caleb, settling it: "Just the rough
  // estimate of the position of the eyes to the finger to the place on
  // screen a straight line has, the angle of the eye is not accurate
  // enough."
  //
  // ROUGH is the operative word and it took three tries to hear. Measuring
  // both depths every frame from apparent size gave 117px of vertical
  // wander on a motionless hand; holding them roughly steady gives 17px.
  // The DepthTracker above is what makes the difference, not the ray.
  //
  // Falls back to the raw pinch point with no face in view, which is wrong
  // by a constant parallax rather than an unknown amount.
  const cursor = (() => {
    if (!pinched || !pinch?.center) return null;
    // AT GAIN 0, DO NOT GO NEAR pointingPoint.
    //
    // Its zero-strength answer is still the fingertip run through a PHYSICAL
    // screen model: camera-space millimetres, a camera offset, a panel size.
    // The fingertip lights are drawn with mx/my, which is a plain mirror of
    // the normalized landmark. Those two mappings have no reason to agree,
    // and they did not: "it's not even close to my finger". The correction
    // being switched off was never the same thing as the correction not
    // running.
    // Through the door, once. The detector then fits a circle in screen
    // space, so the ring is drawn from numbers that are already correct and
    // no second transform can disagree with this one.
    if (parallaxStrength <= 0) return toScreen(pinch.center, lm ? lm[9] : undefined);
    if (latestEyes && lm) {
      const screen: ScreenModel = {
        ...MACBOOK_14,
        widthPx: window.innerWidth,
        heightPx: window.innerHeight,
      };
      const r = pointingPoint(
        { leftEye: latestEyes.left, rightEye: latestEyes.right, hand: lm },
        screen, undefined, undefined, depths, { strength: parallaxStrength },
      );
      if (r) {
        // NO `1 -` HERE. pointingPoint returns real screen pixels in an
        // UNMIRRORED frame, and mx() applies the selfie mirror on the way
        // out. Flipping here as well made two flips, which cancel: the hand
        // on the right drew on the left. One flip, and it lives in mx.
        return { x: r.x / window.innerWidth, y: r.y / window.innerHeight };
      }
    }
    return pinch.center;
  })();

  // THE DETECTOR SEES THE RAW PATH. Compression is a display choice and it
  // must not reach the measurement.
  //
  // `reach` shrinks every movement toward the centre, so at 0.4 a segment
  // that was 0.02 of the frame becomes 0.008, which is close to the
  // detector's minimum segment length. Short segments are dropped because
  // they carry no reliable direction, so the turning angle stopped
  // accumulating and the circle could be started and never finished. He saw
  // it as "circles will start now but its pretty much impossible to finish
  // them".
  //
  // So the gesture is measured in the hand's own full range and only the
  // result is pulled toward the middle of the screen.
  if (cursor) {
    // SMOOTH THE INPUT. Raw landmarks jump a few pixels a frame, and a
    // polyline through them is a jagged wireframe, which is exactly what it
    // looked like. An exponential average on the way in costs one lerp and
    // removes almost all of it.
    const last = stroke[stroke.length - 1];
    const sm = last
      ? { x: last.x + (cursor.x - last.x) * 0.45, y: last.y + (cursor.y - last.y) * 0.45 }
      : cursor;
    stroke.push({ x: sm.x, y: sm.y, rx: sm.x, ry: sm.y, t: now });
    // Hard cap only. The real trim happens after the detector has run,
    // because it depends on this frame's progress and `p` does not exist
    // yet here. Reading it from here threw a ReferenceError every frame,
    // which killed the whole render loop and took the line with it: the
    // symptom was "now I'm not seeing any line", with nothing in the
    // drawing code wrong at all.
    while (stroke.length > 260) stroke.shift();
  } else if (stroke.length) {
    stroke = [];
  }

  let p: CircleProgress;
  if (cursor) {
    // THE DETECTOR WORKS IN A SQUARE SPACE. It used to be fed the raw
    // normalized position, where x is a fraction of 1512 and y a fraction of
    // 982, so a circle on the glass reached it as a 1.54:1 oval. Everything
    // downstream then argued with that: the roundness gate rejected real
    // circles for being too ovular, and the fit landed differently depending
    // on where round the shape the hand started, because it was fitting an
    // ellipse.
    //
    // A 120,960 case sweep is what made it visible, and the giveaway was that
    // a 1.2:1 oval opened a portal MORE often than a perfect circle. It was
    // the oval that was round, in the space that was doing the judging.
    //
    // Both axes are divided by the same number now, so a circle is a circle,
    // and the answer is converted straight back at this one place. See
    // .claude/rules/spatial-one-mapping.md: this file had the rule and broke
    // it anyway, because the detector's own space was never named.
    const raw = detector.push(cursor.x * W / RPX, cursor.y * H / RPX, now);
    p = raw.center
      ? { ...raw, center: { x: raw.center.x * RPX / W, y: raw.center.y * RPX / H } }
      : raw;
  } else {
    detector.reset();
    p = IDLE_PROGRESS;
  }

  // A LINE THAT IS NOT BECOMING A CIRCLE TRAILS OFF. "if it's just a line
  // and not a circle, the end of the line should go after a little bit as
  // your hand moves." Held at full length it piled into a scribble with no
  // shape. Once a circle is being recognised the whole path is kept,
  // because by then the tail is the part already snapped onto the ring and
  // holding it there.
  if (stroke.length) {
    // MEASURED IN PIXELS, NOT IN FRAMES. A frame count is a duration, and a
    // duration is the wrong unit for something whose whole job is to be a
    // length on the glass. Sixteen frames is a stub when the hand is still
    // and a stripe across the display when it is moving, which is exactly
    // what "if I move across the screen quickly it shouldnt be a huge line
    // across the screen" describes. Trimming to a distance instead makes
    // the trail the same size whatever speed it is drawn at.
    //
    // 170px is about a finger's width of travel at arm's length: enough to
    // read as motion behind the fingers, short enough that a fast sweep
    // leaves a comet rather than a scribble. Once a circle is being
    // recognised the whole path is kept, because by then the tail is the
    // part already snapped onto the ring and holding it there.
    // 170px was too short to read as anything: "Lines should still be
    // somewhat curvy as you move your hand around the screen." A hand's
    // circle is roughly 900px around, so 170 is a fifth of a turn and shows
    // as a straight stub however smoothly it is drawn. 300 is a third of a
    // turn, which is visibly an arc, and on a fast sweep across a 1512px
    // display it is still a comet rather than a stripe.
    const circling = p.progress > 0.4 && p.roundness > 0.55;

    // HOW LONG A POINT LIVES DEPENDS ON HOW FAST THE HAND IS GOING.
    //
    // "Time based and speed based." A fixed age is wrong on its own: a fast
    // hand covers a stripe of screen inside it. A fixed length is wrong on
    // its own: a slow hand never travels far enough to trim anything and the
    // line sits there indefinitely. Those were the last two versions, and
    // each fixed the other's failure while reintroducing its own.
    //
    // One rule instead. The lifetime is inversely proportional to speed,
    // bounded at both ends, so the tail stays a readable length whatever the
    // hand is doing:
    //
    //     hand speed     lifetime    tail on screen
    //       80 px/s        650ms          52px
    //      200 px/s        650ms         130px
    //      400 px/s        450ms         180px
    //      800 px/s        225ms         180px
    //     1600 px/s        180ms         288px
    //
    // Between the floor and the ceiling the tail holds at about 180px, which
    // is the point: the line looks the same length whether it is being drawn
    // slowly or thrown across the display. The floor stops a very fast flick
    // vanishing before it is seen, the ceiling stops a still hand keeping a
    // permanent mark.
    // The steady-state tail is LIFE_BASE * LIFE_REF / 1000 px, so 650 * 400
    // is 260px of line on screen at any ordinary drawing speed. It was 180px
    // and that is not enough to steer by: with the ring not appearing until
    // 248 degrees, the line is the only thing showing where the circle is
    // going, and two thirds of it had already faded.
    const LIFE_BASE = 650, LIFE_REF = 400, LIFE_MIN = 180, LIFE_MAX = 800;
    if (!circling && stroke.length > 3) {
      // Speed over the last few samples, in px per second.
      const k = Math.max(0, stroke.length - 6);
      const a = stroke[k], b = stroke[stroke.length - 1];
      const dt = Math.max(1, b.t - a.t);
      const dpx = Math.hypot((b.rx - a.rx) * W, (b.ry - a.ry) * H);
      const speed = (dpx / dt) * 1000;
      const life = Math.max(LIFE_MIN,
        Math.min(LIFE_MAX, LIFE_BASE * (LIFE_REF / Math.max(40, speed))));
      const cutoff = now - life;
      let drop = 0;
      while (drop < stroke.length - 2 && stroke[drop].t < cutoff) drop++;
      if (drop) stroke.splice(0, drop);
    }


    const maxPx = circling ? 4000 : trailPx;
    let run = 0;
    for (let i = stroke.length - 1; i > 0; i--) {
      run += Math.hypot(
        (stroke[i].rx - stroke[i - 1].rx) * W,
        (stroke[i].ry - stroke[i - 1].ry) * H,
      );
      if (run > maxPx) {
        stroke.splice(0, i);
        break;
      }
    }
    // A hard cap on points as well, because a slow hand can otherwise sit
    // inside the distance budget forever and cost a frame to draw.
    while (stroke.length > 260) stroke.shift();
  }

  const prevPhase = state.phase;
  state = stepPortal(
    state,
    {
      now,
      pinched,
      completed: p.completed && !!p.center,
      progress: p.progress,
      center: p.center ? { x: mx(p.center.x), y: my(p.center.y) } : null,
      radius: rpxOf(clampRN(p.radius)),
    },
    { igniteMs: IGNITE_MS, closeMs: CLOSE_MS, minOpenMs: MIN_OPEN_MS },
  );

  const S = state;
  const portalUp = S.phase === "igniting" || S.phase === "open" || S.phase === "closing";

  if (S.phase === "igniting" && prevPhase !== "igniting") {
    if (drawing) {
      geom = { cx: drawing.cx, cy: drawing.cy, r: drawing.r };
    } else if (p.center) {
      // The CENTRE being on screen is not enough: a portal centred near an
      // edge still hangs half of itself off. Inset by its own radius so the
      // whole ring is visible.
      // The radius is in RPX units and the centre is a fraction of each
      // axis, so the inset has to be converted per axis or the ring is held
      // off the left and right edges by the wrong amount.
      const rn = clampRN(p.radius);
      const ix = (rn * RPX) / W, iy = (rn * RPX) / H;
      geom = {
        cx: Math.max(ix, Math.min(1 - ix, p.center.x)),
        cy: Math.max(iy, Math.min(1 - iy, p.center.y)),
        r: p.radius,
      };
    }
    attract = { cx: geom.cx, cy: geom.cy, r: rpxOf(clampRN(geom.r)) };
    // Tell the host where it landed, in CSS points, so it can put the target
    // window behind the hole. Sent once per opening, not per frame.
    window.webkit?.messageHandlers?.portal?.postMessage({
      event: "opened",
      x: mx(geom.cx),
      y: my(geom.cy),
      r: rpxOf(clampRN(geom.r)),
      armed: armed?.label ?? null,
    });
    comet = [];
    const gr = rpxOf(clampRN(geom.r));
    // SPARKS PER UNIT OF RIM, NOT PER RING. A fixed 700 is 0.93 sparks per
    // pixel of circumference at a 120px radius and 0.25 at 452px, so a big
    // portal came out sparse and thin: the other half of "big circles are
    // ugly". Scaling with circumference holds the density constant.
    const rim = 2 * Math.PI * gr;
    const sparkCount = Math.max(260, Math.min(1600, Math.round(rim * 0.93)));
    for (let i = 0; i < sparkCount; i++) {
      const a = Math.random() * Math.PI * 2;
      spawnAt(px(geom.cx) + Math.cos(a) * gr, py(geom.cy) + Math.sin(a) * gr,
        -Math.sin(a), Math.cos(a), 1, 7.0, true);
    }
  }
  if (S.phase !== "drawing" && drawing) drawing = null;
  if (!pinched) { softFit = null; trimmedAtLatch = false; }
  if (portalUp) stroke = [];
  if (!portalUp && prevPhase === "closing") {
    detector.reset(); comet = []; attract = null;
    window.webkit?.messageHandlers?.portal?.postMessage({ event: "closed" });
  }

  // ── Fingertips, faint, so the hand is visible before anything is drawn ──
  if (lm && !portalUp) {
    ctx.globalCompositeOperation = "lighter";
    // THE FINGERTIP POINTS, brought back by name: "bring back the small end
    // of finger points those helped a lot".
    //
    // They were five fat filled circles, cut to a single pixel when that
    // read as a debug overlay sitting on top of the effect. Cutting them
    // that far removed the only thing telling him where the tracker thought
    // his hand was, which is the difference between aiming and guessing.
    // Small and dim, but visible.
    // POINTS, NOT DOTS. "not those dots those are ugly. Im talking the
    // individual small point you had earlier." A filled circle wide enough
    // to read as a shape competes with the effect; a single bright pixel
    // reads as a position and nothing else. The brightness carries the
    // information instead of the size.
    // A POINT OF LIGHT, not a dot and not a pixel.
    //
    // One pixel at 40 percent alpha was invisible: this canvas is
    // transparent glass over a desktop that is usually bright, so a dim mark
    // has nothing to contrast against. "Not seeing the small little light at
    // the tip of my fingers?"
    //
    // The answer is brightness and glow rather than width. A 1.5px core at
    // full alpha with a shadow around it reads as a spark on any background
    // and still does not compete with the ring, which is what made the fat
    // circles ugly.
    // Landmark 9, the middle knuckle, is the hand's anchor: it barely moves
    // as the fingers open and close, so shrinking around it does not make
    // the hand appear to drift.
    const hub = lm[9];
    for (const t of FINGER_TIPS) {
      ctx.shadowBlur = pinched ? 9 : 6;
      ctx.shadowColor = `rgba(${SPARK_MID}, 1)`;
      ctx.fillStyle = `rgba(${SPARK_HOT}, ${pinched ? 1 : 0.8})`;
      ctx.beginPath();
      const q = toScreen(lm[t], hub);
      ctx.arc(mx(q.x), my(q.y), pinched ? 1.7 : 1.4, 0, Math.PI * 2);
      ctx.fill();
    }
    // The pinch point is the pen, so it is the brightest thing on the hand.
    if (pinch?.center) {
      ctx.shadowBlur = 12;
      ctx.shadowColor = `rgba(${CORE}, 1)`;
      ctx.fillStyle = `rgba(${CORE}, 1)`;
      ctx.beginPath();
      const q = toScreen(pinch.center, hub);
      ctx.arc(mx(q.x), my(q.y), 1.9, 0, Math.PI * 2);
      ctx.fill();
    }
    ctx.shadowBlur = 0;

    // HOW MUCH OF THE CIRCLE HAS REGISTERED. "Still really hard to draw
    // circles." Without this the only feedback is the portal appearing or
    // not, so a sweep that registered 40% and one that registered nothing
    // look identical and there is nothing to correct toward. A ring that
    // fills as the turning accumulates makes the gesture learnable.
    if (pinched && pinch?.center) {
      const q = toScreen(pinch.center, hub);
      const cx0 = mx(q.x);
      const cy0 = my(q.y);
      const k = Math.max(0, Math.min(1, p.progress));
      ctx.strokeStyle = `rgba(${SPARK_MID}, 0.25)`;
      ctx.lineWidth = 2;
      ctx.lineCap = "round";
      ctx.beginPath();
      ctx.arc(cx0, cy0, 16, 0, Math.PI * 2);
      ctx.stroke();
      if (k > 0.01) {
        ctx.strokeStyle = `rgba(${CORE}, 0.95)`;
        ctx.lineWidth = 2.8;
        ctx.beginPath();
        ctx.arc(cx0, cy0, 16, -Math.PI / 2, -Math.PI / 2 + k * Math.PI * 2);
        ctx.stroke();
      }
    }
  }

  // ── The line, bending into the circle ────────────────────────────────────
  //
  // From the first pinched frame this is the raw path of the fingertip. As
  // the detector starts recognising a circle, every point slides toward
  // where it would sit on the fitted one, so a scribble straightens into an
  // arc under the hand rather than being replaced by one.
  //
  // `bend` is what does it: 0 draws exactly what was traced, 1 draws the
  // perfect circle, and the ramp between them is the whole effect. The
  // oldest points bend first, because the beginning of the stroke is the
  // part the fit is most confident about and the part the hand has left
  // behind.
  // A PINCH ON ITS OWN IS NOT A GESTURE. While the hand is pinched and
  // nothing circular has been recognised, there is a slow ember or two at
  // the fingers and nothing else: no attractor, no ring, no corona. The
  // effect has to start from almost nothing or there is nowhere for it to
  // build to.
  if (!portalUp && pinched && pinch?.center && p.progress < 0.1) {
    attract = null;
    if (Math.random() < 0.25) {
      const a = Math.random() * Math.PI * 2;
      const q = toScreen(pinch.center, lm ? lm[9] : undefined);
      spawnAt(mx(q.x), my(q.y), Math.cos(a), Math.sin(a), 1, 0.7, false);
    }
  }

  if (!portalUp && pinched && stroke.length > 2) {
    const raw = drawing ?? (p.center ? { cx: p.center.x, cy: p.center.y, r: p.radius } : null);
    if (raw) {
      softFit = softFit
        ? {
            cx: softFit.cx + (raw.cx - softFit.cx) * 0.12,
            cy: softFit.cy + (raw.cy - softFit.cy) * 0.12,
            r: softFit.r + (raw.r - softFit.r) * 0.12,
          }
        : raw;
    }
    const fitC = drawing ?? softFit;
    // EARLY AND FAST. The pull starts at a tenth of a turn and is at full
    // strength by a third, because the correction is most of the effect and
    // arriving late made it look like a separate thing happening afterwards.
    // LATER. Starting at a tenth of a turn meant a curved flick began
    // bending, and a line that is not going to become a circle should not
    // start behaving like one.
    // A THIRD OF A TURN before anything bends. Progress is accumulated
    // turning over the threshold, and a gently curved line collects enough
    // of it to look like the start of a circle without being one. Requiring
    // real curvature first is the difference between a line that bends
    // because it is becoming a circle and one that bends because it moved.
    // TURNING AND ROUNDNESS, BOTH. Progress alone reaches any threshold
    // eventually, however the hand moved, which is why three rounds of
    // raising it did not help: "Still too easily starting the circle."
    // Roundness is the residual of the fit against the spread of the
    // samples, so a path has to have curved AND curved consistently.
    //
    // LATER AGAIN, and this time measured rather than nudged. "Way too
    // easily starting a circle now."
    //
    // Progress is turning over the sweep threshold, and that threshold went
    // from 4.6 rad to 5.4, so the same fraction of progress is now a larger
    // arc than it used to be. But 0.4 of it is still only 124 degrees, and
    // traced against arcs of known sweep the line began bending at:
    //
    //     gate 0.40    starts at 135 deg of arc
    //     gate 0.55    starts at 185 deg
    //     gate 0.62    starts at 210 deg
    //
    // The portal needs 309 degrees to open. Starting the bend at 135 meant
    // more than half the gesture was spent looking committed to something
    // that had not been decided. 0.55 puts the first bend just past halfway
    // and full strength at 0.85, which is 263 degrees, shortly before the
    // ring latches and stops moving.
    // Derived from LATCH_AT, never written separately. The frame the ring
    // appears is the frame it stops moving, and the bend ramps to full over
    // the quarter of progress after that: 201 degrees of arc to 278, with
    // the portal opening at 309.
    // Full strength by 0.95, not 1.05, so the bend actually finishes
    // before the portal opens rather than being cut off mid-way.
    const turned = Math.max(0, Math.min(1, (p.progress - LATCH_AT) / 0.15));
    const round = Math.max(0, Math.min(1, (p.roundness - 0.55) / 0.3));
    const conf = turned * round;
    const k = Math.pow(conf, 0.9);

    // Ease every point toward the circle, a fraction of the remaining
    // distance per frame. This is what makes it MOVE rather than simply be
    // in a different place than it was.
    if (fitC) {
      // PROJECT IN PIXELS, NOT IN NORMALIZED SPACE.
      //
      // x divides by the width and y by the height, so a circle in
      // normalized space is an OVAL on screen. Pulling points onto a
      // normalized circle therefore drew an oval however round the hand's
      // path was, which is the same mistake the ring made earlier and the
      // reason the rule says the correction has to happen in the space it
      // is displayed in.
      // "The line should more quickly curve, currently it slowly moves into
      // a curve." Each point travels this fraction of its remaining distance
      // to the ring per frame, so the number is a speed. At 60fps, frames to
      // cover 90 percent of the way:
      //
      //     conf    0.12+0.30c      0.32+0.46c
      //     0.25    10.6 frames     4.0 frames
      //     0.50     7.3            2.9
      //     1.00     4.2            1.5
      //
      // Ten frames is a sixth of a second of visible drifting, which is what
      // reads as the line moving into a curve rather than becoming one. Four
      // reads as it snapping. The low end matters more than the high end,
      // because that is where the gesture is still being recognised and where
      // the drift was showing.
      const rate = 0.32 + 0.46 * conf;
      const cxp = mx(fitC.cx);
      const cyp = my(fitC.cy);
      const rp = fitC.r * RPX;
      for (const q of stroke) {
        const px0 = mx(q.rx), py0 = my(q.ry);
        const dx = px0 - cxp;
        const dy = py0 - cyp;
        const d = Math.hypot(dx, dy) || 1;
        const tx = cxp + (dx / d) * rp;
        const ty = cyp + (dy / d) * rp;
        const nx = px0 + (tx - px0) * rate;
        const ny = py0 + (ty - py0) * rate;
        // Back to the space the stroke is stored in.
        q.rx = nx / W;
        q.ry = ny / H;
      }
    }

    ctx.globalCompositeOperation = "lighter";
    ctx.lineCap = "round";
    ctx.lineJoin = "round";
    const rBase = fitC ? fitC.r : 0.05;

    // "No line should ever be jagged." The shape is smoothed at the point
    // of drawing, on a copy, so the stored points stay as the hand made them
    // and the circle fit still sees the real gesture. Why two passes and why
    // not more input smoothing is in vendor/smooth.ts, with the numbers.
    // Once per frame. path() draws it twice and the head tangent reads it,
    // and smoothing the same points three times would be three times the
    // cost for the same answer.
    const SP = stroke.length >= 3
      ? smoothPath(stroke.map((q) => ({ x: mx(q.rx), y: my(q.ry) })))
      : null;

    // CURVES, NOT SEGMENTS. Each point becomes a control point and the path
    // runs through the midpoints between them, so corners round off instead
    // of showing as vertices.
    const path = () => {
      ctx.beginPath();
      if (!SP) return;
      const q = SP;
      ctx.moveTo(q[0].x, q[0].y);
      for (let i = 1; i < q.length - 1; i++) {
        ctx.quadraticCurveTo(q[i].x, q[i].y,
          (q[i].x + q[i + 1].x) / 2, (q[i].y + q[i + 1].y) / 2);
      }
      ctx.lineTo(q[q.length - 1].x, q[q.length - 1].y);
    };

    // TWO passes, not three. Three widths of additive stroke on a light
    // background paint the edges twice and leave the middle thin, which
    // reads as a hollow outline rather than a burning line.
    ctx.shadowBlur = 10 + 22 * k;
    ctx.shadowColor = `rgba(${SPARK_MID}, 1)`;
    ctx.strokeStyle = `rgba(${SPARK_MID}, ${0.18 + k * 0.45})`;
    ctx.lineWidth = Math.max(2.5, rBase * RPX * 0.05);
    path(); ctx.stroke();

    ctx.shadowBlur = 6 + 10 * k;
    ctx.strokeStyle = `rgba(${CORE}, ${0.3 + k * 0.6})`;
    ctx.lineWidth = Math.max(1, rBase * RPX * 0.016);
    path(); ctx.stroke();
    ctx.shadowBlur = 0;

    // BINDING IS A PROPORTION, NOT A SWITCH. A spark bound to the circle
    // is pulled onto it; an unbound one drifts and dies where it was born.
    // Making every spark bound the moment a curve is recognised looked like
    // a mode change, and he wanted the opposite: "it should just naturally
    // go into the animation", with "not all the sparks being on the line".
    //
    // So each spark decides at birth, with a probability that rises from
    // nothing to most of them. Early on almost all of them drift; later,
    // most are on the line, and a few stragglers are still loose, which is
    // what stops it reading as a switch being thrown.
    // STARTS AT NOTHING AND CLIMBS. A linear share is already meaningful on
    // the first frame it exists, which reads as the effect switching on.
    // Squared, it is 1 percent at a quarter confidence and 9 percent at a
    // third, so the first sparks all fly off and the line gathers its own
    // slowly. "rmr its sypposed to scale up".
    const boundShare = Math.min(0.4, conf * conf * 0.45);
    const bindMaybe = () => Math.random() < boundShare;

    if (fitC && conf > 0.05) {
      // Sample fewer points early, so the pull shows up as a few strands
      // rather than the whole line lifting at once.
      const step = Math.max(4, Math.round(22 - conf * 18));
      for (let i = 0; i < stroke.length; i += step) {
        const q = stroke[i];
        const gap = Math.hypot(mx(q.rx) - mx(q.x), my(q.ry) - my(q.y));
        if (gap < 6) continue;
        spawnAt(mx(q.rx), my(q.ry),
          (mx(q.x) - mx(q.rx)) / gap, (my(q.y) - my(q.ry)) / gap,
          1, 1.2, bindMaybe());
      }
    }

    // The tangent at the fingertips, which decides which way every spark
    // leaves the line. Taken from two raw samples it is the direction of the
    // last frame's jitter as much as the hand's, so the sparks sprayed at
    // angles the line never went. Off the smoothed path it follows the
    // stroke.
    const head = stroke[stroke.length - 1];
    const prev = stroke[stroke.length - 2] ?? head;
    const hp = SP ? SP[SP.length - 1] : { x: mx(head.rx), y: my(head.ry) };
    const pp = SP && SP.length > 1 ? SP[SP.length - 2] : hp;
    let tx = hp.x - pp.x;
    let ty = hp.y - pp.y;
    const tm = Math.hypot(tx, ty) || 1;
    const n = Math.round(1 + k * 9);
    for (let i = 0; i < n; i++) {
      spawnAt(mx(head.rx), my(head.ry), tx / tm, ty / tm, 1,
        2.2 + k * 3.0, bindMaybe());
    }
    // The attractor only exists once there is something to be attracted to.
    if (fitC && conf > 0.2) attract = { cx: fitC.cx, cy: fitC.cy, r: fitC.r * RPX };
  }

  // ── The latch ────────────────────────────────────────────────────────────
  //
  // The arc used to be drawn here, on the fitted circle. The bending line
  // above replaces it: at full bend the two are the same curve, and drawing
  // both put a perfect arc on top of a hand-drawn one. What survives is the
  // decision about WHERE the circle is, which ignition needs.
  if (S.phase === "drawing" && p.center && p.startAngle !== null && p.progress > 0.16) {
    // TRACK, THEN LATCH. Latching early froze a fit made from a sixth of an
    // arc, whose centre is pulled toward its own samples and whose radius is
    // close to a guess. Below the threshold it follows the hand; past it,
    // it holds, so the target stops moving while it is being closed.
    // MEASURED, not chosen. "if we wait longer we'll get a more accurate
    // read on position and size of the portal", which is true and by more
    // than it looks.
    //
    // On a clean circle with noise the fit is already good at 45 percent and
    // waiting gains about a pixel, so the argument looks weak. On a REAL
    // path it is not close. Against an oval, tilted, drifting as the arm
    // extends, scored against the fit to the whole stroke:
    //
    //     latch at 45%   59px off centre, 32px off size
    //     latch at 65%   19px off,         4px off
    //     latch at 75%   26px,            13px
    //
    // Three times better at 65, and worse again past it because the last
    // stretch of a hand-drawn circle is where the wrist gives out and the
    // path stops describing what was meant.
    if (!drawing || p.progress < LATCH_AT) {
      drawing = { cx: p.center.x, cy: p.center.y, r: p.radius, a0: p.startAngle };
    } else if (!trimmedAtLatch) {
      // "start it not where the circle began, but further along the circle
      // path." The ring is formed by the drawn line bending onto it, so it
      // began wherever the hand began, and by the time a circle is confirmed
      // that is most of a turn behind. Dropping the oldest third at the
      // moment of confirmation starts the ring further round, where the hand
      // actually is, instead of reaching back to the beginning of a gesture
      // that is already over.
      trimmedAtLatch = true;
      if (stroke.length > 12) stroke.splice(0, Math.floor(stroke.length * 0.35));
    }
  }

  // ── The portal ───────────────────────────────────────────────────────────
  if (portalUp) {
    spin += 0.012;
    const ignite = ignitionAmount(S, now, IGNITE_MS);
    const shut = collapseAmount(S, now, CLOSE_MS);
    const e = ease(ignite);
    const cn = { x: geom.cx, y: geom.cy };
    const rn = clampRN(geom.r) * (1 - ease(shut));
    const rpx = rpxOf(rn);
    const vis = e * (1 - shut);
    const age = (now - S.born) / 1000;
    if (S.phase === "open") attract = { cx: cn.x, cy: cn.y, r: rpx };

    if (rpx >= 2) {
      const cx0 = px(cn.x), cy0 = py(cn.y);

      // The interior is DARK: near black to 82%, warmth only at the rim.
      // Painted with source-over so it OCCLUDES the desktop behind the glass,
      // which is what makes it read as a hole rather than a decal.
      if (armed) {
        // A REAL HOLE. destination-out erases the glass, so the window behind
        // this panel shows through: live, no capture, no latency. The edge is
        // left slightly warm so the hole reads as burnt open rather than as
        // a rectangle someone cut out.
        ctx.globalCompositeOperation = "destination-out";
        ctx.globalAlpha = 1;
        disc(cn, rn * 0.985); ctx.fill();
        ctx.globalCompositeOperation = "source-over";
        ctx.globalAlpha = vis * 0.9;
        const lip = ctx.createRadialGradient(cx0, cy0, rpx * 0.88, cx0, cy0, rpx);
        lip.addColorStop(0, "rgba(0,0,0,0)");
        lip.addColorStop(1, "rgba(120, 48, 12, 0.6)");
        ctx.fillStyle = lip;
        disc(cn, rn); ctx.fill();
        ctx.globalAlpha = 1;
      } else {
        ctx.globalCompositeOperation = "source-over";
        ctx.globalAlpha = vis;
        const inner = ctx.createRadialGradient(cx0, cy0, 0, cx0, cy0, rpx);
        inner.addColorStop(0, "rgba(3, 2, 1, 1)");
        inner.addColorStop(0.82, "rgba(10, 5, 2, 1)");
        inner.addColorStop(0.95, "rgba(46, 18, 5, 1)");
        inner.addColorStop(1, "rgba(120, 48, 12, 0.85)");
        ctx.fillStyle = inner;
        disc(cn, rn); ctx.fill();
        ctx.globalAlpha = 1;
      }

      ctx.globalCompositeOperation = "lighter";
      const bloom = ctx.createRadialGradient(cx0, cy0, rpx * 0.9, cx0, cy0, rpx * 1.22);
      bloom.addColorStop(0, `rgba(${SPARK_MID}, ${0.16 * vis})`);
      bloom.addColorStop(1, "rgba(0,0,0,0)");
      ctx.fillStyle = bloom;
      disc(cn, rn * 1.22); ctx.fill();

      if (ignite < 1) {
        ctx.strokeStyle = `rgba(${CORE}, ${(1 - e) * 0.5})`;
        ctx.lineWidth = (1 - e) * 9 + 1;
        arcPath(cn, rn * (1 + e * 0.85), 0, Math.PI * 2); ctx.stroke();
      }

      const flicker = 0.82 + Math.sin(now / 55) * 0.1 + Math.random() * 0.08;
      const heat = 1 + (1 - e) * 1.6 + ease(shut) * 2.6;
      ctx.lineCap = "round";
      ctx.shadowColor = `rgba(${SPARK_MID}, 1)`;

      ctx.shadowBlur = 30 * heat;
      ctx.strokeStyle = `rgba(${SPARK_COLD}, ${0.3 * vis})`;
      ctx.lineWidth = Math.max(4, rpx * 0.1) * heat;
      arcPath(cn, rn, 0, Math.PI * 2, 120, 4); ctx.stroke();

      ctx.shadowBlur = 24 * heat;
      ctx.strokeStyle = `rgba(${SPARK_MID}, ${0.5 * vis})`;
      ctx.lineWidth = Math.max(2.5, rpx * 0.045) * heat;
      arcPath(cn, rn, 0, Math.PI * 2, 120, 2.5); ctx.stroke();

      ctx.shadowBlur = 18 * heat;
      ctx.strokeStyle = `rgba(${SPARK_HOT}, ${0.7 * vis})`;
      ctx.lineWidth = Math.max(1.6, rpx * 0.018) * heat;
      arcPath(cn, rn, 0, Math.PI * 2, 120, 1.2); ctx.stroke();

      ctx.shadowBlur = 10;
      ctx.strokeStyle = `rgba(${CORE}, ${Math.min(1, flicker * vis * 0.8)})`;
      ctx.lineWidth = Math.max(1, rpx * 0.007);
      arcPath(cn, rn, 0, Math.PI * 2, 120); ctx.stroke();
      ctx.shadowBlur = 0;

      const emit = S.phase === "igniting" ? 90 : S.phase === "closing" ? 55 : age < 0.6 ? 46 : 26;
      const inward = S.phase === "closing" ? -1 : 1;
      for (let i = 0; i < emit; i++) {
        const a = Math.random() * Math.PI * 2 + spin;
        spawnAt(cx0 + Math.cos(a) * rpx, cy0 + Math.sin(a) * rpx,
          -Math.sin(a) * inward, Math.cos(a) * inward, 1,
          S.phase === "igniting" ? 6.5 : 4.2, true);
      }
    }
  }

  // ── Sparks ───────────────────────────────────────────────────────────────
  ctx.globalCompositeOperation = "lighter";
  const alive: Spark[] = [];
  for (const sp of sparks) {
    const c = Math.cos(0.035), sn = Math.sin(0.035);
    const nvx = sp.vx * c - sp.vy * sn;
    const nvy = sp.vx * sn + sp.vy * c;
    sp.vx = nvx * 0.975;
    sp.vy = nvy * 0.975 + 0.055;

    if (sp.bind && attract) {
      const Cx = mx(attract.cx), Cy = my(attract.cy), R = attract.r || 1;
      const dx = sp.x - Cx, dy = sp.y - Cy;
      const dl = Math.hypot(dx, dy) || 1;
      const nx = dx / dl, ny = dy / dl;
      // Push out hard inside the rim, fly free once past it, spin throughout.
      // Inside plus tangential is the catherine wheel; outside with no brake
      // is the corona. Anything that slows a spark shortens its streak.
      if (dl < R) { sp.vx += nx * (R - dl) * 0.06; sp.vy += ny * (R - dl) * 0.06; }
      else { sp.vx += nx * 0.22 * sp.life; sp.vy += ny * 0.22 * sp.life; }
      const tang = 1.9 * sp.life;
      sp.vx += -ny * tang; sp.vy += nx * tang;
      sp.vx *= 0.992; sp.vy *= 0.992;
    }

    sp.x += sp.vx; sp.y += sp.vy;
    sp.life -= sp.decay;
    if (sp.life <= 0) continue;
    alive.push(sp);

    const speed = Math.hypot(sp.vx, sp.vy) || 1;
    // A ROUND CAP ON A SHORT STROKE IS A DOT. lineCap "round" adds a
    // half-disc at each end, so a 2px wide streak 2px long draws an exact
    // circle, and every slow spark rendered as a blob. Butt caps, a floor on
    // the length well above the width, and thinner strokes.
    const len = Math.max(5, Math.min(20, speed * 2.4));
    const h = sp.heat * sp.life;
    const col = h > 0.62 ? CORE : h > 0.3 ? SPARK_HOT : h > 0.14 ? SPARK_MID : SPARK_COLD;
    ctx.strokeStyle = `rgba(${col}, ${Math.min(1, sp.life * 1.5)})`;
    ctx.lineWidth = sp.width * (0.25 + sp.life * 0.6);
    ctx.lineCap = "butt";
    ctx.beginPath();
    ctx.moveTo(sp.x, sp.y);
    ctx.lineTo(sp.x - (sp.vx / speed) * len, sp.y - (sp.vy / speed) * len);
    ctx.stroke();
  }
  sparks = alive.length > 1400 ? alive.slice(-1400) : alive;
}
requestAnimationFrame(frame);
