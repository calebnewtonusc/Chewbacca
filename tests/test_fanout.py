#!/usr/bin/env python3
"""The fanout kill-test harness with injected judges in place of Jev and
Claude. Run: python3 tests/test_fanout.py"""
import json
import sys
from pathlib import Path

sys.dont_write_bytecode = True
HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent / "bin" / "lib"))
import fanout  # noqa: E402

PASSED = 0
FAILED = 0


def check(name: str, cond: bool, detail: str = "") -> None:
    global PASSED, FAILED
    if cond:
        PASSED += 1
        print(f"  pass  {name}")
    else:
        FAILED += 1
        print(f"  FAIL  {name}  {detail}")


def main() -> int:
    FIX = HERE / "fixtures" / "fanout"
    preds = fanout.load_predicates()
    events = fanout.load_jsonl(FIX / "sample.jsonl")
    labels = fanout.load_labels(FIX / "labels.jsonl")

    check("25 predicates load", len(preds) == 25, str(len(preds)))
    check("every predicate has a question, action and both thresholds",
          all(p["question"] and p["action"] and 0 < p["review"] < p["accept"] <= 1 for p in preds))
    known = {p["id"] for p in preds}
    check("fixture labels only use known predicates",
          all(s <= known for s in labels.values()), str(set().union(*labels.values()) - known))


    class Oracle:
        """Claude that answers from the labels, and counts what it was asked."""

        def __init__(self):
            self.calls = 0
            self.asked: list[tuple[str, str]] = []

        def __call__(self, prompt: str):
            self.calls += 1
            out = {}
            current = None
            for line in prompt.splitlines():
                if line.startswith("[") and "] check: " in line:
                    current, pids = line[1:].split("] check: ")
                    asked = pids.split(", ")
                    self.asked += [(current, p) for p in asked]
                    out[current] = sorted(labels.get(current, set()) & set(asked))
            return out, 0.01


    def jev_perfect(state, questions):
        ev = next(e for e in events if e["body"] == state["message"])
        return {pid: {"noul": 0.95 if pid in labels[ev["id"]] else 0.02} for pid in questions}, \
            {"input_tokens": 300, "output_tokens": 30}


    def jev_unsure(state, questions):
        return {pid: {"noul": 0.5} for pid in questions}, {"input_tokens": 300, "output_tokens": 30}


    def jev_down(state, questions):
        return None, {}


    # A: an oracle Claude over everything is perfect, and asks every pair.
    o = Oracle()
    run_a = fanout.run_arm("A", events, preds, claude=o)
    sa = fanout.score(run_a, labels, preds)
    check("A with an oracle has recall 1 and precision 1", sa["recall"] == 1.0 and sa["precision"] == 1.0, str(sa))
    check("A asks Claude about every message x predicate", len(o.asked) == len(events) * 25, str(len(o.asked)))
    check("A batches", o.calls == -(-len(events) // fanout.CLAUDE_BATCH), str(o.calls))

    # B: Claude only sees rule hits, so a positive with no rule hit is missed.
    o = Oracle()
    run_b = fanout.run_arm("B", events, preds, claude=o)
    sb = fanout.score(run_b, labels, preds)
    check("B asks Claude only about rule hits",
          all(pid in fanout.rule_hits(next(e for e in events if e["id"] == k), preds) for k, pid in o.asked))
    check("B never reports a predicate it did not ask about",
          all(set(v) <= {p for k2, p in o.asked if k2 == k} for k, v in run_b["positives"].items()))
    check("B's rules catch most fixture positives", sb["recall"] >= 0.6, str(sb["recall"]))

    # C: a confident Jev needs no Claude; an unsure one sends everything to Claude.
    o = Oracle()
    run_c = fanout.run_arm("C", events, preds, jev=jev_perfect, claude=o)
    sc = fanout.score(run_c, labels, preds)
    check("C with a sure, right Jev is perfect and calls Claude zero times",
          sc["recall"] == 1.0 and sc["precision"] == 1.0 and o.calls == 0, f"{sc} calls={o.calls}")
    check("C counts Jev tokens", sc["jev_tokens"] == len(events) * 330, str(sc["jev_tokens"]))

    o = Oracle()
    run_c = fanout.run_arm("C", events, preds, jev=jev_unsure, claude=o)
    check("C sends the review band to Claude", len(o.asked) == len(events) * 25, str(len(o.asked)))

    o = Oracle()
    run_c = fanout.run_arm("C", events, preds, jev=jev_down, claude=o)
    check("Jev down: every message falls through to Claude and is counted as a failure",
          run_c["stats"]["jev_failures"] == len(events) and len(o.asked) == len(events) * 25)

    # Claude failing loses findings and says so.
    run_x = fanout.run_arm("A", events, preds, claude=lambda p: (None, 0.0))
    check("a failed Claude batch is counted, not silently empty",
          run_x["stats"]["claude_failures"] == run_x["stats"]["claude_calls"] > 0)

    # Claude cannot smuggle in a predicate it was not asked about.
    run_y = fanout.run_arm("B", events, preds,
                           claude=lambda p: ({e["id"]: ["secret_pasted"] for e in events}, 0.0))
    check("unasked predicates in a reply are discarded",
          all("secret_pasted" not in v or "secret_pasted" in fanout.rule_hits(
              next(e for e in events if e["id"] == k), preds) for k, v in run_y["positives"].items()))

    # Verdict: the kill rule fires both ways.
    kill = fanout.verdict({**sb, "recall": 0.9, "review_burden": 50, "tp": 45, "claude_usd": 1.0},
                          {**sc, "recall": 0.8, "review_burden": 50, "tp": 40, "claude_usd": 0.2,
                           "jev_tokens": 10000})
    check("verdict says KILL when C recalls less", kill.startswith("KILL"), kill)
    win = fanout.verdict({**sb, "recall": 0.7, "review_burden": 50, "tp": 35, "claude_usd": 1.0},
                         {**sc, "recall": 0.9, "review_burden": 50, "tp": 45, "claude_usd": 0.2,
                          "jev_tokens": 10000})
    check("verdict credits C and prices Jev's break-even", "beats" in win and "Break-even" in win, win)

    # The labels loader: a later row wins, a skip removes.
    tmp = HERE / "fixtures" / "fanout" / ".labels-test.jsonl"
    tmp.write_text("\n".join(json.dumps(r) for r in [
        {"id": "x", "true": ["new_job"]}, {"id": "x", "true": []}, {"id": "y", "true": ["moving"]},
        {"id": "y", "skip": True}]) + "\n")
    lab = fanout.load_labels(tmp)
    tmp.unlink()
    check("relabel wins and skip removes", lab == {"x": set()}, str(lab))

    # The scan is a dry run: it returns actions and has no write path.
    found = fanout.scan(events, preds, jev=jev_perfect, claude=Oracle())
    check("scan returns one finding per labelled positive", len(found) == sum(map(len, labels.values())))
    check("scan findings carry the action", all(f["action"] for f in found))

    two = '{"a": ["x", "y"]}\n\nWait, only checked ones. Corrected output:\n\n{"a": ["x"]}'
    check("a self-corrected reply parses to its last object", fanout.last_json_object(two) == {"a": ["x"]})
    check("no object parses to None", fanout.last_json_object("sorry, cannot") is None)

    # jev.api_key under threads: a slow Keychain lookup must not leave the cache
    # reading "" to the other threads (29 of 30 calls failed this way 2026-09-23).
    import os
    import subprocess
    import threading
    import time
    import jev as jev_client


    class _SlowKeychain:
        returncode = 0
        stdout = "k-test\n"


    def _slow_run(*a, **k):
        time.sleep(0.2)
        return _SlowKeychain()


    saved = (jev_client._key, jev_client.subprocess.run, os.environ.pop("TYPESAFE_API_KEY", None))
    jev_client._key = None
    jev_client.subprocess.run = _slow_run
    got = []
    threads = [threading.Thread(target=lambda: got.append(jev_client.api_key())) for _ in range(8)]
    for th in threads:
        th.start()
        time.sleep(0.01)
    for th in threads:
        th.join()
    jev_client._key, jev_client.subprocess.run = saved[0], subprocess.run
    if saved[2] is not None:
        os.environ["TYPESAFE_API_KEY"] = saved[2]
    check("api_key under 8 threads: nobody reads an empty key mid-lookup",
          got == ["k-test"] * 8, str(got))

    print(f"\n{PASSED} passed, {FAILED} failed")
    return 1 if FAILED else 0


if __name__ == "__main__":
    sys.exit(main())
