#!/usr/bin/env python3
"""One terminal state, folded from hook events. Run: python3 tests/test_terminal_state.py"""
import json
import sys
import tempfile
from importlib.machinery import SourceFileLoader
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
ts = SourceFileLoader("terminal_state", str(ROOT / "bin" / "lib" / "terminal_state.py")).load_module()

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


def ev(event: str, **kw) -> dict:
    base = {"t": 100.0, "event": event, "tool": "", "summary": "", "session": "s", "ask": "", "held": False}
    base.update(kw)
    return base


def main() -> int:
    s = ts.initial()
    check("starts idle", s["state"] == "idle")
    check("idle is t off", ts.strip_line(s) == "t off")
    s = ts.fold(s, ev("PreToolUse", tool="Bash", summary="npm test"))
    check("a tool call is running with its summary", s["state"] == "running" and s["text"] == "npm test")
    check("running strip", ts.strip_line(s) == 't "npm test" state=running', ts.strip_line(s))
    s = ts.fold(s, ev("PostToolUse", tool="Bash"))
    check("after the tool, still running with no text", s["state"] == "running" and s["text"] == "")
    check("running with nothing named says working", ts.strip_line(s) == 't "working" state=running')
    s = ts.fold(s, ev("PermissionRequest", tool="Bash", summary="rm -rf build", ask="a1", held=True))
    check("a held ask is waiting, held", s["state"] == "waiting" and s["held"] is True and s["ask"] == "a1")
    check("waiting strip", ts.strip_line(s) == 't "waiting on you: rm -rf build" state=waiting', ts.strip_line(s))
    s = ts.fold(s, ev("ask_expired", ask="a1"))
    check("an expired ask is still waiting, no longer held", s["state"] == "waiting" and s["held"] is False)
    s = ts.fold(s, ev("ask_answered", ask="a1", summary="allow"))
    check("an answered ask is running", s["state"] == "running" and s["ask"] == "")
    s = ts.fold(s, ev("PermissionRequest", tool="Bash", summary="x", ask="", held=False))
    check("an unheld ask is waiting, not held", s["state"] == "waiting" and s["held"] is False)
    s = ts.fold(s, ev("PermissionDenied", tool="Bash"))
    check("a denial in the tab clears waiting", s["state"] == "running")
    s = ts.fold(s, ev("Stop", summary="All green."))
    check("stop is done with the sentence", s["state"] == "done" and s["text"] == "All green.")
    check("done strip", ts.strip_line(s) == 't "finished: All green." state=done', ts.strip_line(s))
    check("done is not expired early", ts.expire(s, 100.0 + ts.IDLE_AFTER_S - 1)["state"] == "done")
    check("done expires to idle", ts.expire(s, 100.0 + ts.IDLE_AFTER_S + 1)["state"] == "idle")
    s = ts.fold(s, ev("SessionEnd"))
    check("session end is idle", s["state"] == "idle")
    check("fold never mutates its input", ts.initial() == ts.fold(ts.initial(), ev("SessionEnd")))

    print("tail")
    tmp = Path(tempfile.mkdtemp()) / "events.jsonl"
    got, off = ts.tail(tmp, 0)
    check("no file: nothing, offset 0", got == [] and off == 0)
    tmp.write_text(json.dumps(ev("PreToolUse")) + "\n")
    got, off = ts.tail(tmp, 0)
    check("one line read", len(got) == 1 and off == tmp.stat().st_size)
    got2, off2 = ts.tail(tmp, off)
    check("nothing new: nothing", got2 == [] and off2 == off)
    with tmp.open("a") as f:
        f.write("garbage\n" + json.dumps(ev("Stop")) + "\n")
    got3, off3 = ts.tail(tmp, off)
    check("appended lines read, garbage skipped", [g["event"] for g in got3] == ["Stop"] and off3 == tmp.stat().st_size)
    tmp.write_text(json.dumps(ev("SessionEnd")) + "\n")
    got4, off4 = ts.tail(tmp, off3)
    check("a rewritten shorter file restarts from the top", [g["event"] for g in got4] == ["SessionEnd"])

    print(f"\n{PASSED} passed, {FAILED} failed")
    return 1 if FAILED else 0


if __name__ == "__main__":
    sys.exit(main())
