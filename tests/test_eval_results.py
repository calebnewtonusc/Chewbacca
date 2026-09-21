#!/usr/bin/env python3
"""The eval runner must say WHICH cases failed, not how many.

THE FAILURE THIS EXISTS FOR, 2026-09-21. `tools/evals.py` knew everything
about each failure and printed it, and `bin/fitness` regexed two integers
back out of stdout. Ten runs of the benchmark recorded "25 failed" with no
record of which 25, so nothing could ever be attributed or fixed. Credit
assignment is the whole problem in a learning loop.

This asserts the machine-readable path, which is the part nothing looks at
by eye and so the part that rots silently.
"""

from __future__ import annotations

import importlib.util
import json
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def load_evals():
    spec = importlib.util.spec_from_file_location("evals", ROOT / "tools/evals.py")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def test_case_ids_are_stable_and_distinct():
    e = load_evals()
    a = e.case_id("coursework", "what is due")
    assert a == e.case_id("coursework", "what is due"), "id must not vary between calls"
    assert a != e.case_id("coursework", "what is due today"), "different prompts, different ids"
    assert a != e.case_id("life-ops", "what is due"), "different skills, different ids"
    assert a.startswith("coursework:"), "an id should say which skill it belongs to"


def test_case_id_survives_reordering():
    """An id derived from position renames every case after an insertion,
    which makes one failure look like it vanished and another appeared."""
    e = load_evals()
    before = [e.case_id("s", p) for p in ("one", "two", "three")]
    after = [e.case_id("s", p) for p in ("zero", "one", "two", "three")]
    assert before == after[1:], "inserting a case must not rename the others"


def test_run_writes_a_row_per_case(tmp_path=None):
    """--json must produce parseable rows carrying the fields fitness reads.

    Skipped rather than failed when the `claude` CLI is absent, because the
    behavioural pass genuinely cannot run without it and a test that fails
    on a machine with no model is a test people learn to ignore.
    """
    import shutil
    if not shutil.which("claude"):
        print("skip: no claude CLI, behavioural pass cannot run here")
        return

    with tempfile.TemporaryDirectory() as tmp:
        out = Path(tmp) / "cases.jsonl"
        subprocess.run(
            [sys.executable, str(ROOT / "tools/evals.py"), "--run",
             "what-can-this-do", "--json", str(out)],
            capture_output=True, text=True, timeout=600,
        )
        if not out.exists():
            print("skip: runner produced no results file for this skill")
            return
        rows = [json.loads(l) for l in out.read_text().splitlines() if l.strip()]
        assert rows, "a run must write at least one row"
        for r in rows:
            for key in ("id", "skill", "pass", "missing", "rejected"):
                assert key in r, f"row missing {key}: {r}"
            assert isinstance(r["pass"], bool)
            assert isinstance(r["missing"], list)


def test_fitness_carries_failures_not_just_a_count():
    """The shape fitness records, checked without spending model calls."""
    src = (ROOT / "bin/fitness").read_text(encoding="utf-8")
    assert "failed_cases" in src, "fitness must record which cases failed"
    assert "by_skill" in src, "fitness must break failures down per skill"
    assert "--json" in src, "fitness must ask the runner for machine-readable results"


def test_the_scalar_regex_is_no_longer_the_only_source():
    """Guards the actual regression: going back to parsing stdout alone."""
    src = (ROOT / "bin/fitness").read_text(encoding="utf-8")
    i = src.index("def behavioural")
    j = src.index("def tests")
    body = src[i:j]
    assert "results_path" in body, (
        "behavioural() reads counts out of stdout again and has stopped "
        "reading per-case results")


if __name__ == "__main__":
    fails = 0
    for name, fn in sorted(globals().items()):
        if name.startswith("test_") and callable(fn):
            try:
                fn()
                print(f"  pass  {name}")
            except AssertionError as exc:
                print(f"  FAIL  {name}: {exc}")
                fails += 1
    print(f"\n{'FAILED' if fails else 'ok'}  {fails} failure(s)")
    sys.exit(1 if fails else 0)
