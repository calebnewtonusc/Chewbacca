"""Unit tests for the guide CLI's pure functions.

The bash tests in run.sh cover the CLI end to end: new, open, list, progress,
sidecar read-back, trend labels, and the template. This file covers the internal
functions that are easy to get wrong quietly: slug edge cases, sidecar path
computation, latest() across both sidecar shapes, trend() arithmetic, resolve()
name matching, and read_progress() on corrupt or missing files.
"""
from __future__ import annotations

import importlib.util
import json
import os
import sys
import tempfile
from importlib.machinery import SourceFileLoader
from pathlib import Path

BIN = Path(__file__).resolve().parent.parent / "bin" / "guide"
failures: list[str] = []


def check(name: str, ok: bool, detail: str = "") -> None:
    print(f"  {'ok  ' if ok else 'FAIL'} {name} {detail}".rstrip())
    if not ok:
        failures.append(name)


def load(guide_dir: str):
    """Import bin/guide as a module, pointing GUIDE_DIR at a temp dir."""
    os.environ["GUIDE_DIR"] = guide_dir
    spec = importlib.util.spec_from_file_location(
        "guide_mod", BIN, loader=SourceFileLoader("guide_mod", str(BIN))
    )
    m = importlib.util.module_from_spec(spec)
    # Prevent sys.exit from die() killing the test runner.
    sys.modules["guide_mod"] = m
    spec.loader.exec_module(m)
    return m


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

    if failures:
        print(f"\n  {len(failures)} FAILED:")
        for f in failures:
            print(f"    - {f}")
        return 1
    print(f"\n  all passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
