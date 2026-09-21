#!/usr/bin/env python3
"""The merge gate: the retention step evolve has never had.

`evolve` proposes, scores and archives, and never merges. That leaves
variation with no selection, and an archive with no retention is a museum.
The gate is the missing half.

The check that carries the weight is per-case regression: no eval case that
passed may now fail. That comparison was impossible until 2026-09-21, when
`fitness` started recording WHICH cases failed rather than how many, so
these tests guard the thing that made the gate possible at all.
"""

from __future__ import annotations

import importlib.machinery
import importlib.util
import json
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def load():
    # SourceFileLoader explicitly: bin/evolve has no .py extension, so
    # spec_from_file_location finds no loader for it and returns None.
    loader = importlib.machinery.SourceFileLoader("evolve", str(ROOT / "bin/evolve"))
    spec = importlib.util.spec_from_loader(loader.name, loader)
    mod = importlib.util.module_from_spec(spec)
    loader.exec_module(mod)
    return mod


def ledger(tmp, rows):
    p = Path(tmp) / "fitness.jsonl"
    p.write_text("".join(json.dumps(r) + "\n" for r in rows), encoding="utf-8")
    return p


def test_missing_file_is_unknown_not_empty():
    e = load()
    assert e.cases_from(Path("/nonexistent/fitness.jsonl")) is None


def test_no_per_case_data_is_unknown_not_empty():
    """A run from before fitness recorded cases must read as 'I do not know',
    never as 'nothing failed'. Treating the two the same lets a regression
    through as a clean sheet."""
    e = load()
    with tempfile.TemporaryDirectory() as tmp:
        p = ledger(tmp, [{"structural_score": 90.1, "failed": 25}])
        assert e.cases_from(p) is None


def test_reads_the_newest_row_that_has_cases():
    e = load()
    with tempfile.TemporaryDirectory() as tmp:
        p = ledger(tmp, [
            {"failed_cases": [{"id": "old:1111"}]},
            {"structural_score": 1},                      # no cases, skipped
            {"failed_cases": [{"id": "new:2222"}, {"id": "new:3333"}]},
        ])
        assert e.cases_from(p) == {"new:2222", "new:3333"}


def test_empty_failure_list_is_a_real_answer():
    """Zero failures is data: an empty set, not None."""
    e = load()
    with tempfile.TemporaryDirectory() as tmp:
        p = ledger(tmp, [{"failed_cases": []}])
        assert e.cases_from(p) == set()


def test_bad_json_lines_do_not_stop_the_read():
    e = load()
    with tempfile.TemporaryDirectory() as tmp:
        p = Path(tmp) / "f.jsonl"
        p.write_text('{"failed_cases": [{"id": "a:1"}]}\nnot json\n', encoding="utf-8")
        assert e.cases_from(p) == {"a:1"}


def test_gate_refuses_a_change_that_did_not_score():
    e = load()
    allowed, reasons = e.gate(Path("/tmp"), {"structural_score": 90.0}, None)
    assert allowed is False
    assert "nothing to judge" in " ".join(reasons)


def test_unknown_cases_is_a_note_not_a_refusal():
    """Missing per-case data must not block a change on its own, or the gate
    is unusable on every repo that has not run a behavioural pass. It has to
    SAY it could not check, which is the part that must never be silent."""
    src = (ROOT / "bin/evolve").read_text(encoding="utf-8")
    assert "NOT CHECKED" in src, "the gate must say when it could not compare cases"
    i = src.index("def gate")
    body = src[i:src.index("\ndef main")]
    assert 'x.startswith("NOT CHECKED")' in body, (
        "a NOT CHECKED note must be excluded from the hard-refusal list")


def test_gate_never_merges():
    """The three reasons at the top of evolve stand. The gate judges; a human
    applies. Anything that commits or merges here is the bug."""
    src = (ROOT / "bin/evolve").read_text(encoding="utf-8")
    i = src.index("def gate")
    body = src[i:src.index("\ndef main")]
    for forbidden in ("git(\"commit\"", "git(\"merge\"", "git(\"apply\"",
                      '"commit"', '"merge"'):
        assert forbidden not in body, f"the gate must not {forbidden}"


def fake_worktree(tmp, suite_exits, failed_ids):
    """A worktree stub: a suite that exits how we say, and a score ledger."""
    wt = Path(tmp)
    (wt / "tests").mkdir(parents=True, exist_ok=True)
    (wt / "tests/run.sh").write_text(
        f"#!/bin/bash\necho 'stub suite'\nexit {suite_exits}\n", encoding="utf-8")
    (wt / ".evolve-fitness.jsonl").write_text(
        json.dumps({"failed_cases": [{"id": i} for i in failed_ids]}) + "\n",
        encoding="utf-8")
    return wt


def test_gate_REFUSES_a_case_that_passed_and_now_fails(monkeypatch=None):
    """The check the whole gate exists for, proved by making it fire."""
    e = load()
    with tempfile.TemporaryDirectory() as tmp:
        wt = fake_worktree(tmp, suite_exits=0, failed_ids=["skillA:dead1234"])
        home = Path(tmp) / "home"
        (home / ".chewbacca").mkdir(parents=True)
        (home / ".chewbacca/fitness.jsonl").write_text(
            json.dumps({"failed_cases": []}) + "\n", encoding="utf-8")
        real_home = e.pathlib.Path.home
        e.pathlib.Path.home = staticmethod(lambda: home)
        try:
            allowed, reasons = e.gate(wt, {"structural_score": 90.0}, 90.0)
        finally:
            e.pathlib.Path.home = real_home
    assert allowed is False, "a newly failing case must be refused"
    assert any("now fail" in r for r in reasons), reasons
    assert "skillA:dead1234" in " ".join(reasons), "it must name the case"


def test_gate_REFUSES_a_failing_suite():
    e = load()
    with tempfile.TemporaryDirectory() as tmp:
        wt = fake_worktree(tmp, suite_exits=1, failed_ids=[])
        home = Path(tmp) / "home"
        (home / ".chewbacca").mkdir(parents=True)
        (home / ".chewbacca/fitness.jsonl").write_text(
            json.dumps({"failed_cases": []}) + "\n", encoding="utf-8")
        real_home = e.pathlib.Path.home
        e.pathlib.Path.home = staticmethod(lambda: home)
        try:
            allowed, reasons = e.gate(wt, {"structural_score": 90.0}, 95.0)
        finally:
            e.pathlib.Path.home = real_home
    assert allowed is False, "a change must not land on a failing suite, however good its score"
    assert any("test suite failed" in r for r in reasons), reasons


def test_gate_ALLOWS_a_clean_change():
    """The other direction: a guard that refuses everything is no guard."""
    e = load()
    with tempfile.TemporaryDirectory() as tmp:
        wt = fake_worktree(tmp, suite_exits=0, failed_ids=["known:aaaa1111"])
        home = Path(tmp) / "home"
        (home / ".chewbacca").mkdir(parents=True)
        (home / ".chewbacca/fitness.jsonl").write_text(
            json.dumps({"failed_cases": [{"id": "known:aaaa1111"}]}) + "\n",
            encoding="utf-8")
        real_home = e.pathlib.Path.home
        e.pathlib.Path.home = staticmethod(lambda: home)
        try:
            allowed, reasons = e.gate(wt, {"structural_score": 90.0}, 91.0)
        finally:
            e.pathlib.Path.home = real_home
    assert allowed is True, f"a clean change must pass: {reasons}"


def test_gate_checks_the_suite_and_the_cases():
    src = (ROOT / "bin/evolve").read_text(encoding="utf-8")
    i = src.index("def gate")
    body = src[i:src.index("\ndef main")]
    assert "tests/run.sh" in body, "the gate must run the suite"
    assert "newly_failing" in body, "the gate must compare per-case failures"
    assert "structural score fell" in body, "the gate must notice a score drop"


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
