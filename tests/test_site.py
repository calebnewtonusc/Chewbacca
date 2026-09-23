"""Tests for bin/site: find ranks what the kit knows, snap reads a page by role.

Pages are served from a local http.server so nothing here touches the web.
The blocked case is the reason `snap` exists as its own step: a human check
has to come back as BLOCKED with nothing saved, never as an empty map.

    python3 tests/test_site.py
"""

import functools
import http.server
import json
import os
import pathlib
import subprocess
import sys
import tempfile
import threading

ROOT = pathlib.Path(__file__).resolve().parent.parent
SITE = ROOT / "bin" / "site"
PASSED = FAILED = 0


def check(name, condition, detail=""):
    global PASSED, FAILED
    if condition:
        PASSED += 1
        print(f"  pass  {name}")
    else:
        FAILED += 1
        print(f"  FAIL  {name}  {detail}")


def run(env, *args):
    r = subprocess.run([sys.executable, str(SITE), *args], capture_output=True, text=True,
                       env={**os.environ, **env}, timeout=90)
    return r.returncode, r.stdout, r.stderr


FORM = """<!doctype html><title>Stay search</title><body>
<h1>Find a stay</h1>
<label>Where <input type=text name=city></label>
<label><input type=checkbox> Kitchen</label>
<button>Search</button><a href="/help">Help</a></body>"""

WALL = """<!doctype html><title>Just a moment...</title><body>
<p>Checking your browser before accessing the site.</p><button>Verify</button></body>"""

EMPTY = """<!doctype html><title>Too Many Requests</title><body></body>"""


class Quiet(http.server.SimpleHTTPRequestHandler):
    def log_message(self, *args):
        pass


def browser_ready():
    try:
        from playwright.sync_api import sync_playwright
        with sync_playwright() as pw:
            pw.chromium.launch(headless=True).close()
        return True
    except Exception:
        return False


def main():
    tmp = pathlib.Path(tempfile.mkdtemp())
    web = tmp / "web"
    web.mkdir()
    (web / "form.html").write_text(FORM)
    (web / "wall.html").write_text(WALL)
    (web / "empty.html").write_text(EMPTY)
    handler = functools.partial(Quiet, directory=str(web))
    server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), handler)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    base = f"http://127.0.0.1:{server.server_address[1]}"

    maps, procs = tmp / "maps", tmp / "procedures"
    (procs / "stays-compare").mkdir(parents=True)
    (procs / "stays-compare" / "PROCEDURE.md").write_text(
        "# stays-compare\n\nPlaces to stay in a city for given dates, as one table.\n")
    (procs / "course-ingest").mkdir()
    (procs / "course-ingest" / "PROCEDURE.md").write_text(
        "# course-ingest\n\nA whole term read out of Blackboard Ultra: every deadline.\n")
    (maps / "app.clay.com").mkdir(parents=True)
    (maps / "app.clay.com" / "MAP.md").write_text(
        "# app.clay.com\n\nAudiences, searches and enrichment of work email.\n")
    env = {"SITE_MAPS": str(maps), "SITE_PROCEDURES": str(procs)}

    print("find")
    rc, out, _ = run(env, "find", "places to stay in lisbon", "--json")
    hits = json.loads(out)
    check("a task finds its procedure first", hits and hits[0]["name"] == "stays-compare", out)
    check("and nothing unrelated rides along", len(hits) == 1, out)
    rc, out, _ = run(env, "find", "clay work email", "--json")
    check("a site name finds its map", json.loads(out)[0]["name"] == "app.clay.com", out)
    rc, out, _ = run(env, "find", "order pizza")
    check("nothing known says so and exits 1", rc == 1 and "Nothing known" in out, out)

    print("snap")
    if not browser_ready():
        # CI's macOS runner has no Chromium for Playwright. find is the part
        # that runs on every task, so it is always tested; snap is tested
        # wherever a browser exists, which includes every machine that uses it.
        print("  skip  no headless Chromium here (pip3 install playwright && playwright install chromium)")
        server.shutdown()
        print(f"\n{PASSED} passed, {FAILED} failed.")
        return 1 if FAILED else 0
    rc, out, err = run(env, "snap", f"{base}/form.html", "--json")
    snap = json.loads(out)
    roles = {c["role"] for c in snap["controls"]}
    check("controls come back by role", {"textbox", "checkbox", "button", "link"} <= roles, roles)
    check("with their visible names",
          {"role": "button", "name": "Search"} in snap["controls"], snap["controls"])
    check("the bare snap saves nothing", not maps.joinpath("127.0.0.1").exists())

    rc, out, _ = run(env, "snap", f"{base}/form.html", "--save")
    page = maps / "127.0.0.1" / "pages" / "form-html.md"
    check("--save files the page under the host", rc == 0 and page.exists(), out)
    check("and starts a MAP.md", (maps / "127.0.0.1" / "MAP.md").exists())
    check("the saved page holds the tree", page.exists() and 'button "Search"' in page.read_text())
    rc, out, _ = run(env, "find", "kitchen search", "--json")
    check("a saved page is findable afterwards",
          any(h["kind"] == "page" for h in json.loads(out)), out)

    rc, out, err = run(env, "snap", f"{base}/wall.html", "--save")
    check("a human check is BLOCKED, exit 3", rc == 3 and "BLOCKED" in err, (rc, err))
    check("and nothing is saved for it", not (maps / "127.0.0.1" / "pages" / "wall-html.md").exists())
    rc, out, err = run(env, "snap", f"{base}/empty.html")
    check("an empty rate-limit page is BLOCKED too", rc == 3, (rc, err))

    rc, out, _ = run(env, "show", "127.0.0.1")
    check("show lists the pages read", "form-html.md" in out, out)
    rc, out, _ = run(env, "show", "nowhere.example")
    check("show on an unknown site says how to start", rc == 1 and "site snap" in out, out)

    server.shutdown()
    print(f"\n{PASSED} passed, {FAILED} failed.")
    return 1 if FAILED else 0


if __name__ == "__main__":
    sys.exit(main())
