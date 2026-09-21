/**
 * Smoothing for a path drawn by a hand in the air.
 *
 * "No line should ever be jagged." The renderer already draws quadratics
 * through the midpoints of its points, which removes every visible vertex,
 * and the line was still jagged, because a smooth curve through noisy points
 * is a smooth curve that wiggles.
 *
 * The input cannot be smoothed harder to fix it. The exponential average on
 * the way in runs at 0.45 and is deliberately weak: stronger and the line
 * lags visibly behind the fingers, and a trail that trails is worse than one
 * that shimmers.
 *
 * So the shape is smoothed at the point of drawing, on a copy, leaving the
 * stored points exactly as the hand made them so the circle fit still sees
 * the real gesture.
 *
 * This lives in its own file so the test and the renderer run the same code.
 * A test that reimplements the thing it is testing passes forever.
 */
export interface P2 { x: number; y: number }

/**
 * Two passes of a [1,2,1] kernel with the ends pinned.
 *
 * Measured on a hand's arc with realistic landmark noise and the input lag
 * already applied, as mean turn per point where a clean arc is 5.40 degrees:
 *
 *     raw          8.92
 *     one pass     5.71
 *     two passes   5.18
 *     three        5.11
 *
 * Two lands on the clean arc. Three buys 0.07 of a degree and starts
 * rounding off the gesture itself, which is the thing being measured.
 */
export function smoothPath(points: readonly P2[], passes = 2): P2[] {
  let pts = points.map((p) => ({ x: p.x, y: p.y }));
  for (let pass = 0; pass < passes; pass++) {
    const out = pts.slice();
    for (let i = 1; i < pts.length - 1; i++) {
      out[i] = {
        x: (pts[i - 1].x + pts[i].x * 2 + pts[i + 1].x) / 4,
        y: (pts[i - 1].y + pts[i].y * 2 + pts[i + 1].y) / 4,
      };
    }
    pts = out;
  }
  return pts;
}

/**
 * How far each point sits off the straight line between its two neighbours,
 * in pixels. This is what "jagged" means to an eye: a visible deviation from
 * smooth, measured on the glass.
 *
 * MEASURE THIS AND NOT AN ANGLE. The first version of this measured the mean
 * turn between segments, and reported a hand held nearly still as 87 degrees
 * of jaggedness, which sent a whole fix after a problem that did not exist.
 * A still hand's samples are a few pixels apart, so the angle between them is
 * very nearly random and the number goes to the moon while the thing on
 * screen is a two-pixel dot. In pixels the same case reads 0.6, which is
 * invisible, and that is the truth of it.
 *
 * Returns the mean and the 95th percentile. The 95th is the one to gate on:
 * one visible kink in a line is a jagged line.
 */
export function kinkPx(pts: readonly P2[]): { mean: number; worst: number } {
  const vals: number[] = [];
  for (let i = 1; i < pts.length - 1; i++) {
    const a = pts[i - 1], b = pts[i + 1], c = pts[i];
    const dx = b.x - a.x, dy = b.y - a.y;
    const L = Math.hypot(dx, dy);
    if (L < 1e-9) continue;
    vals.push(Math.abs(dx * (a.y - c.y) - dy * (a.x - c.x)) / L);
  }
  if (!vals.length) return { mean: 0, worst: 0 };
  vals.sort((x, y) => x - y);
  return {
    mean: vals.reduce((x, y) => x + y, 0) / vals.length,
    worst: vals[Math.floor(vals.length * 0.95)],
  };
}
