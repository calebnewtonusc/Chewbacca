"""Read a page as text in the user's Chrome over Browser Harness. Read-only.

Run with the jev-ultrafast environment's Python (it owns browser_harness).
Opens its own background tab, waits for the page to settle, returns the
visible text, the links and the controls' labels, then closes the tab. It
never clicks, types or submits.

    python page_read.py <https-url> [wait_seconds]
"""
import json
import sys
import time

from browser_harness.admin import ensure_daemon
from browser_harness.helpers import cdp

READ = r"""(() => {
  const clean = s => (s || '').replace(/\s+/g, ' ').trim();
  const links = [...document.querySelectorAll('a[href]')]
    .map(a => ({text: clean(a.innerText || a.getAttribute('aria-label')), href: a.href}))
    .filter(l => l.text || l.href).slice(0, 400);
  const controls = [...document.querySelectorAll('button,[role=button],[role=tab],[role=menuitem],input,select,textarea')]
    .map(e => clean(e.innerText || e.getAttribute('aria-label') || e.getAttribute('placeholder') || e.name))
    .filter(Boolean).slice(0, 300);
  return {url: location.href, title: document.title,
          text: (document.body ? document.body.innerText : '').slice(0, 60000), links, controls};
})()"""


def main() -> int:
    url = sys.argv[1]
    wait = float(sys.argv[2]) if len(sys.argv) > 2 else 3.0
    ensure_daemon()
    target = cdp("Target.createTarget", url="about:blank", background=True)["targetId"]
    try:
        session = cdp("Target.attachToTarget", targetId=target, flatten=True)["sessionId"]
        call = lambda m, **p: cdp(m, session_id=session, **p)  # noqa: E731
        call("Emulation.setFocusEmulationEnabled", enabled=True)
        call("Page.navigate", url=url)
        deadline = time.monotonic() + 20
        while time.monotonic() < deadline:
            r = call("Runtime.evaluate", expression="document.readyState", returnByValue=True)
            if r.get("result", {}).get("value") == "complete":
                break
            time.sleep(0.1)
        # SPAs (Clay, LinkedIn) render after load: wait until the text stops growing.
        last, stable, end = -1, 0, time.monotonic() + wait + 8
        while time.monotonic() < end:
            r = call("Runtime.evaluate", expression="document.body ? document.body.innerText.length : 0", returnByValue=True)
            n = r.get("result", {}).get("value") or 0
            stable = stable + 1 if n == last and n > 0 else 0
            last = n
            if stable >= int(wait * 2):
                break
            time.sleep(0.5)
        r = call("Runtime.evaluate", expression=READ, returnByValue=True)
        print(json.dumps(r.get("result", {}).get("value") or {"error": "no value"}))
        return 0
    finally:
        cdp("Target.closeTarget", targetId=target)


if __name__ == "__main__":
    sys.exit(main())
