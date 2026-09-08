// @ts-nocheck
/**
 * people dashboard: who you have actually been talking to, ranked by recency.
 *
 * The categorisation here is not inferred and not guessed. It reads the tags
 * already sitting in the contact names, because a person who writes
 * "Sid Chowdhury A2F USC IYA" into their phone has already done the labelling
 * work and knows what those letters mean. Translating "Nemmy" into
 * "Nemirovsky Residential College" would be an invention; the tag is displayed
 * as written.
 *
 * Zero dependencies, same as the CLI it hangs off. Node's own http server.
 */

"use strict";

const http = require("node:http");
const { execFile } = require("node:child_process");

// ---------------------------------------------------------------- tags
//
// group drives the colour and the filter row. label is what shows on the badge.
// Order matters only for `primary`, which decides the heading a person sits
// under in grouped view: the first match in this list wins.
const TAGS = [
  { key: "IYA", label: "IYA", group: "school", match: /\bIYA\b/i },

  { key: "A2F", label: "A2F", group: "faith", match: /\bA2F\b/i },
  { key: "CHALLENGE", label: "Christian Challenge", group: "faith", match: /\bChallenge\b/i },
  { key: "AGO", label: "AGO", group: "faith", match: /\bAGO\b/i },
  { key: "BUAI", label: "BUAI", group: "faith", match: /\bBUAI\b/i },
  { key: "OASIS", label: "Oasis", group: "faith", match: /\bOasis\b/i },
  { key: "CATHOLIC", label: "Catholic", group: "faith", match: /\bCatholic\b/i },
  { key: "ACTS", label: "ACTS", group: "faith", match: /\bACTS\b/ },
  // "Christian" is a first name as often as it is a label. Only a later token
  // counts, so "Christian Stiker IYA" stays a person and "Gabriel Christian
  // Bro USC" picks up the tag.
  { key: "CHRISTIAN", label: "Christian", group: "faith", match: /\S+\s+.*\bChristian\b/i },

  { key: "KTP", label: "KTP", group: "club", match: /\bKTP\b/i },
  { key: "SEP", label: "SEP", group: "club", match: /\bSEP\b/i },
  { key: "180", label: "180DC", group: "club", match: /\b180\b/ },
  { key: "BTG", label: "BTG", group: "club", match: /\bBTG\b/i },
  { key: "RISE", label: "RISE", group: "club", match: /\bRISE\b/i },
  // Maia is a first name as well as a club. Same rule as Christian below:
  // only a token after the first one counts as the label.
  { key: "MAIA", label: "MAIA", group: "club", match: /\S+\s+.*\bMAIA\b/i },
  { key: "FLAVORS", label: "Flavors", group: "club", match: /\bFlavou?rs\b/i },
  { key: "TROYCAMP", label: "Troy Camp", group: "club", match: /\bTroy ?camp\b/i },
  { key: "LAVA", label: "LAVA", group: "club", match: /\bLAVA\b/i },
  { key: "SHIFT", label: "Shift", group: "club", match: /\bShift\b/i },

  { key: "NEMMY", label: "Nemmy", group: "housing", match: /\bNemmy\b/i },
  { key: "AVENUES", label: "Avenues", group: "housing", match: /\bAvenues\b/i },

  { key: "BISC", label: "BISC", group: "class", match: /\bBISC\b/i },
  { key: "GESM", label: "GESM", group: "class", match: /\bGESM\b/i },
  { key: "ACAD", label: "ACAD", group: "class", match: /\bACAD\b/i },
  { key: "WRIT", label: "WRIT", group: "class", match: /\bWRIT\b/i },
  { key: "COGSCI", label: "CogSci", group: "class", match: /\bCogsci\b/i },

  { key: "BASEBALL", label: "Baseball", group: "sport", match: /\bBaseball\b/i },

  { key: "MARSHALL", label: "Marshall", group: "school", match: /\bMarshall\b/i },
  { key: "VITERBI", label: "Viterbi", group: "school", match: /\bViterbi\b/i },
  { key: "SCA", label: "SCA", group: "school", match: /\bSCA\b/ },
  { key: "USC", label: "USC", group: "school", match: /\bUSC\b/i },
];

// Tokens that are a label rather than part of somebody's name, stripped from
// the display name so the badges carry the meaning and the name stays a name.
//
// HARD is safe to remove anywhere. SOFT is the list that is also somebody's
// given name: "Maia IYA" and "Christian Stiker IYA" are both real people whose
// names were being eaten, so a soft label only counts after the first token.
const HARD = [
  "USC", "IYA", "A2F", "AGO", "BUAI", "KTP", "SEP", "BTG", "RISE", "LAVA",
  "SCA", "BISC", "GESM", "ACAD", "WRIT", "MPGU", "BME", "Cogsci", "Nemmy",
  "Avenues", "Flavou?rs", "Troy ?camp", "Marshall", "Viterbi", "Leavey",
  "Baseball", "Oasis", "Catholic", "ACTS", "Challenge", "Shift",
  "Bro", "Bros", "Dude", "Prez", "Club", "Goat", "Cracked", "Jacked", "Frat",
  "Reality", "180", "Consulting",
];
const SOFT = ["Christian", "Maia", "Faith", "Grace", "Hope", "Man"];

const HARD_RE = new RegExp("\\b(" + HARD.join("|") + ")\\b", "gi");
const SOFT_RE = new RegExp("\\b(" + SOFT.join("|") + ")\\b", "gi");

function tagsFor(name) {
  const hits = [];
  for (const t of TAGS) if (t.match.test(name)) hits.push(t);
  return hits;
}

function displayName(name) {
  const parts = String(name).trim().split(/\s+/);
  const first = parts[0] || "";
  const rest = parts.slice(1).join(" ");
  const cleaned = (first + " " + rest.replace(HARD_RE, " ").replace(SOFT_RE, " "))
    .replace(/\s+/g, " ")
    .replace(/^[\s,\-]+|[\s,\-]+$/g, "")
    .trim();
  // The first token is kept even when it is a label, so an entry saved purely
  // as a label ("USC Christian Challenge") survives as itself rather than
  // becoming the single word "USC".
  const firstIsLabel = new RegExp("^(" + HARD.join("|") + ")$", "i").test(first);
  if (firstIsLabel || cleaned.length < 2) return name;
  return cleaned;
}

// ---------------------------------------------------------------- data

function collect(d, opts = {}) {
  const rows = d
    .prepare(
      `SELECT p.id, p.name, p.phone, p.email,
              MAX(m.sent_at)                                   AS last_at,
              COUNT(*)                                         AS total,
              SUM(CASE WHEN m.sent_at >= date('now','-30 day') THEN 1 ELSE 0 END) AS recent
         FROM people p
         JOIN messages m ON m.person_id = p.id
        WHERE p.deleted_at IS NULL
        GROUP BY p.id`,
    )
    .all();

  const lastBody = d.prepare(
    `SELECT body, from_me, sent_at FROM messages
      WHERE person_id = ? ORDER BY sent_at DESC, msg_id DESC LIMIT 1`,
  );

  const out = [];
  for (const r of rows) {
    const tags = tagsFor(r.name);
    // The scope is the question he asked: USC or IYA. Everyone else is a real
    // person but not this list.
    if (!tags.some((t) => t.key === "USC" || t.key === "IYA")) continue;
    const last = lastBody.get(r.id) || {};
    const primary = tags.find((t) => t.key !== "USC") || tags[0];
    out.push({
      id: r.id,
      name: displayName(r.name),
      raw: r.name,
      phone: r.phone || null,
      tags: tags.map((t) => ({ label: t.label, group: t.group, key: t.key })),
      primary: primary ? primary.label : "USC",
      primaryKey: primary ? primary.key : "USC",
      lastAt: r.last_at,
      fromMe: last.from_me === 1,
      preview: (last.body || "").replace(/\s+/g, " ").slice(0, 160),
      total: r.total,
      recent: r.recent,
    });
  }
  out.sort((a, b) => (a.lastAt < b.lastAt ? 1 : a.lastAt > b.lastAt ? -1 : 0));
  return out;
}

// ---------------------------------------------------------------- page

const PAGE = String.raw`<!doctype html>
<html lang="en" class="dark">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Who I've been texting</title>
<link rel="icon" href="data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 32 32'%3E%3Crect width='32' height='32' rx='8' fill='%236366f1'/%3E%3Ccircle cx='16' cy='12' r='5' fill='white'/%3E%3Cpath d='M6 28a10 10 0 0 1 20 0z' fill='white'/%3E%3C/svg%3E">
<script src="https://cdn.tailwindcss.com"></script>
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700&display=swap" rel="stylesheet">
<style>
  body { font-family: Inter, ui-sans-serif, system-ui, sans-serif; }
  ::-webkit-scrollbar { width: 10px; height: 10px; }
  ::-webkit-scrollbar-track { background: #09090b; }
  ::-webkit-scrollbar-thumb { background: #27272a; border-radius: 8px; }
  ::-webkit-scrollbar-thumb:hover { background: #3f3f46; }
</style>
</head>
<body class="antialiased bg-zinc-950 text-zinc-100 min-h-screen">
<div class="fixed inset-0 -z-10 bg-[radial-gradient(ellipse_at_top,_var(--tw-gradient-stops))] from-indigo-900/20 via-zinc-950 to-zinc-950"></div>

<header class="sticky top-0 z-20 border-b border-white/10 bg-zinc-950/80 backdrop-blur-md">
  <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-4">
    <div class="flex flex-wrap items-center gap-4">
      <div class="mr-auto">
        <h1 class="text-xl font-semibold tracking-tight">Who I've been texting</h1>
        <p class="text-sm text-zinc-500" id="sub">loading…</p>
      </div>
      <input id="q" placeholder="Search a name or a tag…" autocomplete="off"
        class="bg-zinc-900 border border-zinc-700 rounded-xl px-4 py-2.5 text-white placeholder-zinc-500 focus:outline-none focus:ring-2 focus:ring-indigo-500 focus:border-transparent transition-all duration-200 w-full sm:w-72">
      <button id="mode"
        class="bg-zinc-800 hover:bg-zinc-700 border border-zinc-700 text-zinc-100 font-medium px-5 py-2.5 rounded-xl transition-all duration-200 cursor-pointer whitespace-nowrap">Group by category</button>
      <button id="sync"
        class="bg-indigo-600 hover:bg-indigo-500 active:bg-indigo-700 text-white font-semibold px-5 py-2.5 rounded-xl transition-all duration-200 shadow-lg shadow-indigo-500/25 cursor-pointer whitespace-nowrap">Refresh</button>
    </div>
    <div id="chips" class="flex flex-nowrap overflow-x-auto sm:flex-wrap sm:overflow-visible gap-2 pt-4 -mx-4 px-4 sm:mx-0 sm:px-0 [scrollbar-width:none] [&::-webkit-scrollbar]:hidden"></div>
  </div>
</header>

<main class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
  <div id="list" class="space-y-2"></div>
  <p id="empty" class="hidden text-center text-zinc-500 py-24">Nobody matches that.</p>
</main>

<script>
const GROUP_STYLE = {
  school:  "bg-indigo-500/10 text-indigo-300 border-indigo-500/20",
  faith:   "bg-amber-500/10 text-amber-300 border-amber-500/20",
  club:    "bg-emerald-500/10 text-emerald-300 border-emerald-500/20",
  housing: "bg-sky-500/10 text-sky-300 border-sky-500/20",
  class:   "bg-violet-500/10 text-violet-300 border-violet-500/20",
  sport:   "bg-rose-500/10 text-rose-300 border-rose-500/20",
};
let DATA = [], FILTER = null, GROUPED = false;

// sent_at has no timezone suffix and is already local, so it must not be
// parsed as UTC. Splitting the parts avoids the browser guessing.
function toDate(s) {
  const [d, t] = s.split(" ");
  const [Y, M, D] = d.split("-").map(Number);
  const [h, m] = (t || "0:0").split(":").map(Number);
  return new Date(Y, M - 1, D, h, m);
}
function ago(s) {
  const mins = Math.max(0, (Date.now() - toDate(s)) / 60000);
  if (mins < 1) return "now";
  if (mins < 60) return Math.round(mins) + "m";
  if (mins < 60 * 24) return Math.round(mins / 60) + "h";
  const days = mins / 1440;
  if (days < 7) return Math.round(days) + "d";
  if (days < 60) return Math.round(days / 7) + "w";
  if (days < 365) return Math.round(days / 30) + "mo";
  return (days / 365).toFixed(1) + "y";
}
function bucket(s) {
  const days = (Date.now() - toDate(s)) / 86400000;
  if (days < 1) return "Today";
  if (days < 2) return "Yesterday";
  if (days < 7) return "This week";
  if (days < 30) return "This month";
  if (days < 90) return "Last three months";
  if (days < 365) return "This year";
  return "Over a year ago";
}
function esc(s) {
  return String(s).replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c]));
}

function badge(t) {
  const cls = GROUP_STYLE[t.group] || GROUP_STYLE.school;
  return '<span class="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium border ' + cls + '">' + esc(t.label) + "</span>";
}

function row(p, rank) {
  const stale = (Date.now() - toDate(p.lastAt)) / 86400000 > 30;
  return (
    '<div class="group flex items-center gap-4 bg-zinc-900/60 border border-zinc-800 rounded-2xl px-5 py-4 hover:border-zinc-700 hover:bg-zinc-900 transition-all duration-200">' +
      '<div class="w-8 shrink-0 text-sm tabular-nums text-zinc-600 font-medium">' + rank + "</div>" +
      '<div class="min-w-0 flex-1">' +
        '<div class="flex flex-wrap items-center gap-2">' +
          '<span class="font-semibold truncate">' + esc(p.name) + "</span>" +
          p.tags.map(badge).join("") +
        "</div>" +
        '<p class="text-sm text-zinc-500 truncate pt-1">' +
          (p.preview ? '<span class="text-zinc-600">' + (p.fromMe ? "you: " : "") + "</span>" + esc(p.preview) : '<span class="text-zinc-700">no text body</span>') +
        "</p>" +
      "</div>" +
      '<div class="text-right shrink-0">' +
        '<div class="text-sm font-semibold tabular-nums ' + (stale ? "text-zinc-500" : "text-indigo-400") + '">' + ago(p.lastAt) + "</div>" +
        '<div class="text-xs text-zinc-600 tabular-nums">' + p.recent + " in 30d</div>" +
      "</div>" +
    "</div>"
  );
}

function render() {
  const q = document.getElementById("q").value.trim().toLowerCase();
  let rows = DATA.filter((p) => {
    if (FILTER && !p.tags.some((t) => t.key === FILTER)) return false;
    if (!q) return true;
    return (p.name + " " + p.raw + " " + p.tags.map((t) => t.label).join(" ")).toLowerCase().includes(q);
  });

  const list = document.getElementById("list");
  document.getElementById("empty").classList.toggle("hidden", rows.length > 0);

  const head = (text, count) =>
    '<div class="flex items-baseline gap-3 pt-8 pb-3 first:pt-0">' +
      '<h2 class="text-sm font-semibold uppercase tracking-wider text-zinc-400">' + esc(text) + "</h2>" +
      '<span class="text-xs text-zinc-600 tabular-nums">' + count + "</span>" +
      '<div class="flex-1 h-px bg-zinc-800"></div>' +
    "</div>";

  let html = "";
  if (GROUPED) {
    const by = new Map();
    for (const p of rows) {
      if (!by.has(p.primary)) by.set(p.primary, []);
      by.get(p.primary).push(p);
    }
    // Categories are ordered by whoever inside them was texted most recently,
    // so the group he is actually in the middle of talking to sits at the top.
    const order = [...by.entries()].sort((a, b) => (a[1][0].lastAt < b[1][0].lastAt ? 1 : -1));
    for (const [cat, people] of order) {
      html += head(cat, people.length);
      html += people.map((p, i) => row(p, i + 1)).join("");
    }
  } else {
    let last = null;
    rows.forEach((p, i) => {
      const b = bucket(p.lastAt);
      if (b !== last) {
        html += head(b, rows.filter((x) => bucket(x.lastAt) === b).length);
        last = b;
      }
      html += row(p, i + 1);
    });
  }
  list.innerHTML = html;
}

function chips() {
  const counts = new Map();
  for (const p of DATA) for (const t of p.tags) {
    if (!counts.has(t.key)) counts.set(t.key, { ...t, n: 0 });
    counts.get(t.key).n++;
  }
  const all = [...counts.values()].sort((a, b) => b.n - a.n);
  const box = document.getElementById("chips");
  const mk = (key, label, n, active) =>
    '<button data-k="' + (key || "") + '" class="chip shrink-0 inline-flex items-center gap-2 px-3 py-1.5 rounded-full text-xs font-medium border transition-all duration-200 cursor-pointer ' +
      (active ? "bg-indigo-600 text-white border-indigo-500" : "bg-white/5 text-zinc-400 border-white/10 hover:text-white hover:bg-white/10") +
      '">' + esc(label) + '<span class="tabular-nums opacity-60">' + n + "</span></button>";
  box.innerHTML =
    mk("", "Everyone", DATA.length, !FILTER) +
    all.map((t) => mk(t.key, t.label, t.n, FILTER === t.key)).join("");
  box.querySelectorAll(".chip").forEach((b) =>
    b.addEventListener("click", () => {
      FILTER = b.dataset.k || null;
      chips();
      render();
    }),
  );
}

async function load(sync) {
  const btn = document.getElementById("sync");
  if (sync) { btn.textContent = "Syncing…"; btn.disabled = true; }
  const res = await fetch("/api/people" + (sync ? "?sync=1" : ""));
  const j = await res.json();
  DATA = j.people;
  document.getElementById("sub").textContent =
    j.people.length + " people from USC or IYA · synced " + j.syncedAt;
  btn.textContent = "Refresh";
  btn.disabled = false;
  chips();
  render();
}

document.getElementById("q").addEventListener("input", render);
document.getElementById("sync").addEventListener("click", () => load(true));
document.getElementById("mode").addEventListener("click", (e) => {
  GROUPED = !GROUPED;
  e.target.textContent = GROUPED ? "Rank by recency" : "Group by category";
  render();
});
load(true);
setInterval(() => load(true), 120000);
</script>
</body>
</html>`;

// ---------------------------------------------------------------- server

function runSync(cb) {
  execFile(
    process.argv[0],
    [process.argv[1], "texts", "sync", "--days", "2", "--quiet"],
    { timeout: 120000 },
    () => cb(),
  );
}

function serve({ db, port, host, onReady }) {
  const server = http.createServer((req, res) => {
    const url = new URL(req.url, "http://localhost");
    if (url.pathname === "/api/people") {
      const done = () => {
        const people = collect(db());
        res.writeHead(200, { "content-type": "application/json" });
        res.end(
          JSON.stringify({
            people,
            syncedAt: new Date().toLocaleTimeString([], { hour: "numeric", minute: "2-digit" }),
          }),
        );
      };
      if (url.searchParams.get("sync")) runSync(done);
      else done();
      return;
    }
    if (url.pathname === "/") {
      res.writeHead(200, { "content-type": "text/html; charset=utf-8" });
      res.end(PAGE);
      return;
    }
    res.writeHead(404, { "content-type": "text/plain" });
    res.end("not found");
  });
  // Bound to loopback on purpose. This is 500k private messages; it does not
  // belong on the local network, let alone anywhere else.
  server.listen(port, host, () => onReady(server));
  return server;
}

module.exports = { serve, collect, tagsFor, displayName, TAGS };
