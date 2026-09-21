// Opening and closing a portal.
//
// "Bro I can't close portals anymore", 2026-09-21. A completion arriving
// while a portal was already open reset its born time and disarmed the
// close, so the portal could never be closed. It hid for weeks because the
// detector used to throw its sweep away on any tracking glitch, which made a
// second completion rare; the moment large circles were made glitch-proof,
// the detector became persistent enough to complete again and this surfaced.
import { initialPortalState, stepPortal } from "./.portal-state-under-test.mjs";

let fails = 0;
const ok = (name, cond) => {
  if (!cond) { fails++; console.log(`  FAIL  ${name}`); }
  else console.log(`  ok    ${name}`);
};

const T = { igniteMs: 1150, closeMs: 380, minOpenMs: 600 };
const IN = (o) => ({
  now: 0, pinched: false, completed: false, progress: 0,
  center: { x: 100, y: 100 }, radius: 80, ...o,
});
const up = (s) => s.phase === "igniting" || s.phase === "open" || s.phase === "closing";

// Draw a circle, hold the pinch, release, re-pinch: that closes it.
function run(steps) {
  let s = initialPortalState();
  for (const st of steps) s = stepPortal(s, IN(st), T);
  return s;
}

console.log("opening and closing:");
let s = run([{ now: 0, pinched: true, completed: true }]);
ok("a completed circle opens one", up(s));

s = run([
  { now: 0, pinched: true, completed: true },
  { now: 100, pinched: true },          // still holding the drawing pinch
]);
ok("the drawing pinch does not close it", up(s));

s = run([
  { now: 0, pinched: true, completed: true },
  { now: 700, pinched: false },         // released
  { now: 800, pinched: true },          // pinched again
]);
ok("release then pinch closes it", s.phase === "closing");

s = run([
  { now: 0, pinched: true, completed: true },
  { now: 100, pinched: false },
  { now: 200, pinched: true },          // inside minOpenMs
]);
ok("it will not close before the minimum open time", up(s) && s.phase !== "closing");

// THE REGRESSION. A second completion while one is already up.
console.log("\na second completion while a portal is up:");
s = run([
  { now: 0, pinched: true, completed: true },
  { now: 300, pinched: true, completed: true },   // another circle finishes
  { now: 700, pinched: false },
  { now: 800, pinched: true },
]);
ok("does not push the close out of reach", s.phase === "closing");

s = run([
  { now: 0, pinched: true, completed: true },
  { now: 200, pinched: true, completed: true },
  { now: 400, pinched: true, completed: true },
  { now: 600, pinched: true, completed: true },   // and again, and again
  { now: 900, pinched: false },
  { now: 1000, pinched: true },
]);
ok("nor does a run of them", s.phase === "closing");

s = run([
  { now: 0, pinched: true, completed: true },
  { now: 300, pinched: true, completed: true, center: { x: 900, y: 900 } },
]);
ok("and the portal does not jump to the new circle", s.x === 100 && s.y === 100);

console.log("\nafter it closes:");
s = run([
  { now: 0, pinched: true, completed: true },
  { now: 700, pinched: false },
  { now: 800, pinched: true },
  { now: 1300, pinched: false },        // collapse finished
  { now: 1400, pinched: true, completed: true },
]);
ok("a new circle opens another one", up(s));

process.exit(fails ? 1 : 0);
