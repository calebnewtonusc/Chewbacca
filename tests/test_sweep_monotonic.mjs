// THE OSCILLATION, MEASURED.
//
// "It keeps oscillating, the white gap appears to be moving back and forth."
// Three fixes aimed at the clock missed it. The claim under test is that the
// cause is the detector's `sweep`, which is a signed accumulation and so goes
// DOWN whenever a real hand wobbles backwards, dragging the boundary with it.
//
// This measures that directly on a noisy circle, and then measures the
// ratchet the renderer applies on top of it.
import { CircleGestureDetector } from "./.circle-under-test.mjs";

// A hand tracing a circle, with the per-frame noise a camera actually gives.
// 6px of wander on a 1512px screen is 0.004 normalized; this uses 0.005.
function noisyCircle(n, noise, seed) {
  let s = seed;
  const rnd = () => (s = (s * 1103515245 + 12345) % 2147483648) / 2147483648 - 0.5;
  const out = [];
  for (let i = 0; i < n; i++) {
    const a = (i / n) * Math.PI * 2 * 1.15;
    out.push({
      x: 0.5 + Math.cos(a) * 0.3 + rnd() * noise,
      y: 0.5 + Math.sin(a) * 0.3 + rnd() * noise,
    });
  }
  return out;
}

let fail = 0;
for (const noise of [0, 0.005, 0.012]) {
  const d = new CircleGestureDetector();
  const pts = noisyCircle(120, noise, 7);
  let prev = 0, backSteps = 0, worstBack = 0;
  let ratchet = 0, ratchetBack = 0;
  let t = 0;
  for (const pt of pts) {
    const p = d.push(pt.x, pt.y, (t += 33));
    const turns = Math.min(1, Math.abs(p.sweep) / (Math.PI * 2));
    if (turns < prev - 1e-9) { backSteps++; worstBack = Math.max(worstBack, prev - turns); }
    prev = turns;
    // what the renderer now does
    const next = Math.max(ratchet, turns);
    if (next < ratchet - 1e-9) ratchetBack++;
    ratchet = next;
  }
  const deg = (worstBack * 360).toFixed(1);
  console.log(
    `  noise ${String(noise).padEnd(6)} raw sweep went backwards ${String(backSteps).padStart(3)} frames` +
    ` (worst ${deg.padStart(5)} deg)   ratcheted ${ratchetBack} frames`);
  if (ratchetBack !== 0) { console.log("  FAIL  the ratchet let the edge walk back"); fail++; }
  if (noise > 0 && backSteps === 0) {
    console.log("  FAIL  no backward steps at all, so this test proves nothing");
    fail++;
  }
}

console.log();
if (fail) { console.log(`${fail} failed`); process.exit(1); }
console.log("the raw signal oscillates, the ratcheted one cannot   ok");
