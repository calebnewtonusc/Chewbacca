# Layer 6: The browser

A large share of real tasks happen inside a browser tab, and a browser is the one app
that hands you a complete, addressable model of its own contents. Driving it through
pixels throws that away.

## The options, ranked

### 1. The browser's own protocol

Chrome DevTools Protocol, through Playwright or Puppeteer. You get the DOM, selectors,
network interception, JavaScript evaluation, and screenshots when you actually want
one.

```bash
npx playwright open https://example.com
```

Attach to the user's *existing* Chrome rather than launching a clean one, and you keep
every login they already have:

```bash
open -a "Google Chrome" --args --remote-debugging-port=9222
# then connect Playwright over CDP to http://localhost:9222
```

This is the highest-leverage trick in this doc. A fresh Playwright browser is logged
into nothing, which is why so many "book me a flight" demos fail on the login page.

### 2. browser-use

[browser-use/browser-use](https://github.com/browser-use/browser-use), 112k stars,
MIT, Python. The most-starred project in this entire space by a wide margin. It gives
an LLM a browser with a structured element index rather than raw pixels: the same
set-of-marks idea, applied to the DOM where it actually works well.

```bash
pip install browser-use
```

If the task is on the web, start here, not with a desktop agent.

### 3. In-page agents

[alibaba/page-agent](https://github.com/alibaba/page-agent), 29k stars, MIT,
TypeScript. Runs inside the page as JavaScript, controlling the interface from within.
Different tradeoff: no driver process, no CDP port, but it lives in the page's own
security context.

[web-infra-dev/midscene](https://github.com/web-infra-dev/midscene), 15k stars, MIT.
Framed as E2E testing, works as a general driver.

### 4. Safari via AppleScript

Free, no install, keeps the user's session and logins, and costs almost nothing.

```bash
osascript -e 'tell application "Safari" to get URL of front document'
osascript -e 'tell application "Safari" to do JavaScript "document.title" in front document'
osascript -e 'tell application "Safari" to open location "https://example.com"'
```

`do JavaScript` requires **Develop > Allow JavaScript from Apple Events** to be turned
on, which is off by default and is the reason this silently fails for most people.

[achiya-automation/safari-mcp](https://github.com/achiya-automation/safari-mcp) (181
stars, MIT) wraps 97 tools around this and claims 40 to 60 percent lower CPU than a
CDP-based MCP on Apple Silicon, because there is no second browser process.

### 5. Agentic browser frameworks

[Skyvern-AI/skyvern](https://github.com/Skyvern-AI/skyvern), 23k stars, AGPL-3.0.
Vision plus DOM for workflows that need to survive site redesigns. Note the license:
AGPL is a real constraint if you are embedding it in something you ship.

## Choosing

| Situation | Use |
|-----------|-----|
| Task needs the user's existing logins | CDP attached to their running Chrome |
| Clean automated task, repeatable | Playwright with its own profile |
| Natural-language web task | browser-use |
| Just reading a URL or title | Safari AppleScript, it is free |
| Site changes constantly | Skyvern, or vision as a fallback |

## What not to do

Do not drive a browser through screenshots and coordinate clicks. It is slower, more
expensive, and less reliable than reading the DOM, and unlike a native app there is no
case where the DOM is unavailable. The only exception is a canvas-rendered web app,
which is the same layer-5 case as a native canvas app.
