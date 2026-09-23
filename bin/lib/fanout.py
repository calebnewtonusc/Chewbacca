"""JevBacca's kill test, run on one person's texts before any company's.

Every message is checked against the predicate library in fanout/predicates/
by three architectures, and each is scored against hand labels:

    A  Claude reads every message against every predicate.
    B  Regex rules pick candidate predicates; Claude reads only the hits.
    C  Jev answers all 25 predicates for a message in one call. Above a
       predicate's `accept` it counts; between `review` and `accept` Claude
       reads it; below `review` it is dropped.

The question from the Master Context (section 33) is whether C changes
findings per dollar enough to matter. If C does not beat B on recall at the
same review burden, Jev adds cost without adding knowledge, and the brain
stays rules plus Claude.

Nothing here writes a belief anywhere. `scan` prints what the gate would
write; applying it is a later, separate step.

Judges are injected (`jev_call`, `claude_call`) so tests run offline.
"""
from __future__ import annotations

import json
import os
import re
import shlex
import subprocess
import time
import urllib.error
import urllib.request
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

import jev

ROOT = Path(__file__).resolve().parent.parent.parent
PREDICATES_DIR = ROOT / "fanout" / "predicates"
DATA_DIR = Path(os.environ.get("FANOUT_DIR", Path.home() / ".chewbacca" / "fanout"))

CLAUDE_CMD = os.environ.get(
    "FANOUT_CLAUDE_CMD",
    # --restricted and an explicit system prompt keep CLAUDE.md and its rules
    # out of the call. Measured 2026-09-23: 419 input tokens, $0.0007, 1.7 s
    # for a one-line prompt on haiku, against 35,335 tokens and $0.074 for a
    # plain `claude -p` (route.py, 2026-09-21).
    "claude -p --restricted --strict-mcp-config --tools '' --no-session-persistence "
    "--output-format json",
)
CLAUDE_MODEL = os.environ.get("FANOUT_CLAUDE_MODEL", "sonnet")
# Guessed, never measured: small enough that one bad reply loses little,
# large enough that the per-call system prompt is not most of the bill.
CLAUDE_BATCH = 8
CLAUDE_TIMEOUT_S = 180
# One synthetic two-question call took 9.1 s cold on 2026-09-23; the people
# eval saw 0.58 s warm. 30 s covers the cold case with room.
JEV_TIMEOUT_S = 30
# 2026-09-23, 25 questions a call: two in flight gave 16 of 16, 0.2 to 8.7 s
# each. One sequential call got an HTTP 520 after 17.5 s, hence the retries.
# More workers were never measured cleanly (the first try hit the key race
# fixed in jev.api_key).
JEV_WORKERS = 2
JEV_RETRY_CODES = (429, 500, 502, 503, 504, 520, 522, 524, 529)
CLAUDE_WORKERS = 4

SYSTEM = (
    "You label text messages for a personal assistant. For each message you are "
    "given predicate ids to check. Return only JSON: an object mapping each message "
    "id to the list of predicate ids that are TRUE for that message. Judge only the "
    "message itself, using the thread lines as context. 'me' is the user."
)


# ------------------------------------------------------------------ inputs


def load_predicates(directory: Path = PREDICATES_DIR) -> list[dict]:
    preds = [json.loads(p.read_text()) for p in sorted(directory.glob("*.json"))]
    for p in preds:
        p["_rules"] = [re.compile(r, re.I) for r in p["rules"]]
    return preds


def load_jsonl(path: Path) -> list[dict]:
    if not path.exists():
        return []
    return [json.loads(line) for line in path.read_text().splitlines() if line.strip()]


def load_labels(path: Path) -> dict[str, set[str]]:
    """Latest label per event wins, so relabelling is an append."""
    out: dict[str, set[str]] = {}
    for row in load_jsonl(path):
        if row.get("skip"):
            out.pop(row["id"], None)
        else:
            out[row["id"]] = set(row["true"])
    return out


def jev_state(ev: dict) -> dict:
    return {
        "message": ev["body"],
        "from": "me" if ev["from_me"] else "them",
        "thread": "\n".join(ev.get("context", [])),
    }


def jev_questions(preds: list[dict]) -> dict:
    # Jev reads the instruction text, not the key, so the whole question goes in.
    return {p["id"]: {"type": "noul", "instructions": p["question"]} for p in preds}


def rule_hits(ev: dict, preds: list[dict]) -> list[str]:
    return [p["id"] for p in preds if any(r.search(ev["body"]) for r in p["_rules"])]


# ------------------------------------------------------------------ judges


def jev_call(state: dict, questions: dict) -> tuple[dict | None, dict]:
    """One Jev request. Returns (answers or None, usage). Retries 429 and 529,
    which the docs say to back off on, and the 5xx its edge returns under load."""
    if not jev.allowed() or not jev.api_key():
        return None, {}
    body = json.dumps({"state": state, "model": jev.MODEL, "questions": questions}).encode()
    for attempt in range(4):
        req = urllib.request.Request(jev.URL, data=body, method="POST", headers={
            "Authorization": f"Bearer {jev.api_key()}", "Content-Type": "application/json",
        })
        try:
            with urllib.request.urlopen(req, timeout=JEV_TIMEOUT_S) as resp:
                payload = json.loads(resp.read())
            answers = payload.get("answers")
            return (answers if isinstance(answers, dict) else None), payload.get("usage", {})
        except urllib.error.HTTPError as e:
            if e.code in JEV_RETRY_CODES and attempt < 3:
                time.sleep(2 ** attempt)
                continue
            return None, {}
        except (OSError, ValueError):
            if attempt < 3:
                time.sleep(2 ** attempt)
                continue
            return None, {}
    return None, {}


def claude_prompt(items: list[tuple[dict, list[str]]], preds_by_id: dict) -> str:
    used = sorted({pid for _, pids in items for pid in pids})
    lines = ["Predicates:"]
    lines += [f"- {pid}: {preds_by_id[pid]['question']}" for pid in used]
    lines.append("\nMessages:")
    for ev, pids in items:
        lines.append(f"\n[{ev['id']}] check: {', '.join(pids)}")
        for c in ev.get("context", []):
            lines.append(f"  (thread) {c}")
        lines.append(f"  {'me' if ev['from_me'] else 'them'}: {ev['body']}")
    lines.append('\nReturn JSON only, e.g. {"<id>": ["predicate_id"], "<id2>": []}')
    return "\n".join(lines)


def last_json_object(text: str) -> dict | None:
    """The last complete JSON object in `text`. Sonnet sometimes answers, then
    writes "Wait, ... Corrected output:" and answers again (2026-09-23, two
    batches of three), and the second answer is the one it stands by."""
    decoder = json.JSONDecoder()
    found = None
    for i, ch in enumerate(text):
        if ch != "{":
            continue
        try:
            obj, _ = decoder.raw_decode(text, i)
        except ValueError:
            continue
        if isinstance(obj, dict):
            found = obj
    return found


def claude_call(prompt: str, model: str | None = None) -> tuple[dict | None, float]:
    """Returns (parsed {id: [pids]} or None, cost in USD summed over attempts).

    One retry: on 2026-09-23 one batch in three failed once and parsed cleanly
    on the rerun, so a single failure is noise, not a verdict."""
    argv = shlex.split(CLAUDE_CMD) + ["--model", model or CLAUDE_MODEL, "--system-prompt", SYSTEM]
    spent = 0.0
    for _ in range(2):
        try:
            out = subprocess.run(argv, input=prompt, capture_output=True, text=True,
                                 timeout=CLAUDE_TIMEOUT_S)
            envelope = json.loads(out.stdout)
        except (OSError, subprocess.TimeoutExpired, ValueError):
            continue
        spent += float(envelope.get("total_cost_usd") or 0.0)
        parsed = last_json_object(envelope.get("result") or "")
        if parsed is not None:
            return parsed, spent
    return None, spent


# ------------------------------------------------------------------ arms


def _claude_over(items, preds_by_id, claude, stats) -> dict[str, set[str]]:
    """Run Claude over (event, pids) items in batches, concurrently. Only the
    pids asked about for an event can come back true."""
    items = [(ev, pids) for ev, pids in items if pids]
    batches = [items[i:i + CLAUDE_BATCH] for i in range(0, len(items), CLAUDE_BATCH)]
    found: dict[str, set[str]] = {}

    def one(batch):
        return batch, claude(claude_prompt(batch, preds_by_id))

    with ThreadPoolExecutor(CLAUDE_WORKERS) as pool:
        for batch, (parsed, cost) in pool.map(one, batches):
            stats["claude_calls"] += 1
            stats["claude_usd"] += cost
            if parsed is None:
                stats["claude_failures"] += 1
                continue
            for ev, pids in batch:
                got = parsed.get(ev["id"]) or []
                found[ev["id"]] = {p for p in got if p in pids}
    return found


def _new_stats() -> dict:
    return {"claude_calls": 0, "claude_usd": 0.0, "claude_failures": 0,
            "jev_calls": 0, "jev_failures": 0, "jev_tokens_in": 0, "jev_tokens_out": 0}


def run_arm(arm: str, events: list[dict], preds: list[dict],
            jev=jev_call, claude=claude_call) -> dict:
    preds_by_id = {p["id"]: p for p in preds}
    all_ids = list(preds_by_id)
    stats = _new_stats()
    t0 = time.time()
    positives: dict[str, set[str]] = {ev["id"]: set() for ev in events}
    scores: dict[str, dict] = {}

    if arm == "A":
        found = _claude_over([(ev, all_ids) for ev in events], preds_by_id, claude, stats)
        for k, v in found.items():
            positives[k] |= v
    elif arm == "B":
        found = _claude_over([(ev, rule_hits(ev, preds)) for ev in events], preds_by_id, claude, stats)
        for k, v in found.items():
            positives[k] |= v
    elif arm == "C":
        qs = jev_questions(preds)

        def one(ev):
            return ev, jev(jev_state(ev), qs)

        band: list[tuple[dict, list[str]]] = []
        with ThreadPoolExecutor(JEV_WORKERS) as pool:
            for ev, (answers, usage) in pool.map(one, events):
                stats["jev_calls"] += 1
                stats["jev_tokens_in"] += int(usage.get("input_tokens", 0))
                stats["jev_tokens_out"] += int(usage.get("output_tokens", 0))
                if answers is None:
                    # No judgment: Claude reads everything for this message,
                    # so a Jev outage costs C money instead of hiding misses.
                    stats["jev_failures"] += 1
                    band.append((ev, all_ids))
                    continue
                p_of = {pid: float((answers.get(pid) or {}).get("noul", 0.0)) for pid in all_ids}
                scores[ev["id"]] = p_of
                sure = {pid for pid, p in p_of.items() if p >= preds_by_id[pid]["accept"]}
                unsure = [pid for pid, p in p_of.items()
                          if preds_by_id[pid]["review"] <= p < preds_by_id[pid]["accept"]]
                positives[ev["id"]] |= sure
                band.append((ev, unsure))
        found = _claude_over(band, preds_by_id, claude, stats)
        for k, v in found.items():
            positives[k] |= v
    else:
        raise ValueError(f"unknown arm {arm}")

    stats["seconds"] = round(time.time() - t0, 2)
    return {"arm": arm, "model": CLAUDE_MODEL, "events": len(events), "stats": stats,
            "positives": {k: sorted(v) for k, v in positives.items()}, "jev_scores": scores}


# ------------------------------------------------------------------ scoring


def score(run: dict, labels: dict[str, set[str]], preds: list[dict]) -> dict:
    ids = [k for k in run["positives"] if k in labels]
    tp = fp = fn = 0
    per: dict[str, list[int]] = {p["id"]: [0, 0, 0] for p in preds}
    for k in ids:
        got, want = set(run["positives"][k]), labels[k]
        for pid in got & want:
            per[pid][0] += 1
        for pid in got - want:
            per.setdefault(pid, [0, 0, 0])[1] += 1
        for pid in want - got:
            per.setdefault(pid, [0, 0, 0])[2] += 1
        tp += len(got & want)
        fp += len(got - want)
        fn += len(want - got)
    s = run["stats"]
    usd = s["claude_usd"]
    return {
        "arm": run["arm"], "labelled": len(ids), "tp": tp, "fp": fp, "fn": fn,
        "recall": round(tp / (tp + fn), 3) if tp + fn else None,
        "precision": round(tp / (tp + fp), 3) if tp + fp else None,
        # Every finding the gate would surface is one thing Gavin reads.
        "review_burden": tp + fp,
        "claude_usd": round(usd, 4),
        "jev_tokens": s["jev_tokens_in"] + s["jev_tokens_out"],
        "jev_tokens_in": s["jev_tokens_in"], "jev_tokens_out": s["jev_tokens_out"],
        "seconds": s["seconds"],
        "failures": s["claude_failures"] + s["jev_failures"],
        "per_predicate": per,
    }


def verdict(b: dict, c: dict) -> str:
    """The Master Context's kill rule, applied to B vs C. Jev has no public
    price, so its cost is reported as the break-even price instead of guessed."""
    if b["recall"] is None or c["recall"] is None:
        return "not enough labelled positives to judge"
    lines = []
    burden_ok = c["review_burden"] <= b["review_burden"] * 1.1
    if c["recall"] > b["recall"] and burden_ok:
        lines.append(f"C beats B on recall ({c['recall']} vs {b['recall']}) at "
                     f"{c['review_burden']} vs {b['review_burden']} findings to review.")
    else:
        lines.append(f"KILL: C does not beat B on recall at the same review burden "
                     f"(recall {c['recall']} vs {b['recall']}, burden {c['review_burden']} vs "
                     f"{b['review_burden']}). Jev is not the unlock for this data.")
    if b["tp"] and c["tp"] and c["jev_tokens"]:
        # Price per million Jev tokens at which C's true findings per dollar equal B's.
        b_rate = b["tp"] / b["claude_usd"] if b["claude_usd"] else float("inf")
        budget = c["tp"] / b_rate - c["claude_usd"] if b_rate != float("inf") else 0.0
        per_m = budget / c["jev_tokens"] * 1e6
        if per_m > 0:
            lines.append(f"Break-even: C matches B's findings per dollar while Jev costs under "
                         f"${per_m:.2f} per million tokens.")
        else:
            lines.append("Break-even: C's Claude spend alone already exceeds B's findings per dollar.")
    return "\n".join(lines)


# ------------------------------------------------------------------ scan (dry run)


def scan(events: list[dict], preds: list[dict], jev=jev_call, claude=claude_call) -> list[dict]:
    """What the gate would write, with the action each predicate names.
    Writes nothing."""
    run = run_arm("C", events, preds, jev=jev, claude=claude)
    by_id = {p["id"]: p for p in preds}
    out = []
    for ev in events:
        for pid in run["positives"][ev["id"]]:
            out.append({"id": ev["id"], "who": ev.get("who"), "predicate": pid,
                        "p": run["jev_scores"].get(ev["id"], {}).get(pid),
                        "action": by_id[pid]["action"], "body": ev["body"]})
    return out
