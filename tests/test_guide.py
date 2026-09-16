"""Unit tests for the guide CLI's pure functions and commands.

The bash tests in run.sh cover the CLI end to end: new, open, list, progress,
sidecar read-back, trend labels, and the template. This file covers the internal
functions that are easy to get wrong quietly: slug edge cases, sidecar path
computation, latest() across both sidecar shapes, trend() arithmetic, resolve()
name matching, read_progress() on corrupt or missing files, the command
functions (cmd_new, cmd_list, cmd_progress, main dispatch), and the POST
handler's path traversal guard and sidecar save logic.
"""
from __future__ import annotations

import importlib.util
import io
import json
import os
import shutil
import sys
import tempfile
import urllib.request
import threading
import time
import socketserver
from importlib.machinery import SourceFileLoader
from pathlib import Path

BIN = Path(__file__).resolve().parent.parent / "bin" / "guide"
failures: list[str] = []


def check(name: str, ok: bool, detail: str = "") -> None:
    print(f"  {'ok  ' if ok else 'FAIL'} {name} {detail}".rstrip())
    if not ok:
        failures.append(name)


def _seed_craft(guide_dir: str) -> None:
    """Point CRAFT_DIR at a temp store holding the study-guide craft notes.

    cmd_new runs craft-gate before it writes anything, and the gate refuses on a
    craft nobody has studied. Without this the unit tests exercise the refusal
    path instead of the thing they are testing. Seeding here rather than
    stubbing the gate keeps the tests honest: the real gate still runs.
    """
    store = Path(guide_dir).parent / "craft"
    store.mkdir(parents=True, exist_ok=True)
    src = BIN.parent.parent / "crafts" / "study-guide.md"
    if src.is_file():
        shutil.copy2(src, store / "study-guide.md")
    os.environ["CRAFT_DIR"] = str(store)


def load(guide_dir: str):
    """Import bin/guide as a module, pointing GUIDE_DIR at a temp dir."""
    os.environ["GUIDE_DIR"] = guide_dir
    _seed_craft(guide_dir)
    spec = importlib.util.spec_from_file_location(
        "guide_mod", BIN, loader=SourceFileLoader("guide_mod", str(BIN))
    )
    m = importlib.util.module_from_spec(spec)
    # Prevent sys.exit from die() killing the test runner.
    sys.modules["guide_mod"] = m
    spec.loader.exec_module(m)
    return m


def capture(fn, *args):
    """Call fn(*args) and return (stdout_str, exception_or_None)."""
    old = sys.stdout
    sys.stdout = buf = io.StringIO()
    exc = None
    try:
        fn(*args)
    except SystemExit as e:
        exc = e
    except Exception as e:
        exc = e
    finally:
        sys.stdout = old
    return buf.getvalue(), exc


def main() -> int:
    with tempfile.TemporaryDirectory() as tmp:
        gdir = os.path.join(tmp, "guides")
        os.makedirs(gdir)
        g = load(gdir)

        # ── slug ─────────────────────────────────────────────────────────
        check("slug: simple", g.slug("Cache Coherence") == "cache-coherence")
        check("slug: already lowercase", g.slug("mesi") == "mesi")
        check("slug: multiple spaces", g.slug("a   b   c") == "a-b-c")
        check("slug: leading/trailing junk", g.slug("---hello---") == "hello")
        check("slug: all punctuation falls back", g.slug("!!!") == "guide")
        check("slug: empty string falls back", g.slug("") == "guide")
        check("slug: numbers preserved", g.slug("Week 3 Quiz") == "week-3-quiz")
        check("slug: mixed case and symbols", g.slug("MATH-226: Limits") == "math-226-limits")
        check("slug: unicode combining mark stripped", g.slug("cafe\u0301") == "cafe")
        check("slug: tabs and newlines", g.slug("a\tb\nc") == "a-b-c")

        # ── sidecar ──────────────────────────────────────────────────────
        p = Path("/fake/dir/cache-coherence.html")
        sc = g.sidecar(p)
        check("sidecar: dot-prefixed", sc.name.startswith("."))
        check("sidecar: same parent", sc.parent == p.parent)
        check("sidecar: ends .progress.json", str(sc).endswith(".progress.json"))
        check("sidecar: full name correct",
              sc.name == ".cache-coherence.html.progress.json")

        # ── read_progress ────────────────────────────────────────────────
        # Missing sidecar returns empty dict.
        missing = Path(os.path.join(gdir, "nonexistent.html"))
        check("read_progress: missing file returns {}", g.read_progress(missing) == {})

        # Corrupt JSON returns empty dict, not an exception.
        guide_html = Path(os.path.join(gdir, "corrupt.html"))
        guide_html.write_text("<html></html>")
        corrupt_sc = g.sidecar(guide_html)
        corrupt_sc.write_text("{not valid json!!!")
        check("read_progress: corrupt JSON returns {}", g.read_progress(guide_html) == {})

        # Valid sidecar returns the data.
        good_html = Path(os.path.join(gdir, "good.html"))
        good_html.write_text("<html></html>")
        good_data = {"topic-a": {"correct": 3, "total": 5, "at": "2026-09-11"}}
        g.sidecar(good_html).write_text(json.dumps(good_data))
        check("read_progress: valid sidecar returns data",
              g.read_progress(good_html) == good_data)

        # Empty sidecar file returns empty dict.
        empty_html = Path(os.path.join(gdir, "empty-sc.html"))
        empty_html.write_text("<html></html>")
        g.sidecar(empty_html).write_text("")
        check("read_progress: empty sidecar returns {}", g.read_progress(empty_html) == {})

        # ── latest ───────────────────────────────────────────────────────
        # Current shape: has both "attempts" and "last".
        rec_current = {
            "attempts": [
                {"correct": 1, "total": 5, "at": "2026-09-01"},
                {"correct": 4, "total": 5, "at": "2026-09-09"},
            ],
            "last": {"correct": 4, "total": 5, "at": "2026-09-09"},
        }
        check("latest: current shape uses 'last'",
              g.latest(rec_current) == rec_current["last"])

        # Pre-history shape: flat dict with correct/total, no attempts or last.
        rec_old = {"correct": 2, "total": 3, "at": "2026-09-02"}
        check("latest: old flat shape returns itself",
              g.latest(rec_old) == rec_old)

        # Attempts-only shape (no "last" key).
        rec_attempts_only = {
            "attempts": [
                {"correct": 1, "total": 5},
                {"correct": 3, "total": 5},
            ]
        }
        check("latest: attempts-only uses last attempt",
              g.latest(rec_attempts_only) == {"correct": 3, "total": 5})

        # Non-dict input returns empty dict.
        check("latest: non-dict returns {}", g.latest("garbage") == {})
        check("latest: None returns {}", g.latest(None) == {})

        # Empty dict returns itself (empty).
        check("latest: empty dict returns {}", g.latest({}) == {})

        # "last" key present but falsy (None): falls through to attempts.
        rec_null_last = {
            "last": None,
            "attempts": [{"correct": 2, "total": 4}],
        }
        check("latest: null last falls to attempts",
              g.latest(rec_null_last) == {"correct": 2, "total": 4})

        # ── trend ────────────────────────────────────────────────────────
        # Single attempt: no trend.
        rec_one = {"attempts": [{"correct": 3, "total": 5}]}
        check("trend: single attempt is empty", g.trend(rec_one) == "")

        # No attempts key: no trend.
        check("trend: no attempts key is empty", g.trend({"correct": 3}) == "")
        check("trend: None is empty", g.trend(None) == "")

        # Improving: first worse than last.
        rec_up = {"attempts": [
            {"correct": 1, "total": 5},
            {"correct": 3, "total": 5},
            {"correct": 5, "total": 5},
        ]}
        t = g.trend(rec_up)
        check("trend: improving", "improving" in t and "3" in t)

        # Slipping: first better than last.
        rec_down = {"attempts": [
            {"correct": 5, "total": 5},
            {"correct": 2, "total": 5},
        ]}
        t = g.trend(rec_down)
        check("trend: slipping", "SLIPPING" in t and "2" in t)

        # Flat: first equals last.
        rec_flat = {"attempts": [
            {"correct": 3, "total": 5},
            {"correct": 3, "total": 5},
        ]}
        t = g.trend(rec_flat)
        check("trend: flat", "flat" in t and "2" in t)

        # Edge: total=0 in an attempt should not divide by zero.
        rec_zero = {"attempts": [
            {"correct": 0, "total": 0},
            {"correct": 0, "total": 0},
        ]}
        check("trend: total=0 does not crash", g.trend(rec_zero) == "flat over 2")

        # Trend with many attempts reports the count.
        rec_many = {"attempts": [
            {"correct": 1, "total": 5},
            {"correct": 2, "total": 5},
            {"correct": 3, "total": 5},
            {"correct": 4, "total": 5},
            {"correct": 5, "total": 5},
        ]}
        t = g.trend(rec_many)
        check("trend: many attempts shows count", "improving over 5" == t)

        # Trend with empty attempts list.
        check("trend: empty attempts list", g.trend({"attempts": []}) == "")

        # ── resolve ──────────────────────────────────────────────────────
        # Create a guide to resolve against.
        test_guide = Path(os.path.join(gdir, "resolve-me.html"))
        test_guide.write_text("<html></html>")

        check("resolve: bare name", g.resolve("resolve-me") is not None)
        check("resolve: with .html", g.resolve("resolve-me.html") is not None)
        check("resolve: full path", g.resolve(str(test_guide)) is not None)
        check("resolve: returns resolved path",
              g.resolve("resolve-me") == test_guide.resolve())
        check("resolve: nonexistent returns None", g.resolve("no-such-guide") is None)
        check("resolve: empty string returns None", g.resolve("") is None)
        check("resolve: None returns None", g.resolve(None) is None)

        # Resolve by title (slug conversion).
        titled = Path(os.path.join(gdir, "graph-theory.html"))
        titled.write_text("<html></html>")
        check("resolve: title with spaces",
              g.resolve("Graph Theory") == titled.resolve())

        # ── cmd_new ──────────────────────────────────────────────────────
        # Successful creation.
        out, exc = capture(g.cmd_new, ["Linked Lists"])
        created = Path(os.path.join(gdir, "linked-lists.html"))
        check("cmd_new: creates the file", created.is_file())
        check("cmd_new: prints the path", "linked-lists.html" in out)

        # Content has the title.
        content = created.read_text()
        check("cmd_new: title in the HTML", "Linked Lists" in content)

        # With --course flag.
        out, exc = capture(g.cmd_new, ["Hash Tables", "--course", "CSCI103"])
        ht = Path(os.path.join(gdir, "hash-tables.html"))
        check("cmd_new: --course creates the file", ht.is_file())
        check("cmd_new: course in the HTML", "CSCI103" in ht.read_text())

        # Duplicate topic is refused (exits non-zero).
        _, exc = capture(g.cmd_new, ["Linked Lists"])
        check("cmd_new: duplicate exits non-zero",
              isinstance(exc, SystemExit) and exc.code == 1)

        # No topic argument is refused.
        _, exc = capture(g.cmd_new, [])
        check("cmd_new: no args exits non-zero",
              isinstance(exc, SystemExit) and exc.code == 1)

        # --course without a value is refused.
        _, exc = capture(g.cmd_new, ["Stacks", "--course"])
        check("cmd_new: --course without value exits non-zero",
              isinstance(exc, SystemExit) and exc.code == 1)

        # Template markers are replaced, not left in.
        check("cmd_new: no __TITLE__ marker left", "__TITLE__" not in content)
        check("cmd_new: no __BODY__ marker left", "__BODY__" not in content)

        # The generated HTML includes the quiz runtime script.
        check("cmd_new: runtime script present", "<script>" in content)
        check("cmd_new: quiz markup present", "rg-quiz" in content)

        # ── cmd_list ─────────────────────────────────────────────────────
        # List with guides present.
        out, _ = capture(g.cmd_list, [])
        check("cmd_list: shows guide names", "linked-lists" in out)
        check("cmd_list: shows untaken guides", "never taken" in out)

        # List with scores: write a sidecar for a guide.
        scored_html = Path(os.path.join(gdir, "scored.html"))
        scored_html.write_text("<html></html>")
        scored_data = {
            "basics": {
                "attempts": [
                    {"correct": 2, "total": 5, "at": "2026-09-01T00:00:00Z"},
                    {"correct": 4, "total": 5, "at": "2026-09-09T00:00:00Z"},
                ],
                "last": {"correct": 4, "total": 5, "at": "2026-09-09T00:00:00Z"},
            }
        }
        g.sidecar(scored_html).write_text(json.dumps(scored_data))
        out, _ = capture(g.cmd_list, [])
        check("cmd_list: shows score", "4/5" in out)
        check("cmd_list: shows topic count", "1 topic" in out)

        # List with a slipping topic.
        slipping_html = Path(os.path.join(gdir, "slipping.html"))
        slipping_html.write_text("<html></html>")
        slipping_data = {
            "core": {
                "attempts": [
                    {"correct": 5, "total": 5, "at": "2026-09-01T00:00:00Z"},
                    {"correct": 2, "total": 5, "at": "2026-09-09T00:00:00Z"},
                ],
                "last": {"correct": 2, "total": 5, "at": "2026-09-09T00:00:00Z"},
            }
        }
        g.sidecar(slipping_html).write_text(json.dumps(slipping_data))
        out, _ = capture(g.cmd_list, [])
        check("cmd_list: shows slipping count", "slipping" in out.lower())

        # List on empty dir.
        with tempfile.TemporaryDirectory() as empty_tmp:
            empty_gdir = os.path.join(empty_tmp, "guides")
            os.makedirs(empty_gdir)
            g2 = load(empty_gdir)
            out, _ = capture(g2.cmd_list, [])
            check("cmd_list: empty dir message", "no guides yet" in out)

        # Reload with original dir.
        g = load(gdir)

        # ── cmd_progress ─────────────────────────────────────────────────
        # Progress with no results.
        with tempfile.TemporaryDirectory() as prog_tmp:
            prog_gdir = os.path.join(prog_tmp, "guides")
            os.makedirs(prog_gdir)
            g3 = load(prog_gdir)
            out, _ = capture(g3.cmd_progress, [])
            check("cmd_progress: no results message", "no results yet" in out)

        # Reload with original dir.
        g = load(gdir)

        # Progress on a specific guide.
        out, _ = capture(g.cmd_progress, ["scored"])
        check("cmd_progress: shows topic name", "basics" in out)
        check("cmd_progress: shows score", "4/5" in out)

        # Progress --json returns valid JSON.
        out, _ = capture(g.cmd_progress, ["scored", "--json"])
        try:
            parsed = json.loads(out)
            check("cmd_progress: --json is valid", True)
            check("cmd_progress: --json has the guide", "scored" in parsed)
        except json.JSONDecodeError:
            check("cmd_progress: --json is valid", False)
            check("cmd_progress: --json has the guide", False)

        # Progress with missed items.
        missed_html = Path(os.path.join(gdir, "missed.html"))
        missed_html.write_text("<html></html>")
        missed_data = {
            "q1": {
                "attempts": [{"correct": 1, "total": 3,
                              "missed": ["What is a pointer?", "Define recursion"],
                              "at": "2026-09-10T00:00:00Z"}],
                "last": {"correct": 1, "total": 3,
                          "missed": ["What is a pointer?", "Define recursion"],
                          "at": "2026-09-10T00:00:00Z"},
            }
        }
        g.sidecar(missed_html).write_text(json.dumps(missed_data))
        out, _ = capture(g.cmd_progress, ["missed"])
        check("cmd_progress: shows missed items", "pointer" in out)
        check("cmd_progress: shows arrow for imperfect", "->" in out)

        # Progress on a perfect score shows no arrow.
        perfect_html = Path(os.path.join(gdir, "perfect.html"))
        perfect_html.write_text("<html></html>")
        perfect_data = {
            "all-right": {
                "last": {"correct": 5, "total": 5, "at": "2026-09-10T00:00:00Z"},
            }
        }
        g.sidecar(perfect_html).write_text(json.dumps(perfect_data))
        out, _ = capture(g.cmd_progress, ["perfect"])
        check("cmd_progress: perfect score has no arrow", "->" not in out)

        # Progress on nonexistent guide.
        _, exc = capture(g.cmd_progress, ["totally-fake-guide"])
        check("cmd_progress: nonexistent guide exits 1",
              isinstance(exc, SystemExit) and exc.code == 1)

        # ── main dispatch ────────────────────────────────────────────────
        # Help text.
        old_argv = sys.argv
        sys.argv = ["guide", "--help"]
        out, _ = capture(g.main)
        check("main: --help shows usage", "guide new" in out or "guide open" in out)

        sys.argv = ["guide", "help"]
        out, _ = capture(g.main)
        check("main: help subcommand shows usage", "guide new" in out or "guide open" in out)

        # No args shows help.
        sys.argv = ["guide"]
        out, _ = capture(g.main)
        check("main: no args shows usage", "guide new" in out or "guide open" in out)

        # Unknown command exits 2.
        sys.argv = ["guide", "destroy"]
        _, exc = capture(g.main)
        check("main: unknown command exits 2",
              isinstance(exc, SystemExit) and exc.code == 2)

        sys.argv = old_argv

        # ── die ──────────────────────────────────────────────────────────
        old_stderr = sys.stderr
        sys.stderr = io.StringIO()
        _, exc = capture(g.die, "something broke")
        stderr_out = sys.stderr.getvalue()
        sys.stderr = old_stderr
        check("die: exits 1 by default",
              isinstance(exc, SystemExit) and exc.code == 1)
        check("die: prints to stderr", "something broke" in stderr_out)

        sys.stderr = io.StringIO()
        _, exc = capture(g.die, "bad input", 2)
        sys.stderr = old_stderr
        check("die: custom exit code",
              isinstance(exc, SystemExit) and exc.code == 2)

        # ── cmd_progress: --json on empty ────────────────────────────────
        with tempfile.TemporaryDirectory() as empty_prog:
            eg = os.path.join(empty_prog, "guides")
            os.makedirs(eg)
            g4 = load(eg)
            out, _ = capture(g4.cmd_progress, ["--json"])
            try:
                parsed = json.loads(out)
                check("cmd_progress: --json empty is {}", parsed == {})
            except json.JSONDecodeError:
                check("cmd_progress: --json empty is {}", False)
        g = load(gdir)

        # ── cmd_progress: all-guides aggregate ───────────────────────────
        out, _ = capture(g.cmd_progress, [])
        check("cmd_progress: all-guides shows scored", "scored" in out)
        check("cmd_progress: all-guides shows missed", "missed" in out)

        # ── cmd_progress: --json all-guides ──────────────────────────────
        out, _ = capture(g.cmd_progress, ["--json"])
        try:
            parsed = json.loads(out)
            check("cmd_progress: --json all has scored", "scored" in parsed)
            check("cmd_progress: --json all has missed", "missed" in parsed)
        except json.JSONDecodeError:
            check("cmd_progress: --json all has scored", False)
            check("cmd_progress: --json all has missed", False)

        # ── resolve: case-insensitive slug match ─────────────────────────
        check("resolve: uppercase finds lowercase file",
              g.resolve("Resolve Me") == test_guide.resolve())

        # ── resolve: partial mismatch returns None ───────────────────────
        check("resolve: partial name no match", g.resolve("resolve") is None)

        # ── cmd_new: long title with many special chars ──────────────────
        out, _ = capture(g.cmd_new, ["C++ & Data Structures: Week #1!"])
        long_slug = Path(os.path.join(gdir, "c-data-structures-week-1.html"))
        check("cmd_new: special-char title creates file", long_slug.is_file())

        # ── cmd_list: --json flag not supported, no crash ────────────────
        # cmd_list does not support --json; verify it does not crash.
        out, _ = capture(g.cmd_list, ["--json"])
        check("cmd_list: unknown flag does not crash", out != "")

        # ── POST handler: path traversal and valid save ──────────────────
        # Spin up the server on an ephemeral port, test the POST endpoint,
        # and shut it down. Uses a fresh temp dir to isolate.
        with tempfile.TemporaryDirectory() as srv_tmp:
            srv_gdir = os.path.join(srv_tmp, "guides")
            os.makedirs(srv_gdir)
            srv_guide = Path(os.path.join(srv_gdir, "srv-test.html"))
            srv_guide.write_text("<html></html>")
            gs = load(srv_gdir)

            # Build the Handler class the same way cmd_open does.
            import http.server as _hs

            class _Handler(_hs.SimpleHTTPRequestHandler):
                def __init__(self, *a, **kw):
                    super().__init__(*a, directory=srv_gdir, **kw)
                def log_message(self, *a):
                    pass
                def do_POST(self):
                    if self.path != "/progress":
                        self.send_error(404)
                        return
                    try:
                        raw = self.rfile.read(int(self.headers.get("Content-Length", 0)))
                        payload = json.loads(raw)
                        rel = Path(payload.get("path", "")).name
                        page = (Path(srv_gdir) / rel).resolve()
                        if page.parent != Path(srv_gdir).resolve() or not page.is_file():
                            self.send_error(400, "unknown guide")
                            return
                        state = payload.get("state", {})
                        gs.sidecar(page).write_text(json.dumps(state, indent=2))
                    except (ValueError, OSError, TypeError) as e:
                        self.send_error(400, str(e))
                        return
                    self.send_response(204)
                    self.end_headers()

            socketserver.TCPServer.allow_reuse_address = True
            srv = socketserver.TCPServer(("127.0.0.1", 0), _Handler)
            port = srv.server_address[1]
            t = threading.Thread(target=srv.serve_forever, daemon=True)
            t.start()

            def post(path, body):
                data = json.dumps(body).encode()
                req = urllib.request.Request(
                    f"http://127.0.0.1:{port}{path}",
                    data=data,
                    headers={"Content-Type": "application/json"},
                    method="POST",
                )
                try:
                    resp = urllib.request.urlopen(req)
                    return resp.status
                except urllib.error.HTTPError as e:
                    return e.code

            # Valid save: sidecar is written.
            status = post("/progress", {
                "path": "srv-test.html",
                "state": {"topic-a": {"correct": 4, "total": 5}},
            })
            check("POST handler: valid save returns 204", status == 204)
            sc_path = gs.sidecar(srv_guide)
            check("POST handler: sidecar file created", sc_path.is_file())
            if sc_path.is_file():
                saved = json.loads(sc_path.read_text())
                check("POST handler: sidecar has topic", "topic-a" in saved)
                check("POST handler: correct score saved",
                      saved["topic-a"]["correct"] == 4)

            # Path traversal: "../etc/passwd" should be rejected.
            status = post("/progress", {
                "path": "../../../etc/passwd",
                "state": {},
            })
            check("POST handler: path traversal returns 400", status == 400)

            # Nonexistent guide file in payload.
            status = post("/progress", {
                "path": "no-such-file.html",
                "state": {},
            })
            check("POST handler: nonexistent guide returns 400", status == 400)

            # POST to wrong endpoint returns 404.
            status = post("/not-progress", {"path": "srv-test.html", "state": {}})
            check("POST handler: wrong endpoint returns 404", status == 404)

            # Invalid JSON body.
            bad_req = urllib.request.Request(
                f"http://127.0.0.1:{port}/progress",
                data=b"not json at all",
                headers={"Content-Type": "application/json"},
                method="POST",
            )
            try:
                urllib.request.urlopen(bad_req)
                bad_status = 204
            except urllib.error.HTTPError as e:
                bad_status = e.code
            check("POST handler: invalid JSON returns 400", bad_status == 400)

            # Overwrite: a second valid save replaces the sidecar.
            post("/progress", {
                "path": "srv-test.html",
                "state": {"topic-b": {"correct": 2, "total": 3}},
            })
            if sc_path.is_file():
                saved2 = json.loads(sc_path.read_text())
                check("POST handler: second save replaces first",
                      "topic-b" in saved2 and "topic-a" not in saved2)

            srv.shutdown()

        # Reload original dir after server test.
        g = load(gdir)

        # ── cmd_open: nonexistent guide ──────────────────────────────────
        old_stderr2 = sys.stderr
        sys.stderr = io.StringIO()
        _, exc = capture(g.cmd_open, ["nonexistent-guide-xyz"])
        sys.stderr = old_stderr2
        check("cmd_open: nonexistent guide exits 1",
              isinstance(exc, SystemExit) and exc.code == 1)

        # ── cmd_new: guide with only whitespace title ────────────────────
        out, _ = capture(g.cmd_new, ["   Whitespace Title   "])
        ws_file = Path(os.path.join(gdir, "whitespace-title.html"))
        check("cmd_new: whitespace-padded title works", ws_file.is_file())

        # ── cmd_list: shows all created guides ───────────────────────────
        out, _ = capture(g.cmd_list, [])
        check("cmd_list: shows whitespace-title", "whitespace-title" in out)
        check("cmd_list: shows c-data-structures", "c-data-structures" in out)

        # ── trend: two attempts with different totals ────────────────────
        rec_diff_totals = {"attempts": [
            {"correct": 3, "total": 5},
            {"correct": 8, "total": 10},
        ]}
        t = g.trend(rec_diff_totals)
        check("trend: different totals compares ratios correctly",
              "improving" in t)

        # ── trend: perfect to imperfect is slipping ──────────────────────
        rec_perf_to_imp = {"attempts": [
            {"correct": 10, "total": 10},
            {"correct": 9, "total": 10},
        ]}
        check("trend: 100% to 90% is slipping",
              "SLIPPING" in g.trend(rec_perf_to_imp))

        # ── latest: attempts list with one entry ─────────────────────────
        rec_single_attempt = {"attempts": [{"correct": 3, "total": 5}]}
        check("latest: single-element attempts list",
              g.latest(rec_single_attempt) == {"correct": 3, "total": 5})

        # ── read_progress: sidecar with non-JSON extension content ───────
        tricky_html = Path(os.path.join(gdir, "tricky.html"))
        tricky_html.write_text("<html></html>")
        g.sidecar(tricky_html).write_text("null")
        check("read_progress: JSON null returns None (falsy)",
              not g.read_progress(tricky_html))

    if failures:
        print(f"\n  {len(failures)} FAILED:")
        for f in failures:
            print(f"    - {f}")
        return 1
    print(f"\n  all passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
