"""Every Jev decision, and what actually happened after it.

Eight call sites asked Jev on 2026-09-24 and none kept a record, so a wrong
route or a missed click left nothing to look at and every floor stayed a
guess. `jev.ask(..., decision="route")` appends one row here; a verifier or a
correction later writes an outcome row against the same id. `bin/decisions`
reads both, and joins them into accuracy by confidence bucket, which is the
evidence a floor needs (see docs/JEV-EVERYWHERE.md, "Calibration").

Local only: ~/.bob/decisions.jsonl never leaves the machine and is not in any
repo. The state is kept as a short excerpt, enough to label a row by hand.
An outcome is only ever written from something observed (a window that did or
did not change, a spoken correction), never from the decision's own confidence.
"""
from __future__ import annotations

import json
import os
import threading
import time
import uuid
from pathlib import Path

LOG = Path(os.environ.get("BOB_DECISIONS", str(Path.home() / ".bob" / "decisions.jsonl")))
STATE_CHARS = 300
# guessed, never measured: a year of voice turns at the rate seen 2026-09-24
# is well under this, and bulk tools (list-sift, fanout) do not log per row.
CAP_BYTES = 20_000_000
OUTCOMES = ("right", "wrong", "unknown")
_lock = threading.Lock()
_last: dict[str, str] = {}


def _write(row: dict) -> None:
    try:
        LOG.parent.mkdir(parents=True, exist_ok=True)
        with _lock:
            if LOG.exists() and LOG.stat().st_size > CAP_BYTES:
                LOG.replace(LOG.with_suffix(".jsonl.1"))
            with LOG.open("a", encoding="utf-8") as f:
                f.write(json.dumps(row, ensure_ascii=False) + "\n")
    except OSError:
        pass  # a full disk must never cost the person their answer


def _summary(answers: dict | None) -> dict:
    out = {}
    for qid, a in (answers or {}).items():
        if not isinstance(a, dict):
            continue
        probs = a.get("probabilities") or {}
        if "choice" in a:
            out[qid] = {"choice": a["choice"], "p": round(float(probs.get(a["choice"], 0.0)), 3)}
        elif "probability" in a:
            out[qid] = {"p": round(float(a["probability"]), 3)}
        else:
            out[qid] = {k: a[k] for k in list(a)[:2]}
    return out


def record(decision: str, state, answers: dict | None, ms: float, error: str | None = None) -> str:
    did = uuid.uuid4().hex[:12]
    text = state if isinstance(state, str) else json.dumps(state, ensure_ascii=False)
    _write({"t": round(time.time(), 3), "kind": "decision", "id": did, "decision": decision,
            "state": text[:STATE_CHARS], "answers": _summary(answers), "ms": round(ms),
            "error": error})
    _last[decision] = did
    return did


def last_id(decision: str) -> str | None:
    return _last.get(decision)


def outcome(did: str | None, result: str, note: str = "") -> bool:
    if not did or result not in OUTCOMES:
        return False
    _write({"t": round(time.time(), 3), "kind": "outcome", "id": did, "outcome": result,
            "note": note[:200]})
    return True


def rows() -> list[dict]:
    out = []
    for path in (LOG.with_suffix(".jsonl.1"), LOG):
        try:
            for line in path.read_text(encoding="utf-8").splitlines():
                try:
                    out.append(json.loads(line))
                except ValueError:
                    continue
        except OSError:
            continue
    return out


def joined() -> list[dict]:
    """Decisions with their latest outcome attached, oldest first."""
    decisions, results = [], {}
    for r in rows():
        if r.get("kind") == "decision":
            decisions.append(r)
        elif r.get("kind") == "outcome":
            results[r.get("id")] = r
    for d in decisions:
        o = results.get(d["id"])
        d["outcome"] = o.get("outcome") if o else None
        d["note"] = o.get("note") if o else None
    return decisions


def top_p(d: dict) -> float | None:
    ps = [a.get("p") for a in (d.get("answers") or {}).values() if isinstance(a, dict) and "p" in a]
    return max(ps) if ps else None


def stats() -> dict:
    """Per decision: calls, errors, median ms, and right/wrong by confidence bucket."""
    table: dict[str, dict] = {}
    for d in joined():
        s = table.setdefault(d["decision"], {"calls": 0, "errors": 0, "ms": [], "buckets": {}})
        s["calls"] += 1
        s["errors"] += bool(d.get("error"))
        s["ms"].append(d.get("ms") or 0)
        if d["outcome"] in ("right", "wrong"):
            p = top_p(d)
            bucket = "?" if p is None else f"{min(int(p * 10), 9) / 10:.1f}"
            b = s["buckets"].setdefault(bucket, {"right": 0, "wrong": 0})
            b[d["outcome"]] += 1
    for s in table.values():
        ms = sorted(s.pop("ms"))
        s["median_ms"] = ms[len(ms) // 2] if ms else 0
    return table
