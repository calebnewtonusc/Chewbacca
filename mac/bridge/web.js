#!/usr/bin/env node
// Chewbacca web bridge. Breaks the "cannot read web content" wall: reads and drives
// the DOM through the Chrome DevTools Protocol, which sees everything the macOS
// accessibility tree does not on Chrome (measured: 18 AX refs vs the full page).
//
// Attaches to a dedicated Chrome instance on a debug port, launched against a
// COPY of the user's real profile so their logins come along but their main
// browser is untouched.
//
//   chewie web read [url]                 dump visible text + links + inputs
//   chewie web eval "<js>" [url]          run JS in the page, return the result
//   chewie web click "<css-or-text>"      click an element
//   chewie web fill "<css>" "<value>"     type into a field
//   chewie web tabs                       list open tabs
//   chewie web goto "<url>"               navigate the active tab
"use strict";
const { spawn, execSync } = require("child_process");
const http = require("http");
const os = require("os");
const path = require("path");
const fs = require("fs");
let CDP;
try {
  CDP = require("chrome-remote-interface");
} catch {
  fail("bridge deps missing. run: cd bridge && npm install");
}

const PORT = parseInt(process.env.CHEWIE_CDP_PORT || "9333", 10);
const CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome";
const REAL_DIR = path.join(
  os.homedir(),
  "Library/Application Support/Google/Chrome",
);

function fail(msg) {
  process.stderr.write("chewie web: " + msg + "\n");
  process.exit(1);
}
function out(obj) {
  process.stdout.write(
    typeof obj === "string" ? obj + "\n" : JSON.stringify(obj, null, 2) + "\n",
  );
}

// Chrome keeps one directory per signed-in account ("Default", "Profile 1", ...)
// and only Local State knows which account each one holds. Copying "Default"
// blind is how this bridge spent a session signed in as the wrong Google account
// while the page it had to drive lived in Profile 1.
function realProfiles() {
  try {
    const ls = JSON.parse(
      fs.readFileSync(path.join(REAL_DIR, "Local State"), "utf8"),
    );
    return Object.entries(ls.profile?.info_cache || {}).map(([dir, v]) => ({
      dir,
      name: v.name || "",
      email: v.user_name || "",
    }));
  } catch {
    return [];
  }
}

// Accepts a directory ("Profile 1"), a profile name ("Work"), or an email.
function resolveProfile(want) {
  const all = realProfiles();
  if (!want) return "Default";
  const hit =
    all.find((p) => p.dir.toLowerCase() === want.toLowerCase()) ||
    all.find((p) => p.email.toLowerCase() === want.toLowerCase()) ||
    all.find((p) => p.name.toLowerCase() === want.toLowerCase()) ||
    all.find((p) => p.email.toLowerCase().includes(want.toLowerCase()));
  if (!hit)
    fail(
      `no Chrome profile matches ${JSON.stringify(want)}. run: chewie web profiles`,
    );
  return hit.dir;
}

const WANT_PROFILE = process.env.CHEWIE_CHROME_PROFILE || "Default";
const SRC_PROFILE = resolveProfile(WANT_PROFILE);
// One debug dir per source profile. Sharing one dir across profiles silently
// served whichever account was copied first.
const PROFILE = path.join(
  os.tmpdir(),
  "chewie-chrome-" + SRC_PROFILE.replace(/\W+/g, "-").toLowerCase(),
);

function debuggerUp() {
  return new Promise((res) => {
    const req = http.get(
      { host: "127.0.0.1", port: PORT, path: "/json/version", timeout: 500 },
      (r) => {
        r.resume();
        res(r.statusCode === 200);
      },
    );
    req.on("error", () => res(false));
    req.on("timeout", () => {
      req.destroy();
      res(false);
    });
  });
}

// The old bridge copied the real Local State verbatim. It lists every account on
// the machine, so Chrome opened chrome://profile-picker and never created a page
// target: `chewie web tabs` returned [] and looked like a dead bridge.
// os_crypt.encrypted_key must survive the trim or every copied cookie decrypts to
// garbage and the logins the copy existed for are gone.
function writeLocalState() {
  let real = {};
  try {
    real = JSON.parse(
      fs.readFileSync(path.join(REAL_DIR, "Local State"), "utf8"),
    );
  } catch {
    /* no real Local State: a logged-out profile still browses */
  }
  const src = real.profile?.info_cache?.[SRC_PROFILE] || {};
  fs.writeFileSync(
    path.join(PROFILE, "Local State"),
    JSON.stringify({
      os_crypt: real.os_crypt || {},
      profile: {
        info_cache: { Default: { ...src, name: src.name || "Chewie" } },
        last_used: "Default",
        profiles_created: 1,
      },
    }),
  );
}

async function ensureChrome() {
  if (await debuggerUp()) return;
  if (!fs.existsSync(CHROME)) fail("Google Chrome not found at " + CHROME);
  // Seed the debug profile from the chosen real profile once, so logins carry over.
  if (!fs.existsSync(PROFILE)) {
    const src = path.join(REAL_DIR, SRC_PROFILE);
    try {
      fs.mkdirSync(PROFILE, { recursive: true });
      if (fs.existsSync(src))
        // Always land at "Default" so the launch below needs no profile juggling.
        // Caches are megabytes of nothing, and skipping them turns a 90s copy into a few seconds.
        execSync(
          `rsync -a --exclude 'Cache/' --exclude 'Code Cache/' --exclude 'GPUCache/' ` +
            `--exclude 'DawnCache/' --exclude 'ShaderCache/' --exclude 'Service Worker/CacheStorage/' ` +
            `${JSON.stringify(src + "/")} ${JSON.stringify(path.join(PROFILE, "Default") + "/")}`,
          { stdio: "ignore" },
        );
      writeLocalState();
    } catch {
      /* a fresh profile still works, just logged out */
    }
  }
  const child = spawn(
    CHROME,
    [
      `--remote-debugging-port=${PORT}`,
      `--user-data-dir=${PROFILE}`,
      "--profile-directory=Default",
      "--no-first-run",
      "--no-default-browser-check",
      "--restore-last-session=false",
    ],
    { detached: true, stdio: "ignore" },
  );
  child.unref();
  for (let i = 0; i < 40; i++) {
    if (await debuggerUp()) return;
    await new Promise((r) => setTimeout(r, 250));
  }
  fail("Chrome debug port never came up on " + PORT);
}

// A cross-origin iframe is its own CDP target, and its text is absent from the
// parent's document.body.innerText. Talking only to the top frame is what made
// Figma's education form look like it rendered an empty page after Next: step two
// is a SheerID iframe, fully rendered, in a target this bridge never opened.
const WANT_FRAME = process.env.CHEWIE_WEB_FRAME || "";

async function withTab(fn, targetUrl) {
  await ensureChrome();
  let client;
  try {
    if (WANT_FRAME) {
      const all = await CDP.List({ port: PORT });
      const tgt = all.find(
        (t) =>
          (t.type === "iframe" || t.type === "page") &&
          (t.url || "").includes(WANT_FRAME),
      );
      if (!tgt)
        fail(
          `no frame url contains ${JSON.stringify(WANT_FRAME)}. run: chewie web frames`,
        );
      client = await CDP({ port: PORT, target: tgt });
    } else if (targetUrl) {
      const tgt = await CDP.New({ port: PORT, url: targetUrl });
      client = await CDP({ port: PORT, target: tgt });
    } else {
      client = await CDP({ port: PORT });
    }
    const { Page, Runtime, DOM, Input } = client;
    await Promise.all([Page.enable(), Runtime.enable(), DOM.enable()]);
    return await fn({ Page, Runtime, DOM, Input, client });
  } finally {
    if (client) await client.close();
  }
}

async function evalInPage(Runtime, expression) {
  const { result, exceptionDetails } = await Runtime.evaluate({
    expression,
    returnByValue: true,
    awaitPromise: true,
  });
  if (exceptionDetails)
    throw new Error(
      exceptionDetails.exception?.description || exceptionDetails.text,
    );
  return result.value;
}

const READ_JS = `(() => {
  const clean = s => (s || '').replace(/\\s+/g, ' ').trim()
  const vis = el => { const r = el.getBoundingClientRect(); const st = getComputedStyle(el)
    return r.width > 0 && r.height > 0 && st.visibility !== 'hidden' && st.display !== 'none' }
  const links = [...document.querySelectorAll('a[href]')].filter(vis)
    .map(a => ({ text: clean(a.innerText).slice(0, 80), href: a.href })).filter(l => l.text).slice(0, 60)
  const inputs = [...document.querySelectorAll('input,textarea,select,[contenteditable=true]')].filter(vis)
    .map(el => ({ tag: el.tagName.toLowerCase(), type: el.type || null,
      name: el.name || el.id || null, placeholder: el.placeholder || null,
      label: clean(el.labels && el.labels[0] ? el.labels[0].innerText : ''),
      value: (el.value || '').slice(0, 60) })).slice(0, 40)
  const buttons = [...document.querySelectorAll('button,[role=button],input[type=submit]')].filter(vis)
    .map(b => clean(b.innerText || b.value)).filter(Boolean).slice(0, 40)
  return { url: location.href, title: document.title,
    text: clean(document.body.innerText).slice(0, 6000),
    links, inputs, buttons }
})()`;

// Find an element by CSS selector, or by visible text if the selector fails.
const FIND_JS = (sel) => `(() => {
  const q = ${JSON.stringify(sel)}
  let el = null
  try { el = document.querySelector(q) } catch (e) {}
  if (!el) {
    const all = [...document.querySelectorAll('a,button,[role=button],input,label,span,div')]
    el = all.find(e => (e.innerText || e.value || '').trim().toLowerCase() === q.toLowerCase())
       || all.find(e => (e.innerText || e.value || '').trim().toLowerCase().includes(q.toLowerCase()))
  }
  if (!el) return null
  el.scrollIntoView({ block: 'center' })
  const r = el.getBoundingClientRect()
  return { x: r.x + r.width / 2, y: r.y + r.height / 2, tag: el.tagName.toLowerCase() }
})()`;

async function main() {
  const [cmd, ...rest] = process.argv.slice(2);
  switch (cmd) {
    case "frames": {
      await ensureChrome();
      const list = await CDP.List({ port: PORT });
      out(
        list
          .filter((t) => t.type === "page" || t.type === "iframe")
          .map((t) => ({ type: t.type, title: t.title, url: t.url })),
      );
      break;
    }
    case "profiles": {
      out(realProfiles().map((p) => ({ ...p, active: p.dir === SRC_PROFILE })));
      break;
    }
    case "tabs": {
      await ensureChrome();
      const list = await CDP.List({ port: PORT });
      out(
        list
          .filter((t) => t.type === "page")
          .map((t) => ({ title: t.title, url: t.url })),
      );
      break;
    }
    case "read": {
      await withTab(async ({ Runtime, Page }) => {
        if (rest[0]) await Page.loadEventFired();
        out(await evalInPage(Runtime, READ_JS));
      }, rest[0]);
      break;
    }
    case "goto": {
      if (!rest[0]) fail("goto needs a url");
      await withTab(async ({ Page }) => {
        await Page.navigate({ url: rest[0] });
        await Page.loadEventFired();
        out("ok: " + rest[0]);
      }, rest[0]);
      break;
    }
    case "eval": {
      if (!rest[0]) fail("eval needs an expression");
      await withTab(
        async ({ Runtime }) => out(await evalInPage(Runtime, rest[0])),
        rest[1],
      );
      break;
    }
    case "click": {
      if (!rest[0]) fail("click needs a selector or text");
      await withTab(async ({ Runtime, Input }) => {
        const hit = await evalInPage(Runtime, FIND_JS(rest[0]));
        if (!hit) fail("no element matched: " + rest[0]);
        for (const type of ["mousePressed", "mouseReleased"])
          await Input.dispatchMouseEvent({
            type,
            x: hit.x,
            y: hit.y,
            button: "left",
            clickCount: 1,
          });
        out(
          "clicked " +
            hit.tag +
            " at " +
            Math.round(hit.x) +
            "," +
            Math.round(hit.y),
        );
      }, rest[1]);
      break;
    }
    case "fill": {
      if (rest.length < 2) fail("fill needs a selector and a value");
      await withTab(async ({ Runtime }) => {
        const ok = await evalInPage(
          Runtime,
          `(() => {
          const el = document.querySelector(${JSON.stringify(rest[0])})
          if (!el) return false
          el.focus(); el.value = ${JSON.stringify(rest[1])}
          el.dispatchEvent(new Event('input', {bubbles:true}))
          el.dispatchEvent(new Event('change', {bubbles:true}))
          return true })()`,
        );
        if (!ok) fail("no field matched: " + rest[0]);
        out("filled " + rest[0]);
      }, rest[2]);
      break;
    }
    default:
      out(
        "usage: chewie web {read|eval|click|fill|goto|tabs|profiles} ...\n" +
          "  CHEWIE_CHROME_PROFILE picks the account, by dir, name or email.\n" +
          "  it defaults to Default, which is often the wrong one. run: chewie web profiles",
      );
  }
}
main().catch((e) => fail(e.message));
