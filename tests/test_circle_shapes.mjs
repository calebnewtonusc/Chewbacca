// What opens a portal, and what must not.
//
// Every case is something a hand can draw in the air. The list exists because
// the detector kept saying yes to things that are not circles:
//   "It is detecting a portal on smth too ovular"
//   "A somewhat round triangle is doing it bruh wtf"
//   "I barely drew part of a circle and the portal opened"
// all 2026-09-21.
//
// The third one found the real bug. Roundness was computed, returned, and
// read by the renderer to decide how to draw, and by nothing at all to decide
// whether the gesture had happened. Completion was the accumulated turn
// alone, so a rounded square at 0.170 roundness and a rounded triangle at
// 0.000 both opened portals. Completion now needs three things: it turned far
// enough, it stayed round, and it came back to where it started.
import { CircleGestureDetector } from "./.circle-under-test.mjs";

let fails = 0;
const ok = (name, cond, note = "") => {
  if (!cond) { fails++; console.log(`  FAIL  ${name}${note && "  " + note}`); }
  else console.log(`  ok    ${name}`);
};

// Deterministic noise. A run that passes today passes tomorrow.
let seed = 7;
const rnd = () => { seed = (seed * 1103515245 + 12345) & 0x7fffffff; return seed / 0x7fffffff; };
const nz = (a) => (rnd() - 0.5) * a;
const TAU = Math.PI * 2;

// Does this path open a portal? The only question that matters.
function opens(pts) {
  const d = new CircleGestureDetector();
  let t = 0;
  for (const p of pts) {
    if (d.push(p.x * 0.18 + 0.5, p.y * 0.18 + 0.5, (t += 16)).completed) return true;
  }
  return false;
}

const ring = (f, n = 90, j = 0.006) =>
  Array.from({ length: n }, (_, i) => {
    const t = (i / n) * TAU; const [x, y] = f(t, i / n);
    return { x: x + nz(j), y: y + nz(j) };
  });

const smooth = (p, k) => {
  for (let s = 0; s < k; s++)
    p = p.map((_, i) => {
      const a = p[(i - 1 + p.length) % p.length], c = p[i], b = p[(i + 1) % p.length];
      return { x: (a.x + c.x * 2 + b.x) / 4, y: (a.y + c.y * 2 + b.y) / 4 };
    });
  return p;
};

function ngon(sides, rounding, n = 90, j = 0.006) {
  const v = Array.from({ length: sides }, (_, i) => {
    const a = (TAU * i) / sides - Math.PI / 2;
    return { x: Math.cos(a), y: Math.sin(a) };
  });
  const p = Array.from({ length: n }, (_, i) => {
    const f = (i / n) * sides, k = Math.floor(f), t = f - k;
    const a = v[k % sides], b = v[(k + 1) % sides];
    return { x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t };
  });
  return smooth(p, rounding).map((o) => ({ x: o.x + nz(j), y: o.y + nz(j) }));
}

console.log("a circle, however badly drawn, opens a portal:");
ok("a circle",                opens(ring((t) => [Math.cos(t), Math.sin(t)])));
ok("with camera noise",       opens(ring((t) => [Math.cos(t), Math.sin(t)], 90, 0.025)));
ok("with heavy noise",        opens(ring((t) => [Math.cos(t), Math.sin(t)], 90, 0.045)));
ok("with a hand tremor",      opens(ring((t, f) => { const d = 1 + 0.05 * Math.sin(f * TAU * 9); return [Math.cos(t) * d, Math.sin(t) * d]; })));
ok("1.2:1 oval",              opens(ring((t) => [Math.cos(t) * 1.2, Math.sin(t)])));
ok("1.4:1 oval",              opens(ring((t) => [Math.cos(t) * 1.4, Math.sin(t)])));
ok("1.35:1 oval, tilted",     opens(ring((t) => { const x = Math.cos(t) * 1.35, y = Math.sin(t); return [x * 0.8 - y * 0.6, x * 0.6 + y * 0.8]; })));
ok("with one dent in it",     opens(ring((t, f) => { const d = 1 - 0.13 * Math.exp(-((f - 0.4) ** 2) / 0.002); return [Math.cos(t) * d, Math.sin(t) * d]; })));
ok("with the arm drifting",   opens(ring((t, f) => [Math.cos(t) + 0.25 * f, Math.sin(t) + 0.15 * f])));
ok("speeding up as it goes",  opens(Array.from({ length: 90 }, (_, i) => { const t = (i / 90) ** 1.6 * TAU; return { x: Math.cos(t) + nz(0.006), y: Math.sin(t) + nz(0.006) }; })));
ok("lumpy",                   opens(ring((t, f) => { const d = 1 + 0.09 * Math.sin(f * TAU * 3); return [Math.cos(t) * d, Math.sin(t) * d]; })));
ok("squashed on one side",    opens(ring((t) => [Math.cos(t), Math.sin(t) * (Math.sin(t) < 0 ? 0.82 : 1)])));
ok("an egg",                  opens(ring((t) => [Math.cos(t), Math.sin(t) * (1 + 0.16 * Math.cos(t))])));

console.log("\nanything that is not a circle does not:");
// Corners. A rounded triangle has perfectly even radii, so the radial test
// alone scores it like a slightly squashed circle. The corner test is what
// catches it: a circle turns at a constant rate, a triangle turns nothing
// for a third of the way and then 120 degrees at once.
for (const k of [1, 3, 10, 25]) ok(`a triangle, rounded x${k}`, !opens(ngon(3, k)));
for (const k of [1, 3, 10, 25]) ok(`a square, rounded x${k}`,   !opens(ngon(4, k)));
ok("a sharp pentagon",        !opens(ngon(5, 1)));
ok("a 2:1 oval",              !opens(ring((t) => [Math.cos(t) * 2, Math.sin(t)])));
ok("a 3:1 oval",              !opens(ring((t) => [Math.cos(t) * 3, Math.sin(t)])));
ok("a five-point star",       !opens(ring((t, f) => { const r = (Math.floor(f * 10) % 2) ? 0.45 : 1; return [Math.cos(t) * r, Math.sin(t) * r]; })));
ok("a heart",                 !opens(ring((t) => [Math.pow(Math.sin(t), 3), 0.81 * Math.cos(t) - 0.31 * Math.cos(2 * t) - 0.12 * Math.cos(3 * t) - 0.04 * Math.cos(4 * t)])));
ok("a teardrop",              !opens(ring((t) => [Math.cos(t), Math.sin(t) * Math.pow(Math.sin(t / 2), 0.8)])));
ok("a crescent",              !opens(ring((t) => [Math.cos(t), Math.sin(t) - 0.55 * Math.cos(t) * Math.cos(t)])));
ok("a D with a flat side",    !opens(smooth(ring((t) => [Math.max(-0.1, Math.cos(t)), Math.sin(t)]), 2)));
ok("a figure eight",          !opens(ring((t) => [Math.sin(2 * t) * 0.9, Math.sin(t)])));
ok("a 2:1 rounded rectangle", !opens(smooth(Array.from({ length: 90 }, (_, i) => { const f = (i / 90) * 4, k = Math.floor(f), t = f - k; const v = [{ x: -2, y: -1 }, { x: 2, y: -1 }, { x: 2, y: 1 }, { x: -2, y: 1 }]; const a = v[k % 4], b = v[(k + 1) % 4]; return { x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t }; }), 10)));
ok("a zigzag",                !opens(Array.from({ length: 90 }, (_, i) => ({ x: -1 + (2 * i) / 90 + nz(0.006), y: (i % 8 < 4 ? 0.35 : -0.35) + nz(0.006) }))));
ok("a scribble",              !opens(Array.from({ length: 90 }, (_, i) => ({ x: Math.cos(i * 1.9) * rnd(), y: Math.sin(i * 2.3) * rnd() }))));
ok("a straight line",         !opens(Array.from({ length: 90 }, (_, i) => ({ x: -1 + (2 * i) / 90 + nz(0.006), y: nz(0.006) }))));
ok("an L",                    !opens(smooth(Array.from({ length: 90 }, (_, i) => (i < 45 ? { x: -1 + (2 * i) / 45, y: -1 } : { x: 1, y: -1 + (2 * (i - 45)) / 45 })), 2)));
// "I barely drew part of a circle and the portal opened."
ok("half a circle",           !opens(ring((t) => [Math.cos(t), Math.sin(t)], 90).slice(0, 45)));
ok("three quarters of one",   !opens(ring((t) => [Math.cos(t), Math.sin(t)], 90).slice(0, 67)));

// KNOWN AND ACCEPTED, not overlooked. Measured boundary by sides and rounding:
// triangles and squares never fire at any rounding; a sharp pentagon does not;
// a rounded pentagon and everything with six or more sides does. A heptagon
// drawn in the air with a fingertip is a circle, and no measurement this side
// of the camera noise floor says otherwise. A spiral fires on its first loop,
// because its first loop is a circle.
console.log("\nknown to open a portal, and that is the intended answer:");
ok("a rounded hexagon",        opens(ngon(6, 10)));
ok("a rounded octagon",        opens(ngon(8, 10)));

process.exit(fails ? 1 : 0);
