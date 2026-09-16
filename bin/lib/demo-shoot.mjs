// Plan-driven demo shoot: record a product demo from a storyboard somebody
// wrote, instead of one a regex guessed at.
//
// WHY THIS EXISTS. Cap's bundled cap-demo skill scouts a page at runtime and
// scores every anchor and button to pick a "CTA": +3 if the text matches
// /features|pricing|docs/, +2 if it has a background colour, -5 if it says
// "sign up". That is a beauty contest between link labels. It has no idea what
// the product does, which flow matters, or what the user is supposed to feel.
// Pointed at calebnewton.me it found no CTA at all, fell back to scrolling, and
// logged `0 clicks`: a demo of a product with nothing being demonstrated.
//
// Chewbacca is not in that position. It has the repo. Routes, components,
// data-testids and, best of all, the e2e specs, which are a recorded script of
// the exact journey the team already decided was the product. Reading those and
// writing the storyboard is strictly better than scoring link text, and it is
// the whole difference between a screen recording and a demo.
//
// So this takes a plan and executes it. Everything else, the virtual cursor,
// the glide easing, the shimmer dot that keeps the encoder awake, the window
// matching, the Cap record lifecycle and the timeline contract that treat.py
// reads, is Cap's (apps/.../scout-shoot.mjs, AGPL, by Cap Software) and is
// preserved so the downstream treat + export stage works unchanged.
//
// Usage: node demo-shoot.mjs <plan.json> <outDir> <slug>

import { execFileSync, execSync } from "node:child_process";
import {
  existsSync,
  mkdirSync,
  readFileSync,
  readdirSync,
  writeFileSync,
} from "node:fs";
import { join } from "node:path";
import { chromium } from "playwright-core";

const [planPath, outDir, slug] = process.argv.slice(2);
if (!planPath || !outDir || !slug) {
  throw new Error("usage: node demo-shoot.mjs <plan.json> <outDir> <slug>");
}
const plan = JSON.parse(readFileSync(planPath, "utf8"));
if (!plan.url) throw new Error("plan needs a url");
if (!Array.isArray(plan.beats) || plan.beats.length === 0) {
  throw new Error("plan needs a non-empty beats array");
}
// 12s is treat.py's hard ceiling and the tail gets shaved evenly past it, so a
// plan that overruns silently loses its ending. Fail here instead, where the
// author can cut a beat on purpose.
const budget = plan.beats.reduce((n, b) => n + (b.ms ?? 0), 0);
if (budget > 12000) {
  throw new Error(
    `plan budgets ${(budget / 1000).toFixed(1)}s of explicit dwell, over the 12s ceiling. Cut a beat.`,
  );
}
mkdirSync(outDir, { recursive: true });

function resolveCap() {
  if (process.env.CAP_BIN) return process.env.CAP_BIN;
  try {
    const p = execSync("command -v cap", { encoding: "utf8" }).trim();
    if (p) return p;
  } catch {}
  throw new Error("cap CLI not found on PATH. Install Cap, or set CAP_BIN.");
}
const CAP = resolveCap();

function resolveChromium() {
  const HOME = process.env.HOME;
  const suffix =
    "chrome-mac-arm64/Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing";
  try {
    const base = `${HOME}/Library/Caches/ms-playwright`;
    const dirs = readdirSync(base)
      .filter((d) => /^chromium-\d+$/.test(d))
      .map((d) => ({ d, n: parseInt(d.split("-")[1], 10) }))
      .sort((a, b) => b.n - a.n);
    for (const { d } of dirs) {
      const exe = join(base, d, suffix);
      if (existsSync(exe)) return exe;
    }
  } catch {}
  return `${HOME}/Library/Caches/ms-playwright/chromium-1228/${suffix}`;
}

const PROJECT = join(outDir, `${slug}.cap`);
const TIMELINE = join(outDir, `${slug}.timeline.json`);
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const jitter = (b, s) => b + (Math.random() - 0.5) * s;

// Stale test-chrome windows stay enumerable in `cap record windows` and the
// match can grab the wrong one. Finder windows composite into the capture.
try {
  execSync('pkill -f "Google Chrome for Testing" || true');
} catch {}
try {
  execSync(
    `osascript -e 'tell application "Finder" to close every window' || true`,
  );
} catch {}
await sleep(800);

const browser = await chromium.launch({
  executablePath: resolveChromium(),
  headless: false,
  ignoreDefaultArgs: ["--enable-automation"],
  args: [
    "--window-size=1560,1000",
    "--window-position=120,60",
    "--disable-blink-features=AutomationControlled",
  ],
});
const page = await browser.newPage({ viewport: null });
await page.goto(plan.url, { waitUntil: "load", timeout: 60000 });
await sleep(2600);

await page
  .evaluate(() => {
    const re =
      /^(accept|accept all|allow all|agree|i agree|got it|ok|reject all|decline|dismiss|close)$/i;
    for (const el of document.querySelectorAll("button, a, [role=button]")) {
      if (re.test((el.textContent || "").trim())) {
        try {
          el.click();
        } catch {}
      }
    }
  })
  .catch(() => {});
await sleep(400);

const geo = await page.evaluate(() => ({
  chromeTop: window.outerHeight - window.innerHeight,
  iw: window.innerWidth,
  ih: window.innerHeight,
}));
const toFrac = (b) => ({
  x: (b.x + b.width / 2) / geo.iw,
  y: (geo.chromeTop + b.y + b.height / 2) / (geo.ih + geo.chromeTop),
});
const pointFrac = (p) => ({
  x: p.x / geo.iw,
  y: (geo.chromeTop + p.y) / (geo.ih + geo.chromeTop),
});

// Near-invisible orbiting dot. Window capture stalls timestamps on static
// pixels, so without this the video clock freezes on a still page.
const injectShimmer = () =>
  page
    .evaluate(() => {
      if (document.getElementById("__cap_shimmer")) return;
      const d = document.createElement("div");
      d.id = "__cap_shimmer";
      d.style.cssText =
        "position:fixed;right:6px;bottom:6px;width:3px;height:3px;background:rgba(127,127,127,0.02);z-index:2147483647;pointer-events:none;";
      document.documentElement.appendChild(d);
      let t = 0;
      const tick = () => {
        t += 0.25;
        d.style.transform = `translate(${Math.sin(t) * 2}px, ${Math.cos(t) * 2}px)`;
        requestAnimationFrame(tick);
      };
      requestAnimationFrame(tick);
    })
    .catch(() => {});
await injectShimmer();

// Brand colours still come off the page, because that part of scouting was
// never the problem: reading a background is a fact, scoring a link is a guess.
const palette = await page.evaluate(() => {
  const parse = (c) => {
    const m = c?.match(/rgba?\((\d+),\s*(\d+),\s*(\d+)/);
    return m ? [+m[1], +m[2], +m[3]] : null;
  };
  let pageBg = null;
  for (const el of [
    document.body,
    document.documentElement,
    ...document.querySelectorAll("main, header, section"),
  ]) {
    const c = parse(getComputedStyle(el).backgroundColor);
    if (c) {
      pageBg = c;
      break;
    }
  }
  let accent = null;
  for (const el of document.querySelectorAll("a, button, [role=button]")) {
    const s = getComputedStyle(el);
    const c = parse(s.backgroundColor);
    const r = el.getBoundingClientRect();
    if (c && r.width > 90 && r.height > 28 && (c[0] || c[1] || c[2])) {
      accent = c;
      break;
    }
  }
  return { title: document.title, pageBg, accent };
});

const events = [];
const cursorLog = { moves: [], clicks: [] };
let t0 = 0;
const now = () => (Date.now() - t0) / 1000;
let vpos = { x: geo.iw * 0.55, y: geo.ih * 0.45 };

const logMove = () => {
  const f = pointFrac(vpos);
  cursorLog.moves.push({ t: now(), x: f.x, y: f.y });
};
const vmove = async (p) => {
  vpos = p;
  await page.mouse.move(p.x, p.y).catch(() => {});
  logMove();
};
async function glide(to, ms) {
  const from = { ...vpos };
  const steps = Math.max(8, Math.round(ms / 16));
  for (let i = 1; i <= steps; i++) {
    const t = i / steps;
    const e = t * t * (3 - 2 * t);
    await vmove({
      x: from.x + (to.x - from.x) * e,
      y: from.y + (to.y - from.y) * e,
    });
    await sleep(ms / steps);
  }
}
const vclick = async () => {
  cursorLog.clicks.push({ t: now(), down: true });
  await page.mouse.down().catch(() => {});
  await sleep(70);
  await page.mouse.up().catch(() => {});
  cursorLog.clicks.push({ t: now() - 0.001, down: false });
};
const center = (b) => ({ x: b.x + b.width / 2, y: b.y + b.height / 2 });

/**
 * Resolve a beat's target to a box. A beat names its target the way the repo
 * does, so a plan written off a component or an e2e spec can be pasted in.
 * Missing is fatal: a demo that silently skips its own climax is worse than one
 * that stops and says the selector moved.
 */
async function boxFor(beat) {
  const sel = beat.selector;
  if (!sel) return null;
  const loc = beat.text
    ? page.locator(sel).filter({ hasText: beat.text }).first()
    : page.locator(sel).first();
  const box = await loc.boundingBox().catch(() => null);
  if (!box) {
    throw new Error(
      `beat "${beat.label ?? sel}" could not find ${sel}${beat.text ? ` with text ${JSON.stringify(beat.text)}` : ""}. ` +
        "The selector is stale or the element is off screen. Fix the plan.",
    );
  }
  return box;
}

const pageTitle = await page.title();
const windows = JSON.parse(
  execFileSync(CAP, ["record", "windows", "--json"], { encoding: "utf8" }),
);
const chromeWins = windows.filter(
  (w) =>
    /Chrome for Testing/i.test(w.ownerName ?? "") ||
    /Chrome for Testing/i.test(w.name ?? ""),
);
let win = chromeWins.find((w) => (w.name ?? "").trim() === pageTitle.trim());
if (!win && chromeWins.length === 1) win = chromeWins[0];
if (!win) {
  await browser.close();
  throw new Error(
    `window not found (title="${pageTitle}", ${chromeWins.length} chrome windows)`,
  );
}

execFileSync(
  CAP,
  [
    "record",
    "start",
    "--detach",
    "--window",
    String(win.id),
    "--fps",
    "60",
    "--path",
    PROJECT,
  ],
  { encoding: "utf8" },
);
t0 = Date.now();
const mark = (n, extra = {}) => {
  events.push({ name: n, t: now(), ...extra });
  console.log(`[${now().toFixed(2)}s] ${n}`);
};

// SPEAK treat.py's VOCABULARY, don't replace treat.py.
//
// Cap's treat stage is the good half of its pipeline: the 3D camera math, the
// tail-anchored alignment, the editorial cut, the gradient and the cursor
// synthesis. It reads a fixed set of event names, because it only ever had two
// storyboards to serve: `hero_frac`, `cta_frac`, `page2_frac`, `click_cta`,
// `page_ready`, `scroll_start` and `end`.
//
// A plan uses whatever labels its author found meaningful, so the first run of
// a plan-driven shoot died on `KeyError: 'scroll1_start'`. Rewriting treat.py
// to take arbitrary labels would mean re-deriving camera math that already
// works. Emitting both names costs one extra event per beat and keeps the
// downstream stage untouched, which also means Cap's updates to it keep
// applying.
//
// The mapping is positional, and the positions are what a demo is made of: the
// thing you look at first, the thing you click, where you land, and the beat
// after that.
const firstClickIdx = plan.beats.findIndex((b) => b.do === "click");
const STORY = firstClickIdx >= 0 ? "click" : "scroll";
let heroMarked = false;
let ctaMarked = false;
let scrollStartMarked = false;
/** Emit a canonical alias when this beat fills one of treat.py's slots. */
const alias = (name, extra) => mark(name, extra);

try {
  logMove();
  for (const [i, beat] of plan.beats.entries()) {
    const label = beat.label ?? `${beat.do}_${i}`;
    // treat.py reads `scroll_start` in BOTH of its branches to place the second
    // 3D shot, so a plan with no scroll beat still has to supply one. The beat
    // after the primary click is where the second shot belongs anyway: it is
    // the moment the demo has landed and is showing you the result.
    if (!scrollStartMarked && firstClickIdx >= 0 && i === firstClickIdx + 1) {
      scrollStartMarked = true;
      alias("scroll_start");
    }
    switch (beat.do) {
      // AIM marks a landmark for treat.py to point a 3D shot at. It moves
      // nothing, which is why a plan can name the thing the shot is about
      // separately from the thing the cursor touches.
      case "aim": {
        const box = await boxFor(beat);
        if (box) mark(`${label}_frac`, toFrac(box));
        if (box && !heroMarked) {
          heroMarked = true;
          alias("hero_frac", toFrac(box));
        }
        break;
      }
      case "dwell": {
        mark(label);
        await sleep(beat.ms ?? 1000);
        break;
      }
      case "move": {
        const box = await boxFor(beat);
        mark(label);
        await glide(center(box), beat.ms ?? 700);
        break;
      }
      case "click": {
        const box = await boxFor(beat);
        const c = center(box);
        mark(`${label}_frac`, toFrac(box));
        const isPrimaryClick = i === firstClickIdx;
        if (isPrimaryClick) {
          if (!heroMarked) {
            heroMarked = true;
            alias("hero_frac", toFrac(box));
          }
          ctaMarked = true;
          alias("cta_frac", toFrac(box));
        }
        // Approach off-centre then settle, so the cursor reads as a hand
        // rather than a teleport. This easing is Cap's.
        await glide({ x: c.x + 16, y: c.y + 24 }, beat.ms ?? 700);
        await glide(c, 380);
        await sleep(320);
        mark(label);
        if (isPrimaryClick) alias("click_cta");
        await vclick();
        if (beat.waitFor !== false) {
          await page
            .waitForLoadState("load", { timeout: 25000 })
            .catch(() => {});
          await injectShimmer();
        }
        await sleep(beat.settle ?? 1000);
        mark(`${label}_ready`);
        if (isPrimaryClick) alias("page_ready", toFrac(box));
        break;
      }
      case "type": {
        const box = await boxFor(beat);
        const c = center(box);
        // Aim at the text-entry point, not the field centre: a demo of
        // typing should look at where the characters appear.
        await glide({ x: box.x + 24, y: c.y }, beat.ms ?? 600);
        mark(`${label}_frac`, toFrac(box));
        await vclick();
        mark(label);
        await page.keyboard.type(beat.text ?? "", {
          delay: beat.delay ?? 55,
        });
        await sleep(beat.settle ?? 700);
        break;
      }
      case "scroll": {
        mark(`${label}_start`);
        // ORDER MATTERS AND IS NOT OBVIOUS. treat.py's scroll branch reads
        // `scroll1_start` as the FIRST scroll and `scroll_start` as the later
        // one, then cuts at s1+0.9 and s1+1.1. Emitting them the other way
        // round inverts the edit and the second shot lands before the first.
        if (STORY === "scroll" && !ctaMarked) {
          ctaMarked = true;
          alias("scroll1_start");
        } else if (!scrollStartMarked) {
          scrollStartMarked = true;
          alias("scroll_start");
        }
        if (beat.selector) {
          const box = await boxFor(beat);
          mark(`${label}_frac`, toFrac(box));
          await page.evaluate(
            (s) =>
              document
                .querySelector(s)
                ?.scrollIntoView({ behavior: "smooth", block: "center" }),
            beat.selector,
          );
        } else {
          await page.evaluate(
            (d) => window.scrollBy({ top: d, behavior: "smooth" }),
            beat.by ?? Math.round(geo.ih * 0.9),
          );
        }
        await glide({ x: vpos.x + 90, y: vpos.y + 110 }, 900);
        await sleep(beat.settle ?? 800);
        mark(`${label}_settled`);
        break;
      }
      case "idle": {
        mark(label);
        const until = Date.now() + (beat.ms ?? 2000);
        while (Date.now() < until) {
          await vmove({
            x: vpos.x + jitter(0, 2.4),
            y: vpos.y + jitter(0, 2.4),
          });
          await sleep(150);
        }
        break;
      }
      default:
        throw new Error(`unknown beat "${beat.do}" at index ${i}`);
    }
  }
  mark("end");
} finally {
  execFileSync(CAP, ["record", "stop", "--path", PROJECT], {
    encoding: "utf8",
  });
  writeFileSync(
    TIMELINE,
    JSON.stringify(
      {
        // The branch treat.py takes, not a description of this shoot. A plan
        // with a click is a click story to the edit, whatever the plan calls it.
        story: STORY,
        scout: { ...palette, heroBox: null },
        events,
        cursorLog,
      },
      null,
      1,
    ),
  );
  await browser.close();
}

console.log(
  JSON.stringify({
    slug,
    story: "plan",
    beats: plan.beats.length,
    clicks: cursorLog.clicks.filter((c) => c.down).length,
    scout: {
      title: palette.title,
      accent: palette.accent,
      pageBg: palette.pageBg,
    },
  }),
);
console.log("DONE");
