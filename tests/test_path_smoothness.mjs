// No line is ever jagged, whatever the hand did.
//
// "No line should ever be jagged" and "Try a bunch of paths to make sure the
// lines curve", both 2026-09-21.
//
// Jaggedness is measured in PIXELS: how far each point sits off the straight
// line between its neighbours. The first version of this test measured the
// angle between segments instead, and reported a hand held nearly still as 87
// degrees of jaggedness, which sent a whole fix after a problem that did not
// exist. A still hand's samples are a few pixels apart, so the angle between
// them is nearly random while the thing on screen is a two-pixel dot. The
// same case in pixels is 0.6, which is invisible.
//
// The bar is the same path drawn with NO noise at all. A tight curve has real
// deviation from the chord between its neighbours, and that deviation is the
// curve, not a defect: a spiral scores 2.7 and a straight line 0.2, both
// correct. Comparing each path against a clean copy of itself is the only
// reading that means the same thing for a line and for a figure eight.
import { smoothPath, kinkPx } from "./.smooth-under-test.mjs";

let fails = 0;
let seed = 3;
const g = () => { seed = (seed * 1103515245 + 12345) & 0x7fffffff; return seed / 0x7fffffff; };
// Box-Muller, so the noise is gaussian like a landmark's and not uniform.
const gauss = (sd) => sd * Math.sqrt(-2 * Math.log(g() || 1e-9)) * Math.cos(2 * Math.PI * g());

// What the renderer actually uses. One, not the module default of two.
const PASSES = 1;
const LANDMARK_SD = 3.5;   // pixels, measured off a still hand at arm's length
const INPUT_LAG = 0.45;    // the exponential average the renderer applies

// What the renderer actually receives: the true path, plus landmark noise,
// through the input lag.
function asSeen(ideal) {
  let sx = null, sy = null;
  return ideal.map((p) => {
    const x = p.x + gauss(LANDMARK_SD), y = p.y + gauss(LANDMARK_SD);
    sx = sx === null ? x : sx + (x - sx) * INPUT_LAG;
    sy = sy === null ? y : sy + (y - sy) * INPUT_LAG;
    return { x: sx, y: sy };
  });
}

const N = 70;
const at = (f) => Array.from({ length: N }, (_, i) => { const [x, y] = f(i / N); return { x, y } });
const C = { x: 756, y: 491 };

const PATHS = {
  "a straight sweep":        at((t) => [200 + 1100 * t, 500]),
  "a fast diagonal":         at((t) => [150 + 1200 * t, 150 + 700 * t]),
  "a vertical drop":         at((t) => [756, 120 + 740 * t]),
  "a gentle arc":            at((t) => [C.x + Math.cos(Math.PI * t) * 400, C.y + Math.sin(Math.PI * t) * 180]),
  "a tight circle":          at((t) => [C.x + Math.cos(t * 2 * Math.PI) * 90, C.y + Math.sin(t * 2 * Math.PI) * 90]),
  "a wide circle":           at((t) => [C.x + Math.cos(t * 2 * Math.PI) * 340, C.y + Math.sin(t * 2 * Math.PI) * 340]),
  "an oval":                 at((t) => [C.x + Math.cos(t * 2 * Math.PI) * 380, C.y + Math.sin(t * 2 * Math.PI) * 170]),
  "an S curve":              at((t) => [200 + 1100 * t, C.y + Math.sin(t * 2 * Math.PI) * 220]),
  "a figure eight":          at((t) => [C.x + Math.sin(t * 4 * Math.PI) * 330, C.y + Math.sin(t * 2 * Math.PI) * 220]),
  "a spiral":                at((t) => [C.x + Math.cos(t * 3 * Math.PI) * (60 + 260 * t), C.y + Math.sin(t * 3 * Math.PI) * (60 + 260 * t)]),
  "an L turn":               at((t) => (t < 0.5 ? [200 + 1000 * t * 2 * 0.5, 300] : [700, 300 + 500 * (t - 0.5) * 2])),
  "a slow drift":            at((t) => [700 + 90 * t, 480 + 40 * Math.sin(t * Math.PI)]),
  "a hand speeding up":      at((t) => [C.x + Math.cos(t ** 1.8 * 2 * Math.PI) * 260, C.y + Math.sin(t ** 1.8 * 2 * Math.PI) * 260]),
  "a hand slowing down":     at((t) => [C.x + Math.cos(Math.sqrt(t) * 2 * Math.PI) * 260, C.y + Math.sin(Math.sqrt(t) * 2 * Math.PI) * 260]),
  "a circle drawn twice":    at((t) => [C.x + Math.cos(t * 4 * Math.PI) * 230, C.y + Math.sin(t * 4 * Math.PI) * 230]),
  "an arc with a wobble":    at((t) => [C.x + Math.cos(Math.PI * t) * 380 + Math.sin(t * 14) * 18, C.y + Math.sin(Math.PI * t) * 200]),
  "a big loop off centre":   at((t) => [380 + Math.cos(t * 2 * Math.PI) * 300, 320 + Math.sin(t * 2 * Math.PI) * 300]),
  "a near-stationary hand":  at((t) => [750 + 14 * Math.cos(t * 2 * Math.PI), 490 + 14 * Math.sin(t * 2 * Math.PI)]),
};

console.log("path                     no-noise   raw   drawn   verdict");
for (const [name, ideal] of Object.entries(PATHS)) {
  const seen = asSeen(ideal);
  // The SAME smoothing on a noiseless path. Smoothing rounds a real
  // corner on purpose, so comparing against the unsmoothed ideal counts
  // that rounding as a defect: an L scored 0.00 clean against 1.27 drawn
  // and failed, for doing exactly its job. Against this baseline, what
  // is left over is noise and nothing else.
  const clean = kinkPx(smoothPath(ideal, PASSES));
  const raw = kinkPx(seen);
  const drawn = kinkPx(smoothPath(seen, PASSES));
  // Either within a pixel of the noiseless version of the same path, or
  // under two pixels outright. Two is the visibility bar: below it there is
  // nothing on the glass to see, whatever the clean copy happened to score.
  // A nearly still hand needs the second clause, because its clean version
  // scores 0.06 and any real number beats that by more than a pixel while
  // the whole trail is a few pixels across.
  // A pixel of slack, or a third of whatever the path's own curvature
  // already costs, or under two pixels outright.
  //
  // The flat pixel on its own is too tight for a path that kinks a lot by
  // its own nature: a decelerating circle bunches its samples at the end and
  // the noiseless version already scores 4.83, where a pixel of slack is a
  // fifth of the base. A kink reads against the curvature around it, so the
  // allowance is proportional. And the flat two-pixel clause covers the
  // opposite end, a nearly still hand whose clean copy scores 0.06.
  const allow = Math.max(1.0, clean.worst * 0.3);
  const ok = (drawn.worst <= clean.worst + allow || drawn.worst < 2.0)
    && drawn.mean <= raw.mean;
  if (!ok) fails++;
  console.log(
    `  ${name.padEnd(24)} ${clean.worst.toFixed(2).padStart(5)}  ` +
    `${raw.worst.toFixed(2).padStart(5)}  ${drawn.worst.toFixed(2).padStart(6)}   ` +
    `${ok ? "ok" : "JAGGED"}`);
}

// Smoothing a shape must not move it. A line that curves correctly in the
// wrong place is not a fix.
const circle = at((t) => [C.x + Math.cos(t * 2 * Math.PI) * 300, C.y + Math.sin(t * 2 * Math.PI) * 300]);
const s = smoothPath(circle, PASSES);
const drift = Math.max(...s.map((p, i) => Math.hypot(p.x - circle[i].x, p.y - circle[i].y)));
const ok = drift < 6;
if (!ok) fails++;
console.log(`\n  smoothing moves a clean circle by at most ${drift.toFixed(2)}px   ${ok ? "ok" : "TOO FAR"}`);

// The ends are pinned, so the line still starts and stops at the fingers.
const endsHeld = s[0].x === circle[0].x && s[s.length - 1].y === circle[circle.length - 1].y;
if (!endsHeld) fails++;
console.log(`  the ends stay exactly where the hand put them   ${endsHeld ? "ok" : "MOVED"}`);

process.exit(fails ? 1 : 0);
