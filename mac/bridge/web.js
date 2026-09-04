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
'use strict'
const { spawn, execSync } = require('child_process')
const http = require('http')
const os = require('os')
const path = require('path')
const fs = require('fs')
let CDP
try { CDP = require('chrome-remote-interface') }
catch { fail('bridge deps missing. run: cd bridge && npm install') }

const PORT = parseInt(process.env.CHEWIE_CDP_PORT || '9333', 10)
const CHROME = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'
const PROFILE = path.join(os.tmpdir(), 'chewie-chrome-profile')

function fail(msg) { process.stderr.write('chewie web: ' + msg + '\n'); process.exit(1) }
function out(obj) { process.stdout.write(typeof obj === 'string' ? obj + '\n' : JSON.stringify(obj, null, 2) + '\n') }

function debuggerUp() {
  return new Promise(res => {
    const req = http.get({ host: '127.0.0.1', port: PORT, path: '/json/version', timeout: 500 },
      r => { r.resume(); res(r.statusCode === 200) })
    req.on('error', () => res(false))
    req.on('timeout', () => { req.destroy(); res(false) })
  })
}

async function ensureChrome() {
  if (await debuggerUp()) return
  if (!fs.existsSync(CHROME)) fail('Google Chrome not found at ' + CHROME)
  // Seed the debug profile from the real Default profile once, so logins carry over.
  if (!fs.existsSync(PROFILE)) {
    const real = path.join(os.homedir(), 'Library/Application Support/Google/Chrome')
    try {
      fs.mkdirSync(PROFILE, { recursive: true })
      if (fs.existsSync(path.join(real, 'Default')))
        execSync(`cp -R ${JSON.stringify(path.join(real, 'Default'))} ${JSON.stringify(path.join(PROFILE, 'Default'))}`,
          { stdio: 'ignore' })
      if (fs.existsSync(path.join(real, 'Local State')))
        execSync(`cp ${JSON.stringify(path.join(real, 'Local State'))} ${JSON.stringify(path.join(PROFILE, 'Local State'))}`,
          { stdio: 'ignore' })
    } catch { /* a fresh profile still works, just logged out */ }
  }
  const child = spawn(CHROME, [
    `--remote-debugging-port=${PORT}`,
    `--user-data-dir=${PROFILE}`,
    '--no-first-run', '--no-default-browser-check',
    '--restore-last-session=false',
  ], { detached: true, stdio: 'ignore' })
  child.unref()
  for (let i = 0; i < 40; i++) {
    if (await debuggerUp()) return
    await new Promise(r => setTimeout(r, 250))
  }
  fail('Chrome debug port never came up on ' + PORT)
}

async function withTab(fn, targetUrl) {
  await ensureChrome()
  let client
  try {
    if (targetUrl) {
      const tgt = await CDP.New({ port: PORT, url: targetUrl })
      client = await CDP({ port: PORT, target: tgt })
    } else {
      client = await CDP({ port: PORT })
    }
    const { Page, Runtime, DOM, Input } = client
    await Promise.all([Page.enable(), Runtime.enable(), DOM.enable()])
    return await fn({ Page, Runtime, DOM, Input, client })
  } finally {
    if (client) await client.close()
  }
}

async function evalInPage(Runtime, expression) {
  const { result, exceptionDetails } = await Runtime.evaluate({
    expression, returnByValue: true, awaitPromise: true,
  })
  if (exceptionDetails) throw new Error(exceptionDetails.exception?.description || exceptionDetails.text)
  return result.value
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
})()`

// Find an element by CSS selector, or by visible text if the selector fails.
const FIND_JS = sel => `(() => {
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
})()`

async function main() {
  const [cmd, ...rest] = process.argv.slice(2)
  switch (cmd) {
    case 'tabs': {
      await ensureChrome()
      const list = await CDP.List({ port: PORT })
      out(list.filter(t => t.type === 'page').map(t => ({ title: t.title, url: t.url })))
      break
    }
    case 'read': {
      await withTab(async ({ Runtime, Page }, ) => {
        if (rest[0]) await Page.loadEventFired()
        out(await evalInPage(Runtime, READ_JS))
      }, rest[0])
      break
    }
    case 'goto': {
      if (!rest[0]) fail('goto needs a url')
      await withTab(async ({ Page }) => { await Page.navigate({ url: rest[0] }); await Page.loadEventFired()
        out('ok: ' + rest[0]) }, rest[0])
      break
    }
    case 'eval': {
      if (!rest[0]) fail('eval needs an expression')
      await withTab(async ({ Runtime }) => out(await evalInPage(Runtime, rest[0])), rest[1])
      break
    }
    case 'click': {
      if (!rest[0]) fail('click needs a selector or text')
      await withTab(async ({ Runtime, Input }) => {
        const hit = await evalInPage(Runtime, FIND_JS(rest[0]))
        if (!hit) fail('no element matched: ' + rest[0])
        for (const type of ['mousePressed', 'mouseReleased'])
          await Input.dispatchMouseEvent({ type, x: hit.x, y: hit.y, button: 'left', clickCount: 1 })
        out('clicked ' + hit.tag + ' at ' + Math.round(hit.x) + ',' + Math.round(hit.y))
      }, rest[1])
      break
    }
    case 'fill': {
      if (rest.length < 2) fail('fill needs a selector and a value')
      await withTab(async ({ Runtime }) => {
        const ok = await evalInPage(Runtime, `(() => {
          const el = document.querySelector(${JSON.stringify(rest[0])})
          if (!el) return false
          el.focus(); el.value = ${JSON.stringify(rest[1])}
          el.dispatchEvent(new Event('input', {bubbles:true}))
          el.dispatchEvent(new Event('change', {bubbles:true}))
          return true })()`)
        if (!ok) fail('no field matched: ' + rest[0])
        out('filled ' + rest[0])
      }, rest[2])
      break
    }
    default:
      out('usage: chewie web {read|eval|click|fill|goto|tabs} ...')
  }
}
main().catch(e => fail(e.message))
