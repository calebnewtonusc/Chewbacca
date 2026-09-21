// What the circle detector must and must not accept.
//
// Every case here is something a hand actually drew at the HUD and got the
// wrong answer for. "It is detecting a portal on smth too ovular" and "A
// somewhat round triangle is doing it bruh wtf", both 2026-09-21.
import { CircleGestureDetector } from "./.circle-under-test.mjs";

let fails = 0;
const ok = (name, cond) => {
  if (!cond) { fails++; console.log(`  FAIL  ${name}`); }
  else console.log(`  ok    ${name}`);
};

// Deterministic noise, so a run that passes today passes tomorrow.
let seed = 42;
const noise = (a) => { seed = (seed * 1103515245 + 12345) & 0x7fffffff; return (seed / 0x7fffffff - 0.5) * a; };

// Roundness AT THE LATCH, which is the only moment it is read. Taking the
// best value over the whole stroke passes a 1.9:1 oval, because the first
// third of any ellipse is an arc and an arc is round.
function feed(pts) {
  const d = new CircleGestureDetector();   // the smoothing that actually ships
  let t = 0, last = 0;
  for (const p of pts) {
    const r = d.push(p.x * 0.18 + 0.5, p.y * 0.18 + 0.5, (t += 16));
    last = r.roundness;
    if (r.progress >= 0.65) return r.roundness;
  }
  return last;
}

function ellipse(aspect, n = 90, jitter = 0.006) {
  return Array.from({ length: n }, (_, i) => {
    const t = (i / n) * Math.PI * 2;
    return { x: Math.cos(t) * aspect + noise(jitter), y: Math.sin(t) + noise(jitter) };
  });
}

function ngon(sides, smooth, n = 90, jitter = 0.006) {
  const v = Array.from({ length: sides }, (_, i) => {
    const a = (2 * Math.PI * i) / sides - Math.PI / 2;
    return { x: Math.cos(a), y: Math.sin(a) };
  });
  let pts = Array.from({ length: n }, (_, i) => {
    const f = (i / n) * sides, k = Math.floor(f), t = f - k;
    const a = v[k % sides], b = v[(k + 1) % sides];
    return { x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t };
  });
  for (let s = 0; s < smooth; s++) {
    pts = pts.map((_, i) => {
      const a = pts[(i - 1 + pts.length) % pts.length], c = pts[i], b = pts[(i + 1) % pts.length];
      return { x: (a.x + c.x * 2 + b.x) / 4, y: (a.y + c.y * 2 + b.y) / 4 };
    });
  }
  return pts.map((p) => ({ x: p.x + noise(jitter), y: p.y + noise(jitter) }));
}

const GATE = 0.55;   // the value portal.entry.ts gates on

// Measured at the latch with the shipped smoothing:
//
//   circle        0.95      triangle, rounded x3     0.00
//   noisy circle  0.79      triangle, rounded x10    0.00
//   very noisy    0.56      triangle, rounded x25    0.00
//   ellipse 1.25  0.84      square, rounded x10      0.04
//   ellipse 1.45  0.74      ellipse 1.9              0.55
//
// The corner gate is decisive: anything with corners lands at zero. The oval
// boundary is soft and always will be, because there is no sharp line
// between a circle and a 1.4:1 oval drawn by a hand in the air. So the oval
// cases here are tested where there is real margin, not at the boundary.
console.log("must be accepted as a circle:");
ok("a circle",                   feed(ellipse(1.0)) > GATE);
ok("a circle with camera noise", feed(ellipse(1.0, 90, 0.02)) > GATE);
ok("a hand's 1.25:1 oval",       feed(ellipse(1.25)) > GATE);
ok("a hand's 1.45:1 oval",       feed(ellipse(1.45)) > GATE);

console.log("must be refused:");
ok("a 2.2:1 oval",               feed(ellipse(2.2)) < GATE);
// These are the ones that matter. A rounded triangle has perfectly even
// radii, so it must be refused by a wide margin or it is being refused by
// luck. "A somewhat round triangle is doing it bruh wtf", 2026-09-21.
ok("a barely rounded triangle",  feed(ngon(3, 3))  < 0.2);
ok("a somewhat round triangle",  feed(ngon(3, 10)) < 0.2);
ok("a very round triangle",      feed(ngon(3, 25)) < 0.2);
ok("a rounded square",           feed(ngon(4, 10)) < 0.2);

process.exit(fails ? 1 : 0);
