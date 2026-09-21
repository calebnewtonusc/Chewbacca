import type { Landmark } from "./types";

/**
 * Detects a hand drawn in a circle, the sling-ring gesture.
 *
 * WHY THIS IS NOT IN gestures.ts. `classifyGesture` reads a single frame: it
 * asks which fingers are extended right now. A circle does not exist in one
 * frame. It is a path through time, so it needs state, and state is why this
 * is a class rather than a function.
 *
 * HOW IT WORKS: TOTAL TURNING ANGLE. Take consecutive segments of the path
 * and sum the signed angle from one to the next. A closed loop turns through
 * 2*PI no matter where it sits, how big it is, or what shape it is. A straight
 * line turns through nothing.
 *
 * WHY NOT ANGLE ABOUT A CENTRE. The first version of this did exactly that:
 * take the centroid of a sliding window of points and accumulate each point's
 * angle about it. It failed its own "fires on a full circle" test, and the
 * reason is worth keeping. The centroid of a PARTIAL arc is not the centre of
 * the circle, it sits inside the arc and slides forward as you draw, so the
 * angle is being measured about a moving origin and never sums to 2*PI.
 * Widening the window does not fix it, it only changes which part of the
 * gesture is wrong. Turning angle needs no origin, so the problem disappears
 * rather than getting tuned.
 *
 * A least-squares circle fit would also have been wrong, for a different
 * reason: it answers "are these points on a circle", and a hand held still on
 * the rim of an imaginary circle fits perfectly while having drawn nothing.
 *
 * THE NOISE TRAP. MediaPipe landmarks move a few pixels a frame even when
 * the hand does not, which is about 0.003 to 0.006 normalized, and the turn
 * between consecutive segments of a hand-drawn circle is only about 0.1
 * radians. So noise of that size swamps the sign of the turn. Any rule that
 * branches on `Math.sign(turn)` therefore fires at random on real input while
 * passing every test written with a compass. Smooth first, and let noise
 * cancel itself rather than trying to detect it.
 *
 * THE JITTER TRAP. Segment direction is meaningless when the segment is a
 * pixel long, so short segments produce uniformly random turns. Summing those
 * is a random walk that eventually crosses any threshold. Segments below
 * `minSegment` are therefore dropped entirely rather than smoothed, which is
 * also what makes a stationary hand read as no gesture instead of a slow one.
 *
 * Centre and radius are still reported, because the caller needs somewhere to
 * put the portal, but nothing in the detection depends on them.
 */

export interface CircleGestureOptions {
  /**
   * Radians of accumulated turning before the gesture fires. Default 4.6,
   * about 264 degrees, so three quarters of a turn is enough.
   *
   * It was 306 degrees and he could not close one: "Still really hard to
   * draw circles." An arm sweeping in the air runs out of comfortable range
   * before it comes all the way round, and the last quarter turn is the
   * part where the wrist is fighting itself.
   */
  sweepThreshold?: number;
  /** Trail length in samples. Default 240, enough to hold a whole slow
   * circle, since the fit is only as good as the arc it sees. */
  trailLength?: number;
  /**
   * Shortest segment, in normalized units, that carries a usable direction.
   * Default 0.006. Anything shorter is dropped, not smoothed. See THE JITTER
   * TRAP above.
   */
  minSegment?: number;
  /**
   * Largest per-segment turn that still counts as an arc. Default PI/3. A
   * sharper corner than this is a zigzag or a tracking glitch and resets.
   */
  maxTurn?: number;
  /** Discard the trail after this many ms with no sample. Default 400. */
  staleMs?: number;
  /**
   * Exponential smoothing on the incoming point, 0 to 1. Default 0.45.
   * Lower is smoother and laggier. See THE NOISE TRAP.
   */
  smoothing?: number;
}

export interface CircleProgress {
  /** 0 to 1, how much of the required sweep has been travelled. */
  progress: number;
  /** Signed sweep in radians. Positive is clockwise on screen. */
  sweep: number;
  /** Centre of the trail, normalized coords, or null with too few samples. */
  center: { x: number; y: number } | null;
  /** Mean radius of the trail in normalized units. */
  radius: number;
  /** True on the single frame the circle completes. */
  completed: boolean;
  /** Direction, once there is enough sweep to tell. */
  direction: "cw" | "ccw" | null;
  /**
   * Angle of the FIRST sampled point about the fitted centre, radians.
   * With `endAngle` this is the arc the hand has actually swept, on the
   * circle it is drawing, which is what lets a caller draw the ring building
   * along its own circumference instead of a free path through the air.
   */
  startAngle: number | null;
  /** Angle of the most recent point about the fitted centre, radians. */
  endAngle: number | null;
  /**
   * How well the path actually lies on the circle that was fitted to it,
   * 0 to 1. 1 is every sample at the same radius.
   *
   * WHY TURNING IS NOT ENOUGH. `sweep` says the path curved. It does not
   * say the path curved CONSISTENTLY, and a hand wandering across the
   * frame accumulates turning without ever being round. Caleb, three
   * thresholds into trying to fix this by requiring more turning: "Still
   * too easily starting the circle."
   *
   * Raising the turning threshold cannot separate them, because a meander
   * reaches any threshold eventually. Roundness can: it is the spread of
   * the sample radii about their mean, which is small for an arc and large
   * for a wander, whatever either of them has turned through.
   */
  roundness: number;
}

const EMPTY: CircleProgress = {
  progress: 0,
  sweep: 0,
  center: null,
  radius: 0,
  completed: false,
  direction: null,
  startAngle: null,
  endAngle: null,
  roundness: 0,
};

interface Sample {
  x: number;
  y: number;
  t: number;
}

export class CircleGestureDetector {
  private trail: Sample[] = [];
  private smooth: { x: number; y: number } | null = null;
  private sweep = 0;
  private lastT = 0;
  private readonly o: Required<CircleGestureOptions>;

  constructor(options: CircleGestureOptions = {}) {
    this.o = {
      sweepThreshold: options.sweepThreshold ?? 4.6,
      trailLength: options.trailLength ?? 240,
      minSegment: options.minSegment ?? 0.004,
      maxTurn: options.maxTurn ?? Math.PI / 2.2,
      staleMs: options.staleMs ?? 400,
      smoothing: options.smoothing ?? 0.45,
    };
  }

  /** Feed one frame. Pass null when the hand is gone. */
  update(lm: Landmark[] | null | undefined, now = Date.now()): CircleProgress {
    if (!lm || lm.length < 21) {
      this.reset();
      return EMPTY;
    }
    // Index fingertip. Pointing is how anybody draws a circle in the air, and
    // the wrist barely moves during the gesture, so it is the only landmark
    // with enough travel to measure.
    return this.push(lm[8].x, lm[8].y, now);
  }

  /** Feed a raw point, for tests and for non-MediaPipe sources. */
  push(x: number, y: number, now = Date.now()): CircleProgress {
    if (this.lastT && now - this.lastT > this.o.staleMs) this.reset();
    this.lastT = now;

    // Smooth before measuring anything. See THE NOISE TRAP.
    if (!this.smooth) {
      this.smooth = { x, y };
    } else {
      const a = this.o.smoothing;
      this.smooth = {
        x: this.smooth.x + (x - this.smooth.x) * a,
        y: this.smooth.y + (y - this.smooth.y) * a,
      };
    }
    x = this.smooth.x;
    y = this.smooth.y;

    const prev = this.trail[this.trail.length - 1];
    if (prev) {
      // Drop segments too short to have a meaningful direction. See THE
      // JITTER TRAP. This is a hard drop, not a smooth: the sample is not
      // recorded at all, so the next real move measures from the last real
      // position rather than from noise.
      if (Math.hypot(x - prev.x, y - prev.y) < this.o.minSegment) {
        return this.report();
      }
    }

    this.trail.push({ x, y, t: now });
    if (this.trail.length > this.o.trailLength) this.trail.shift();

    const n = this.trail.length;
    if (n >= 3) {
      const a = this.trail[n - 3];
      const b = this.trail[n - 2];
      const c = this.trail[n - 1];
      const v1x = b.x - a.x;
      const v1y = b.y - a.y;
      const v2x = c.x - b.x;
      const v2y = c.y - b.y;
      // Signed angle from v1 to v2. atan2(cross, dot) is already folded into
      // (-PI, PI], so there is no seam to cross and no wraparound to handle.
      const turn = Math.atan2(v1x * v2y - v1y * v2x, v1x * v2x + v1y * v2y);

      if (Math.abs(turn) > this.o.maxTurn) {
        // A corner this sharp is a zigzag, a wave turning around, or a
        // tracking glitch. Not an arc. This one guard is what rejects a
        // back-and-forth wave, because the turn at each end of a wave is
        // close to PI and nothing else in a real circle comes near maxTurn.
        this.sweep = 0;
      } else {
        // Plain accumulation. An earlier version restarted the sweep whenever
        // the turn changed sign, and that is what made the detector unusable
        // with a real hand: turn per frame on a hand-drawn circle is about
        // 0.1 radians, landmark jitter flips its sign constantly, and every
        // flip threw the accumulation away. It passed every synthetic test
        // and fired 0 times out of 20 on a circle with realistic jitter.
        // Noise does not need rejecting here, it random walks about zero.
        this.sweep += turn;
      }
    }

    const done = Math.abs(this.sweep) >= this.o.sweepThreshold;
    const out = this.report(done);
    if (done) {
      // Consume it, so the caller gets exactly one completed frame per circle
      // and needs no debounce of its own.
      this.sweep = 0;
      this.trail = [];
    }
    return out;
  }

  private report(completed = false): CircleProgress {
    if (this.trail.length < 3) {
      return { ...EMPTY, completed: false };
    }
    const { center, radius } = this.fit();
    const first = this.trail[0];
    const last = this.trail[this.trail.length - 1];
    // Spread of the sample radii about their mean, inverted. A coefficient
    // of variation over about 0.35 is a wander rather than an arc.
    //
    // MEASURED AGAINST THE SPREAD OF THE POINTS, NOT THE FITTED RADIUS.
    // Dividing the residual by the fitted radius scores a wander as round,
    // because a wander fits a huge circle and any deviation looks small
    // beside it. A sine curve across the frame scored 0.78 that way. The
    // spread about the centroid is what the samples actually occupy, so an
    // arc has a residual far smaller than its spread and a wander has one
    // comparable to it, whatever either fit came out as.
    let roundness = 0;
    if (this.trail.length >= 4) {
      const m = this.centroid();
      const spread = Math.sqrt(
        this.trail.reduce(
          (a, q) => a + (q.x - m.x) ** 2 + (q.y - m.y) ** 2, 0) / this.trail.length);
      const radii = this.trail.map((q) => Math.hypot(q.x - center.x, q.y - center.y));
      const mean = radii.reduce((a, b) => a + b, 0) / radii.length;
      const sd = Math.sqrt(
        radii.reduce((a, r) => a + (r - mean) ** 2, 0) / radii.length);
      if (spread > 1e-6) roundness = Math.max(0, 1 - (sd / spread) / 0.45);
    }
    return {
      roundness,
      startAngle: Math.atan2(first.y - center.y, first.x - center.x),
      endAngle: Math.atan2(last.y - center.y, last.x - center.x),
      progress: Math.min(1, Math.abs(this.sweep) / this.o.sweepThreshold),
      sweep: this.sweep,
      center,
      radius,
      completed,
      direction:
        Math.abs(this.sweep) > 0.5 ? (this.sweep > 0 ? "cw" : "ccw") : null,
    };
  }

  reset() {
    this.trail = [];
    this.smooth = null;
    this.sweep = 0;
    this.lastT = 0;
  }

  /**
   * Algebraic least-squares circle fit (Kasa). Returns the centre of the
   * circle the path lies on, which is NOT the centroid of the path.
   *
   * WHY NOT THE CENTROID. The centroid of an arc sits inside the arc, pulled
   * toward wherever the samples are densest, and only coincides with the
   * centre when the loop is complete and evenly sampled. A hand always stops
   * a little short and always slows on one side, so the portal landed
   * consistently off from the circle the person actually drew.
   *
   * Fits x^2 + y^2 = a*x + b*y + c, which is linear in (a, b, c), so it is a
   * 3x3 solve with no iteration. Centre is (a/2, b/2). Coordinates are
   * shifted to the centroid first, because the raw normalized values are all
   * near 0.5 and squaring them costs precision in the normal equations.
   *
   * Falls back to the centroid when the points are nearly collinear, where
   * the fit is singular and would throw the portal off screen.
   */
  private fit(): { center: { x: number; y: number }; radius: number } {
    const m = this.centroid();
    const n = this.trail.length;
    let Sxx = 0, Sxy = 0, Syy = 0, Sxz = 0, Syz = 0, Sz = 0, Sx = 0, Sy = 0;
    for (const q of this.trail) {
      const x = q.x - m.x;
      const y = q.y - m.y;
      const z = x * x + y * y;
      Sxx += x * x;
      Sxy += x * y;
      Syy += y * y;
      Sxz += x * z;
      Syz += y * z;
      Sz += z;
      Sx += x;
      Sy += y;
    }
    // Shifted to the centroid, so Sx and Sy are ~0 and the system reduces to
    // a 2x2 in (a, b).
    const det = Sxx * Syy - Sxy * Sxy;
    const meanR = Math.sqrt(Sz / n);
    if (!isFinite(det) || Math.abs(det) < 1e-12) {
      return { center: m, radius: meanR };
    }
    const a = (Sxz * Syy - Syz * Sxy) / det;
    const b = (Syz * Sxx - Sxz * Sxy) / det;
    const cx = a / 2;
    const cy = b / 2;
    const c = Sz / n - (cx * Sx * 2 + cy * Sy * 2) / n;
    const r2 = cx * cx + cy * cy + c;
    const radius = r2 > 0 ? Math.sqrt(r2) : meanR;
    const center = { x: m.x + cx, y: m.y + cy };
    // A fit can run away on a short or noisy arc. Anything wildly outside
    // what the samples support is worse than the centroid.
    const drift = Math.hypot(cx, cy);
    // AN ILL-CONDITIONED FIT IS WORSE THAN NO FIT. On a short, barely curved
    // path the least-squares solution is a vast circle whose arc happens to
    // pass through those few points: correct, and useless. It put an arc
    // right off the screen on a small flick of a pinched hand.
    //
    // Two ceilings. The first is relative, because a fitted radius far
    // larger than the spread of the samples means the curvature was too
    // slight to trust. The second is absolute, because the coordinate space
    // is the camera frame and nothing sensible is drawn on a circle wider
    // than it.
    if (
      !isFinite(radius) ||
      radius > meanR * 2.5 ||
      drift > meanR * 2.5 ||
      radius > 0.75
    ) {
      return { center: m, radius: Math.min(meanR, 0.75) };
    }
    return { center, radius };
  }

  private centroid() {
    let x = 0;
    let y = 0;
    for (const p of this.trail) {
      x += p.x;
      y += p.y;
    }
    return { x: x / this.trail.length, y: y / this.trail.length };
  }
}

/**
 * Convert an angle measured in NORMALIZED landmark space to the angle to use
 * when drawing on a MIRRORED canvas, the selfie view every webcam UI uses.
 *
 * The mirror negates x, so a normalized point at theta lands at screen
 * (cx - r*cos theta, cy + r*sin theta). Matching that against the canvas
 * convention (cx + R*cos phi, cy + R*sin phi) gives cos phi = -cos theta and
 * sin phi = sin theta, so phi = PI - theta.
 *
 * The consequence that actually bites: the map NEGATES the angle, so any
 * sweep or direction measured in normalized space must also be negated, or
 * arcs build away from the hand that is drawing them.
 */
export function mirrorAngle(theta: number): number {
  return Math.PI - theta;
}
