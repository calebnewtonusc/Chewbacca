// chewbacca open: the whole kit on one screen.
//
// Everything this kit knows is already on the machine and none of it is
// visible. You learn you have fifteen overdue people by running a command you
// have to remember exists, and you learn the IYA deadline moved by opening a
// markdown file. A glance should do it.
//
// Zero dependencies, same as the rest of the kit. node:sqlite for the store,
// node:http for the server, one inline page. Bound to loopback on purpose:
// this reads a private message archive and it does not belong on the network.

const http = require("node:http");
const fs = require("node:fs");
const path = require("node:path");
const os = require("node:os");
const { execFileSync } = require("node:child_process");

let DatabaseSync;
try {
  ({ DatabaseSync } = require("node:sqlite"));
} catch {
  console.error("chewbacca open needs Node 22.5 or newer (node:sqlite).");
  process.exit(1);
}

const PEOPLE_DB = path.join(
  process.env.PEOPLE_DIR || path.join(os.homedir(), ".chewbacca", "people"),
  "people.db",
);
const ROOT = process.env.CHEWBACCA_ROOT || path.join(__dirname, "..", "..");

function openDb() {
  if (!fs.existsSync(PEOPLE_DB)) return null;
  try {
    return new DatabaseSync(PEOPLE_DB, { readOnly: true });
  } catch {
    return null;
  }
}

const q = (db, sql, ...a) => {
  try {
    return db.prepare(sql).all(...a);
  } catch {
    return [];
  }
};
const q1 = (db, sql, ...a) => q(db, sql, ...a)[0] || {};

// Ranking, and the reason it is not the store's own.
//
// `people reconnect` scores urgency as base_score * (1 + over/cadence).
// base_score is zero for anyone with no hand-written observations, so on a
// freshly imported machine it is zero times everything, the sort does nothing,
// and the list comes back in table order. On this machine that was 944 of 945
// people and an "overdue list" that read A, A, A, A.
//
// A display cannot wait for that fix upstream, so it ranks on how far past
// cadence somebody is and uses score only to break ties. Somebody 410 days
// past a 330 day cadence outranks somebody 12 days past, which is the thing
// the eye is actually asking.
function overdue(db, limit = 20) {
  const rows = q(
    db,
    `SELECT p.name, p.company, p.cadence_days, s.base_score, s.last_interaction_at
       FROM people p LEFT JOIN person_scores s ON s.person_id = p.id
      WHERE p.deleted_at IS NULL AND p.muted_at IS NULL
        AND s.last_interaction_at IS NOT NULL`,
  );
  const now = Date.now();
  const out = [];
  for (const r of rows) {
    const t = Date.parse(r.last_interaction_at);
    if (!t) continue;
    const days = Math.floor((now - t) / 86400000);
    const score = r.base_score || 0;
    const cadence = r.cadence_days || Math.round(30 + (1 - score) * 300);
    const over = days - cadence;
    if (over < 0) continue;
    out.push({
      name: r.name,
      company: r.company || "",
      days,
      cadence,
      over,
      score,
    });
  }
  out.sort(
    (a, b) => b.over / b.cadence - a.over / a.cadence || b.score - a.score,
  );
  // The total travels with the page, because the panel can only show a screen
  // of them and "14 overdue" printed above a list of 14 was the length of the
  // slice rather than the size of the problem. On this machine the two differ
  // by two orders of magnitude.
  const shown = out.slice(0, limit);
  shown.total = out.length;
  return shown;
}

function pulse(db, days = 21) {
  const rows = q(
    db,
    `SELECT date(sent_at) AS d, count(*) AS n FROM messages
      WHERE sent_at >= date('now', ?) GROUP BY d ORDER BY d`,
    `-${days} days`,
  );
  const byDay = new Map(rows.map((r) => [r.d, r.n]));
  const out = [];
  for (let i = days - 1; i >= 0; i--) {
    const d = new Date(Date.now() - i * 86400000).toISOString().slice(0, 10);
    out.push({ day: d, n: byDay.get(d) || 0 });
  }
  return out;
}

// Kits carry a .kit marker and a DEADLINES.md with dated rows. Reading the
// markdown rather than a database is deliberate: the kit is the source of
// truth for its own dates and it is the file the human edits.
function kits() {
  const home = os.homedir();
  const found = [];
  const walk = (dir, depth) => {
    if (depth > 3) return;
    let entries = [];
    try {
      entries = fs.readdirSync(dir, { withFileTypes: true });
    } catch {
      return;
    }
    if (entries.some((e) => e.name === ".kit")) {
      found.push(dir);
      return;
    }
    for (const e of entries) {
      if (
        !e.isDirectory() ||
        e.name.startsWith(".") ||
        e.name === "node_modules"
      )
        continue;
      walk(path.join(dir, e.name), depth + 1);
    }
  };
  for (const base of ["dev", "Documents", "Desktop", ""]) {
    walk(path.join(home, base), 0);
  }
  return [...new Set(found)];
}

function deadlines() {
  const out = [];
  const today = new Date().toISOString().slice(0, 10);
  for (const dir of kits()) {
    const f = path.join(dir, "DEADLINES.md");
    if (!fs.existsSync(f)) continue;
    let text = "";
    try {
      text = fs.readFileSync(f, "utf8");
    } catch {
      continue;
    }
    for (const line of text.split("\n")) {
      const m = line.match(
        /\|\s*\**(\d{4}-\d{2}-\d{2})\**\s*\|([^|]*)\|([^|]*)\|/,
      );
      if (!m) continue;
      const when = m[1];
      if (when < today) continue;
      out.push({
        date: when,
        org: m[2].replace(/\*/g, "").trim(),
        what: m[3].replace(/\*/g, "").trim(),
        kit: path.basename(dir),
        days: Math.round((Date.parse(when) - Date.parse(today)) / 86400000),
      });
    }
  }
  out.sort((a, b) => a.date.localeCompare(b.date));
  return out.slice(0, 6);
}

function repoState() {
  const git = (...a) => {
    try {
      return execFileSync("git", ["-C", ROOT, ...a], {
        encoding: "utf8",
      }).trim();
    } catch {
      return "";
    }
  };
  const dirty = git("status", "--porcelain").split("\n").filter(Boolean).length;
  let ahead = 0;
  try {
    ahead = Number(git("rev-list", "--count", "@{u}..HEAD")) || 0;
  } catch {
    ahead = 0;
  }
  let version = "";
  try {
    version = fs.readFileSync(path.join(ROOT, "VERSION"), "utf8").trim();
  } catch {
    version = "unknown";
  }
  let skills = 0;
  try {
    skills = fs.readdirSync(path.join(ROOT, "skills")).length;
  } catch {
    skills = 0;
  }
  return {
    branch: git("rev-parse", "--abbrev-ref", "HEAD") || "?",
    dirty,
    ahead,
    version,
    skills,
  };
}

function snapshot() {
  const db = openDb();
  const base = {
    people: 0,
    messages: 0,
    overdue: [],
    overdueTotal: 0,
    pulse: [],
    recent: [],
    range: null,
  };
  if (db) {
    base.people =
      q1(db, "SELECT count(*) AS n FROM people WHERE deleted_at IS NULL").n ||
      0;
    base.messages = q1(db, "SELECT count(*) AS n FROM messages").n || 0;
    const od = overdue(db);
    base.overdue = od;
    base.overdueTotal = od.total;
    base.pulse = pulse(db);
    base.recent = q(
      db,
      `SELECT p.name, max(m.sent_at) AS t FROM messages m JOIN people p ON p.id = m.person_id
        WHERE m.room IS NULL GROUP BY p.id ORDER BY t DESC LIMIT 12`,
    );
    const r = q1(
      db,
      "SELECT min(date(sent_at)) AS a, max(date(sent_at)) AS b FROM messages",
    );
    base.range = r.a ? `${r.a} to ${r.b}` : null;
    db.close();
  }
  return {
    ...base,
    deadlines: deadlines(),
    kits: kits().map((d) => path.basename(d)),
    repo: repoState(),
    host: os.hostname().replace(/\.local$/, ""),
    at: new Date().toISOString(),
  };
}

// The screen answers ONE question: who is slipping away from you. Everything
// else on it is periphery, sized and coloured like periphery.
//
// The look is aimed at instruments rather than at science fiction, and those
// are different targets. Movie interfaces are designed to be looked at: scan
// lines, hexagons, glowing borders, numbers that tick because motion reads as
// advanced. They photograph well and are stupid after ten seconds. Real
// instruments (a flight display, a mixing desk, a terminal) are dense, almost
// monochrome, and every moving thing moves because a value changed.
//
// So the rules this file follows, and the reasons:
//
//   One accent. Amber appears on the single most urgent row and nowhere else.
//   The previous version put it on 25 chart bars, six headline numbers and
//   four badges at once, which is the same as having no accent at all.
//
//   Numerals are monospaced and tabular. This is the cheapest and strongest
//   signal that a surface is an instrument, and it stops columns of figures
//   shifting by a pixel every time a digit changes.
//
//   Nothing loops. The clock ticks because time passes, the transmit dot
//   lights while a fetch is actually in flight, and a number animates only
//   when it differs from the number already on screen.
//
//   No scroll. It is a panel you glance at, not a page you read.
const PAGE = `<!doctype html>
<html lang="en"><head>
<meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Chewbacca</title>
<link rel="icon" href="data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 32 32'%3E%3Ccircle cx='16' cy='16' r='13' fill='none' stroke='%23f0b429' stroke-width='3'/%3E%3Ccircle cx='16' cy='16' r='5' fill='%23f0b429'/%3E%3C/svg%3E">
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=Inter:wght@300;400;500;600;700;800&family=JetBrains+Mono:wght@300;400;500;700&display=swap" rel="stylesheet">
<style>
:root{
  --void:#050506;
  --panel:rgba(255,255,255,.022);
  --panel-lit:rgba(255,255,255,.04);
  --hair:rgba(255,255,255,.07);
  --hair-lit:rgba(255,255,255,.14);
  --ice:#eceef2;
  --steel:#7e8791;
  --faint:#464d55;
  --ghost:#2a2f35;
  --amber:#f0b429;
  --amber-dim:rgba(240,180,41,.5);
  --amber-ghost:rgba(240,180,41,.09);
  --sans:"Inter",-apple-system,BlinkMacSystemFont,sans-serif;
  --mono:"JetBrains Mono",ui-monospace,SFMono-Regular,monospace;
  --ease:cubic-bezier(.16,.84,.28,1);
}
*{box-sizing:border-box;margin:0;padding:0}
html,body{height:100%}
body{
  background:var(--void);
  color:var(--ice);
  font-family:var(--sans);
  -webkit-font-smoothing:antialiased;
  overflow:hidden;
}
/* Three offset washes and a masked grid. The grid is what stops the black
   from reading as "unstyled background" at a glance, and the mask keeps it
   from tiling visibly into the corners. */
body::before{
  content:"";position:fixed;inset:0;pointer-events:none;
  background:
    radial-gradient(900px 520px at 14% -6%, rgba(240,180,41,.07), transparent 62%),
    radial-gradient(760px 480px at 92% 4%, rgba(90,130,200,.055), transparent 60%),
    radial-gradient(1100px 700px at 50% 108%, rgba(240,180,41,.035), transparent 66%);
}
body::after{
  content:"";position:fixed;inset:0;pointer-events:none;opacity:.5;
  background-image:
    linear-gradient(var(--hair) 1px,transparent 1px),
    linear-gradient(90deg,var(--hair) 1px,transparent 1px);
  background-size:68px 68px;
  -webkit-mask-image:radial-gradient(ellipse 78% 62% at 50% 40%,#000 25%,transparent 100%);
  mask-image:radial-gradient(ellipse 78% 62% at 50% 40%,#000 25%,transparent 100%);
}

.shell{
  position:relative;z-index:1;height:100%;
  display:grid;grid-template-rows:auto 1fr auto;
  gap:16px;padding:18px 26px 14px;
  max-width:1680px;margin:0 auto;
}

/* ------------------------------------------------------------- top rail */
.rail{display:flex;align-items:center;gap:18px}
.mark{
  font-size:15px;font-weight:800;letter-spacing:.34em;
  background:linear-gradient(92deg,var(--ice) 34%,var(--amber));
  -webkit-background-clip:text;background-clip:text;color:transparent;
}
.rail .sep{flex:1;height:1px;background:linear-gradient(90deg,var(--hair),transparent)}
.chip{
  font-family:var(--mono);font-size:10px;letter-spacing:.16em;
  color:var(--faint);text-transform:uppercase;display:flex;align-items:center;gap:7px;
}
/* Lights while a fetch is in flight and goes dark when it lands. It is the
   only thing on screen that moves without a value changing, and it is
   reporting a real event rather than decorating one. */
.tx{width:5px;height:5px;border-radius:50%;background:var(--ghost);transition:all .3s var(--ease)}
.tx.on{background:var(--amber);box-shadow:0 0 10px var(--amber-dim)}
.clock{font-family:var(--mono);font-size:12px;font-weight:300;color:var(--steel);font-variant-numeric:tabular-nums}

/* --------------------------------------------------------------- body */
.body{display:grid;grid-template-columns:minmax(0,1.32fr) minmax(0,1fr);gap:16px;min-height:0}
.col{display:grid;gap:16px;min-height:0;min-width:0}
.col.right{grid-template-rows:auto auto minmax(0,1fr)}

.panel{
  position:relative;border:1px solid var(--hair);border-radius:14px;
  background:var(--panel);backdrop-filter:blur(22px);-webkit-backdrop-filter:blur(22px);
  padding:15px 17px;min-height:0;display:flex;flex-direction:column;
  transition:border-color .35s var(--ease);
}
.panel:hover{border-color:var(--hair-lit)}
/* A one-pixel specular line along the top edge. Cheap, and it is most of
   what makes a flat panel read as a surface with a light above it. */
.panel::before{
  content:"";position:absolute;left:14px;right:14px;top:0;height:1px;
  background:linear-gradient(90deg,transparent,rgba(255,255,255,.16),transparent);
}
.phead{display:flex;align-items:baseline;gap:10px;margin-bottom:12px;flex:none}
.ptitle{font-family:var(--mono);font-size:9.5px;font-weight:500;letter-spacing:.26em;color:var(--steel);text-transform:uppercase}
.pnote{font-family:var(--mono);font-size:9.5px;letter-spacing:.1em;color:var(--faint);margin-left:auto;font-variant-numeric:tabular-nums}
.pbody{flex:1;min-height:0;overflow:hidden}

/* ------------------------------------------------------------ slipping */
/* The elapsed time is the subject and the name is the caption, which is the
   inverse of every contact list. The name alone tells you nothing you do not
   already know; the number is the whole point. */
.slip{display:grid;grid-template-columns:auto 1fr;gap:3px 15px;align-items:center}
.srow{display:contents}
.selapsed{
  font-family:var(--mono);font-size:19px;font-weight:300;color:var(--steel);
  text-align:right;font-variant-numeric:tabular-nums;letter-spacing:-.01em;
  transition:color .4s var(--ease);
}
.sbody{
  padding:6px 0;border-bottom:1px solid rgba(255,255,255,.035);min-width:0;
  display:flex;align-items:center;gap:14px;
}
.srow:last-child .sbody{border-bottom:none}
.sname{font-size:13px;color:var(--faint);overflow:hidden;text-overflow:ellipsis;white-space:nowrap;transition:color .4s var(--ease);flex:1;min-width:0}
/* THERE IS NO PROGRESS METER ON THESE ROWS, and it is not an omission.
   Two versions had one, showing how far past their own cadence somebody is.
   It was cut because on this machine, and on any install where nobody has
   hand-set a cadence, every person falls back to the same 330-day default.
   The ratios across the visible twenty then ran 4.21 to 4.09, which draws as
   twenty identical dashes. Rescaling it against the worst row on screen did
   not help: uniform data does not become varied by changing the axis.
   A gauge that always reads the same is decoration wearing the clothes of
   information, and the elapsed figure already carries the magnitude. If
   cadences ever become real per-person values, this is worth revisiting. */
.srow.worst .selapsed{color:var(--amber)}
.srow.worst .sname{color:var(--ice)}
.srow.cold .selapsed{color:var(--ice)}
.srow.cold .sname{color:var(--steel)}

/* --------------------------------------------------------------- pulse */
.pulse{display:flex;align-items:flex-end;gap:3px;height:60px}
.pbar{
  flex:1;background:var(--ghost);border-radius:1.5px;min-height:2px;
  transition:height .8s var(--ease),background .4s var(--ease);
}
.pbar.today{background:var(--amber)}
.paxis{display:flex;justify-content:space-between;margin-top:8px;font-family:var(--mono);font-size:9px;color:var(--faint);letter-spacing:.08em}

/* ------------------------------------------------------------ deadline */
.dl{display:flex;flex-direction:column;gap:0;height:100%;overflow:hidden}
.drow{display:flex;align-items:baseline;gap:12px;padding:7px 0;border-bottom:1px solid rgba(255,255,255,.035)}
.drow:last-child{border-bottom:none}
.din{font-family:var(--mono);font-size:13px;font-weight:400;color:var(--steel);min-width:46px;font-variant-numeric:tabular-nums}
.drow.near .din{color:var(--amber)}
.dwhat{font-size:12px;color:var(--faint);overflow:hidden;text-overflow:ellipsis;white-space:nowrap;flex:1;min-width:0}
.dwho{font-size:12px;color:var(--steel);flex:none}

/* ---------------------------------------------------------- last spoken */
.seen{display:flex;flex-direction:column;overflow:hidden}
.srow2{display:flex;align-items:baseline;gap:12px;padding:5.5px 0;border-bottom:1px solid rgba(255,255,255,.03)}
.srow2:last-child{border-bottom:none}
.s2name{font-size:12.5px;color:var(--steel);overflow:hidden;text-overflow:ellipsis;white-space:nowrap;flex:1;min-width:0}
.s2when{font-family:var(--mono);font-size:10.5px;color:var(--faint);font-variant-numeric:tabular-nums;flex:none}

/* ----------------------------------------------------------- bottom rail */
.counts{display:flex;align-items:center;gap:0;flex:none}
.count{display:flex;align-items:baseline;gap:7px;padding:0 20px;border-right:1px solid var(--hair)}
.count:first-child{padding-left:0}
.count:last-child{border-right:none}
.cn{font-family:var(--mono);font-size:15px;font-weight:400;color:var(--ice);font-variant-numeric:tabular-nums}
.ck{font-family:var(--mono);font-size:9px;letter-spacing:.2em;color:var(--faint);text-transform:uppercase}
.counts .sep{flex:1}
.stamp{font-family:var(--mono);font-size:9px;letter-spacing:.14em;color:var(--ghost);text-transform:uppercase}

.empty{font-size:12px;color:var(--faint);padding:6px 0}

/* Staggered entrance, once, on the first paint only. A list that re-animates
   every thirty seconds is a list nobody can read. */
@keyframes rise{from{opacity:0;transform:translateY(7px)}to{opacity:1;transform:none}}
.in{animation:rise .5s var(--ease) both}

@media (max-width:1100px){
  body{overflow:auto}
  .body{grid-template-columns:1fr}
  .shell{height:auto;min-height:100%}
}
/* A grid item's default min-width is auto, which is its INTRINSIC width, so
   the counts rail (four fixed-padding cells that refuse to wrap) was quietly
   setting the floor for the entire page: 541px of horizontal scroll at 375,
   with every panel dragged out to match. The rail wraps here and the tracks
   are allowed to be narrower than their contents. */
@media (max-width:640px){
  .shell{padding:14px 16px 12px;gap:12px}
  .shell > *, .body > *, .col > *{min-width:0}
  .rail{flex-wrap:wrap;gap:10px}
  .rail .sep{display:none}
  .clock{margin-left:auto}
  .counts{flex-wrap:wrap;gap:8px 0}
  .count{padding:0 14px}
  .count:first-child{padding-left:0}
  .counts .sep{display:none}
  .stamp{width:100%;padding-top:6px}
  .selapsed{font-size:16px}
  .dwho{display:none}
}
</style></head><body>
<div class="shell">
  <header class="rail">
    <div class="mark">CHEWBACCA</div>
    <div class="chip"><span class="tx" id="tx"></span><span id="host">local</span></div>
    <div class="sep"></div>
    <div class="clock" id="clock"></div>
  </header>

  <div class="body">
    <div class="col">
      <section class="panel" style="flex:1">
        <div class="phead"><span class="ptitle">Slipping</span><span class="pnote" id="slipnote"></span></div>
        <div class="pbody"><div class="slip" id="slip"></div></div>
      </section>
    </div>
    <div class="col right">
      <section class="panel">
        <div class="phead"><span class="ptitle">Pulse</span><span class="pnote" id="pulsenote"></span></div>
        <div class="pulse" id="pulse"></div>
        <div class="paxis"><span id="paxisa"></span><span id="paxisb"></span></div>
      </section>
      <section class="panel">
        <div class="phead"><span class="ptitle">Ahead</span><span class="pnote" id="dlnote"></span></div>
        <div class="pbody"><div class="dl" id="dl"></div></div>
      </section>
      <section class="panel">
        <div class="phead"><span class="ptitle">Last spoken to</span><span class="pnote" id="seennote"></span></div>
        <div class="pbody"><div class="seen" id="seen"></div></div>
      </section>
    </div>
  </div>

  <footer class="counts" id="counts"></footer>
</div>
<script>
const esc = s => String(s == null ? "" : s).replace(/[&<>"]/g, c => ({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;"}[c]));
const num = n => Number(n || 0).toLocaleString();
const $ = id => document.getElementById(id);

function tick(){
  $("clock").textContent = new Date().toLocaleTimeString([], {hour:"2-digit", minute:"2-digit", second:"2-digit", hour12:false});
}
setInterval(tick, 1000); tick();

// 1720 is a number nobody feels. "4y 8m" is the same fact in the unit a
// person actually thinks in, and that conversion is most of the difference
// between a readout and a sentence.
function since(days){
  if (days == null) return "never";
  if (days < 60) return days + "d";
  var months = Math.round(days / 30.44);
  if (months < 24) return months + "mo";
  var years = Math.floor(days / 365.25);
  var rem = Math.round((days - years * 365.25) / 30.44);
  return rem ? years + "y " + rem + "m" : years + "y";
}

// A wall-clock stamp is precise and unreadable at a glance. These rows are
// scanned, not studied, so they get the distance instead of the coordinate.
function ago(ts){
  if (!ts) return "";
  var then = new Date(String(ts).replace(" ", "T")).getTime();
  if (!then) return "";
  var mins = Math.max(0, Math.round((Date.now() - then) / 60000));
  if (mins < 60) return mins + "m";
  if (mins < 60 * 24) return Math.round(mins / 60) + "h";
  return Math.round(mins / 1440) + "d";
}

// Counts up only when the value on screen is not already the value being
// set. Re-running the animation every poll turns a steady number into a
// flicker and makes the whole surface feel unreliable.
function settle(el, value){
  var prev = Number(el.dataset.v || 0);
  if (prev === value) return;
  el.dataset.v = value;
  var from = prev, delta = value - from, t0 = performance.now(), ms = 620;
  function step(now){
    var k = Math.min(1, (now - t0) / ms);
    var eased = 1 - Math.pow(1 - k, 3);
    el.textContent = num(Math.round(from + delta * eased));
    if (k < 1) requestAnimationFrame(step);
  }
  requestAnimationFrame(step);
}

var first = true;

function render(d){
  $("host").textContent = d.host || "local";

  // ------------------------------------------------------------ slipping
  var slip = $("slip");
  var rows = d.overdue || [];
  var total = d.overdueTotal || rows.length;
  $("slipnote").textContent = total
    ? (total > rows.length ? rows.length + " of " + num(total) : total + " overdue")
    : "";
  if (!rows.length) {
    slip.innerHTML = '<div class="empty">Nobody is overdue.</div>';
  } else {
    slip.innerHTML = rows.map(function(r, i){
      var cls = i === 0 ? "worst" : (r.days >= 365 ? "cold" : "");
      var delay = first ? ' style="animation-delay:' + (i * 42) + 'ms"' : '';
      return '<div class="srow ' + cls + (first ? ' in' : '') + '"' + delay + '>' +
        '<div class="selapsed">' + esc(since(r.days)) + '</div>' +
        '<div class="sbody"><div class="sname">' + esc(r.name) + '</div></div>' +
      '</div>';
    }).join("");
  }

  // --------------------------------------------------------------- pulse
  var p = d.pulse || [];
  var peak = Math.max(1, Math.max.apply(null, p.map(function(x){ return x.n; })));
  $("pulse").innerHTML = p.map(function(x, i){
    var h = Math.max(2, Math.round((x.n / peak) * 60));
    var last = i === p.length - 1;
    return '<div class="pbar' + (last ? " today" : "") + '" style="height:' + h + 'px" title="' + esc(x.day) + ': ' + x.n + '"></div>';
  }).join("");
  // Labelled with the window it actually plots. The old version printed the
  // full history span here while charting the last 21 days, so the panel
  // disagreed with itself and the chart was the honest half.
  $("pulsenote").textContent = peak + " peak";
  $("paxisa").textContent = p.length ? p[0].day.slice(5) : "";
  $("paxisb").textContent = "today";

  // ------------------------------------------------------------ deadlines
  var dl = d.deadlines || [];
  $("dlnote").textContent = dl.length ? dl.length + " tracked" : "";
  $("dl").innerHTML = dl.length ? dl.slice(0, 6).map(function(x){
    return '<div class="drow' + (x.days != null && x.days <= 30 ? " near" : "") + '">' +
      '<div class="din">' + (x.days == null ? "—" : esc(x.days) + "d") + '</div>' +
      '<div class="dwhat">' + esc(x.what || "") + '</div>' +
      '<div class="dwho">' + esc(x.org || "") + '</div></div>';
  }).join("") : '<div class="empty">Nothing dated.</div>';

  // ----------------------------------------------------------- last seen
  var seen = d.recent || [];
  $("seennote").textContent = seen.length ? seen.length + " threads" : "";
  $("seen").innerHTML = seen.length
    ? seen.map(function(r){
        return '<div class="srow2"><div class="s2name">' + esc(r.name) + '</div>' +
               '<div class="s2when">' + esc(ago(r.t)) + '</div></div>';
      }).join("")
    : '<div class="empty">No conversations on file.</div>';

  // --------------------------------------------------------------- counts
  var counts = $("counts");
  if (!counts.dataset.built) {
    counts.dataset.built = "1";
    var spec = [["messages","Messages"],["people","People"],["skills","Skills"],["kitcount","Kits"]];
    counts.innerHTML = spec.map(function(s){
      return '<div class="count"><span class="cn" id="c-' + s[0] + '">0</span><span class="ck">' + s[1] + '</span></div>';
    }).join("") + '<div class="sep"></div><div class="stamp" id="stamp"></div>';
  }
  settle($("c-messages"), d.messages || 0);
  settle($("c-people"), d.people || 0);
  settle($("c-skills"), (d.repo && d.repo.skills) || 0);
  settle($("c-kitcount"), (d.kits || []).length);
  $("stamp").textContent = "loopback · " + new Date().toLocaleTimeString([], {hour:"2-digit",minute:"2-digit",hour12:false});

  first = false;
}

async function load(){
  var tx = $("tx");
  tx.classList.add("on");
  try {
    render(await (await fetch("/api/state")).json());
  } catch (e) {
    $("slip").innerHTML = '<div class="empty">' + esc(e.message) + '</div>';
  } finally {
    setTimeout(function(){ tx.classList.remove("on"); }, 260);
  }
}
load();
setInterval(load, 30000);
</script></body></html>`;

function serve({ port = 7474, host = "127.0.0.1", onReady }) {
  const server = http.createServer((req, res) => {
    if (req.url.startsWith("/api/state")) {
      res.writeHead(200, { "content-type": "application/json" });
      res.end(JSON.stringify(snapshot()));
      return;
    }
    if (req.url === "/" || req.url.startsWith("/?")) {
      res.writeHead(200, { "content-type": "text/html; charset=utf-8" });
      res.end(PAGE);
      return;
    }
    res.writeHead(404, { "content-type": "text/plain" });
    res.end("not found");
  });
  server.listen(port, host, () => onReady(server));
  return server;
}

module.exports = { serve, snapshot };

if (require.main === module) {
  const port = Number(process.env.CHEWBACCA_HUD_PORT || 7474);
  if (process.argv.includes("--json")) {
    console.log(JSON.stringify(snapshot(), null, 2));
  } else {
    serve({
      port,
      onReady: () => {
        const url = `http://localhost:${port}`;
        console.log(`  chewbacca is open at ${url}`);
        try {
          execFileSync("open", [url]);
        } catch {
          /* headless, the URL above is the whole answer */
        }
      },
    });
  }
}
