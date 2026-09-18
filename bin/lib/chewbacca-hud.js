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
function overdue(db, limit = 8) {
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
  return out.slice(0, limit);
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
    pulse: [],
    recent: [],
    range: null,
  };
  if (db) {
    base.people =
      q1(db, "SELECT count(*) AS n FROM people WHERE deleted_at IS NULL").n ||
      0;
    base.messages = q1(db, "SELECT count(*) AS n FROM messages").n || 0;
    base.overdue = overdue(db);
    base.pulse = pulse(db);
    base.recent = q(
      db,
      `SELECT p.name, max(m.sent_at) AS t FROM messages m JOIN people p ON p.id = m.person_id
        WHERE m.room IS NULL GROUP BY p.id ORDER BY t DESC LIMIT 6`,
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

const PAGE = `<!doctype html>
<html lang="en"><head>
<meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Chewbacca</title>
<link rel="icon" href="data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 32 32'%3E%3Ccircle cx='16' cy='16' r='13' fill='none' stroke='%23f0b429' stroke-width='3'/%3E%3Ccircle cx='16' cy='16' r='5' fill='%23f0b429'/%3E%3C/svg%3E">
<link rel="preconnect" href="https://fonts.googleapis.com">
<link href="https://fonts.googleapis.com/css2?family=Inter:wght@300;400;500;600;700;800;900&display=swap" rel="stylesheet">
<style>
:root{
  --bg:#08080a; --panel:rgba(255,255,255,.035); --line:rgba(255,255,255,.08);
  --ink:#fafafa; --mute:#71717a; --dim:#a1a1aa;
  --accent:#f0b429; --accent-dim:rgba(240,180,41,.14); --bad:#f87171;
}
*{box-sizing:border-box;margin:0;padding:0}
html,body{height:100%}
body{
  background:var(--bg); color:var(--ink);
  font-family:Inter,ui-sans-serif,system-ui,sans-serif; -webkit-font-smoothing:antialiased;
  overflow-x:hidden;
}
/* Three stacked radials plus a hairline grid. A flat panel on flat black reads
   as a terminal; the grid is what makes it read as an instrument. */
body::before{
  content:"";position:fixed;inset:0;pointer-events:none;z-index:0;
  background:
    radial-gradient(900px 600px at 15% -10%, rgba(240,180,41,.10), transparent 60%),
    radial-gradient(700px 500px at 100% 0%, rgba(99,102,241,.10), transparent 55%),
    radial-gradient(1000px 700px at 50% 120%, rgba(240,180,41,.05), transparent 60%);
}
body::after{
  content:"";position:fixed;inset:0;pointer-events:none;z-index:0;opacity:.35;
  background-image:linear-gradient(var(--line) 1px,transparent 1px),linear-gradient(90deg,var(--line) 1px,transparent 1px);
  background-size:64px 64px;
  mask-image:radial-gradient(circle at 50% 30%,#000 0%,transparent 75%);
}
.wrap{position:relative;z-index:1;max-width:1400px;margin:0 auto;padding:28px 16px 64px}
header{display:flex;align-items:baseline;gap:16px;flex-wrap:wrap;margin-bottom:34px}
.mark{
  font-size:clamp(28px,4.2vw,46px);font-weight:900;letter-spacing:-.04em;
  background:linear-gradient(105deg,#fff 0%,#fff 40%,var(--accent) 100%);
  -webkit-background-clip:text;background-clip:text;color:transparent;
}
.host{font-size:12px;color:var(--mute);letter-spacing:.14em;text-transform:uppercase}
.clock{margin-left:auto;font-variant-numeric:tabular-nums;font-weight:600;color:var(--dim);font-size:14px}
.dot{display:inline-block;width:7px;height:7px;border-radius:99px;background:var(--accent);
  box-shadow:0 0 12px var(--accent);margin-right:8px;animation:beat 2.4s ease-in-out infinite}
@keyframes beat{0%,100%{opacity:1}50%{opacity:.35}}

.stats{display:grid;grid-template-columns:repeat(auto-fit,minmax(150px,1fr));gap:12px;margin-bottom:26px}
.stat{padding:18px 20px;border:1px solid var(--line);border-radius:18px;background:var(--panel);
  backdrop-filter:blur(14px);transition:border-color .2s,transform .2s}
.stat:hover{border-color:rgba(240,180,41,.35);transform:translateY(-2px)}
.stat .n{font-size:clamp(26px,3.4vw,40px);font-weight:800;letter-spacing:-.035em;
  font-variant-numeric:tabular-nums;line-height:1.05;
  background:linear-gradient(180deg,#fff,#a1a1aa);-webkit-background-clip:text;background-clip:text;color:transparent}
.stat .n.hot{background:linear-gradient(180deg,var(--accent),#b45309);-webkit-background-clip:text;background-clip:text;color:transparent}
.stat .k{margin-top:7px;font-size:10.5px;letter-spacing:.16em;text-transform:uppercase;color:var(--mute)}

.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(330px,1fr));gap:14px;align-items:start}
.card{border:1px solid var(--line);border-radius:20px;background:var(--panel);backdrop-filter:blur(14px);
  padding:20px 22px;transition:border-color .2s}
.card:hover{border-color:rgba(255,255,255,.16)}
.card h2{font-size:10.5px;letter-spacing:.18em;text-transform:uppercase;color:var(--mute);
  font-weight:600;margin-bottom:16px;display:flex;align-items:center;gap:8px}
.card h2 .pill{margin-left:auto;font-size:10px;letter-spacing:.06em;text-transform:none;
  color:var(--accent);background:var(--accent-dim);border:1px solid rgba(240,180,41,.24);
  padding:2px 9px;border-radius:99px}
.wide{grid-column:1/-1}

.row{display:flex;align-items:center;gap:12px;padding:9px 0;border-bottom:1px solid rgba(255,255,255,.05)}
.row:last-child{border-bottom:0}
.row .nm{font-weight:500;font-size:14px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.row .sub{font-size:11.5px;color:var(--mute);margin-left:auto;white-space:nowrap;font-variant-numeric:tabular-nums}
.meter{height:4px;border-radius:99px;background:rgba(255,255,255,.07);overflow:hidden;width:76px;flex:none}
.meter i{display:block;height:100%;border-radius:99px;background:linear-gradient(90deg,var(--accent),#ef4444)}

.spark{display:flex;align-items:flex-end;gap:3px;height:76px;margin-top:4px}
.spark i{flex:1;border-radius:3px 3px 0 0;background:linear-gradient(180deg,var(--accent),rgba(240,180,41,.18));
  min-height:2px;transition:opacity .2s}
.spark i:hover{opacity:.6}
.axis{display:flex;justify-content:space-between;margin-top:8px;font-size:10.5px;color:var(--mute)}

.dl{display:flex;align-items:center;gap:14px;padding:11px 0;border-bottom:1px solid rgba(255,255,255,.05)}
.dl:last-child{border-bottom:0}
.dl .when{font-variant-numeric:tabular-nums;font-weight:700;font-size:15px;min-width:62px}
.dl .when.soon{color:var(--bad)}
.dl .what{font-size:13px;color:var(--dim);line-height:1.35}
.dl .what b{color:var(--ink);font-weight:600;display:block;font-size:13.5px}
.dl .date{margin-left:auto;font-size:11px;color:var(--mute);white-space:nowrap}

.chips{display:flex;flex-wrap:wrap;gap:7px}
.chip{font-size:11.5px;color:var(--dim);border:1px solid var(--line);background:rgba(255,255,255,.03);
  padding:5px 11px;border-radius:99px}
.chip.on{color:var(--accent);border-color:rgba(240,180,41,.3);background:var(--accent-dim)}
.empty{font-size:13px;color:var(--mute);padding:8px 0}
footer{margin-top:30px;font-size:11px;color:var(--mute);text-align:center;letter-spacing:.05em}

.boot{animation:rise .55s cubic-bezier(.2,.7,.3,1) backwards}
@keyframes rise{from{opacity:0;transform:translateY(14px)}to{opacity:1;transform:none}}
@media (max-width:640px){.wrap{padding:20px 16px 48px}.clock{width:100%;margin:6px 0 0}}
</style></head><body>
<div class="wrap">
  <header class="boot">
    <div class="mark">CHEWBACCA</div>
    <div class="host"><span class="dot"></span><span id="host">local</span></div>
    <div class="clock" id="clock"></div>
  </header>
  <div class="stats" id="stats"></div>
  <div class="grid" id="grid"></div>
  <footer>loopback only &middot; <span id="stamp"></span></footer>
</div>
<script>
const esc = s => String(s == null ? "" : s).replace(/[&<>"]/g, c => ({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;"}[c]));
const num = n => Number(n || 0).toLocaleString();

function tick(){
  document.getElementById("clock").textContent =
    new Date().toLocaleTimeString([], {hour:"numeric", minute:"2-digit", second:"2-digit"});
}
setInterval(tick, 1000); tick();

function stat(n, k, hot){
  return '<div class="stat boot"><div class="n' + (hot ? " hot" : "") + '">' + esc(n) + '</div><div class="k">' + esc(k) + '</div></div>';
}

function render(d){
  document.getElementById("host").textContent = d.host;
  document.getElementById("stamp").textContent =
    "refreshed " + new Date(d.at).toLocaleTimeString([], {hour:"numeric", minute:"2-digit"});

  document.getElementById("stats").innerHTML =
    stat(num(d.messages), "messages") +
    stat(num(d.people), "people") +
    stat(d.overdue.length, "slipping", d.overdue.length > 0) +
    stat(d.kits.length, "kits") +
    stat(d.repo.skills, "skills") +
    stat(d.repo.version, "version");

  const cards = [];

  const peak = Math.max(1, ...d.pulse.map(p => p.n));
  cards.push('<div class="card wide boot"><h2>Signal' +
    (d.range ? '<span class="pill">' + esc(d.range) + '</span>' : '') + '</h2>' +
    '<div class="spark">' + d.pulse.map(p =>
      '<i style="height:' + Math.max(2, Math.round(p.n / peak * 100)) + '%" title="' +
      esc(p.day) + ': ' + p.n + '"></i>').join("") + '</div>' +
    '<div class="axis"><span>' + esc(d.pulse[0] ? d.pulse[0].day : "") +
    '</span><span>' + num(peak) + ' peak</span><span>today</span></div></div>');

  cards.push('<div class="card boot"><h2>Slipping' +
    (d.overdue.length ? '<span class="pill">' + d.overdue.length + '</span>' : '') + '</h2>' +
    (d.overdue.length ? d.overdue.map(p => {
      const ratio = Math.min(1, p.over / Math.max(1, p.cadence * 2));
      return '<div class="row"><span class="nm">' + esc(p.name) + '</span>' +
        '<span class="meter"><i style="width:' + Math.round(ratio * 100) + '%"></i></span>' +
        '<span class="sub">' + p.days + 'd</span></div>';
    }).join("") : '<div class="empty">Nobody is past their cadence.</div>') + '</div>');

  cards.push('<div class="card boot"><h2>Ahead of you' +
    (d.deadlines.length ? '<span class="pill">next ' + d.deadlines.length + '</span>' : '') + '</h2>' +
    (d.deadlines.length ? d.deadlines.map(x =>
      '<div class="dl"><span class="when' + (x.days <= 30 ? " soon" : "") + '">' + x.days + 'd</span>' +
      '<span class="what"><b>' + esc(x.org) + '</b>' + esc(x.what) + '</span>' +
      '<span class="date">' + esc(x.date) + '</span></div>').join("")
      : '<div class="empty">No dated rows in any kit.</div>') + '</div>');

  cards.push('<div class="card boot"><h2>Last spoken to</h2>' +
    (d.recent.length ? d.recent.map(r =>
      '<div class="row"><span class="nm">' + esc(r.name) + '</span>' +
      '<span class="sub">' + esc(String(r.t).slice(0, 10)) + '</span></div>').join("")
      : '<div class="empty">No message history synced.</div>') + '</div>');

  cards.push('<div class="card boot"><h2>The kit<span class="pill">' + esc(d.repo.branch) + '</span></h2>' +
    '<div class="chips">' +
    '<span class="chip' + (d.repo.dirty ? " on" : "") + '">' + d.repo.dirty + ' uncommitted</span>' +
    '<span class="chip' + (d.repo.ahead ? " on" : "") + '">' + d.repo.ahead + ' unpushed</span>' +
    d.kits.map(k => '<span class="chip">' + esc(k) + '</span>').join("") +
    '</div></div>');

  document.getElementById("grid").innerHTML = cards.join("");
}

async function load(){
  try {
    render(await (await fetch("/api/state")).json());
  } catch (e) {
    document.getElementById("grid").innerHTML =
      '<div class="card"><h2>Offline</h2><div class="empty">' + esc(e.message) + '</div></div>';
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
