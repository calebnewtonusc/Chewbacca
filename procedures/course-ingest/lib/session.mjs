// One signed-in Blackboard session, reusable between runs.
//
// A school LMS sits behind SSO, so a session has to be established by a human
// once: the password and the MFA push are theirs and only theirs. After that
// the cookies live in a state file and every later run is unattended.
//
// It must be storageState, not a persistent profile directory. Blackboard's
// session cookie is a session cookie, so Chromium never flushes it to disk and
// a profile dir comes back signed out. storageState dumps the live cookie jar,
// which is the only reason a second run needs no login.
import { chromium } from 'playwright';
import { existsSync, chmodSync, mkdirSync } from 'node:fs';
import { homedir } from 'node:os';
import { dirname } from 'node:path';

export const stateFile = (school) => `${homedir()}/.config/course-ingest/${school}.state.json`;

export async function open(cfg, { headless = !cfg.headed, fresh = false } = {}) {
  const state = stateFile(cfg.school);
  mkdirSync(dirname(state), { recursive: true });
  const browser = await chromium.launch({ headless });
  const ctx = await browser.newContext({
    viewport: { width: 1440, height: 900 },
    ...(!fresh && existsSync(state) ? { storageState: state } : {}),
  });
  const page = await ctx.newPage();
  return {
    browser, ctx, page,
    save: async () => { await ctx.storageState({ path: state }); chmodSync(state, 0o600); },
    close: async () => { await ctx.close(); await browser.close(); },
  };
}

export async function signedIn(page, host) {
  await page.goto(`https://${host}/ultra/stream`, { waitUntil: 'domcontentloaded' }).catch(() => {});
  await page.waitForTimeout(3500);
  return page.evaluate(() => !document.querySelector('input[type="password"]'));
}

// Every Ultra screen is painted from these JSON endpoints. Reading them beats
// scraping the DOM: the payload carries the exact due timestamp the card
// rounds to "Due Sunday", and it survives Blackboard restyling the card.
//
// Note the /learn/api/v1 prefix, NOT /learn/api/public/v1. The public REST API
// wants an OAuth app and answers a browser session with
// {"status":401,"message":"API request is not authenticated."}.
export async function api(page, host, path) {
  const url = path.startsWith('http') ? path : `https://${host}${path}`;
  return page.evaluate(async (u) => {
    const r = await fetch(u, { credentials: 'include', headers: { Accept: 'application/json' } });
    const body = await r.text();
    try { return { status: r.status, json: JSON.parse(body) }; }
    catch { return { status: r.status, text: body.slice(0, 1500) }; }
  }, url);
}
