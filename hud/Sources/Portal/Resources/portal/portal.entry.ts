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
  progress: 0, sweep: 0, center: null, radius: 0,
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
    const maxRN = 0.46;
    return Math.max(minRN, Math.min(maxRN, scaled));
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
  const rpxOf = (_cn: { x: number; y: number }, rn: number) => rn * RPX || 1;
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
  let p: CircleProgress;
  if (cursor) {
    p = detector.push(cursor.x, cursor.y, now);
  } else {
    detector.reset();
    p = IDLE_PROGRESS;
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
      radius: rpxOf(p.center, clampRN(p.radius)),
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
      const rn = clampRN(p.radius);
      geom = {
        cx: Math.max(rn, Math.min(1 - rn, p.center.x)),
        cy: Math.max(rn, Math.min(1 - rn, p.center.y)),
        r: p.radius,
      };
    }
    attract = { cx: geom.cx, cy: geom.cy, r: rpxOf({ x: geom.cx, y: geom.cy }, clampRN(geom.r)) };
    // Tell the host where it landed, in CSS points, so it can put the target
    // window behind the hole. Sent once per opening, not per frame.
    window.webkit?.messageHandlers?.portal?.postMessage({
      event: "opened",
      x: mx(geom.cx),
      y: my(geom.cy),
      r: rpxOf({ x: geom.cx, y: geom.cy }, clampRN(geom.r)),
      armed: armed?.label ?? null,
    });
    comet = [];
    const gr = rpxOf({ x: geom.cx, y: geom.cy }, clampRN(geom.r));
    for (let i = 0; i < 700; i++) {
      const a = Math.random() * Math.PI * 2;
      spawnAt(px(geom.cx) + Math.cos(a) * gr, py(geom.cy) + Math.sin(a) * gr,
        -Math.sin(a), Math.cos(a), 1, 7.0, true);
    }
  }
  if (S.phase !== "drawing" && drawing) drawing = null;
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

  // ── The ring building along its own circumference ───────────────────────
  if (S.phase === "drawing" && p.center && p.startAngle !== null && p.progress > 0.16) {
    // LATCH. The first frame past the threshold decides where the circle is;
    // every frame after that only extends the arc along it. Re-fitting as
    // the trail grows is mathematically better and feels worse, because the
    // thing being aimed at keeps moving.
    // TRACK, THEN LATCH. Latching at 16 percent froze a fit made from a
    // sixth of an arc, whose centre is pulled toward the samples and whose
    // radius is a guess, so the ring stopped moving and stopped matching.
    // Below the threshold it follows the hand; past it, it holds.
    const LATCH_AT = 0.45;
    if (!drawing || p.progress < LATCH_AT) {
      drawing = { cx: p.center.x, cy: p.center.y, r: p.radius, a0: p.startAngle };
    }
    const cn = { x: drawing.cx, y: drawing.cy };
    // Normalized radius is the source of truth, because arcPath maps every
    // point. `rpx` exists only for line widths and glow radii, which are
    // genuinely screen quantities.
    const rn = clampRN(drawing.r);
    const rpx = rpxOf(cn, rn);
    // Normalized angles do not survive the mirror: phi = PI - theta, and the
    // map negates the angle, so the sweep flips with it.
    // NO mirrorAngle, and no negated sweep. Both existed because the
    // detector used to work in landmark space while the ring was drawn in
    // mirrored screen space. The detector is fed toScreen output now, so
    // its angles ARE screen angles and flipping them again would send the
    // arc backwards, which is the same bug from the other direction.
    //
    // This is what one door buys: the correction disappears rather than
    // needing to be maintained.
    const swept = Math.max(-Math.PI * 2, Math.min(Math.PI * 2, p.sweep));
    const a0 = drawing.a0;
    const a1 = a0 + swept;
    const k = Math.pow(p.progress, 1.6);

    ctx.globalCompositeOperation = "lighter";
    ctx.lineCap = "round";

    ctx.shadowBlur = 8 + 30 * k;
    ctx.shadowColor = `rgba(${SPARK_MID}, 1)`;
    ctx.strokeStyle = `rgba(${SPARK_COLD}, ${0.03 + k * 0.18})`;
    ctx.lineWidth = Math.max(1.5, rpx * (0.02 + k * 0.06));
    arcPath(cn, rn, a0, a1, 96, 3); ctx.stroke();

    ctx.strokeStyle = `rgba(${SPARK_MID}, ${0.05 + k * 0.3})`;
    ctx.lineWidth = Math.max(1.2, rpx * (0.01 + k * 0.03));
    arcPath(cn, rn, a0, a1, 96, 1.5); ctx.stroke();

    ctx.shadowBlur = 6 + 16 * k;
    ctx.strokeStyle = `rgba(${CORE}, ${0.04 + k * 0.36})`;
    ctx.lineWidth = Math.max(0.8, rpx * (0.004 + k * 0.011));
    arcPath(cn, rn, a0, a1); ctx.stroke();

    const headSpan = Math.sign(swept) * Math.min(Math.abs(swept), 0.55);
    ctx.shadowBlur = 14 + 50 * k;
    ctx.strokeStyle = `rgba(${CORE}, ${0.2 + k * 0.35})`;
    ctx.lineWidth = Math.max(1.4, rpx * (0.012 + k * 0.042));
    arcPath(cn, rn, a1 - headSpan, a1, 24); ctx.stroke();
    ctx.shadowBlur = 0;

    const hx = px(cn.x) + Math.cos(a1) * rpx;
    const hy = py(cn.y) + Math.sin(a1) * rpx;
    const dir = Math.sign(swept) || 1;
    const tx = -Math.sin(a1) * dir;
    const ty = Math.cos(a1) * dir;
    const prev = comet[comet.length - 1];
    const speedPx = prev ? Math.hypot(hx - prev.x, hy - prev.y) : 0;
    comet.push({ x: hx, y: hy });
    if (comet.length > 40) comet.shift();
    spawnAt(hx, hy, tx, ty,
      Math.round((1 + k * 9) * (1 + Math.min(0.8, speedPx * 0.03))), 2.2 + k * 3.0, true);
    spawnAt(hx, hy, tx, ty, Math.round(k * 3), 3.0 + k * 2.8, false);
    attract = { cx: cn.x, cy: cn.y, r: rpx };
  }

  // ── The portal ───────────────────────────────────────────────────────────
  if (portalUp) {
    spin += 0.012;
    const ignite = ignitionAmount(S, now, IGNITE_MS);
    const shut = collapseAmount(S, now, CLOSE_MS);
    const e = ease(ignite);
    const cn = { x: geom.cx, y: geom.cy };
    const rn = clampRN(geom.r) * (1 - ease(shut));
    const rpx = rpxOf(cn, rn);
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
